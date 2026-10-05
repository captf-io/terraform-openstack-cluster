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

# One plan per variable validation and precondition of the cluster role,
# each expected to fail on exactly that check (CONVENTIONS.md section 14).

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
      names = ["az-1"]
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

run "invalid_captf_contract" {
  command = plan
  variables {
    captf_contract = "v1alpha2"
  }
  expect_failures = [var.captf_contract]
}

run "invalid_additional_tags_count" {
  command = plan
  variables {
    additional_tags = { for i in range(45) : "tag-${i}" => "x" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_key" {
  command = plan
  variables {
    additional_tags = { "example.com/team" = "platform" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_reserved" {
  command = plan
  variables {
    additional_tags = { "CAPTF.io:cluster" = "other" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_length" {
  command = plan
  variables {
    additional_tags = { note = format("%0251d", 0) }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_api_allowed_cidrs" {
  command = plan
  variables {
    api_allowed_cidrs = ["10.0.0.0/33"]
  }
  expect_failures = [var.api_allowed_cidrs]
}

run "invalid_availability_zones" {
  command = plan
  variables {
    availability_zones = [""]
  }
  expect_failures = [var.availability_zones]
}

run "invalid_control_plane_server_group_policy" {
  command = plan
  variables {
    control_plane_server_group_policy = "affinity"
  }
  expect_failures = [var.control_plane_server_group_policy]
}

run "invalid_distribution" {
  command = plan
  variables {
    distribution = "k3s"
  }
  expect_failures = [var.distribution]
}

run "invalid_floating_ip_pool" {
  command = plan
  variables {
    floating_ip_pool = ""
  }
  expect_failures = [var.floating_ip_pool]
}

run "invalid_loadbalancer_provider" {
  command = plan
  variables {
    loadbalancer_provider = ""
  }
  expect_failures = [var.loadbalancer_provider]
}

run "invalid_node_allowed_address_cidrs" {
  command = plan
  variables {
    node_allowed_address_cidrs = ["10.6.0.300/32"]
  }
  expect_failures = [var.node_allowed_address_cidrs]
}

run "invalid_provider_id_format" {
  command = plan
  variables {
    provider_id_format = "zonal"
  }
  expect_failures = [var.provider_id_format]
}

run "invalid_region" {
  command = plan
  variables {
    region = ""
  }
  expect_failures = [var.region]
}

run "invalid_ssh_allowed_cidrs" {
  command = plan
  variables {
    ssh_allowed_cidrs = ["any"]
  }
  expect_failures = [var.ssh_allowed_cidrs]
}

run "invalid_subnet_id" {
  command = plan
  variables {
    subnet_id = null
  }
  expect_failures = [var.subnet_id]
}

run "public_requires_allowed_cidrs" {
  command = plan
  variables {
    api_load_balancer_public = true
    floating_ip_pool         = "public"
  }
  expect_failures = [openstack_lb_loadbalancer_v2.api_load_balancer]
}

run "rejects_public_without_floating_ip_pool" {
  command = plan
  variables {
    api_load_balancer_public = true
    api_allowed_cidrs        = ["198.51.100.0/24"]
  }
  expect_failures = [openstack_lb_loadbalancer_v2.api_load_balancer]
}

run "rejects_api_allowed_cidrs_family" {
  command = plan
  variables {
    api_allowed_cidrs = ["2001:db8::/64"]
  }
  expect_failures = [openstack_lb_loadbalancer_v2.api_load_balancer]
}

run "rejects_api_allowed_cidrs_with_ovn" {
  command = plan
  variables {
    loadbalancer_provider = "ovn"
    api_allowed_cidrs     = ["198.51.100.0/24"]
  }
  expect_failures = [openstack_lb_loadbalancer_v2.api_load_balancer]
}

run "rejects_supervisor_port_collision" {
  command = plan
  variables {
    distribution    = "rke2"
    cluster_network = { pods = [], services = [], service_domain = null, api_server_port = 9345 }
  }
  expect_failures = [openstack_lb_loadbalancer_v2.api_load_balancer]
}

run "rejects_missing_subnet" {
  command = plan
  variables {
    subnet_id = "7a3e9c50-1f2b-4d6e-8c4a-2b9d0e1f3c5a"
  }
  expect_failures = [openstack_networking_secgroup_v2.node_security_group]
}

run "rejects_oversized_tags" {
  command = plan
  variables {
    captf_tags = {
      "captf.io/cluster"  = "demo"
      "captf.io/template" = format("%0240d", 0)
    }
  }
  expect_failures = [openstack_networking_secgroup_v2.node_security_group[0]]
}
