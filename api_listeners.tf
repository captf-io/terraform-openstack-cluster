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

# One TCP listener per API port: kube-apiserver on the endpoint port and,
# for RKE2, the supervisor on 9345 (DESIGN.md decision 1).
resource "openstack_lb_listener_v2" "api_listeners" {
  for_each = { for name, ports in local.api_ports : name => ports if local.create_load_balancer }

  allowed_cidrs   = local.listener_allowed_cidrs
  loadbalancer_id = openstack_lb_loadbalancer_v2.api_load_balancer[0].id
  name            = "${local.name_prefix}-api-${replace(each.key, "_", "-")}"
  protocol        = "TCP"
  protocol_port   = each.value.frontend
  tags            = [for k, v in local.tags : "${k}=${v}"]
  # Octavia's 50 s idle timeout would cut watches, `kubectl exec` and
  # `logs -f`: an hour, in milliseconds.
  timeout_client_data = 3600000
  timeout_member_data = 3600000
}
