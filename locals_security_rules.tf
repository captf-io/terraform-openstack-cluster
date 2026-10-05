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

# Security group rules as keyed maps, one entry per Neutron rule (DESIGN.md
# decision 2). Every rule attribute forces a new rule, so keys and
# descriptions are fixed strings.
locals {
  # The API backend port(s) of control-plane nodes, from the node subnet:
  # the amphora source-NATs every client to its own subnet address, which
  # is also how a control-plane node reaches itself through the VIP
  # (hairpin, cluster.md "Hairpin reachability"). No rule names
  # api_allowed_cidrs: they restrict the listener only.
  control_plane_ingress_rules = {
    for name, p in local.api_ports : "${name}-from-subnet" => {
      description      = "${name} from the node subnet (load balancer, nodes)"
      protocol         = "tcp"
      port_range_min   = p.backend
      port_range_max   = p.backend
      remote_ip_prefix = local.subnet_cidr
    }
  }

  # Every node, the control plane included. A rule names a CIDR, or the
  # node group itself when remote_ip_prefix is null.
  node_ingress_rules = merge(
    {
      # Nodes of one cluster accept all traffic from each other
      # (CONVENTIONS.md section 8): kubelet, etcd, CNI encapsulation and
      # native pod routing alike, so any CNI works without port lists.
      # Neutron counts a member port's allowed address pairs as group
      # members, so pod addresses under pod_address_pairs are covered.
      any-from-nodes = {
        description      = "Any protocol between the cluster's nodes"
        protocol         = null
        port_range_min   = null
        port_range_max   = null
        remote_ip_prefix = null
      }
      # NodePort Services, reached by Octavia Service load balancers, which
      # source-NAT from the node subnet (README "Exceptions").
      nodeports-tcp = {
        description      = "NodePort Services (TCP) from the node subnet"
        protocol         = "tcp"
        port_range_min   = 30000
        port_range_max   = 32767
        remote_ip_prefix = local.subnet_cidr
      }
      nodeports-udp = {
        description      = "NodePort Services (UDP) from the node subnet"
        protocol         = "udp"
        port_range_min   = 30000
        port_range_max   = 32767
        remote_ip_prefix = local.subnet_cidr
      }
    },
    { for c in local.ssh_allowed_cidrs : "ssh-from-${c}" => {
      description      = "SSH from an allowed CIDR"
      protocol         = "tcp"
      port_range_min   = 22
      port_range_max   = 22
      remote_ip_prefix = c
    } },
  )

  # delete_default_rules removes Neutron's default egress rules too, so
  # both families are explicit: nodes pull images and reach the OpenStack
  # APIs. Neutron's own defaults are the same two rules.
  node_egress_rules = toset(["IPv4", "IPv6"])
}
