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

# User variables of the cluster role, set through the TerraformCluster's
# spec.variables or spec.variablesFrom
# (https://captf.io/docs/user-guide/variables.html). Alphabetical.

variable "additional_tags" {
  description = "Extra tags for every resource, as Nova metadata pairs and Neutron/Octavia \"<key>=<value>\" tags. Empty by default: captf_tags already identifies every resource."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    # Neutron allows 50 tags per resource and captf_tags takes 6.
    condition     = length(var.additional_tags) <= 44
    error_message = "additional_tags may hold at most 44 entries: Neutron allows 50 tags per resource and captf_tags takes 6."
  }
  validation {
    # The Nova server metadata key rule; it excludes "/" and "=", so every
    # Neutron tag string splits at its first "=".
    condition     = alltrue([for k in keys(var.additional_tags) : can(regex("^[a-zA-Z0-9-_:. ]{1,255}$", k))])
    error_message = "additional_tags keys must be 1 to 255 characters of letters, digits, \"-\", \"_\", \":\", \".\" and space (the Nova metadata key rule)."
  }
  validation {
    condition     = alltrue([for k in keys(var.additional_tags) : !startswith(lower(k), "captf.io:")])
    error_message = "additional_tags keys must not start with \"captf.io:\": that prefix holds the captf_tags."
  }
  validation {
    condition     = alltrue([for k, v in var.additional_tags : length("${k}=${v}") <= 255])
    error_message = "additional_tags entries must each fit in a 255-character \"<key>=<value>\" Neutron tag."
  }
}

variable "api_allowed_cidrs" {
  description = "Client CIDRs the API listeners accept (Octavia allowed_cidrs), of the node subnet's address family. Empty by default: an internal load balancer accepts every client that can route to it. Required when api_load_balancer_public is true; the node subnet is always added."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.api_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "api_allowed_cidrs entries must be CIDR blocks, for example 192.0.2.0/24."
  }
}

variable "api_load_balancer_public" {
  description = "Put a floating IP on the API load balancer and use it as the endpoint. False by default: the endpoint is the internal VIP. Needs floating_ip_pool and api_allowed_cidrs."
  type        = bool
  default     = false
  nullable    = false
}

variable "availability_zones" {
  description = "Nova availability zones to report as failure domains. Empty by default: every zone Nova lists as available. Set it to pin the list, since a zone that turns unavailable otherwise drops out of the failure domains."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    # Cluster.status.failureDomains holds at most 100 entries of 1 to 256
    # characters (cluster.md "failure_domains (output)").
    condition     = length(var.availability_zones) <= 100 && alltrue([for z in var.availability_zones : length(z) >= 1 && length(z) <= 256])
    error_message = "availability_zones may hold at most 100 names of 1 to 256 characters."
  }
}

variable "control_plane_server_group_policy" {
  description = "Nova server group policy for the control-plane machines: soft-anti-affinity (the default: spreads them over hosts when it can, and still schedules on a single host), anti-affinity (fails a machine rather than share a host), or null for no server group."
  type        = string
  default     = "soft-anti-affinity"

  validation {
    condition     = var.control_plane_server_group_policy == null || contains(["soft-anti-affinity", "anti-affinity"], coalesce(var.control_plane_server_group_policy, "-"))
    error_message = "control_plane_server_group_policy must be soft-anti-affinity, anti-affinity or null."
  }
}

variable "distribution" {
  description = "Kubernetes distribution of the control plane: kubeadm (the default; KubeadmControlPlane) or rke2 (RKE2ControlPlane, which adds the supervisor listener on 9345)."
  type        = string
  default     = "kubeadm"
  nullable    = false

  validation {
    condition     = contains(["kubeadm", "rke2"], var.distribution)
    error_message = "distribution must be kubeadm or rke2."
  }
}

variable "floating_ip_pool" {
  description = "Name of the external network to take the API floating IP from (the Neutron floating IP pool). Required when api_load_balancer_public is true; unused otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.floating_ip_pool == null || try(length(var.floating_ip_pool) > 0, false)
    error_message = "floating_ip_pool must be a non-empty external network name, or null."
  }
}

variable "loadbalancer_provider" {
  description = "Octavia provider of the API load balancer. Defaults to amphora, the provider whose source NAT gives control-plane nodes the hairpin path the contract requires; null takes the cloud's default provider."
  type        = string
  default     = "amphora"

  validation {
    condition     = var.loadbalancer_provider == null || try(length(var.loadbalancer_provider) > 0, false)
    error_message = "loadbalancer_provider must be a non-empty Octavia provider name, or null."
  }
}

variable "node_allowed_address_cidrs" {
  description = "Extra CIDRs every node port may send from (Neutron allowed address pairs), for example a kube-vip address. Empty by default; pod_address_pairs adds the pod CIDRs."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.node_allowed_address_cidrs : can(cidrhost(c, 0))])
    error_message = "node_allowed_address_cidrs entries must be CIDR blocks, for example 192.0.2.10/32."
  }
}

variable "pod_address_pairs" {
  description = "Add the pod CIDRs to every node port's allowed address pairs, for CNIs that route pod traffic without encapsulation (Calico without IP-in-IP or VXLAN, Cilium native routing). False by default: encapsulating CNIs send from node addresses only, and port security then drops any other source."
  type        = bool
  default     = false
  nullable    = false
}

variable "provider_id_format" {
  description = "Format of the provider IDs machines report: default (openstack:///<server-id>) or regional (openstack://<region>/<server-id>). It must match the cloud controller manager's OS_CCM_REGIONAL setting."
  type        = string
  default     = "default"
  nullable    = false

  validation {
    condition     = contains(["default", "regional"], var.provider_id_format)
    error_message = "provider_id_format must be default or regional."
  }
}

variable "region" {
  description = "OpenStack region of the cluster. Null by default: the identity's region (region_name in clouds.yaml, or OS_REGION_NAME). Machines use the same region through the exports."
  type        = string
  default     = null

  validation {
    condition     = var.region == null || try(length(var.region) > 0, false)
    error_message = "region must be a non-empty region name, or null."
  }
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to reach every node on TCP 22. Empty by default: no SSH."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.ssh_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "ssh_allowed_cidrs entries must be CIDR blocks, for example 192.0.2.0/24."
  }
}

variable "subnet_id" {
  description = "UUID of the existing Neutron subnet for the API load balancer and every node (bring your own network). Required: set spec.variables.subnet_id on the TerraformCluster."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subnet_id))
    error_message = "subnet_id must be the UUID of an existing Neutron subnet: set spec.variables.subnet_id on the TerraformCluster."
  }
}
