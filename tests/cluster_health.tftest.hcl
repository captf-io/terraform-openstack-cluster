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

# Cluster health for each Octavia provisioning status the module maps
# (README "Health"). Each run re-applies one state; the status data source
# is re-read with the overridden value.

mock_provider "openstack" {
  mock_data "openstack_networking_subnet_ids_v2" {
    defaults = {
      ids = ["5c1d7a0e-2b4f-4e83-9a61-0d8f3b2c4e71"]
    }
  }
  mock_data "openstack_networking_subnet_v2" {
    defaults = {
      id         = "5c1d7a0e-2b4f-4e83-9a61-0d8f3b2c4e71"
      network_id = "9e4b2c71-6a3d-4f05-8b19-7c2e5d0a6f38"
      cidr       = "10.6.0.0/24"
      ip_version = 4
      region     = "RegionOne"
    }
  }
  mock_data "openstack_compute_availability_zones_v2" {
    defaults = {
      names = ["nova"]
    }
  }
  mock_data "openstack_lb_loadbalancer_v2" {
    defaults = {
      provisioning_status = "ACTIVE"
    }
  }
  mock_resource "openstack_lb_loadbalancer_v2" {
    defaults = {
      vip_address = "10.6.0.10"
      vip_port_id = "0b6e8f3a-1c2d-4e5f-8a9b-7c6d5e4f3a2b"
    }
  }
}

variables {
  captf_contract = "v1alpha1"
  captf_cluster  = { name = "demo", namespace = "team-a" }
  captf_object   = { kind = "TerraformCluster", name = "demo", namespace = "team-a" }
  captf_tags = {
    "captf.io/cluster"    = "demo"
    "captf.io/namespace"  = "team-a"
    "captf.io/kind"       = "TerraformCluster"
    "captf.io/name"       = "demo"
    "captf.io/managed-by" = "captf"
    "captf.io/template"   = ""
  }
  control_plane_endpoint    = null
  kubernetes_version        = null
  control_plane_initialized = false
  cluster_network           = null

  subnet_id = "5c1d7a0e-2b4f-4e83-9a61-0d8f3b2c4e71"
}

run "health_running" {
  assert {
    condition     = output.health.state == "running" && output.health.healthy && length(output.health.reasons) == 0
    error_message = "ACTIVE is running and healthy."
  }
}

run "health_running_while_updating" {
  override_data {
    target = data.openstack_lb_loadbalancer_v2.api_load_balancer_status
    values = { provisioning_status = "PENDING_UPDATE" }
  }

  assert {
    condition     = output.health.state == "running" && output.health.healthy
    error_message = "PENDING_UPDATE keeps serving: a control-plane member being added must not flip Ready."
  }
}

run "health_pending" {
  override_data {
    target = data.openstack_lb_loadbalancer_v2.api_load_balancer_status
    values = { provisioning_status = "PENDING_CREATE" }
  }

  assert {
    condition     = output.health.state == "pending" && !output.health.healthy && jsonencode(output.health.reasons) == jsonencode(["LoadBalancerPendingCreate"])
    error_message = "PENDING_CREATE is pending."
  }
}

run "health_degraded" {
  override_data {
    target = data.openstack_lb_loadbalancer_v2.api_load_balancer_status
    values = { provisioning_status = "ERROR" }
  }

  assert {
    condition     = output.health.state == "degraded" && !output.health.healthy && jsonencode(output.health.reasons) == jsonencode(["LoadBalancerError"])
    error_message = "ERROR is degraded."
  }
  assert {
    condition     = endswith(output.health.message, " is ERROR")
    error_message = "health.message must name the Octavia state."
  }
}

run "health_terminated" {
  override_data {
    target = data.openstack_lb_loadbalancer_v2.api_load_balancer_status
    values = { provisioning_status = "DELETED" }
  }

  assert {
    condition     = output.health.state == "terminated" && !output.health.healthy && jsonencode(output.health.reasons) == jsonencode(["LoadBalancerDeleted"])
    error_message = "DELETED is terminated."
  }
}

run "health_unknown" {
  override_data {
    target = data.openstack_lb_loadbalancer_v2.api_load_balancer_status
    values = { provisioning_status = "SOMETHING_NEW" }
  }

  assert {
    condition     = output.health.state == "unknown" && !output.health.healthy && jsonencode(output.health.reasons) == jsonencode(["LoadBalancerStatusUnknown"])
    error_message = "An unmapped state is unknown."
  }
}
