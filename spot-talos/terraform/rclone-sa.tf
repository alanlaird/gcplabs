resource "google_service_account" "rclone" {
  account_id   = "rclone-gdrive"
  display_name = "rclone Google Drive"
}

resource "google_service_account_key" "rclone" {
  service_account_id = google_service_account.rclone.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}
