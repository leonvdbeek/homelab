# Vault — secrets management (homelab)

HashiCorp Vault single-node instance in an LXC on `m920x`, used as the source of
truth for all task credentials rather than ad-hoc secret files.

## Runtime
- **LXC**: VMID `106`, hostname `vault`, Debian 13 template, `192.168.4.232`,
  1 vCPU / 1 GiB RAM / 6 GiB disk on `local-lvm`, network via `vmbr0`, auto-start.
- **Vault**: v2.2.0, file storage at `/opt/vault/data`, listener `0.0.0.0:8200`
  (plain HTTP on the LAN), KV **v2** engine mounted at `secret/`.
- **Auto-unseal**: systemd `vault-unseal.service` runs `/usr/local/bin/vault-unseal.sh`
  on boot (reads 3 Shamir keys from `/etc/vault.d/unseal.env`, root-only).
- **Initialization**: 5 key-shares / 3 threshold; keys + root token are held by the
  operator (Leon) and backed up at `~/.hermes/vault/` on the control host.

## Secrets (path -> content)
- `secret/homelab/cloudflare`  -> `api_key`, `email`, `ddns_api_token` (UniFi DDNS CF token)
- `secret/homelab/truenas`     -> `api_key` (truenas_csi driver)
- `secret/homelab/proxmox`     -> `api_token_secret` (PVE terraform token)
- `secret/homelab/openrouter`  -> `api_key`
- `secret/homelab/telegram`    -> `home_channel`
- (extend under `secret/homelab/*` as new credentials appear)

## Access
```
export VAULT_ADDR=http://192.168.4.232:8200
vault login             # root token (or a scoped token via a policy on secret/homelab/*)
vault kv get secret/homelab/truenas
```

## Reproduce
`bootstrap-vault.sh` re-runs the full provisioning (LXC create -> install ->
init -> unseal -> store secrets) against a fresh state. It does NOT contain
secret values; it sources them from the control host's local secret files
(`~/.hermes/.env`, `~/.hermes/vault/*`, homelab-cluster/secrets) or interactive
prompts, and prints a new init block to save.