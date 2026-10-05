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

# The cluster role's contract outputs, in contract order
# (https://captf.io/docs/module-author/contract/v1alpha1/cluster.html
# "Outputs" and common.md "Outputs").

output "control_plane_endpoint" {
  description = "The Kubernetes API endpoint: the load balancer's VIP, or its floating IP when public, on the endpoint port; the supplied endpoint when one was given (cluster.md \"control_plane_endpoint (output)\")."
  value       = var.control_plane_endpoint != null ? var.control_plane_endpoint : local.api_endpoint
}

output "failure_domains" {
  description = "The Nova availability zones machines spread over, all eligible for the control plane (cluster.md \"failure_domains (output)\")."
  value       = [for name in local.failure_domain_names : { name = name, control_plane = true, attributes = {} }]
}

output "exports" {
  description = "Values every machine receives as captf_cluster_outputs: network, security groups, server group, API pools, failure domains (cluster.md \"exports (output)\"; schema in README \"Exports\")."
  value       = local.exports
}

output "health" {
  description = "Health of the API load balancer from its Octavia provisioning status (common.md \"Outputs\"; mapping in README \"Health\")."
  value       = local.health
}
