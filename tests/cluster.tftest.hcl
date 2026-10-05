# Copyright 2026 The CAPTF Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Unit tests of the cluster role with a mocked OpenStack provider: nothing
# reaches a cloud. Plan-only runs come first, while the state is empty; the
# apply runs after them share one state, as successive CAPTF applies do.
# Run names follow CONVENTIONS.md section 14.

mock_provider "openstack" {
  mock_data "openstack_networking_subnet_ids_v2" {
    defaults = {
      ids = ["5c1d7a0e-2b4f-4e83-9a61-0d8f3b2c4e71"]
    }
  }
  mock_data "openstack_networking_subnet_v2" {
    defaults = {
      id          = "5c1d7a0e-2b4f-4e83-9a61-0d8f3b2c4e71"
      network_id  = "9e4b2c71-6a3d-4f05-8b19-7c2e5d0a6f38"
      cidr        = "10.6.0.0/24"
      gateway_ip  = "10.6.0.1"
      ip_version  = 4
      region      = "RegionOne"
      enable_dhcp = true
    }
  }
  mock_data "openstack_compute_availability_zones_v2" {
    defaults = {
      names  = ["az-1", "az-2", "az-3"]
      region = "RegionOne"
    }
  }
  mock_data "openstack_lb_loadbalancer_v2" {
    defaults = {
      provisioning_status = "ACTIVE"
      operating_status    = "ONLINE"
      region              = "RegionOne"
    }
  }
  # No id defaults: reapply_is_stable proves ids survive a second apply.
  mock_resource "openstack_lb_loadbalancer_v2" {
    defaults = {
      vip_address    = "10.6.0.10"
      vip_port_id    = "0b6e8f3a-1c2d-4e5f-8a9b-7c6d5e4f3a2b"
      vip_network_id = "9e4b2c71-6a3d-4f05-8b19-7c2e5d0a6f38"
      region         = "RegionOne"
    }
  }
  mock_resource "openstack_networking_floatingip_v2" {
    defaults = {
      address  = "203.0.113.10"
      fixed_ip = "10.6.0.10"
    }
  }
}

# Every contract input the controller passes to the cluster role.
# captf_cluster_outputs is not passed to it (common.md).
variables {
  captf_contract = "v1alpha1"
  captf_cluster  = { name = "demo", namespace = "team-a" }
  captf_object   = { kind = "TerraformCluster", name = "demo", namespace = "team-a" }
  captf_tags = {
    "captf.io/cluster"    = "demo"
    "captf.io/namespace"  = "team-a"
    "captf.io/kind"       = "TerraformCluster"
    "captf.io/name"       = "demo"
    "captf.io/managed-by" = "captf"
    "captf.io/template"   = ""
  }
  control_plane_endpoint    = null
  kubernetes_version        = "v1.33.1"
  control_plane_initialized = false
  cluster_network = {
    pods            = ["192.168.0.0/16"]
    services        = ["10.128.0.0/12"]
    service_domain  = "cluster.local"
    api_server_port = 6443
  }

  subnet_id = "5c1d7a0e-2b4f-4e83-9a61-0d8f3b2c4e71"
}

run "user_endpoint_skips_load_balancer" {
  command = plan

  variables {
    control_plane_endpoint = { host = "api.demo.example.com", port = 443 }
  }

  assert {
    condition = (
      length(openstack_lb_loadbalancer_v2.api_load_balancer) == 0
      && length(openstack_lb_listener_v2.api_listeners) == 0
      && length(openstack_lb_pool_v2.api_pools) == 0
      && length(openstack_lb_monitor_v2.api_monitors) == 0
      && length(openstack_networking_floatingip_v2.api_floating_ip) == 0
      && length(terraform_data.api_endpoint_guard) == 0
      && length(data.openstack_lb_loadbalancer_v2.api_load_balancer_status) == 0
    )
    error_message = "A supplied control_plane_endpoint must create no load balancer, listener, pool, monitor, floating IP or guard."
  }
  assert {
    condition     = output.control_plane_endpoint == { host = "api.demo.example.com", port = 443 }
    error_message = "control_plane_endpoint must echo the supplied endpoint."
  }
  assert {
    condition     = output.exports.api == null
    error_message = "exports.api must be null without a load balancer: machines have no pool to join."
  }
  assert {
    condition     = output.health.state == "running" && output.health.healthy && length(output.health.reasons) == 0
    error_message = "health must be running and healthy without a load balancer to observe."
  }
  assert {
    condition     = contains(keys(openstack_networking_secgroup_rule_v2.control_plane_ingress_rules), "kube_apiserver-from-subnet")
    error_message = "The control plane must still accept the API port: the supplied endpoint forwards to it."
  }
}

