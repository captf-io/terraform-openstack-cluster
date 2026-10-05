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

# captf_tags and additional_tags in OpenStack's tag shapes (CONVENTIONS.md
# section 7): Nova metadata maps "/" in keys to ":" (captf.io:cluster), and
# Neutron and Octavia take the same pairs as "<key>=<value>" strings.
locals {
  captf_tags = { for k, v in var.captf_tags : replace(k, "/", ":") => v }
  # captf keys merge last: additional_tags cannot override them.
  tags = merge(var.additional_tags, local.captf_tags)
  # Neutron allows 255 characters per tag; a longer pair fails a
  # precondition rather than being truncated into a misleading value.
  oversized_tags = [for k, v in local.tags : "${k}=${v}" if length("${k}=${v}") > 255]
}
