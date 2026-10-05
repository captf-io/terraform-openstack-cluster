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

# Security group of the control-plane nodes, on top of the node group: the
# API backend ports, etcd and, for RKE2, the supervisor (DESIGN.md decision
# 2).
resource "openstack_networking_secgroup_v2" "control_plane_security_group" {
  # Counted like node_security_group, for the exports.
  count = 1

  delete_default_rules = true
  description          = "CAPTF control plane of cluster ${local.cluster_key}"
  name                 = "${local.name_prefix}-control-plane"
  tags                 = [for k, v in local.tags : "${k}=${v}"]
}
