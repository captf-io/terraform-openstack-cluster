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

# The cluster role's contract inputs, in contract order, with the contract's
# types (https://captf.io/docs/module-author/contract/v1alpha1/common.html and
# https://captf.io/docs/module-author/contract/v1alpha1/cluster.html).

# Read only by its own validation, which tflint does not count as a use.
# tflint-ignore: terraform_unused_declarations
variable "captf_contract" {
  description = "Contract version the controller rendered these inputs for (common.md \"Inputs\")."
  type        = string

  validation {
    condition     = var.captf_contract == "v1alpha1"
    error_message = "captf_contract must be \"v1alpha1\": this module implements the v1alpha1 cluster role only."
  }
}

variable "captf_cluster" {
  description = "The owning CAPI Cluster (common.md \"Inputs\"); its namespace and name key every resource name."
  type = object({
    name      = string
    namespace = string
  })
}

# tflint-ignore: terraform_unused_declarations
variable "captf_object" {
  description = "The TerraformCluster being reconciled (common.md \"Inputs\"). Unused: resource names derive from captf_cluster, and captf_tags already carries this object's kind and name."
  type = object({
    kind      = string
    name      = string
    namespace = string
  })
}

# tflint-ignore: terraform_unused_declarations
variable "captf_cluster_outputs" {
  description = "Not passed to the cluster role (common.md \"captf_cluster_outputs\"); declared with a null default, as the contract skeleton does, and never read."
  type        = any
  default     = null
}

variable "captf_tags" {
  description = "Tags the controller sets on every cloud resource (common.md \"captf_tags\"); mapped to Nova metadata keys and Neutron/Octavia tag strings in locals_tags.tf."
  type        = map(string)
}

variable "control_plane_endpoint" {
  description = "An endpoint this module does not own (cluster.md \"control_plane_endpoint (input)\"). Non-null means: create no API load balancer and report this endpoint."
  type = object({
    host = string
    port = number
  })
  default = null
}

# tflint-ignore: terraform_unused_declarations
variable "kubernetes_version" {
  description = "Cluster.spec.topology.version, or null without ClusterClass (cluster.md \"kubernetes_version (input)\"). Unused: no OpenStack cluster resource depends on the Kubernetes version."
  type        = string
  default     = null
}

# tflint-ignore: terraform_unused_declarations
variable "control_plane_initialized" {
  description = "Whether the workload control plane is up, latched (cluster.md \"control_plane_initialized (input)\"). Unused: this module creates nothing inside the workload cluster."
  type        = bool
}

variable "cluster_network" {
  description = "Cluster.spec.clusterNetwork, or null (cluster.md \"cluster_network (input)\"). api_server_port sets the API listener port (default 6443); pods feeds the security group rules and the node ports' allowed address pairs."
  # Every attribute is always present when cluster_network is non-null (an
  # unset CIDR list renders as [], an unset scalar as null), so none is
  # optional() (cluster.md "Minimal skeleton").
  type = object({
    pods            = list(string)
    services        = list(string)
    service_domain  = string
    api_server_port = number
  })
  default = null
}
