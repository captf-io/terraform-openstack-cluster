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

# The API endpoint, its listeners and the CIDRs they and the security groups
# admit (DESIGN.md decisions 1 and 2).
locals {
  # A user or control-plane-provider endpoint means no load balancer
  # (cluster.md "control_plane_endpoint (input)").
  create_load_balancer = var.control_plane_endpoint == null

  # The frontend port is the endpoint port. The backend port is
  # api_server_port ?? 6443, kept equal to the KubeadmConfig bindPort by
  # the templates; RKE2 always serves on 6443 and ignores apiServerPort
  # (cluster.md "Control-plane provider requirements").
  api_server_port = coalesce(try(var.cluster_network.api_server_port, null), 6443)
  api_listener_ports = {
    kube_apiserver = {
      frontend = local.api_server_port
      backend  = var.distribution == "rke2" ? 6443 : local.api_server_port
    }
    rke2_supervisor = { frontend = 9345, backend = 9345 }
  }
  # RKE2 joins through the supervisor on 9345 of the same host as the
  # endpoint (control-planes/rke2.md "Networking and load balancer").
  api_ports = { for k, v in local.api_listener_ports : k => v if k != "rke2_supervisor" || var.distribution == "rke2" }

  # The subnet is read only while it exists (data_node_subnet.tf); these
  # fall back, so a destroy after it is gone still plans.
  subnet_found = length(data.openstack_networking_subnet_v2.node_subnet) == 1
  subnet_cidr  = try(cidrsubnet(data.openstack_networking_subnet_v2.node_subnet[0].cidr, 0, 0), null)
  # Rules naming a security group instead of a CIDR need the family.
  subnet_ethertype = try(data.openstack_networking_subnet_v2.node_subnet[0].ip_version, 4) == 6 ? "IPv6" : "IPv4"

  # cidrsubnet(c, 0, 0) normalizes 10.0.0.1/8 to 10.0.0.0/8, so one range
  # written two ways is one rule and one listener entry, not two.
  api_allowed_cidrs = sort(distinct([for c in var.api_allowed_cidrs : cidrsubnet(c, 0, 0)]))
  pod_cidrs         = distinct([for c in coalesce(try(var.cluster_network.pods, null), []) : cidrsubnet(c, 0, 0)])
  ssh_allowed_cidrs = distinct([for c in var.ssh_allowed_cidrs : cidrsubnet(c, 0, 0)])
  # Sorted, the order Octavia is expected to return them in, so the list
  # attribute does not diff (DESIGN.md "Unverified"). The node subnet is
  # always in: nodes reach an internal VIP from it, and a restricted
  # listener must not lock them out.
  listener_allowed_cidrs = length(local.api_allowed_cidrs) == 0 ? null : sort(distinct(compact(concat(local.api_allowed_cidrs, [local.subnet_cidr]))))

  node_allowed_address_cidrs = sort(distinct(concat(
    [for c in var.node_allowed_address_cidrs : cidrsubnet(c, 0, 0)],
    var.pod_address_pairs ? local.pod_cidrs : [],
  )))

  # What fixes the endpoint once it exists: the VIP's subnet, whether the
  # host is a floating IP and from which pool, and the frontend port. The
  # guard adds the load balancer's provider (api_endpoint_guard.tf).
  api_endpoint_identity = {
    subnet_id                = var.subnet_id
    api_load_balancer_public = var.api_load_balancer_public
    floating_ip_pool         = var.api_load_balancer_public ? var.floating_ip_pool : null
    port                     = local.api_server_port
  }

  # one() over a splat is null, never an error, when the resource has no
  # instance, so neither branch can fail a refresh.
  api_endpoint_host = (var.api_load_balancer_public
    ? one(openstack_networking_floatingip_v2.api_floating_ip[*].address)
    : one(openstack_lb_loadbalancer_v2.api_load_balancer[*].vip_address)
  )
  api_endpoint = local.create_load_balancer && local.api_endpoint_host != null ? {
    host = local.api_endpoint_host
    port = local.api_server_port
  } : null
}
