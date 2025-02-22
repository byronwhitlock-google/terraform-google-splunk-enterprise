# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file e7xcept in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


####
## Cluster Master
####
resource "google_compute_instance" "splunk_cluster_master" {
  name         = local.splunk_cluster_master_name
  machine_type = "n1-standard-4"
  zone = local.zone
  tags = ["splunk"]
  #allow_stopping_for_update = true
  scheduling {
    on_host_maintenance = "TERMINATE"
  }
  # confidential_instance_config {
  #   enable_confidential_compute = var.enable_confidential_compute
  # }   

  shielded_instance_config {
    enable_secure_boot          = var.enable_secure_boot
  }

  boot_disk {
    # USE CMEK KEY!
    kms_key_self_link =  google_kms_crypto_key.key.id
    
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      type  = "pd-ssd"
      size  = "50"
    }
  }

  network_interface {
    network = var.create_network ? google_compute_network.vpc_network[0].self_link : var.splunk_network
    network_ip = google_compute_address.splunk_cluster_master_ip.address
    subnetwork = var.create_network ? google_compute_subnetwork.splunk_subnet[0].self_link : var.splunk_subnet

    # Removing this removes the ephemeral ip
    #access_config {
    #  # Ephemeral IP
    #}
  }

  metadata = {
    startup-script = templatefile("${path.module}/startup_script.sh.tpl", {
      SPLUNK_PACKAGE_URL              = local.splunk_package_url
      SPLUNK_PACKAGE_NAME             = local.splunk_package_name
      SPLUNK_ADMIN_PASSWORD           = var.splunk_admin_password
      SPLUNK_CLUSTER_SECRET           = var.splunk_cluster_secret
      SPLUNK_INDEXER_DISCOVERY_SECRET = var.splunk_indexer_discovery_secret
      SPLUNK_CM_PRIVATE_IP            = google_compute_address.splunk_cluster_master_ip.address
      SPLUNK_DEPLOYER_PRIVATE_IP      = google_compute_address.splunk_deployer_ip.address
    })

    splunk-role    = "IDX-Master"
    enable-guest-attributes = "TRUE"
  }
    depends_on = [
      google_compute_address.splunk_cluster_master_ip,
      google_compute_address.splunk_deployer_ip,

      google_compute_firewall.splunk_allow_internal,
      google_compute_firewall.splunk_allow_ssh,
      google_compute_firewall.allow_splunk_web,
  ]
}

####
## Search Head Deployer
####
resource "google_compute_instance" "splunk_deployer" {
  name         = "splunk-deployer"
  machine_type = "n1-standard-4"
  zone = local.zone
  tags = ["splunk"]
 # allow_stopping_for_update = true

  shielded_instance_config {
    enable_secure_boot          = var.enable_secure_boot
  }
  scheduling {
    on_host_maintenance = "TERMINATE"
  }
  #confidential_instance_config {
  #  enable_confidential_compute = var.enable_confidential_compute
  #}   
  boot_disk {
    kms_key_self_link =  google_kms_crypto_key.key.id
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      type  = "pd-ssd"
      size  = "50"
    }
  }

  network_interface {
    network = var.create_network ? google_compute_network.vpc_network[0].self_link : var.splunk_network
    network_ip = google_compute_address.splunk_deployer_ip.address
    subnetwork = var.create_network ? google_compute_subnetwork.splunk_subnet[0].self_link : var.splunk_subnet
    # Removing this removes the ephemeral ip
    #access_config {
    #  # Ephemeral IP
    #}
  }

  metadata = {
    startup-script = templatefile("${path.module}/startup_script.sh.tpl", {
      SPLUNK_PACKAGE_URL              = local.splunk_package_url
      SPLUNK_PACKAGE_NAME             = local.splunk_package_name
      SPLUNK_ADMIN_PASSWORD           = var.splunk_admin_password
      SPLUNK_CLUSTER_SECRET           = var.splunk_cluster_secret
      SPLUNK_INDEXER_DISCOVERY_SECRET = var.splunk_indexer_discovery_secret
      SPLUNK_CM_PRIVATE_IP            = google_compute_address.splunk_cluster_master_ip.address
      SPLUNK_DEPLOYER_PRIVATE_IP      = google_compute_address.splunk_deployer_ip.address
    })
    splunk-role    = "SHC-Deployer"
    enable-guest-attributes = "TRUE"
  }

  depends_on = [
    google_compute_address.splunk_cluster_master_ip,
    google_compute_address.splunk_deployer_ip,
    google_compute_firewall.splunk_allow_internal,
    google_compute_firewall.splunk_allow_ssh,
    google_compute_firewall.allow_splunk_web,
  ]
}