run "api_server_port_override" {
  command = plan

  variables {
    cluster_network = {
      pods            = ["192.168.0.0/16"]
      services        = ["10.128.0.0/12"]
      service_domain  = "cluster.local"
      api_server_port = 8443
    }
  }

  assert {
    condition     = openstack_lb_listener_v2.api_listeners["kube_apiserver"].protocol_port == 8443
    error_message = "The API listener must listen on cluster_network.api_server_port."
  }
  assert {
    condition     = openstack_networking_secgroup_rule_v2.control_plane_ingress_rules["kube_apiserver-from-subnet"].port_range_min == 8443 && openstack_networking_secgroup_rule_v2.control_plane_ingress_rules["kube_apiserver-from-subnet"].port_range_max == 8443
    error_message = "With kubeadm the backend port follows api_server_port (bindPort), and the security group must open it."
  }
  assert {
    condition     = terraform_data.api_endpoint_guard[0].input.port == 8443
    error_message = "The endpoint guard must record the endpoint port."
  }
}

run "rke2_adds_supervisor" {
  command = plan

  variables {
    distribution = "rke2"
    cluster_network = {
      pods            = ["192.168.0.0/16"]
      services        = ["10.128.0.0/12"]
      service_domain  = "cluster.local"
      api_server_port = 8443
    }
  }

  assert {
    condition     = sort(keys(openstack_lb_listener_v2.api_listeners)) == tolist(["kube_apiserver", "rke2_supervisor"])
    error_message = "RKE2 needs a second listener, for the supervisor."
  }
  assert {
    condition     = openstack_lb_listener_v2.api_listeners["rke2_supervisor"].protocol_port == 9345 && openstack_lb_listener_v2.api_listeners["kube_apiserver"].protocol_port == 8443
    error_message = "The supervisor listens on 9345; kube-apiserver on the endpoint port."
  }
  assert {
    condition     = openstack_networking_secgroup_rule_v2.control_plane_ingress_rules["kube_apiserver-from-subnet"].port_range_min == 6443
    error_message = "RKE2 serves the API on 6443 whatever apiServerPort says: the backend port must be 6443."
  }
  assert {
    condition     = sort(keys(openstack_networking_secgroup_rule_v2.control_plane_ingress_rules)) == tolist(["kube_apiserver-from-subnet", "rke2_supervisor-from-subnet"])
    error_message = "RKE2 control planes take 6443 and 9345 from the subnet; etcd and the rest come with the node group."
  }
}

run "failure_domains_pinned" {
  command = plan

  variables {
    availability_zones = ["zone-b", "zone-a", "zone-b"]
  }

  assert {
    condition     = length(data.openstack_compute_availability_zones_v2.availability_zones) == 0
    error_message = "Pinned availability_zones must not read the zone list."
  }
  assert {
    condition     = output.failure_domains == [{ name = "zone-b", control_plane = true, attributes = {} }, { name = "zone-a", control_plane = true, attributes = {} }]
    error_message = "failure_domains must be the pinned zones, de-duplicated, in the given order."
  }
}

