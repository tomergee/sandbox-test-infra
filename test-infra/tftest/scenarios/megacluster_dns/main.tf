data "google_project" "project" {}

data "google_compute_network" "vpc" {
  name                    = "%TFTEST_NETWORK%"
}

resource "google_compute_subnetwork" "vpc" {
  name          = "%TFTEST_CLUSTER_NAME%-vpc-subnet"
  ip_cidr_range = "10.0.0.0/9"
  region        = "%TFTEST_REGION%"
  network       = data.google_compute_network.vpc.id

  depends_on = [data.google_compute_network.vpc]
}

resource "google_compute_router" "router" {
  name    = "nat-router-%TFTEST_CLUSTER_NAME%"
  region  = "%TFTEST_REGION%"
  network = data.google_compute_network.vpc.id

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
  min_master_version = "%TFTEST_MIN_MASTER_VERSION%"
  node_locations     = %TFTEST_NODE_LOCATIONS%
  initial_node_count = %TFTEST_INITIAL_NODE_COUNT%
  default_max_pods_per_node = %TFTEST_MAX_PODS_PER_NODE%

  release_channel {
    channel = "RAPID"
  }
  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 20
    disk_type = "pd-standard"
    labels = {
      worker-node-pool = "true"
    }
  }

  # Do not block on destroy attempts.
  deletion_protection = false

  # Networking-related options.
  network           = data.google_compute_network.vpc.id
  subnetwork        = google_compute_subnetwork.vpc.id
  networking_mode   = "VPC_NATIVE"
  datapath_provider = "%TFTEST_DATAPATH%"

  master_authorized_networks_config {
    %TFTEST_AUTH_NETWORK_ADDR%
  }

  private_cluster_config {
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }
  ip_allocation_policy {
    # Value for cluster_ipv4_cidr_block enables the automatic deployment of ip-masq-agent
    # https://cloud.google.com/kubernetes-engine/docs/concepts/ip-masquerade-agent#when-ip-masq-included
    cluster_ipv4_cidr_block  = "10.128.0.0/10"
    services_ipv4_cidr_block = "/18"
  }

  workload_identity_config {
    workload_pool = "${data.google_project.project.project_id}.svc.id.goog"
  }

  # Miscellaneous other configuration options.
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

  depends_on = [google_compute_router_nat.nat]
}

locals {
  node_pool_parameters = merge(
    {
      for i in range(%TFTEST_NODE_POOL_COUNT%) : format("pool%02d", i+1) => %TFTEST_NODE_POOL_SIZE%
    }
  )
}

resource "google_container_node_pool" "heapster-pool" {
  cluster = google_container_cluster.test_cluster.id
  name = "heapster-pool"
  node_count = %TFTEST_HEAPSTER_POOL_NODE_COUNT%
  node_config {
    machine_type = %TFTEST_HEAPSTER_POOL_MACHINE_TYPE%
  }

  timeouts {
    create = "%TFTEST_NODE_POOL_CREATE_TIMEOUT%"
  }
}

resource "google_container_node_pool" "coredns-pool" {
  cluster    = google_container_cluster.test_cluster.id
  name       = "coredns-pool"
  node_count = %TFTEST_COREDNS_POOL_NODE_COUNT%
  node_config {
    machine_type = %TFTEST_COREDNS_POOL_MACHINE_TYPE%
  }

  timeouts {
    create = "%TFTEST_NODE_POOL_CREATE_TIMEOUT%"
  }
}

resource "google_container_node_pool" "%TFTEST_NODE_POOL_RESOURCE_NAME%" {
  for_each         = local.node_pool_parameters

  cluster          = google_container_cluster.test_cluster.id
  name             = each.key
  node_count       = each.value
  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 20
    disk_type = "pd-standard"
    labels = {
      worker-node-pool = "true"
    }
  }

  timeouts {
    create = "%TFTEST_NODE_POOL_CREATE_TIMEOUT%"
  }
}
