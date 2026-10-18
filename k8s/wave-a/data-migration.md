# Wave A — data migration (docker host -> cluster PVCs)

Stateful data for homepage/ntfy/uptime-kuma lives on TrueNAS **iSCSI** volumes
(`truenas-iscsi-fast`, block devs formatted ext4 and mounted by the CSI node
plugin into pods). Migrating requires writing the data into the *mounted*
filesystem of a pod — there is no SSH on the Talos node and the PVCs are block
devices, so the data is pushed through a temporary **migrator pod** that mounts
the claims.

## Source (docker host .73)
- homepage config     `/home/leon/portainer/homepage/config`       (872 K)
- ntfy                `/home/leon/portainer/ntfy/{etc,cache,var/lib}` (empty)
- uptime-kuma data    `/home/leon/portainer/uptime-kuma-data`        (777 M)

## Procedure
```sh
# 1. Stop the cluster app (avoid clobbering the empty PVC):
kubectl -n apps scale deploy homepage ntfy uptime-kuma --replicas=0

# 2. Stage the source off .73 to the control host (rsync over the existing SSH):
RSH="ssh -F /root/.ssh/config -i /root/.ssh/id_ed25519_hermes -o BatchMode=yes"
rsync -a -e "$RSH" portainer:/home/leon/portainer/homepage/config/   ~/.scratch/wavea/homepage/
rsync -a -e "$RSH" portainer:/home/leon/portainer/ntfy/              ~/.scratch/wavea/ntfy/
rsync -a -e "$RSH" portainer:/home/leon/portainer/uptime-kuma-data/  ~/.scratch/wavea/uptime/

# 3. Migrator pod mounts the claims:
kubectl -n apps apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: migrator, namespace: apps}
spec:
  restartPolicy: Never
  containers:
  - name: migrator
    image: busybox
    command: ["/bin/sh","-c","sleep 3600"]
    volumeMounts:
    - {name: home,   mountPath: /migrate/homepage}
    - {name: uptime, mountPath: /migrate/uptime}
    - {name: ntfy,   mountPath: /migrate/ntfy}
  volumes:
  - {name: home,   persistentVolumeClaim: {claimName: homepage-config}}
  - {name: uptime, persistentVolumeClaim: {claimName: uptime-kuma-data}}
  - {name: ntfy,   persistentVolumeClaim: {claimName: ntfy-data}}
EOF

# 4. Push staged data into the mounted filesystems:
kubectl -n apps cp ~/.scratch/wavea/homepage/. migrator:/migrate/homepage/
kubectl -n apps cp ~/.scratch/wavea/uptime/.   migrator:/migrate/uptime/
kubectl -n apps cp ~/.scratch/wavea/ntfy/.     migrator:/migrate/ntfy/
# ntfy subPath dirs (etc, cache, var/lib) are created by the mounts.

kubectl -n apps delete pod migrator
# 5. Scale the apps back to 1.
```

## Notes
- uptime-kuma is SQLite (kuma.db + -wal/-shm). For a fully clean restore, stop
  the container on .73 first (checkpoint the WAL); .73 remains the rollback.
- homepage's docker widget and uptime-kuma's Docker monitors need the docker
  socket, which does not exist on Talos — those specific integrations won't show
  data on-cluster (the rest of the apps work normally).