run "ipv6_subnet" {
  command = plan

  override_data {
    target = data.openstack_networking_subnet_v2.node_subnet
    values = {
      cidr       = "2001:db8:6::/64"
      ip_version = 6
      network_id = "9e4b2c71-6a3d-4f05-8b19-7c2e5d0a6f38"
      region     = "RegionOne"
    }
  }

  assert {
    condition     = openstack_networking_secgroup_rule_v2.node_ingress_rules["any-from-nodes"].ethertype == "IPv6" && openstack_networking_secgroup_rule_v2.node_ingress_rules["nodeports-tcp"].ethertype == "IPv6"
    error_message = "Group rules and subnet rules must follow the subnet's address family."
  }
  assert {
    condition     = openstack_networking_secgroup_rule_v2.control_plane_ingress_rules["kube_apiserver-from-subnet"].remote_ip_prefix == "2001:db8:6::/64"
    error_message = "The API rule must name the IPv6 subnet."
  }
}

run "native_pod_routing" {
  command = plan

  variables {
    pod_address_pairs = true
  }

  assert {
    condition     = output.exports.node_allowed_address_cidrs == tolist(["192.168.0.0/16"])
    error_message = "Native pod routing must export the pod CIDR as an allowed address pair of every node port."
  }
  assert {
    condition     = sort(keys(openstack_networking_secgroup_rule_v2.node_ingress_rules)) == tolist(["any-from-nodes", "nodeports-tcp", "nodeports-udp"])
    error_message = "Pod traffic needs no rule of its own: Neutron counts allowed address pairs as members of the node group."
  }
}

run "rules_are_unique" {
  command = plan

  # One SSH range written two ways: Neutron refuses duplicate rules.
  variables {
    ssh_allowed_cidrs = ["192.0.2.1/24", "192.0.2.0/24"]
  }

  assert {
    condition     = length([for k in keys(openstack_networking_secgroup_rule_v2.node_ingress_rules) : k if startswith(k, "ssh-from-")]) == 1
    error_message = "One SSH range written two ways is one rule."
  }
}

