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

# The backend pool of each API listener. Control-plane machines add
# themselves as members from their own state (machine role, exports
# api.pools). The OVN provider supports SOURCE_IP_PORT only.
resource "openstack_lb_pool_v2" "api_pools" {
  for_each = openstack_lb_listener_v2.api_listeners

  lb_method   = openstack_lb_loadbalancer_v2.api_load_balancer[0].loadbalancer_provider == "ovn" ? "SOURCE_IP_PORT" : "ROUND_ROBIN"
  listener_id = each.value.id
  name        = "${local.name_prefix}-api-${replace(each.key, "_", "-")}"
  protocol    = "TCP"
  tags        = [for k, v in local.tags : "${k}=${v}"]
}
