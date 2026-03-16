resource "google_compute_network" "vpc" {
  auto_create_subnetworks = false
  name                    = "%TFTEST_CLUSTER_NAME%-vpc"
}

resource "google_compute_subnetwork" "vpc" {
  name          = "%TFTEST_CLUSTER_NAME%-vpc-subnet"
  ip_cidr_range = "10.11.192.0/18"
  region        = "%TFTEST_REGION%"
  network       = google_compute_network.vpc.id

  depends_on = [google_compute_network.vpc]
}

resource "google_compute_router" "router" {
  name    = "nat-router-%TFTEST_CLUSTER_NAME%"
  region  = "%TFTEST_REGION%"
  network = google_compute_network.vpc.id

  depends_on = [google_compute_subnetwork.vpc]
}

resource "google_compute_router_nat" "nat" {
  name                               = "nat-router-%TFTEST_CLUSTER_NAME%"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES"
  min_ports_per_vm                   = 64

  depends_on = [google_compute_router.router]
}

resource "google_container_cluster" "test_cluster" {
  name               = "%TFTEST_CLUSTER_NAME%"
  location           = "%TFTEST_LOCATION%"
  node_locations     = %TFTEST_NODE_LOCATIONS%
  initial_node_count = %TFTEST_INITIAL_NODE_COUNT%
  release_channel {
    channel = "RAPID"
  }
  node_config {
    machine_type = "n1-standard-64"
    disk_size_gb = 50
  }

  # Do not block on destroy attempts.
  deletion_protection = false

  # Networking-related options.
  network           = google_compute_network.vpc.id
  subnetwork        = google_compute_subnetwork.vpc.id
  networking_mode   = "VPC_NATIVE"

  master_authorized_networks_config {
    %TFTEST_AUTH_NETWORK_ADDR%
  }

  private_cluster_config {
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "/10"
    services_ipv4_cidr_block = "/16"
  }

  # Miscellaneous other configuration options.
  addons_config {
    dns_cache_config {
      enabled = true
    }
  }
  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
      "APISERVER",
      "SCHEDULER",
      "CONTROLLER_MANAGER"
    ]
  }
  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "APISERVER",
      "SCHEDULER",
      "CONTROLLER_MANAGER"
    ]
  }

  timeouts {
    create = "%TFTEST_RESOURCE_CREATE_TIMEOUT%"
    delete = "%TFTEST_RESOURCE_DELETE_TIMEOUT%"
  }

  depends_on = [google_compute_subnetwork.vpc]
}

# Using for_each, provision 600 NPs with 8 Nodes each.
locals {
  node_pool_parameters = merge(
    {
      for i in range(%TFTEST_NODE_POOL_COUNT%) : format("%s%02d", "np-small-", i) => %TFTEST_NODE_POOL_SIZE%
    }
  )

  taint_parameters = merge (
    {
      for i in range(10): format("%s%02d", "taint-", i) => format("%s%02d", "taint-", i)
    }
  )
}

resource "google_container_node_pool" "%TFTEST_NODE_POOL_RESOURCE_NAME%" {
  for_each         = local.node_pool_parameters

  cluster          = google_container_cluster.test_cluster.id
  name             = each.key
  node_count       = each.value
  node_config {
    machine_type = "e2-small"
    disk_size_gb = 50
    dynamic "taint" {
      for_each = local.taint_parameters
      iterator = t

      content {
        key = t.key
        value = t.value
        effect = "PREFER_NO_SCHEDULE"
      }
    }
  }
}
