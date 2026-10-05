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

# The API load balancer's provisioning status for the health output, re-read
# on every refresh; the resource does not expose it (locals_health.tf).
data "openstack_lb_loadbalancer_v2" "api_load_balancer_status" {
  # Counted over the load balancer, never [0]: after an out-of-band delete
  # a refresh reads nothing and reports terminated, where [0] would fail it
  # (DESIGN.md "Out-of-band deletes").
  count = length(openstack_lb_loadbalancer_v2.api_load_balancer)

  loadbalancer_id = openstack_lb_loadbalancer_v2.api_load_balancer[count.index].id
}
