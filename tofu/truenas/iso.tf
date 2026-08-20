resource "proxmox_download_file" "truenas_iso" {
  content_type = "iso"
  datastore_id = var.iso_datastore
  node_name    = var.node_name
  url          = var.truenas_iso_url
  # Derive the stored filename from the URL (…/TrueNAS-SCALE-24.10.2.iso).
  file_name = reverse(split("/", var.truenas_iso_url))[0]
  overwrite = false
}
