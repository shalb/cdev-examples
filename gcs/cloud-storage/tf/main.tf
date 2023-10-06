resource "random_id" "bucket" {
  prefix      = "terraform-static-content-"
  byte_length = 2
}

resource "google_compute_network" "default" {
  name                    = var.name
  auto_create_subnetworks = "false"
}

locals {
  health_check = {
    request_path = "/"
    port         = 80
  }
}

module "gce-lb-https" {
  source            = "GoogleCloudPlatform/lb-http/google"
  version           = "9.2.0"
  name              = var.name
  project           = var.project_id
  firewall_networks = [google_compute_network.default.self_link]
  url_map           = google_compute_url_map.gce-lb-https.self_link
  create_url_map    = false
  ssl               = true
  private_key       = tls_private_key.example.private_key_pem
  certificate       = tls_self_signed_cert.example.cert_pem

  backends = {
    default = {
      protocol    = "HTTP"
      port        = 80
      port_name   = "http"
      timeout_sec = 10
      enable_cdn  = false

      health_check = local.health_check
      log_config = {
        enable      = true
        sample_rate = 1.0
      }
      groups = [
      ]

      iap_config = {
        enable = false
      }
    }
  }
}

resource "google_compute_url_map" "gce-lb-https" {
  // note that this is the name of the load balancer
  name            = var.name
  default_service = google_compute_backend_bucket.bucket.self_link

  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_bucket.bucket.self_link

    path_rule {
      paths = [
        "/",
        "/*"
      ]
      service = google_compute_backend_bucket.bucket.self_link
    }
  }
}

resource "google_compute_backend_bucket" "bucket" {
  name        = random_id.bucket.hex
  description = "Contains static resources for example app"
  bucket_name = google_storage_bucket.bucket.name
  enable_cdn  = true
}

resource "google_storage_bucket" "bucket" {
  name     = random_id.bucket.hex
  location = var.location

  // delete bucket and contents on destroy.
  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }
  force_destroy = true
}

// The image object in Cloud Storage.
// Note that the path in the bucket matches the paths in the url map path rule above.
resource "google_storage_bucket_object" "index" {
  name    = "index.html"
  content = var.content
  bucket  = google_storage_bucket.bucket.name
}

// Make object public readable.
resource "google_storage_object_acl" "index-acl" {
  bucket         = google_storage_bucket.bucket.name
  object         = google_storage_bucket_object.index.name
  predefined_acl = "publicRead"
}

resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "example" {
  private_key_pem = tls_private_key.example.private_key_pem

  # Certificate expires after 12 hours.
  validity_period_hours = 12

  # Generate a new certificate if Terraform is run within three
  # hours of the certificate's expiration time.
  early_renewal_hours = 3

  # Reasonable set of uses for a server SSL certificate.
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  dns_names = ["example.com", "example.net"]

  subject {
    common_name  = "example.com"
    organization = "ACME Examples, Inc"
  }
}

output "load-balancer-ip" {
  value = module.gce-lb-https.external_ip
}

output "index-url" {
  value = "https://${module.gce-lb-https.external_ip}/index.html"
}


variable "project_id" {
  description = "The project to deploy to, if not set the default provider project is used."
  type        = string
}

variable "name" {
  description = "Name for the forwarding rule and prefix for supporting resources"
  type        = string
}

variable "content" {
  type = string
}

variable "location" {
  type = string
}