####
## Indexers
####
resource "google_compute_disk" "indexer-data-disk" {
  # Don't create if using local ssd
  count = var.idx_disk_type == "local-ssd" ? 0 : 1
  name = "splunk-indexer-data"
  size = var.idx_disk_size
  type = var.idx_disk_type
  zone = local.zone
}

resource "google_compute_image" "indexer-data-disk-image" {
  # Don't create if using local ssd
  count = var.idx_disk_type == "local-ssd" ? 0 : 1
  name = "splunk-indexer-data-image"
  source_disk = google_compute_disk.indexer-data-disk[0].self_link
  depends_on = [google_compute_disk.indexer-data-disk]
}

# Indexer Template for Persistent Disk
resource "google_compute_instance_template" "splunk_idx_template-pd" {
  count = var.idx_disk_type != "local-ssd" ? 1 : 0
  name_prefix  = "splunk-idx-template-"
  machine_type = "n1-standard-4"
  tags = ["splunk"]

 # allow_stopping_for_update = true
  shielded_instance_config {
    enable_secure_boot          = var.enable_secure_boot
  }
  scheduling {
    on_host_maintenance = "TERMINATE"
  }
  #confidential_instance_config {
  #  enable_confidential_compute = var.enable_confidential_compute
  #}   

  # boot disk
  disk {
    disk_encryption_key {
      kms_key_self_link =  google_kms_crypto_key.key.id
    }
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    disk_type    = "pd-ssd"
    disk_size_gb = "50"
    auto_delete  = false
    boot         = true
  }
  # data disk
  disk {
    disk_encryption_key {
      kms_key_self_link =  google_kms_crypto_key.key.id
    }
    source_image = google_compute_image.indexer-data-disk-image[0].name
    disk_name = "splunk-db"
    auto_delete = false
    boot = false
  }
  network_interface {
    network = var.create_network ? google_compute_network.vpc_network[0].self_link : var.splunk_network
    subnetwork = var.create_network ? google_compute_subnetwork.splunk_subnet[0].self_link : var.splunk_subnet
    # Removing this removes the ephemeral ip
    #access_config {
    #  # Ephemeral IP
    #}
  }
  metadata = {
    startup-script = templatefile("${path.module}/startup_script.sh.tpl", {
      SPLUNK_PACKAGE_URL              = local.splunk_package_url
      SPLUNK_PACKAGE_NAME             = local.splunk_package_name
      SPLUNK_ADMIN_PASSWORD           = var.splunk_admin_password
      SPLUNK_CLUSTER_SECRET           = var.splunk_cluster_secret
      SPLUNK_INDEXER_DISCOVERY_SECRET = var.splunk_indexer_discovery_secret
      SPLUNK_CM_PRIVATE_IP            = google_compute_address.splunk_cluster_master_ip.address
      SPLUNK_DEPLOYER_PRIVATE_IP      = google_compute_address.splunk_deployer_ip.address
    })
    splunk-role    = "IDX-Peer"
    enable-guest-attributes = "TRUE"
  }

  lifecycle {
    create_before_destroy = true
  }
  
  depends_on = [google_compute_image.indexer-data-disk-image,
        google_compute_address.splunk_cluster_master_ip,
      google_compute_address.splunk_deployer_ip,
  ]
}

