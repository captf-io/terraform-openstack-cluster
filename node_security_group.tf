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

# Security group of every node, the control plane included (DESIGN.md
# decision 2). delete_default_rules keeps the cloud's default rules out;
# node_egress_rules adds egress back explicitly.
resource "openstack_networking_secgroup_v2" "node_security_group" {
  # Counted so a group deleted out of band reads as gone, not unknown, in
  # the exports (CONVENTIONS.md section 9).
  count = 1

  delete_default_rules = true
  description          = "CAPTF nodes of cluster ${local.cluster_key}"
  name                 = "${local.name_prefix}-node"
  tags                 = [for k, v in local.tags : "${k}=${v}"]

  lifecycle {
    precondition {
      # The subnet data source is counted so a destroy survives a deleted
      # subnet; every other plan must find it.
      condition     = local.subnet_found
      error_message = "subnet_id ${coalesce(var.subnet_id, "-")} is not a subnet this identity can see: create it, or set spec.variables.subnet_id to an existing one."
    }
    precondition {
      condition     = length(local.oversized_tags) == 0
      error_message = "captf_tags and additional_tags must each fit in a 255-character \"<key>=<value>\" Neutron tag; too long: ${join(", ", local.oversized_tags)}. Shorten the Cluster, TerraformCluster or template name."
    }
  }
}
