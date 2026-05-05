# Thin extension of upstream autopve with extras needed by our register-netbox playbook.
# Bump the FROM tag (or add --pull on build) to upgrade autopve itself.
FROM ghcr.io/natankeddem/autopve:latest

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends sshpass openssh-client \
 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir pynetbox
# entrypoint / user are inherited from base
