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

# Cluster health from the API load balancer's Octavia provisioning_status,
# never operating_status, which follows the members (CONVENTIONS.md section 10).
# https://docs.openstack.org/api-ref/load-balancer/v2/#provisioning-status-codes
locals {
  # Octavia provisioning_status -> contract health ("health" in common.md).
  health_by_state = {
    ACTIVE = { state = "running", healthy = true, reason = null }
    # Octavia applies a listener or member change; the load balancer keeps
    # serving, and a control-plane machine joining must not flip Ready.
    PENDING_UPDATE = { state = "running", healthy = true, reason = null }
    PENDING_CREATE = { state = "pending", healthy = false, reason = "LoadBalancerPendingCreate" }
    ERROR          = { state = "degraded", healthy = false, reason = "LoadBalancerError" }
    PENDING_DELETE = { state = "terminated", healthy = false, reason = "LoadBalancerPendingDelete" }
    DELETED        = { state = "terminated", healthy = false, reason = "LoadBalancerDeleted" }
  }
  api_load_balancer_status = try(upper(data.openstack_lb_loadbalancer_v2.api_load_balancer_status[0].provisioning_status), "")
  health_reading           = lookup(local.health_by_state, local.api_load_balancer_status, { state = "unknown", healthy = false, reason = "LoadBalancerStatusUnknown" })

  # A refresh drops a load balancer deleted out of band from state, which
  # leaves the counted resource empty: a known value, so it reads as gone.
  api_load_balancer_gone = local.create_load_balancer && length(openstack_lb_loadbalancer_v2.api_load_balancer) == 0

  health = local.api_load_balancer_gone ? {
    state   = "terminated"
    healthy = false
    message = "Octavia load balancer not found: deleted outside this module"
    reasons = ["LoadBalancerNotFound"]
    } : local.create_load_balancer ? {
    state   = local.health_reading.state
    healthy = local.health_reading.healthy
    message = "Octavia load balancer ${coalesce(one(openstack_lb_loadbalancer_v2.api_load_balancer[*].id), "-")} is ${local.api_load_balancer_status == "" ? "UNKNOWN" : local.api_load_balancer_status}"
    reasons = local.health_reading.healthy ? [] : [local.health_reading.reason]
    } : {
    # The endpoint belongs to someone else: there is nothing of this
    # module's to observe beyond what the apply created.
    state   = "running"
    healthy = true
    message = "control-plane endpoint supplied to the module; no load balancer is managed"
    reasons = []
  }
}
