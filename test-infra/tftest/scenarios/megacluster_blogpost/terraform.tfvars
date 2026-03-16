project_name  = "gke-scalability-megacluster"
cluster_name  = "gke-65k-cluster"
region = "us-central1"
min_master_version = "1.31.2"
vpc_network="b327346189-gke-ai-training-megacluster"
node_locations = ["us-central1-a", "us-central1-b", "us-central1-c", "us-central1-f"]
datapath_provider = "ADVANCED_DATAPATH"
master_ipv4_cidr_block="172.16.0.0/28"
ip_cidr_range= "10.0.0.0/9"
# Value for cluster_ipv4_cidr_block enables the automatic deployment of ip-masq-agent
# https://cloud.google.com/kubernetes-engine/docs/concepts/ip-masquerade-agent#when-ip-masq-included
cluster_ipv4_cidr_block = "10.128.0.0/10"
services_ipv4_cidr_block = "/18"
node_pool_count = 16
node_pool_size = 1000
initial_node_count = 250
node_pool_create_timeout = "60m"
