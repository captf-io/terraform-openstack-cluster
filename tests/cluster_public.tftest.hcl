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

# The opt-in public endpoint, in its own state: the endpoint guard records
# public = true at the first apply, which the default runs in
# cluster.tftest.hcl must not inherit.

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
  mock_resource "openstack_networking_floatingip_v2" {
    defaults = {
      address  = "203.0.113.10"
      fixed_ip = "10.6.0.10"
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
    "captf.io/template"   = "demo-template"
  }
  control_plane_endpoint    = null
  kubernetes_version        = null
  control_plane_initialized = false
  cluster_network           = null

  subnet_id                = "5c1d7a0e-2b4f-4e83-9a61-0d8f3b2c4e71"
  api_load_balancer_public = true
  floating_ip_pool         = "public"
  # Unsorted, duplicated and with host bits set: the listener must get the
  # normalized, sorted set plus the node subnet.
  api_allowed_cidrs = ["198.51.100.7/24", "192.0.2.0/24", "198.51.100.0/24"]
}

run "public_endpoint_uses_floating_ip" {
  assert {
    condition     = output.control_plane_endpoint == { host = "203.0.113.10", port = 6443 }
    error_message = "A public endpoint is the floating IP on the API port."
  }
  assert {
    condition = (
      openstack_networking_floatingip_v2.api_floating_ip[0].pool == "public"
      && openstack_networking_floatingip_v2.api_floating_ip[0].port_id == openstack_lb_loadbalancer_v2.api_load_balancer[0].vip_port_id
      && contains(openstack_networking_floatingip_v2.api_floating_ip[0].tags, "captf.io:template=demo-template")
    )
    error_message = "The floating IP comes from floating_ip_pool, sits on the VIP port and carries the captf tags."
  }
  assert {
    condition     = openstack_lb_listener_v2.api_listeners["kube_apiserver"].allowed_cidrs == tolist(["10.6.0.0/24", "192.0.2.0/24", "198.51.100.0/24"])
    error_message = "The listener must accept the normalized, sorted allowed_cidrs and the node subnet."
  }
  assert {
    condition     = jsonencode(terraform_data.api_endpoint_guard[0].input) == jsonencode({ api_load_balancer_public = true, floating_ip_pool = "public", loadbalancer_provider = "amphora", port = 6443, subnet_id = var.subnet_id })
    error_message = "The guard must record the public endpoint and its pool."
  }
  assert {
    condition     = sort(keys(openstack_networking_secgroup_rule_v2.control_plane_ingress_rules)) == tolist(["kube_apiserver-from-subnet"])
    error_message = "api_allowed_cidrs restrict the listener only: the amphora source-NATs clients, so no node rule names them."
  }
}

run "rejects_floating_ip_pool_change" {
  command = plan

  variables {
    floating_ip_pool = "public-2"
  }

  expect_failures = [terraform_data.api_endpoint_guard]
}

run "rejects_api_load_balancer_public_change" {
  command = plan

  variables {
    api_load_balancer_public = false
  }

  expect_failures = [terraform_data.api_endpoint_guard]
}