run "happy_path" {
  assert {
    condition     = output.control_plane_endpoint == { host = "10.6.0.10", port = 6443 }
    error_message = "control_plane_endpoint must be the internal VIP on the API port."
  }
  assert {
    condition = output.failure_domains == [
      { name = "az-1", control_plane = true, attributes = {} },
      { name = "az-2", control_plane = true, attributes = {} },
      { name = "az-3", control_plane = true, attributes = {} },
    ]
    error_message = "failure_domains must list every available zone, all eligible for the control plane."
  }
  assert {
    condition = (
      output.exports.schema == "captf.io/openstack-cluster/v1"
      && output.exports.region == "RegionOne"
      && output.exports.network_id == "9e4b2c71-6a3d-4f05-8b19-7c2e5d0a6f38"
      && output.exports.subnet_id == "5c1d7a0e-2b4f-4e83-9a61-0d8f3b2c4e71"
      && output.exports.distribution == "kubeadm"
      && output.exports.provider_id_format == "default"
      && length(output.exports.node_allowed_address_cidrs) == 0
    )
    error_message = "exports must carry the schema, region, network, subnet, distribution and provider ID format, and no allowed address CIDRs by default."
  }
  assert {
    condition = (
      output.exports.security_group_ids.control_plane == [openstack_networking_secgroup_v2.control_plane_security_group[0].id, openstack_networking_secgroup_v2.node_security_group[0].id]
      && output.exports.security_group_ids.worker == [openstack_networking_secgroup_v2.node_security_group[0].id]
      && output.exports.control_plane_server_group_id == openstack_compute_servergroup_v2.control_plane_server_group[0].id
    )
    error_message = "exports must give control-plane machines both groups, workers the node group, and the server group."
  }
  assert {
    condition     = jsonencode(output.exports.api) == jsonencode({ host = "10.6.0.10", port = 6443, pools = { kube_apiserver = { id = openstack_lb_pool_v2.api_pools["kube_apiserver"].id, port = 6443 } } })
    error_message = "exports.api must carry the endpoint and name the kube-apiserver pool with its backend port."
  }
  assert {
    condition     = output.health.state == "running" && output.health.healthy && output.health.message == "Octavia load balancer ${openstack_lb_loadbalancer_v2.api_load_balancer[0].id} is ACTIVE" && length(output.health.reasons) == 0
    error_message = "An ACTIVE load balancer is running and healthy, and the message names the state."
  }
  assert {
    condition     = output.api_load_balancer_id == openstack_lb_loadbalancer_v2.api_load_balancer[0].id
    error_message = "api_load_balancer_id must be the load balancer's id."
  }
  assert {
    condition = (
      openstack_lb_loadbalancer_v2.api_load_balancer[0].vip_subnet_id == var.subnet_id
      && openstack_lb_loadbalancer_v2.api_load_balancer[0].loadbalancer_provider == "amphora"
      && openstack_lb_loadbalancer_v2.api_load_balancer[0].name == "captf-team-a-demo-1960e37c-api"
    )
    error_message = "The load balancer must be an amphora on the node subnet, named from the cluster key."
  }
  assert {
    condition = (
      sort(keys(openstack_lb_listener_v2.api_listeners)) == tolist(["kube_apiserver"])
      && openstack_lb_listener_v2.api_listeners["kube_apiserver"].protocol == "TCP"
      && openstack_lb_listener_v2.api_listeners["kube_apiserver"].allowed_cidrs == null
      && openstack_lb_listener_v2.api_listeners["kube_apiserver"].timeout_client_data == 3600000
      && openstack_lb_listener_v2.api_listeners["kube_apiserver"].timeout_member_data == 3600000
    )
    error_message = "kubeadm needs one TCP listener, open to every client of the internal VIP, with one-hour data timeouts."
  }
  assert {
    condition     = openstack_lb_pool_v2.api_pools["kube_apiserver"].lb_method == "ROUND_ROBIN" && openstack_lb_monitor_v2.api_monitors["kube_apiserver"].type == "TCP"
    error_message = "The amphora pool balances round robin, with a TCP monitor."
  }
  assert {
    condition     = length(openstack_networking_floatingip_v2.api_floating_ip) == 0
    error_message = "The load balancer is internal by default."
  }
  assert {
    condition = (
      openstack_networking_secgroup_v2.node_security_group[0].delete_default_rules
      && openstack_networking_secgroup_v2.control_plane_security_group[0].delete_default_rules
    )
    error_message = "Both groups must drop Neutron's default rules."
  }
  assert {
    condition = sort(keys(openstack_networking_secgroup_rule_v2.control_plane_ingress_rules)) == sort([
      "kube_apiserver-from-subnet",
    ])
    error_message = "kubeadm control planes take only the API from the subnet; everything else between nodes comes with the node group."
  }
  assert {
    condition     = openstack_networking_secgroup_rule_v2.node_ingress_rules["any-from-nodes"].remote_group_id == openstack_networking_secgroup_v2.node_security_group[0].id && openstack_networking_secgroup_rule_v2.node_ingress_rules["any-from-nodes"].protocol == null
    error_message = "Nodes accept every protocol from the node group, and from nothing wider (CONVENTIONS.md section 8)."
  }
  assert {
    condition     = sort(keys(openstack_networking_secgroup_rule_v2.node_ingress_rules)) == tolist(["any-from-nodes", "nodeports-tcp", "nodeports-udp"])
    error_message = "Nodes take everything from each other and NodePorts from the subnet; no SSH by default."
  }
  assert {
    condition     = sort(keys(openstack_networking_secgroup_rule_v2.node_egress_rules)) == tolist(["IPv4", "IPv6"])
    error_message = "Egress must be explicit for both families."
  }
  assert {
    condition     = jsonencode(terraform_data.api_endpoint_guard[0].input) == jsonencode({ api_load_balancer_public = false, floating_ip_pool = null, loadbalancer_provider = "amphora", port = 6443, subnet_id = var.subnet_id })
    error_message = "The guard must record what fixes the endpoint."
  }
  assert {
    condition     = openstack_compute_servergroup_v2.control_plane_server_group[0].policies == tolist(["soft-anti-affinity"])
    error_message = "Control-plane machines spread with soft anti-affinity by default."
  }
}

