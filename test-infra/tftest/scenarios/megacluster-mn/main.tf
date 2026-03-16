data "google_project" "project" {}

data "google_compute_network" "vpc" {
  name                    = "%TFTEST_NETWORK%"
}

resource "google_compute_subnetwork" "vpc" {
  name          = "%TFTEST_CLUSTER_NAME%-vpc-subnet"
  ip_cidr_range = "10.193.0.0/16"
  region        = "%TFTEST_REGION%"
  network       = data.google_compute_network.vpc.id

  depends_on = [data.google_compute_network.vpc]
}

data "google_compute_network" "vpc-mn-1" {
  name                    = "b363582603-gke-ai-training-megacluster-mn"
}

resource "google_compute_subnetwork" "vpc-mn-1" {
  name          = format("%s-sub", data.google_compute_network.vpc-mn-1.name)
  ip_cidr_range = "10.194.0.0/16"
  region        = "%TFTEST_REGION%"
  network       = data.google_compute_network.vpc-mn-1.id

  depends_on = [data.google_compute_network.vpc-mn-1]
}

data "google_compute_network" "vpc-mn-2" {
  name                    = "b363582603-gke-ai-training-megacluster-mn-2"
}

resource "google_compute_subnetwork" "vpc-mn-2" {
  name          = format("%s-sub", data.google_compute_network.vpc-mn-2.name)
  ip_cidr_range = "10.195.0.0/16"
  region        = "%TFTEST_REGION%"
  network       = data.google_compute_network.vpc-mn-2.id

  depends_on = [data.google_compute_network.vpc-mn-2]
}

data "google_compute_network" "vpc-mn-3" {
  name                    = "b363582603-gke-ai-training-megacluster-mn-3"
}

resource "google_compute_subnetwork" "vpc-mn-3" {
  name          = format("%s-sub", data.google_compute_network.vpc-mn-3.name)
  ip_cidr_range = "10.196.0.0/16"
  region        = "%TFTEST_REGION%"
  network       = data.google_compute_network.vpc-mn-3.id

  depends_on = [data.google_compute_network.vpc-mn-3]
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
  enable_multi_networking = true

  master_authorized_networks_config {
    %TFTEST_AUTH_NETWORK_ADDR%
  }

  private_cluster_config {
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "10.128.0.0/10"
    services_ipv4_cidr_block = "10.192.0.0/16"
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

  depends_on = [google_compute_subnetwork.vpc, google_compute_subnetwork.vpc-mn-1,google_compute_subnetwork.vpc-mn-2,google_compute_subnetwork.vpc-mn-3,google_compute_router_nat.nat]
}

data "google_client_config" "provider" {}

provider "kubectl" {
  host                    = "https://${resource.google_container_cluster.test_cluster.endpoint}"
  cluster_ca_certificate  = base64decode(resource.google_container_cluster.test_cluster.master_auth[0].cluster_ca_certificate)
  load_config_file        = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command = "gke-gcloud-auth-plugin"
  }
}

resource "kubectl_manifest" "netdevice-1" {
  yaml_body = <<YAML
apiVersion: networking.gke.io/v1
kind: GKENetworkParamSet
metadata:
  name: mn-net1
spec:
  vpc: "${data.google_compute_network.vpc-mn-1.name}"
  vpcSubnet: "${google_compute_subnetwork.vpc-mn-1.name}"
  deviceMode: NetDevice
YAML
}

resource "kubectl_manifest" "netdevice-network-1" {
  yaml_body = <<YAML
apiVersion: networking.gke.io/v1
kind: Network
metadata:
  name: mn-net1
spec:
  type: "Device"
  parametersRef:
    group: networking.gke.io
    kind: GKENetworkParamSet
    name: mn-net1
YAML
}

resource "kubectl_manifest" "netdevice-2" {
  yaml_body = <<YAML
apiVersion: networking.gke.io/v1
kind: GKENetworkParamSet
metadata:
  name: mn-net2
spec:
  vpc: "${data.google_compute_network.vpc-mn-2.name}"
  vpcSubnet: "${google_compute_subnetwork.vpc-mn-2.name}"
  deviceMode: NetDevice
YAML
}

resource "kubectl_manifest" "netdevice-network-2" {
  yaml_body = <<YAML
apiVersion: networking.gke.io/v1
kind: Network
metadata:
  name: mn-net2
spec:
  type: "Device"
  parametersRef:
    group: networking.gke.io
    kind: GKENetworkParamSet
    name: mn-net2
YAML
}

resource "kubectl_manifest" "netdevice-3" {
  yaml_body = <<YAML
apiVersion: networking.gke.io/v1
kind: GKENetworkParamSet
metadata:
  name: mn-net3
spec:
  vpc: "${data.google_compute_network.vpc-mn-3.name}"
  vpcSubnet: "${google_compute_subnetwork.vpc-mn-3.name}"
  deviceMode: NetDevice
YAML
}

resource "kubectl_manifest" "netdevice-network-3" {
  yaml_body = <<YAML
apiVersion: networking.gke.io/v1
kind: Network
metadata:
  name: mn-net3
spec:
  type: "Device"
  parametersRef:
    group: networking.gke.io
    kind: GKENetworkParamSet
    name: mn-net3
YAML
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
  node_count = 4
  node_config {
    machine_type = "n1-standard-64"
  }

  timeouts {
    create = "%TFTEST_NODE_POOL_CREATE_TIMEOUT%"
  }
}

resource "google_container_node_pool" "coredns-pool" {
  cluster    = google_container_cluster.test_cluster.id
  name       = "coredns-pool"
  node_count = 50
  node_config {
    machine_type = "n1-standard-2"
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
    machine_type = "e2-standard-4"
    disk_size_gb = 20
    disk_type = "pd-standard"
    labels = {
      worker-node-pool = "true"
    }
  }

  network_config {
    enable_private_nodes = true
    additional_node_network_configs {
      network = data.google_compute_network.vpc-mn-1.name
      subnetwork = google_compute_subnetwork.vpc-mn-1.name
    }
    additional_node_network_configs {
      network = data.google_compute_network.vpc-mn-2.name
      subnetwork = google_compute_subnetwork.vpc-mn-2.name
    }
    additional_node_network_configs {
      network = data.google_compute_network.vpc-mn-3.name
      subnetwork = google_compute_subnetwork.vpc-mn-3.name
    }
  }

  depends_on = [google_compute_subnetwork.vpc-mn-1,google_compute_subnetwork.vpc-mn-2,google_compute_subnetwork.vpc-mn-3,kubectl_manifest.netdevice-network-1,kubectl_manifest.netdevice-network-2,kubectl_manifest.netdevice-network-3]

  timeouts {
    create = "%TFTEST_NODE_POOL_CREATE_TIMEOUT%"
  }
}
