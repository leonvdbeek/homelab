#!/bin/bash
# Unseal Vault at boot with the 3 Shamir keys in /etc/vault.d/unseal.env (root 600).
set -u
export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
k=/etc/vault.d/unseal.env
/usr/bin/vault status -address="$VAULT_ADDR" | grep -qi "Sealed *false" && exit 0
for i in 1 2 3; do
  key="$(sed -n "${i}p" "$k")"
  [ -n "$key" ] || continue
  /usr/bin/vault operator unseal -address="$VAULT_ADDR" "$key" >/dev/null 2>&1 || true
  /usr/bin/vault status -address="$VAULT_ADDR" | grep -qi "Sealed *false" && break
done