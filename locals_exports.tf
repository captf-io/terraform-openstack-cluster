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

# The exports every machine receives as captf_cluster_outputs (CONVENTIONS.md
# section 12; README "Exports"). Integers and strings only: they are hashed
# into every machine's inputs. Nothing secret: they are stored in clear.
locals {
  exports = {
    schema             = "captf.io/openstack-cluster/v1"
    region             = one(data.openstack_networking_subnet_v2.node_subnet[*].region)
    network_id         = one(data.openstack_networking_subnet_v2.node_subnet[*].network_id)
    subnet_id          = var.subnet_id
    failure_domains    = { for name in local.failure_domain_names : name => {} }
    distribution       = var.distribution
    provider_id_format = var.provider_id_format
    security_group_ids = {
      control_plane = concat(openstack_networking_secgroup_v2.control_plane_security_group[*].id, openstack_networking_secgroup_v2.node_security_group[*].id)
      worker        = openstack_networking_secgroup_v2.node_security_group[*].id
    }
    control_plane_server_group_id = one(openstack_compute_servergroup_v2.control_plane_server_group[*].id)
    node_allowed_address_cidrs    = local.node_allowed_address_cidrs
    # The endpoint, and the pools control-plane machines join with the
    # backend port of each (CONVENTIONS.md section 12). Null for a user
    # endpoint: nothing to join.
    api = local.create_load_balancer ? {
      host = try(local.api_endpoint.host, null)
      port = local.api_server_port
      pools = { for name, pool in openstack_lb_pool_v2.api_pools : name => {
        id   = pool.id
        port = local.api_ports[name].backend
      } }
    } : null
  }
}
