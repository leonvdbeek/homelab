locals {
  talos_schematic_yaml = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = var.talos_extensions
      }
    }
  })
}

# POST the schematic to the Talos Image Factory; it returns a deterministic
# schematic ID we use to fetch the matching customized ISO. The ID is stable
# for a given schematic, so re-plans hit the same URL.
data "external" "talos_schematic" {
  program = ["bash", "-c", "jq -r .yaml | curl -fsS -X POST --data-binary @- https://factory.talos.dev/schematics"]
  query   = { yaml = local.talos_schematic_yaml }
}

locals {
  talos_schematic_id = data.external.talos_schematic.result.id
  talos_iso_url      = "https://factory.talos.dev/image/${local.talos_schematic_id}/${var.talos_version}/metal-${var.talos_arch}.iso"
  talos_iso_filename = "talos-${var.talos_version}-${var.talos_arch}-${substr(local.talos_schematic_id, 0, 12)}.iso"
}

# Download the customized Talos ISO once per node so each VM can boot from
# local storage.
resource "proxmox_download_file" "talos" {
  for_each = toset(var.proxmox_nodes)

  content_type = "iso"
  datastore_id = var.iso_datastore
  node_name    = each.value
  url          = local.talos_iso_url
  file_name    = local.talos_iso_filename
  overwrite    = false
}