# Indexer Template for Local SSD's
resource "google_compute_instance_template" "splunk_idx_template-localssd" {
  count = var.idx_disk_type == "local-ssd" ? 1 : 0
  name_prefix  = "splunk-idx-template-"
  machine_type = "n1-standard-4"
  tags = ["splunk"]
  
 # allow_stopping_for_update = true
  shielded_instance_config {
    enable_secure_boot          = var.enable_secure_boot
  }
  scheduling {
    on_host_maintenance = "TERMINATE"
  }
  #confidential_instance_config {
  #  enable_confidential_compute = var.enable_confidential_compute
  #}   

  # boot disk
  disk {
    disk_encryption_key {
      kms_key_self_link =  google_kms_crypto_key.key.id
    }
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    disk_type    = "pd-ssd"
    disk_size_gb = "50"
    auto_delete = false
    boot        = true
  }
  # Local SSD Block
  dynamic "disk" {
    for_each = range(var.idx_disk_count)
    content {
      disk_type = "local-ssd"
      interface = "SCSI"
      type = "SCRATCH"
      disk_size_gb = 375
    }
  }
  network_interface {
    network = var.create_network ? google_compute_network.vpc_network[0].self_link : var.splunk_network
    subnetwork = var.create_network ? google_compute_subnetwork.splunk_subnet[0].self_link : var.splunk_subnet
    # Removing this removes the ephemeral ip
    #access_config {
    #  # Ephemeral IP
    #}
  }
  metadata = {
    startup-script = templatefile("${path.module}/startup_script.sh.tpl", {
      SPLUNK_PACKAGE_URL              = local.splunk_package_url
      SPLUNK_PACKAGE_NAME             = local.splunk_package_name
      SPLUNK_ADMIN_PASSWORD           = var.splunk_admin_password
      SPLUNK_CLUSTER_SECRET           = var.splunk_cluster_secret
      SPLUNK_INDEXER_DISCOVERY_SECRET = var.splunk_indexer_discovery_secret
      SPLUNK_CM_PRIVATE_IP            = google_compute_address.splunk_cluster_master_ip.address
      SPLUNK_DEPLOYER_PRIVATE_IP      = google_compute_address.splunk_deployer_ip.address
    })
    splunk-role    = "IDX-Peer"
    enable-guest-attributes = "TRUE"
  }
  depends_on = [         google_compute_address.splunk_cluster_master_ip,
      google_compute_address.splunk_deployer_ip, ]
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "indexer_cluster" {
  provider           = google-beta
  name               = "splunk-idx-mig"
  region             = var.region
  base_instance_name = "splunk-idx"
  target_size        = var.splunk_idx_cluster_size

  version {
    name              = "splunk-idx-mig-version-0"
    instance_template = var.idx_disk_type == "local-ssd" ? google_compute_instance_template.splunk_idx_template-localssd[0].self_link : google_compute_instance_template.splunk_idx_template-pd[0].self_link
  }

  named_port {
    name = "splunkhec"
    port = "8088"
  }

  named_port {
    name = "splunktcp"
    port = "9997"
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.splunk_idx.self_link
    initial_delay_sec = 300
  }

  depends_on = [google_compute_instance.splunk_cluster_master]
}

####
## Search Heads
####
resource "google_compute_instance_template" "splunk_shc_template" {
  name_prefix  = "splunk-shc-template-"
  machine_type = "n1-standard-4"
  tags = ["splunk"]
 # allow_stopping_for_update = true
  
  shielded_instance_config {
    enable_secure_boot          = var.enable_secure_boot
  }

  scheduling {
    on_host_maintenance = "TERMINATE"
  }
  #confidential_instance_config {
  #  enable_confidential_compute = var.enable_confidential_compute
  #}   
  # boot disk
  disk {
    disk_encryption_key {
      kms_key_self_link =  google_kms_crypto_key.key.id
    }
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    disk_type    = "pd-ssd"
    disk_size_gb = "50"
    boot         = "true"
  }
  
  network_interface {
    network = var.create_network ? google_compute_network.vpc_network[0].self_link : var.splunk_network
    subnetwork = var.create_network ? google_compute_subnetwork.splunk_subnet[0].self_link : var.splunk_subnet
    # Removing this removes the ephemeral ip
    #access_config {
    #  # Ephemeral IP
    #}
  }

  metadata = {
    startup-script = templatefile("${path.module}/startup_script.sh.tpl", {
      SPLUNK_PACKAGE_URL              = local.splunk_package_url
      SPLUNK_PACKAGE_NAME             = local.splunk_package_name
      SPLUNK_ADMIN_PASSWORD           = var.splunk_admin_password
      SPLUNK_CLUSTER_SECRET           = var.splunk_cluster_secret
      SPLUNK_INDEXER_DISCOVERY_SECRET = var.splunk_indexer_discovery_secret
      SPLUNK_CM_PRIVATE_IP            = google_compute_address.splunk_cluster_master_ip.address
      SPLUNK_DEPLOYER_PRIVATE_IP      = google_compute_address.splunk_deployer_ip.address
    })
    splunk-role    = "SHC-Member"
    enable-guest-attributes = "TRUE"
  }
}

resource "google_compute_region_instance_group_manager" "search_head_cluster" {
  provider           = google-beta
  name               = "splunk-shc-mig"
  region             = var.region
  base_instance_name = "splunk-sh"

  target_size = var.splunk_sh_cluster_size

  version {
    name              = "splunk-shc-mig-version-0"
    instance_template = google_compute_instance_template.splunk_shc_template.self_link
  }

  named_port {
    name = "splunkweb"
    port = "8000"
  }

  depends_on = [         google_compute_address.splunk_cluster_master_ip,
      google_compute_address.splunk_deployer_ip, 
    google_compute_instance.splunk_cluster_master,
    google_compute_instance.splunk_deployer,
    google_compute_instance_template.splunk_shc_template
  ]
}


