#!/usr/bin/env bash
# Provision the homelab Vault LXC on m920x.
# No secret values are embedded here; it sources them from the control host's
# local secret files (or prompts). Run from a host with SSH access to m920x and
# the hermes key. Re-runnable to rebuild a fresh Vault from scratch.
#
# Requires: pct on m920x, a Debian template, root SSH to m920x.

set -euo pipefail

M920X="${M920X:-m920x}"
VMID="${VMID:-106}"
IP="${IP:-192.168.4.232}"
GW="${GW:-192.168.4.1}"
CT_TEMPLATE="${CT_TEMPLATE:-local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst}"
PIN_KEY="${HERMES_PUBKEY:-/root/.ssh/id_ed25519_hermes.pub}"
HERMES_ID="${HERMES_ID:-/root/.ssh/id_ed25519_hermes}"

sshx() { ssh -i "$HERMES_ID" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$@"; }

echo "== 1. create LXC =="
sshx "$M920X" "cat '$PIN_KEY' > /root/vault_hermes.pub"
sshx "$M920X" "pct create $VMID '$CT_TEMPLATE' --hostname vault --storage local-lvm --rootfs 6 \
  --cores 1 --memory 1024 --swap 256 --net0 name=eth0,bridge=vmbr0,ip=$IP/24,gw=$GW \
  --nameserver 1.1.1.1 --unprivileged 1 --features nesting=1 \
  --ssh-public-keys /root/vault_hermes.pub --onboot 1 --start 1"

# wait for ssh
for _ in $(seq 1 30); do timeout 3 bash -c "exec 3<>/dev/tcp/$IP/22" 2>/dev/null && break; sleep 3; done

CT="root@$IP"
echo "== 2. install Vault (HashiCorp apt repo) =="
sshx "$CT" 'set -e; export DEBIAN_FRONTEND=noninteractive
  CODENAME=$(sed -n "s/^VERSION_CODENAME=//p" /etc/os-release)
  apt-get update -qq >/dev/null; apt-get install -y -qq curl gnupg >/dev/null
  install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $CODENAME main" > /etc/apt/sources.list.d/hashicorp.list
  apt-get update -qq >/dev/null; apt-get install -y -qq vault'

echo "== 3. configure + start =="
sshx "$CT" 'cat > /etc/vault.d/vault.hcl <<EOF
storage "file" { path = "/opt/vault/data" }
listener "tcp" { address = "0.0.0.0:8200"; tls_disable = true }
api_addr = "http://<IP>:8200"
ui = true
disable_mlock = true
EOF
chown vault:vault /etc/vault.d/vault.hcl
systemctl enable --now vault'

echo "== 4. init (5/3)  ==="
sshx "$CT" 'export VAULT_ADDR=http://127.0.0.1:8200; vault operator init -key-shares=5 -key-threshold=3'
echo "   >>> SAVE the printed Unseal Keys + Initial Root Token securely (NOT in the repo)."

echo "== 5. unseal + auto-unseal + KV =="
# place 3 unseal keys (paste below) into /etc/vault.d/unseal.env, root 600
cat <<'NOTE'
Manually: put three of the unseal keys (one per line) in /etc/vault.d/unseal.env
on the CT, then run:
  for i in 1 2 3; do vault operator unseal "$(sed -n ${i}p /etc/vault.d/unseal.env)"; done
Install /usr/local/bin/vault-unseal.sh + the vault-unseal.service from the
collocated assets in this repo, then:
  vault secrets enable -path=secret kv-v2
NOTE
echo done