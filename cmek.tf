# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

resource "google_kms_key_ring" "default" {

  name = var.CMEK_keyring_name

  location = var.region

}

resource "google_kms_crypto_key" "key" {

    name = var.CMEK_key_name
    key_ring = google_kms_key_ring.default.id
    rotation_period = var.CMEK_rotation_period


    version_template {
        algorithm = var.CMEK_algorithm
    }
    lifecycle {
        prevent_destroy = false
    }

}

resource "google_kms_crypto_key_iam_binding" "crypto_key" {

  crypto_key_id = google_kms_crypto_key.key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  members       = [
     "serviceAccount:service-${data.google_project.project.number}@compute-system.iam.gserviceaccount.com",
  ]

}