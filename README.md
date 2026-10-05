# terraform-openstack-cluster

The CAPTF OpenStack `cluster` module: the Terraform/OpenTofu root module
behind `TerraformCluster`. Module images are published from
[openstack-modules](https://github.com/captf-io/openstack-modules) as `ghcr.io/captf-io/openstack-cluster`.

The `cluster` role for OpenStack: what a `TerraformCluster` runs. On a
subnet you already have, it creates the security groups of the nodes, the
Octavia load balancer behind the Kubernetes API, and a server group that
spreads the control plane. Machines receive everything they need through
the `exports` output.

Design and evidence: [DESIGN.md](https://github.com/captf-io/terraform-openstack-cluster/blob/main/DESIGN.md). Rules every file follows:
[CONVENTIONS.md](https://github.com/captf-io/terraform-openstack-cluster/blob/main/CONVENTIONS.md). Contract:
<https://captf.io/docs/module-author/contract/v1alpha1/cluster.html>.

## Usage

CAPTF runs this module from the module image `ghcr.io/captf-io/openstack-cluster`: set the image on
a `TerraformCluster`'s `spec.source.image`, and the controller renders every
input. The module is also published to the Terraform Registry as
`captf-io/cluster/openstack` and can be called directly:

```hcl
module "cluster" {
  source  = "captf-io/cluster/openstack"
  version = "~> 0.1"

  # The contract inputs the controller would render (captf_contract,
  # captf_cluster, captf_object, captf_tags, ...; see Inputs), and any
  # user variables.
}
```

Called directly, the module is a CAPTF root module first:

- it configures its own `provider "openstack"` block, so the calling
  module cannot use `count`, `for_each` or `depends_on` on it, and the
  provider takes its credentials from the environment (see Identity
  Secret);
- its providers are pinned to exact versions (`versions.tf`), which the
  calling configuration has to accept;
- you set the `captf_*` inputs yourself.

## What it creates

| Resource | Count | Purpose |
| --- | --- | --- |
| `openstack_networking_secgroup_v2.node_security_group` | 1 | Every node: all traffic from the cluster's nodes, NodePorts, optional SSH, egress |
| `openstack_networking_secgroup_v2.control_plane_security_group` | 1 | Control-plane nodes, on top of the node group: the API backend ports from the subnet |
| `openstack_networking_secgroup_rule_v2.node_ingress_rules` | one per rule | Ingress of the node group (table below) |
| `openstack_networking_secgroup_rule_v2.node_egress_rules` | 2 | Egress anywhere, IPv4 and IPv6 |
| `openstack_networking_secgroup_rule_v2.control_plane_ingress_rules` | one per rule | Ingress of the control-plane group (table below) |
| `openstack_lb_loadbalancer_v2.api_load_balancer` | 1, 0 with a supplied endpoint | Octavia load balancer, VIP on `subnet_id` |
| `openstack_lb_listener_v2.api_listeners` | 1, 2 with `rke2` | TCP listeners: kube-apiserver; RKE2 supervisor on 9345 |
| `openstack_lb_pool_v2.api_pools` | one per listener | Pools control-plane machines join |
| `openstack_lb_monitor_v2.api_monitors` | one per pool | TCP health monitors |
| `openstack_networking_floatingip_v2.api_floating_ip` | 1 with `api_load_balancer_public`, else 0 | Floating IP on the VIP port; the endpoint host |
| `openstack_compute_servergroup_v2.control_plane_server_group` | 1, 0 with policy `null` | Server group of the control-plane machines |
| `terraform_data.api_endpoint_guard` | 1, 0 with a supplied endpoint | Fails a plan that would move the endpoint |

Data sources: `openstack_networking_subnet_ids_v2.visible_subnets` (every
subnet the identity sees), `openstack_networking_subnet_v2.node_subnet`
(CIDR, family, network, region; read only while `subnet_id` is in that
list, so a destroy survives a deleted subnet),
`openstack_compute_availability_zones_v2.availability_zones`
(only when `availability_zones` is empty), and
`openstack_lb_loadbalancer_v2.api_load_balancer_status` (health).

Security group rules. "Subnet" is the CIDR of `subnet_id`; "node group"
is the node security group. Nodes of one cluster accept all traffic from
each other (CONVENTIONS.md section 8), so any CNI works without port lists
and etcd, kubelet and the rest need no rule of their own; Neutron counts a
port's allowed address pairs as group members, so pod addresses under
`pod_address_pairs` are covered too. The API rows use the backend port:
`cluster_network.api_server_port`, default 6443, and always 6443 with
`rke2`. `api_allowed_cidrs` restricts the listeners only: the amphora
source-NATs every client to its subnet address.

| Group | Rule key | Protocol and ports | From |
| --- | --- | --- | --- |
| control plane | `kube_apiserver-from-subnet` | TCP API port | subnet (the amphora, hairpin through the VIP) |
| control plane | `rke2_supervisor-from-subnet` | TCP 9345 (`rke2`) | subnet |
| node | `any-from-nodes` | any | node group |
| node | `nodeports-tcp`, `nodeports-udp` | TCP and UDP 30000-32767 | subnet (Octavia Service load balancers; see Exceptions) |
| node | `ssh-from-<cidr>` | TCP 22 | each `ssh_allowed_cidrs` entry |
| node (egress) | `IPv4`, `IPv6` | any | anywhere |

## Prerequisites

- **Network.** An existing Neutron network and subnet with DHCP, routed to
  wherever the nodes pull images from, and reachable from the management
  cluster: the endpoint is the internal VIP unless `api_load_balancer_public`
  is set. The
  module never creates or deletes them. With `api_load_balancer_public`, an
  external network for `floating_ip_pool` and a router gateway on the
  subnet's router.
- **Services.** Nova, Neutron with security groups and resource tags,
  Glance, and Octavia with the amphora provider (or set
  `loadbalancer_provider`; see Limitations). Octavia API 2.12 or later for
  `api_allowed_cidrs`.
- **Quotas**, per cluster: 2 security groups and about 6 rules (more with
  SSH CIDRs); 1 load balancer with 1 or 2 listeners, pools and
  monitors, and the amphora VM Octavia boots for it; 1 floating IP with
  `api_load_balancer_public`; 1 server group, with one member per control-plane machine
  (Nova's default member quota is 10).
- **Permissions.** The identity's user needs the `member` role in the
  project. Clouds still on Octavia's legacy policy also require
  `load-balancer_member`. An application credential needs no unrestricted
  flag: the module creates no credentials.
- **Images.** None for this role.

## Inputs

Contract inputs ([cluster.md "Inputs"](https://captf.io/docs/module-author/contract/v1alpha1/cluster.html#inputs)):

| Input | Used for |
| --- | --- |
| `captf_contract` | Validated to be `v1alpha1` |
| `captf_cluster` | Resource names (`captf-<namespace>-<name>-<hash>`) |
| `captf_object` | Unused: `captf_tags` already names the object |
| `captf_cluster_outputs` | Declared with a `null` default, never read (not passed to this role) |
| `captf_tags` | Tags on every taggable resource (see Tags) |
| `control_plane_endpoint` | Non-null: no load balancer, the endpoint is echoed |
| `kubernetes_version` | Unused |
| `control_plane_initialized` | Unused: the module creates nothing inside the workload cluster |
| `cluster_network` | `api_server_port` sets the API port (default 6443); `pods` feeds the rules and the allowed address pairs |

User variables, set in `TerraformCluster.spec.variables`
([Module Variables](https://captf.io/docs/user-guide/variables.html)):

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `additional_tags` | `map(string)` | `{}` | Extra tags on every resource. At most 44; keys follow the Nova metadata key rule, must not start with `captf.io:`, and `<key>=<value>` fits in 255 characters |
| `api_allowed_cidrs` | `list(string)` | `[]` | Clients the API listeners accept, of the subnet's address family. Empty: any client that can route to the VIP. Required with `api_load_balancer_public`; refused with the `ovn` provider. The node subnet is always added |
| `api_load_balancer_public` | `bool` | `false` | Put a floating IP on the VIP and use it as the endpoint |
| `availability_zones` | `list(string)` | `[]` | Nova zones to report as failure domains. Empty: every available zone |
| `control_plane_server_group_policy` | `string` | `"soft-anti-affinity"` | `soft-anti-affinity`, `anti-affinity`, or `null` for no server group |
| `distribution` | `string` | `"kubeadm"` | `kubeadm` or `rke2` (adds the 9345 listener) |
| `floating_ip_pool` | `string` | `null` | External network for the floating IP. Required with `api_load_balancer_public` |
| `loadbalancer_provider` | `string` | `"amphora"` | Octavia provider; `null` takes the cloud's default |
| `node_allowed_address_cidrs` | `list(string)` | `[]` | Extra source CIDRs every node port may send from, for example a kube-vip address |
| `pod_address_pairs` | `bool` | `false` | Add the pod CIDRs to every node port's allowed address pairs, for CNIs that route pods without encapsulation |
| `provider_id_format` | `string` | `"default"` | `default` (`openstack:///<id>`) or `regional` (`openstack://<region>/<id>`), as the cloud controller manager's `OS_CCM_REGIONAL` |
| `region` | `string` | `null` | OpenStack region. `null`: the identity's region |
| `ssh_allowed_cidrs` | `list(string)` | `[]` | CIDRs allowed on TCP 22 of every node |
| `subnet_id` | `string` | `null` | **Required.** UUID of the subnet for the VIP and every node |

## Outputs

| Output | Value |
| --- | --- |
| `control_plane_endpoint` | `{host, port}`: the VIP, or the floating IP with `api_load_balancer_public`, on the API port; the supplied endpoint when one is given |
| `failure_domains` | One entry per zone, `control_plane = true`, no attributes |
| `exports` | See Exports |
| `health` | See Health |
| `api_load_balancer_id` | Not a contract output: the Octavia load balancer's UUID, `null` without one |

## Exports

`exports`, schema `captf.io/openstack-cluster/v1`. Every machine receives
it as `captf_cluster_outputs`; an externally managed TerraformCluster's
machines take the same object from `external_cluster_exports`. Adding a key
keeps the schema; renaming or removing one moves it to `v2`.

| Key | Type | Value |
| --- | --- | --- |
| `schema` | `string` | `"captf.io/openstack-cluster/v1"` |
| `region` | `string` | The cluster's region, the machines' provider region |
| `network_id` | `string` | Network of `subnet_id` |
| `subnet_id` | `string` | `subnet_id` |
| `failure_domains` | `map(object({}))` | One key per availability zone |
| `distribution` | `string` | `kubeadm` or `rke2` (informational) |
| `provider_id_format` | `string` | `default` or `regional` |
| `security_group_ids` | `object({control_plane = list(string), worker = list(string)})` | Groups of each machine kind's port |
| `control_plane_server_group_id` | `string` or `null` | Server group control-plane machines join |
| `node_allowed_address_cidrs` | `list(string)` | Allowed address pairs of every node port |
| `api` | `object({host = string, port = number, pools = map(object({id = string, port = number}))})` or `null` | The endpoint, and the pools control-plane machines join, keyed `kube_apiserver` and `rke2_supervisor`, with the backend port; `null` with a supplied endpoint |

## Identity Secret

The module reads OpenStack credentials only from the identity Secret
([Identities](https://captf.io/docs/user-guide/identities.html)); the
provider block sets nothing but the region. Recommended keys:

| Key | Example | Purpose |
| --- | --- | --- |
| `OS_CLOUD` | `openstack` | The `clouds.yaml` entry to use |
| `OS_CLIENT_CONFIG_FILE` | `/var/run/captf/credentials/clouds.yaml` | Where the provider finds `clouds.yaml` |
| `clouds.yaml` | an application credential entry | Mounted as a file at that path |
| `cacert.pem` | PEM bundle | Optional: a private CA, named by `cacert` in `clouds.yaml` |

Plain `OS_AUTH_URL`, `OS_APPLICATION_CREDENTIAL_ID`,
`OS_APPLICATION_CREDENTIAL_SECRET`, `OS_REGION_NAME` and `OS_CACERT` keys
work too. A full example is in [`examples/identity.yaml`](https://github.com/captf-io/terraform-openstack-cluster/blob/main/examples/identity.yaml).

## Tags

The six `captf_tags` keys and `additional_tags` go on every resource that
takes tags. OpenStack has two shapes:

| Shape | Mapping | Example | Resources |
| --- | --- | --- | --- |
| Neutron and Octavia `tags` | `"<key>=<value>"`, with `/` in the key mapped to `:` | `captf.io:cluster=demo` | security groups, load balancer, listeners, pools, floating IP |
| Nova metadata | `/` in the key mapped to `:` | `captf.io:cluster = demo` | (machine role) |

Not taggable in provider 3.4.0: security group rules, health monitors and
server groups; they belong to a tagged group, pool or project. A tag over
255 characters fails a precondition instead of being truncated.

## Health

From the load balancer's Octavia `provisioning_status`, re-read on every
refresh. `operating_status` is not used: it follows the members, which are
down during every normal control-plane bring-up.

| Octavia state | `state` | `healthy` | `reasons` |
| --- | --- | --- | --- |
| `ACTIVE` | `running` | `true` | `[]` |
| `PENDING_UPDATE` | `running` | `true` | `[]` |
| `PENDING_CREATE` | `pending` | `false` | `LoadBalancerPendingCreate` |
| `ERROR` | `degraded` | `false` | `LoadBalancerError` |
| `PENDING_DELETE` | `terminated` | `false` | `LoadBalancerPendingDelete` |
| `DELETED` | `terminated` | `false` | `LoadBalancerDeleted` |
| load balancer deleted out of band | `terminated` | `false` | `LoadBalancerNotFound` |
| anything else | `unknown` | `false` | `LoadBalancerStatusUnknown` |

`message` names the load balancer and its state. With a supplied endpoint
the health is `running` and healthy: there is nothing of the module's to
observe.

## Limitations

- **The endpoint is fixed.** `subnet_id`, `api_load_balancer_public`,
  `floating_ip_pool`,
  `cluster_network.api_server_port` and `loadbalancer_provider` cannot
  change once the load balancer exists: the plan fails, since CAPI never
  updates the Cluster's endpoint.
- **No hosted control planes.** With a `null` endpoint input the module
  always creates a load balancer and reports its endpoint, which CAPI
  copies first. A control-plane provider that sets the endpoint itself
  later (a hosted control plane) is not supported; supply its endpoint in
  `Cluster.spec.controlPlaneEndpoint` before the first apply instead.
- **Public endpoints and hairpin.** Nodes reach a public endpoint through
  their router, which source-NATs them to its external gateway address.
  Put that address in `api_allowed_cidrs`, with the management cluster's and
  your operators' addresses, or the first control-plane node cannot reach
  itself and `kubeadm init` never finishes.
- **Octavia providers.** The module is designed for the amphora provider.
  The OVN provider rejects `api_allowed_cidrs` (a precondition stops
  that combination, so `api_load_balancer_public` is amphora-only), and
  it keeps client addresses, so only clients on the node subnet or in the
  node group pass the control-plane security group. Its
  hairpin behaviour is not verified (DESIGN.md "Unverified").
- **Switching to a supplied endpoint.** Setting `control_plane_endpoint`
  on a cluster whose module created the load balancer plans its
  destruction; only the destructive-plan approval stops it. The
  controller does not do this itself: with `captf.io/endpoint-source:
  module` it keeps the input `null`.
- **Failure domains follow availability.** Without `availability_zones`,
  a zone Nova marks unavailable drops out of `failure_domains` at the next
  refresh. Pin the list for production clusters.
- **No node identity.** The OpenStack cloud controller manager and Cinder
  CSI need a `cloud.conf` you supply (DESIGN.md decision 4;
  [`examples/cloud-controller-manager.yaml`](https://github.com/captf-io/terraform-openstack-cluster/blob/main/examples/cloud-controller-manager.yaml)).
  Leave the controller manager's `manage-security-groups` off: it would
  edit the node ports' groups behind the machine module.
- **Rule changes replace rules.** Every security group rule attribute
  forces a new rule, so a changed CIDR plans a delete and a create, which
  the destructive-plan guard holds for approval.
- **A deleted subnet.** Plans other than a destroy fail a precondition
  until `subnet_id` names an existing subnet; a destroy still runs.

## Exceptions

- `captf_object`, `kubernetes_version` and `control_plane_initialized` are
  declared and unused (`tflint-ignore`, CONVENTIONS.md section 8).
  `captf_contract` is read only by its validation, which tflint does not
  count.
- NodePorts are open from the node subnet, beyond the API port
  (CONVENTIONS.md section 8): Octavia load balancers for Services of type
  LoadBalancer source-NAT from the subnet, and the alternative, the cloud
  controller manager's `manage-security-groups`, edits the node ports'
  groups behind the machine module.
- No `tfcapi-lint` warning is allowed; `make tfcapi-lint` runs with none.

## Examples

[`examples/`](https://github.com/captf-io/terraform-openstack-cluster/blob/main/examples/) holds the identity, a kubeadm cluster with a
MachineDeployment, and the cloud controller manager's `cloud.conf`. The
smallest `TerraformCluster`:

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha1
kind: TerraformCluster
metadata:
  name: demo
spec:
  source:
    image: ghcr.io/captf-io/openstack-cluster:v0.1.0-opentofu
  identityRef:
    name: openstack
  variables:
    subnet_id: 5c1d7a0e-2b4f-4e83-9a61-0d8f3b2c4e71
```

## Development

The host needs `make`, `podman` (or `docker` with `ENGINE=docker`), `jq` and
Go. Every other tool runs in a digest-pinned container. `make verify` is the
gate. Variables: `RUNTIMES` (default `terraform opentofu`), `ENGINE` and
`PROVIDER_DIR` (default `../cluster-api-provider-terraform`, where
`tfcapi-lint` is built from; the target skips when the directory is absent).

| Target | What it does |
| --- | --- |
| `make help` | Lists the targets |
| `make fmt` | Formats the module with `terraform fmt` and `tofu fmt`, in place |
| `make fmt-check` | Fails on any file the formatters would change |
| `make validate` | `init` and `validate` on both runtimes and on their floors (Terraform 1.5.7, OpenTofu 1.6.3) |
| `make unit-test` | `terraform test` / `tofu test` with mocked providers |
| `make tflint` | `tflint` with the terraform ruleset (preset all) and the cloud ruleset |
| `make tfcapi-lint` | `tfcapi-lint module --strict`, built from `PROVIDER_DIR` |
| `make scan` | `trivy config` over the repository |
| `make check-conventions` | `hack/check-layout.sh` and `hack/check-tags.sh` (CONVENTIONS.md) |
| `make shellcheck` | `shellcheck` over `hack/` and every shell template, rendered with placeholders |
| `make check-headers` | Fails on any source file without the Apache-2.0 license header |
| `make fix-headers` | Adds the license header to every source file missing it |
| `make verify` | All of the above, in parallel groups |
| `make clean` | Removes `build/`; keeps `.cache/` and `.tools/` |

Module images are not built here; [openstack-modules](https://github.com/captf-io/openstack-modules) builds them from
this code.
