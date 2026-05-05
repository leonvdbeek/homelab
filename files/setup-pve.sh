#!/bin/bash
# autopve first-boot: switch to no-subscription repos + remove nag banner
set -e
exec > /var/log/autopve-firstboot.log 2>&1
echo "[$(date)] autopve first-boot starting"

# Disable enterprise repos (PVE 9 uses deb822 .sources files)
for f in /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources; do
  [ -f "$f" ] && sed -i 's/^Enabled:.*/Enabled: false/I' "$f" || true
done

# Add PVE no-subscription repo (Trixie / PVE 9)
cat > /etc/apt/sources.list.d/pve-no-subscription.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

# Add Ceph no-subscription repo (Squid for PVE 9)
cat > /etc/apt/sources.list.d/ceph-no-subscription.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/ceph-squid
Suites: trixie
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

# Patch out the no-subscription nag dialog
JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
if [ -f "$JS" ]; then
  cp -n "$JS" "${JS}.autopve.bak"
  # Defang both the popup body and the check that triggers it
  sed -i "s|data.status.toLowerCase() !== 'active'|false|g" "$JS"
  sed -i "s|res === null \|\| res === undefined \|\| !res \|\| res|false \&\& (res|g" "$JS"
fi

apt-get update -qq || true
systemctl restart pveproxy || true

echo "[$(date)] autopve first-boot complete"
