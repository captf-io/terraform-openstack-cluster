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

# A TCP health monitor per API pool, valid for kube-apiserver and the RKE2
# supervisor alike (control-planes/checklist.md "Health checks"). Monitors
# cannot carry tags.
resource "openstack_lb_monitor_v2" "api_monitors" {
  for_each = openstack_lb_pool_v2.api_pools

  # Two successes 10 s apart bring a member up: the first control-plane
  # node turns healthy alone in about 20 s.
  delay            = 10
  max_retries      = 2
  max_retries_down = 2
  name             = "${local.name_prefix}-api-${replace(each.key, "_", "-")}"
  pool_id          = each.value.id
  timeout          = 5
  type             = "TCP"
}
