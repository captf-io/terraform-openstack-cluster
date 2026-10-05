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

# Ingress rules of the control-plane security group, one per entry of
# local.control_plane_ingress_rules (locals_security_rules.tf). Rules
# cannot carry tags; they go with their group.
resource "openstack_networking_secgroup_rule_v2" "control_plane_ingress_rules" {
  for_each = local.control_plane_ingress_rules

  description       = each.value.description
  direction         = "ingress"
  ethertype         = local.subnet_ethertype
  port_range_max    = each.value.port_range_max
  port_range_min    = each.value.port_range_min
  protocol          = each.value.protocol
  remote_ip_prefix  = each.value.remote_ip_prefix
  security_group_id = openstack_networking_secgroup_v2.control_plane_security_group[0].id
}
