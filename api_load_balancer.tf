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

# The Octavia load balancer behind the Kubernetes API, internal on the node
# subnet (DESIGN.md decision 1); none when the endpoint is supplied. Its VIP
# is the endpoint host: api_endpoint_guard pins what would replace it.
resource "openstack_lb_loadbalancer_v2" "api_load_balancer" {
  count = local.create_load_balancer ? 1 : 0

  description           = "CAPTF Kubernetes API of cluster ${local.cluster_key}"
  loadbalancer_provider = var.loadbalancer_provider
  name                  = "${local.name_prefix}-api"
  tags                  = [for k, v in local.tags : "${k}=${v}"]
  vip_subnet_id         = var.subnet_id

  # An amphora boots a VM: slow clouds take longer than the provider's
  # 10-minute default.
  timeouts {
    create = "30m"
  }

  lifecycle {
    precondition {
      condition     = !var.api_load_balancer_public || length(var.api_allowed_cidrs) > 0
      error_message = "api_allowed_cidrs must be set when api_load_balancer_public is true: set spec.variables.api_allowed_cidrs to the CIDRs of the management cluster, the operators and the node router's external address."
    }
    precondition {
      condition     = !var.api_load_balancer_public || var.floating_ip_pool != null
      error_message = "floating_ip_pool must be set when api_load_balancer_public is true: set spec.variables.floating_ip_pool to the name of the external network to take the floating IP from."
    }
    precondition {
      # Octavia refuses allowed_cidrs of another IP version than the VIP's.
      condition     = alltrue([for c in local.api_allowed_cidrs : (can(cidrnetmask(c)) ? "IPv4" : "IPv6") == local.subnet_ethertype])
      error_message = "api_allowed_cidrs entries must be of the node subnet's address family (${local.subnet_ethertype}): Octavia refuses a listener with mixed families."
    }
    precondition {
      # ovn-octavia-provider driver.py _check_for_allowed_cidrs.
      condition     = !(var.loadbalancer_provider == "ovn" && length(var.api_allowed_cidrs) > 0)
      error_message = "api_allowed_cidrs must be empty with loadbalancer_provider ovn, which rejects them (so api_load_balancer_public too), or use loadbalancer_provider amphora."
    }
    precondition {
      condition     = !(var.distribution == "rke2" && local.api_server_port == 9345)
      error_message = "cluster_network.api_server_port must not be 9345 with distribution rke2: the RKE2 supervisor listens there on the same load balancer."
    }
  }
}
