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

# The bring-your-own subnet of the load balancer and every node: its CIDR and
# family shape the rules, its network and region go to the exports. Read only
# while it exists, so a destroy after it is gone still runs.
data "openstack_networking_subnet_v2" "node_subnet" {
  # Every destroy refreshes data sources, and this one fails on a missing
  # subnet; the listing does not (CONVENTIONS.md section 9). Plans that
  # need it fail a precondition on node_security_group instead.
  count = contains(data.openstack_networking_subnet_ids_v2.visible_subnets.ids, coalesce(var.subnet_id, "-")) ? 1 : 0

  subnet_id = var.subnet_id
}
