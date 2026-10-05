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

# Names of the cluster's OpenStack resources, derived from the Cluster's
# namespace and name with a hash that keeps truncated names unique
# (CONVENTIONS.md section 6).
locals {
  cluster_key  = "${var.captf_cluster.namespace}/${var.captf_cluster.name}"
  cluster_hash = substr(sha256(local.cluster_key), 0, 8)
  # Neutron, Octavia and Nova names allow 255 characters. 235 leaves room
  # for the longest suffix, "-api-rke2-supervisor"; minus 9 for "-" and
  # the hash.
  name_max    = 235
  name_prefix = "${trimsuffix(substr(replace(lower("captf-${var.captf_cluster.namespace}-${var.captf_cluster.name}"), "/[^a-z0-9-]/", "-"), 0, local.name_max - 9), "-")}-${local.cluster_hash}"
}
