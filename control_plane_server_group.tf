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

# Nova server group of the control-plane machines, spreading them over
# hypervisors; on single-zone clouds the only spread there is (DESIGN.md
# decision 3). Server groups cannot carry tags.
resource "openstack_compute_servergroup_v2" "control_plane_server_group" {
  count = var.control_plane_server_group_policy != null ? 1 : 0

  name     = "${local.name_prefix}-control-plane"
  policies = [var.control_plane_server_group_policy]
}
