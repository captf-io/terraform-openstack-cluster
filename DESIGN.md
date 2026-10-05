# Design: terraform-openstack-cluster

Why this module looks the way it does. Each decision names the evidence it
rests on; anything not yet checked against a real cloud is listed under
"Unverified" and must be confirmed on the first reviewed apply. Decision
and item numbers are shared with the sibling repo
[terraform-openstack-machine](https://github.com/captf-io/terraform-openstack-machine) and
are cited from code comments, so a number that concerns only the other
role is kept as a pointer.

Pins: `terraform-provider-openstack/openstack` 3.4.0. Runtimes: Terraform
>= 1.5, OpenTofu >= 1.6. Conventions: [CONVENTIONS.md](CONVENTIONS.md).
Contract: <https://captf.io/docs/module-author/contract/v1alpha1/>.

Provider facts below come from `providers schema -json` at the pin
(`hack/tf-run.sh schema`) and the provider source at tag `v3.4.0`; "the
provider" means that version.

## Scope

- This repo is the `cluster` role; the `machine` role is in
  [terraform-openstack-machine](https://github.com/captf-io/terraform-openstack-machine).
  There is no `machinepool`: OpenStack
  has no native scaling group (Heat and Senlin are optional services many
  clouds do not deploy), and a pool of individually managed servers is
  what MachineDeployments already provide.
- Bring-your-own network: the network, subnet, router and floating IP
  network exist before the cluster. The cluster role creates security
  groups, the Octavia load balancer and a control-plane server group.
- The API load balancer is internal by default; a floating IP is opt-in
  and needs an explicit allowed-CIDR list.
- No node identity (decision 4).

## Decisions

### 1. API load balancer (Octavia)

- `openstack_lb_loadbalancer_v2` on the subnet, one TCP listener, pool and
  TCP health monitor per port: kube-apiserver and, with
  `distribution = "rke2"`, the supervisor on 9345.
- Ports: the frontend is the endpoint port,
  `cluster_network.api_server_port ?? 6443`. The kube-apiserver backend is
  the same port with kubeadm (templates keep `bindPort` equal), and always
  6443 with RKE2, which ignores `apiServerPort` (contract
  `control-planes/rke2.md`). `api_server_port = 9345` with RKE2 fails a
  precondition: both listeners would share a port.
- Listener `timeout_client_data` and `timeout_member_data` are one hour
  (3,600,000 ms): Octavia's 50 s default cuts idle watches, `kubectl exec`
  and `logs -f`.
- Monitors: delay 10 s, timeout 5 s, two retries up and down, so a single
  member goes healthy in about 20 s.
- `lb_method` is `ROUND_ROBIN`, or `SOURCE_IP_PORT` when the load balancer's
  provider is `ovn`, the only method that provider supports.
- `loadbalancer_provider` defaults to `amphora`: its source NAT gives a
  control-plane node the hairpin path through the VIP that the contract
  requires (cluster.md "Hairpin reachability"), and the security group
  admits the API port from the subnet CIDR for it. `null` takes the cloud's
  default provider. A cloud without amphora fails the first apply with
  Octavia's error rather than building a cluster whose first node never
  reaches itself.
- The load balancer's create timeout is 30 minutes: the provider's default
  is 10 (`resource_openstack_lb_loadbalancer_v2.go`), and an amphora boots
  a VM.
- Listener `allowed_cidrs` (`api_allowed_cidrs`) restricts clients. The variable's CIDRs are
  normalized (`cidrsubnet(c, 0, 0)`), de-duplicated and sorted, the order
  Octavia is expected to return them in (the attribute is a list; see
  "Unverified"), and the node subnet is always added, so restricting the
  listener never locks out nodes that reach an internal VIP directly.
  Empty means `null`: every client. Every entry must be of the subnet's
  address family (precondition): Octavia refuses others
  (`octavia/api/v2/controllers/listener.py`
  `_validate_cidr_compatible_with_vip`). They restrict the listener only:
  the amphora source-NATs clients, so no security group rule names them.
- Public opt-in: `openstack_networking_floatingip_v2` from
  `floating_ip_pool` on the VIP port; the floating IP is the endpoint host.
  `api_load_balancer_public` needs `api_allowed_cidrs` and
  `floating_ip_pool` (preconditions).
  Nodes reach the floating IP through their router, which source-NATs them
  to its gateway address, so that address must be in `api_allowed_cidrs`; the
  README says so. Looking the router up instead would take three more
  data sources (a port by gateway IP, its router, its gateway), any of
  which fails the plan on a subnet whose gateway is not a Neutron router.
- `terraform_data.api_endpoint_guard` records the VIP subnet,
  `api_load_balancer_public`,
  `floating_ip_pool`, the endpoint port and the load balancer's actual
  provider (`loadbalancer_provider` forces a new load balancer) when the
  load balancer is created (`ignore_changes = [input]`), and a
  postcondition fails any later plan that changes them, instead of
  planning a new VIP, floating IP or listener. The provider is compared
  only when the variable is set: `null` means the cloud's default, which
  is what was recorded. CAPI never updates `Cluster.spec.controlPlaneEndpoint` after
  the first copy (cluster.md). No `prevent_destroy`: it would block cluster
  deletion too; CAPTF's destructive-plan guard still holds any replacement
  for approval.

### 2. Security groups

`delete_default_rules = true` on both groups, so behaviour does not depend
on a cloud's default rules. A node group on every node and a control-plane
group on top of it; rules are `openstack_networking_secgroup_rule_v2`
resources over keyed maps, one resource per group and direction. A rule
names a CIDR or one of the two groups, so the keys stay known at plan time.

- Nodes of one cluster accept all traffic from each other (CONVENTIONS.md
  section 8): one any-protocol rule from the node group, so kubelet, etcd,
  CNI encapsulation and native pod routing need no port lists and any CNI
  works. Neutron counts a member port's allowed address pairs as group
  members (`_select_ips_for_remote_group` in
  `neutron/db/securitygroups_rpc_base.py` joins `AllowedAddressPair`), so
  pod addresses under `pod_address_pairs` pass the same rule.
- Control plane: only the API backend port(s) from the subnet CIDR
  (amphora and hairpin): kube-apiserver, and 9345 with RKE2. No rule names
  `api_allowed_cidrs`: the amphora source-NATs every client to its subnet
  address, and the ovn provider cannot take them.
- Nodes, beyond the node group: NodePorts 30000-32767 TCP and UDP from the
  subnet, a listed exception to "nothing else open by default" (Octavia
  Service load balancers source-NAT from the subnet; the alternative,
  the controller manager's `manage-security-groups`, edits the node ports'
  groups behind the machine module), and TCP 22 from `ssh_allowed_cidrs`
  (empty by default).
- `pod_address_pairs` (default false) adds the pod CIDRs to every node
  port's allowed address pairs, for CNIs that route pods unencapsulated
  (Calico without IP-in-IP or VXLAN, cross-subnet modes, Cilium native
  routing); port security otherwise drops pod-sourced packets. Encapsulating
  CNIs send from node addresses only, so it is off by default.
- Egress: one rule per family with no remote prefix, which Neutron reads
  as any address, as its own default egress rules do.
- Allowed address pairs are sent as CIDRs and read back as sent: Neutron
  stores them as `AuthenticIPNetwork`, which keeps the input's format
  (`neutron/objects/port/extensions/allowedaddresspairs.py`), so the set
  does not diff.
- CIDRs are normalized with `cidrsubnet(c, 0, 0)`. Neutron does not
  normalize them itself (`_validate_ip_prefix` in
  `neutron/db/securitygroups_db.py` keeps host bits), so without it the
  same range written two ways would be two rules.
- Every rule attribute forces a new rule in the provider; keys and
  descriptions are fixed strings, so a changed CIDR replaces only its own
  rule.

### 3. Placement

Failure domains are Nova availability zones: `availability_zones`, or every
available zone from `data.openstack_compute_availability_zones_v2` (the
non-detailed list, which leaves out the `internal` zone). All are eligible
for the control plane. Without the variable, a zone Nova marks unavailable
drops out at the next refresh; the README recommends pinning the list.
Control-plane machines join a server group with the `soft-anti-affinity`
policy by default (configurable to `anti-affinity` or none), which spreads
them across hosts on single-zone clouds. A zone dropping out of the list never moves a machine: a machine's
inputs, its `captf_cluster_outputs` included, are pinned at its first
apply and re-fed unchanged to every refresh, drift and destroy
(machine.md "Lifecycle"), so its zone and the precondition that checks
it see the same list for the machine's whole life. Machines without a
requested failure domain pick
`sort(zones)[parseint(sha256(machine_name)[:8], 16) mod len(zones)]`
(CONVENTIONS.md section 11).

### 4. No node identity

The OpenStack cloud controller manager and Cinder CSI need a `cloud.conf`
with credentials inside the workload cluster. The modules do not create
them:

- an application credential belongs to the user Terraform runs as, so its
  lifetime and roles are tied to that user;
- Keystone refuses to let an application-credential session create another
  application credential unless the parent is unrestricted;
- the secret would sit in cluster state, and exports must not carry
  secrets.

The operator supplies `cloud.conf` (ClusterResourceSet or an add-on) with a
dedicated, ideally access-rule-restricted, application credential.
`examples/cloud-controller-manager.yaml` shows how.

### 5. Machine

The server, its port and the control-plane pool membership are the machine role. See [DESIGN.md of terraform-openstack-machine](https://github.com/captf-io/terraform-openstack-machine/blob/main/DESIGN.md).

### 6. Cluster health

- Cluster health from the load balancer's Octavia `provisioning_status`,
  read by `data.openstack_lb_loadbalancer_v2.api_load_balancer_status`;
  never `operating_status`, which follows member health
  (CONVENTIONS.md section 10). `PENDING_UPDATE` is running and healthy:
  Octavia passes through it on every member change, while still serving.
  An earlier draft reported only the load balancer's presence, on the
  grounds that reading a vanished load balancer would fail the refresh;
  "Out-of-band deletes" shows it does not when the read is counted.

Provider_id, addresses and machine health belong to the machine role.
See [DESIGN.md of terraform-openstack-machine](https://github.com/captf-io/terraform-openstack-machine/blob/main/DESIGN.md), decision 6.

### 7. Tags

- Nova server metadata keys allow `[a-zA-Z0-9-_:. ]`, no `/`
  (`nova/api/validation/parameter_types.py` `metadata`): keys map `/` to
  `:` (`captf.io:cluster`). Neutron and Octavia tags use the same mapped
  key, as `"<key>=<value>"` strings.
- Nova server tags (`^[^,/]*$`, at most 60 characters) cannot carry the
  captf tags and are not used.
- Neutron tags: at most 255 characters each and 50 per resource
  (`neutron/extensions/tagging.py` `MAX_TAG_LEN`, `MAX_TAGS_COUNT`), so
  `additional_tags` takes at most 44, and a longer pair fails a
  precondition rather than being truncated.
- Taggable in 3.4.0 (schema `tags`): security groups, load balancer,
  listeners, pools, members, floating IP, port. Not taggable: security
  group rules, monitors, server groups. The server carries metadata
  instead (`hack/tags.json` exemption).

### 8. Credentials

The provider block sets only `region` (cluster: `var.region`; machine: the
cluster's exported region). Identity Secret: `OS_CLOUD` and
`OS_CLIENT_CONFIG_FILE=/var/run/captf/credentials/clouds.yaml`, with
`clouds.yaml` (application credential) and an optional `cacert.pem` as file
keys; or the plain `OS_AUTH_URL`, `OS_APPLICATION_CREDENTIAL_ID`,
`OS_APPLICATION_CREDENTIAL_SECRET`, `OS_REGION_NAME`, `OS_CACERT`
variables. gophercloud/utils `clientconfig.FindAndReadCloudsYAML` reads
`OS_CLIENT_CONFIG_FILE` first, and the provider takes the region from the
`clouds.yaml` entry when none is set (`terraform/auth/config.go`).

### 9. Out-of-band deletes

When a refresh finds a resource gone, it drops it from state. What a
reference to it evaluates to then was checked with a `local_file` stand-in
on Terraform 1.16.4 and OpenTofu 1.12.6 (`apply`, delete the file,
`apply -refresh-only`), with identical results on both:

- a single resource (no `count`) evaluates to unknown, so every output
  built from it is stored as `null`;
- a counted resource evaluates to an empty tuple, a known value:
  `length(r) == 0` is true and `one(r[*].id)` is `null`;
- `r[0]` on that empty tuple fails the refresh when it appears in a data
  source argument or a condition (managed resource arguments are not
  evaluated in refresh-only mode).

So the server, its port and both security groups have `count = 1`, and
the load balancer its natural count;
both status data sources are counted with `count = length(<resource>)`;
nothing indexes `[0]` outside `try()`. A deleted server then reports
`provider_id = null` and `health.state = "terminated"`
(`ServerNotFound`), a deleted load balancer `terminated`
(`LoadBalancerNotFound`).

Data sources must not fail once a brought resource is gone, because every
destroy refreshes them (CONVENTIONS.md section 9). The subnet is read by
`openstack_networking_subnet_v2` only while
`openstack_networking_subnet_ids_v2` lists it (an empty listing never
fails); other plans then fail a precondition naming `subnet_id`, which a
destroy skips.

### 10. Images

The machine image carries no capacity labels. See [DESIGN.md of terraform-openstack-machine](https://github.com/captf-io/terraform-openstack-machine/blob/main/DESIGN.md).

### 11. Tests

Mocked tests per CONVENTIONS.md section 14, green on Terraform 1.16.4 and
OpenTofu 1.12.6. Two portability findings beyond the conventions:

- OpenTofu 1.12.6 does not resolve `run.<name>` (or even `output.<name>`
  in the same condition) in an `assert`; it does in a run's `variables`.
  `reapply_is_stable` passes the previous run's outputs as variables.
- OpenTofu rejects a mock default for an attribute the configuration sets
  ("overriding configuration values is not allowed"); Terraform ignores
  it. Mock defaults cover computed attributes only.

### 12. Bootstrap payload in instance metadata

Bootstrap payloads are handled by the machine role. See [DESIGN.md of terraform-openstack-machine](https://github.com/captf-io/terraform-openstack-machine/blob/main/DESIGN.md).

## Exports (`captf.io/openstack-cluster/v1`)

```hcl
{
  schema                        = "captf.io/openstack-cluster/v1"
  region                        = "<region>"
  network_id                    = "<uuid>"
  subnet_id                     = "<uuid>"
  failure_domains               = { "<az>" = {} }
  distribution                  = "kubeadm" | "rke2"
  provider_id_format            = "default" | "regional"
  security_group_ids            = { control_plane = ["<cp>", "<node>"], worker = ["<node>"] }
  control_plane_server_group_id = "<uuid>" # null without a server group
  node_allowed_address_cidrs    = [...]
  # null for a user-supplied endpoint; rke2_supervisor only with rke2
  api = {
    host  = "<VIP or floating IP>"
    port  = 6443
    pools = { kube_apiserver = { id = "<uuid>", port = 6443 }, rke2_supervisor = { id = "<uuid>", port = 9345 } }
  }
}
```

## Unverified

1. Octavia OVN provider: hairpin from a member to its own VIP, and the
   `SOURCE_IP_PORT` pool method. Verified from source: it rejects
   `allowed_cidrs` (`ovn_octavia_provider/driver.py`
   `_check_for_allowed_cidrs`), so a precondition refuses that
   combination.
2. Octavia tag limits (assumed equal to Neutron's).
3. See [terraform-openstack-machine](https://github.com/captf-io/terraform-openstack-machine/blob/main/DESIGN.md).
4. See [terraform-openstack-machine](https://github.com/captf-io/terraform-openstack-machine/blob/main/DESIGN.md).
5. See [terraform-openstack-machine](https://github.com/captf-io/terraform-openstack-machine/blob/main/DESIGN.md).
6. Octavia returning a listener's `allowed_cidrs` in sorted order (the
   provider attribute is a list; another order is a perpetual in-place
   diff).
7. Nodes reaching a public endpoint source-NATed to the router's gateway
   address, so that address must be in `api_allowed_cidrs`.
8. See [terraform-openstack-machine](https://github.com/captf-io/terraform-openstack-machine/blob/main/DESIGN.md).
9. The OpenStack cloud controller manager v1.34.1 manifests with the
   control-plane node selector changed to `""`, as
   `examples/cloud-controller-manager.yaml` describes.
10. Neutron's ML2/OVN driver counting allowed address pairs as remote
    group members like the iptables/OVS driver does (verified in Neutron's
    RPC source only), which native pod routing relies on.

## Rejected alternatives

- A machinepool role (no native group).
- Creating application credentials (lifetime, Keystone restriction, state
  secret).
- Nova server tags for captf tags (character and length limits).
- Cluster health from load balancer presence alone (an `ERROR` load
  balancer would read healthy).
- `prevent_destroy` on the load balancer (blocks cluster deletion).
