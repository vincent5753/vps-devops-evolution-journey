# 全新的靜態外部 IP（區域與原本一致，但是新位址）
resource "google_compute_address" "wg_ip" {
  name   = "wg-002-static-ip"
  region = var.region
  network_tier = "STANDARD"
}

# WireGuard 防火牆規則（對應 allow-wireguard: udp/51820）
resource "google_compute_firewall" "allow_wireguard" {
  name    = "allow-wireguard-002"
  network = "default"

  allow {
    protocol = "udp"
    ports    = ["51820"]
  }

  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]
}

# WireGuard VM（e2-micro / us-west1-b / default 網路，比照原規格）
resource "google_compute_instance" "wg_vm" {
  name         = "wireguard-002"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.wg_ip.address
      network_tier = "STANDARD"
    }
  }

  # 透過 GCP 的 user-data metadata 餵給 cloud-init
  metadata = {
    user-data = file("${path.module}/cloud-init-wg.yaml")
  }
}
