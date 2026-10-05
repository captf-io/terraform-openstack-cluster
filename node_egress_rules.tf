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

# Egress of every node to anywhere, one rule per address family, replacing
# the Neutron defaults delete_default_rules removed (DESIGN.md decision 2).
# Rules cannot carry tags; they go with their group.
resource "openstack_networking_secgroup_rule_v2" "node_egress_rules" {
  for_each = local.node_egress_rules

  description = "Any egress (${each.value})"
  direction   = "egress"
  ethertype   = each.value
  # No remote_ip_prefix: any address, as in Neutron's own defaults.
  security_group_id = openstack_networking_secgroup_v2.node_security_group[0].id
}
