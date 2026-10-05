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

# Opt-in public endpoint: a floating IP from floating_ip_pool on the load
# balancer's VIP port, and the endpoint host (DESIGN.md decision 1). The
# listeners' api_allowed_cidrs restrict who reaches it.
resource "openstack_networking_floatingip_v2" "api_floating_ip" {
  count = local.create_load_balancer && var.api_load_balancer_public ? 1 : 0

  description = "CAPTF Kubernetes API of cluster ${local.cluster_key}"
  pool        = var.floating_ip_pool
  port_id     = openstack_lb_loadbalancer_v2.api_load_balancer[0].vip_port_id
  tags        = [for k, v in local.tags : "${k}=${v}"]
}
