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

# Non-contract outputs, for operators: the controller never reads them.

output "api_load_balancer_id" {
  description = "UUID of the Octavia API load balancer (`openstack loadbalancer show <id>`); null when the endpoint is supplied."
  value       = one(openstack_lb_loadbalancer_v2.api_load_balancer[*].id)
}