run "tags_on_taggable_resources" {
  command = plan

  variables {
    additional_tags = { team = "platform" }
  }

  assert {
    condition = alltrue([
      for tags in concat(
        [openstack_networking_secgroup_v2.node_security_group[0].tags, openstack_networking_secgroup_v2.control_plane_security_group[0].tags],
        [for lb in openstack_lb_loadbalancer_v2.api_load_balancer : lb.tags],
        [for l in openstack_lb_listener_v2.api_listeners : l.tags],
        [for p in openstack_lb_pool_v2.api_pools : p.tags],
      ) : setintersection(tags, ["captf.io:cluster=demo", "captf.io:namespace=team-a", "captf.io:kind=TerraformCluster", "captf.io:name=demo", "captf.io:managed-by=captf", "captf.io:template=", "team=platform"]) == toset(tags) && length(tags) == 7
    ])
    error_message = "Every taggable resource must carry the captf tags as captf.io:<key>=<value> strings, plus additional_tags."
  }
}

run "reapply_is_stable" {
  # run.<name> works in OpenTofu's run variables but not in its assertions.
  variables {
    previous_load_balancer_id = run.happy_path.api_load_balancer_id
    previous_exports          = run.happy_path.exports
    previous_endpoint         = run.happy_path.control_plane_endpoint
  }

  assert {
    condition     = output.api_load_balancer_id == var.previous_load_balancer_id
    error_message = "A second identical apply must keep the load balancer."
  }
  assert {
    condition     = jsonencode(output.exports) == jsonencode(var.previous_exports)
    error_message = "A second identical apply must keep every exported id: groups, server group and pools."
  }
  assert {
    condition     = jsonencode(output.control_plane_endpoint) == jsonencode(var.previous_endpoint)
    error_message = "A second identical apply must keep the endpoint."
  }
}

run "exports_shape" {
  assert {
    condition = sort(keys(output.exports)) == sort([
      "schema", "region", "network_id", "subnet_id", "failure_domains", "distribution", "provider_id_format",
      "security_group_ids", "control_plane_server_group_id", "node_allowed_address_cidrs", "api",
    ])
    error_message = "exports must hold exactly the keys of captf.io/openstack-cluster/v1 (README \"Exports\")."
  }
  assert {
    condition     = jsonencode(output.exports.failure_domains) == jsonencode({ az-1 = {}, az-2 = {}, az-3 = {} })
    error_message = "exports.failure_domains must map each zone to an empty attribute object."
  }
  assert {
    condition     = sort(keys(output.exports.security_group_ids)) == tolist(["control_plane", "worker"])
    error_message = "exports.security_group_ids must hold the control_plane and worker lists."
  }
  assert {
    condition     = alltrue([for p in values(output.exports.api.pools) : floor(p.port) == p.port])
    error_message = "Exported ports must be integers: exports are hashed into every machine's inputs."
  }
}

run "node_identity_byo" {
  # DESIGN.md decision 4: no node identity. The cloud controller manager's
  # cloud.conf is the operator's, so nothing secret may reach the exports,
  # which are stored in clear in every machine's inputs.
  assert {
    condition     = length([for k in keys(output.exports) : k if can(regex("(?i)credential|secret|password|token|key$", k))]) == 0
    error_message = "exports must carry no credential."
  }
}

run "rejects_api_server_port_change" {
  command = plan

  variables {
    cluster_network = {
      pods            = ["192.168.0.0/16"]
      services        = ["10.128.0.0/12"]
      service_domain  = "cluster.local"
      api_server_port = 8443
    }
  }

  expect_failures = [terraform_data.api_endpoint_guard]
}

run "rejects_loadbalancer_provider_change" {
  command = plan

  variables {
    loadbalancer_provider = "ovn"
  }

  expect_failures = [terraform_data.api_endpoint_guard]
}

run "rejects_subnet_id_change" {
  command = plan

  override_data {
    target = data.openstack_networking_subnet_ids_v2.visible_subnets
    values = { ids = ["5c1d7a0e-2b4f-4e83-9a61-0d8f3b2c4e71", "7a3e9c50-1f2b-4d6e-8c4a-2b9d0e1f3c5a"] }
  }

  variables {
    subnet_id = "7a3e9c50-1f2b-4d6e-8c4a-2b9d0e1f3c5a"
  }

  expect_failures = [terraform_data.api_endpoint_guard]
}
