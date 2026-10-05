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

# Records what fixes the API endpoint when the load balancer is created and
# fails any later plan that would move it: CAPI never updates the Cluster's
# endpoint after the first copy (cluster.md "control_plane_endpoint (output)").
resource "terraform_data" "api_endpoint_guard" {
  count = local.create_load_balancer ? 1 : 0

  # The provider the load balancer actually got, not the variable: null
  # takes the cloud's default, and a later explicit value equal to it must
  # not trip the guard.
  input = merge(local.api_endpoint_identity, {
    loadbalancer_provider = openstack_lb_loadbalancer_v2.api_load_balancer[0].loadbalancer_provider
  })

  lifecycle {
    # The recorded value never follows the configuration. No prevent_destroy
    # instead of this guard: it would block deleting the cluster too.
    ignore_changes = [input]

    postcondition {
      condition = (
        self.input.subnet_id == local.api_endpoint_identity.subnet_id
        && self.input.api_load_balancer_public == local.api_endpoint_identity.api_load_balancer_public
        && self.input.floating_ip_pool == local.api_endpoint_identity.floating_ip_pool
        && self.input.port == local.api_endpoint_identity.port
        && (var.loadbalancer_provider == null || var.loadbalancer_provider == self.input.loadbalancer_provider)
      )
      error_message = "The API endpoint of this cluster is fixed once its load balancer exists: subnet_id, api_load_balancer_public, floating_ip_pool, cluster_network.api_server_port and loadbalancer_provider cannot change (recorded ${jsonencode(self.input)}, requested ${jsonencode(merge(local.api_endpoint_identity, { loadbalancer_provider = var.loadbalancer_provider }))}). Revert the change, or create a new cluster."
    }
  }
}
