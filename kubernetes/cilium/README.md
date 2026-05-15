# cilium

Cilium replaces Flannel as the CNI on this Talos cluster and provides:
- Pod networking (no `kube-proxy` — `kubeProxyReplacement: true`)
- Gateway API implementation (`gatewayAPI.enabled: true`)
- LoadBalancer IP assignment via LB IPAM + L2 announcements (no MetalLB)
- Hubble observability (no UI; metrics scraped by the in-cluster Prometheus)

`values.yaml` is the source of truth for chart values. Tofu installs the
chart via `helm_release` — see `../../tofu/talos/cilium.tf`.

The post-install resources in this directory (LB IP pool, L2 policy, the
shared Gateway) are applied via kustomize after the chart is healthy:

```sh
kubectl apply -k .
```

## One-time migration from Flannel

The cluster is currently Flannel + kube-proxy. Switching to Cilium is a
**runtime CNI swap**, which has a brief outage. Steps:

1. **Patch Talos.** `tofu -chdir=../../tofu/talos apply` — the patches in
   `talos.tf` and `cilium.tf` set `cluster.network.cni.name=none` and
   `cluster.proxy.disabled=true`, then install Cilium via helm.
2. **Delete the old DaemonSets** (Tofu doesn't own them):
   ```sh
   kubectl -n kube-system delete daemonset kube-flannel kube-proxy
   ```
3. **Roll all pods** so they pick up Cilium-assigned IPs:
   ```sh
   kubectl get pods -A -o wide | awk '{print $1, $2}' | xargs -L1 kubectl -n
   ```
   (or just reboot the nodes one at a time)
4. **Apply the post-install resources**: `kubectl apply -k .`
5. **Verify**:
   ```sh
   kubectl -n kube-system get pods -l k8s-app=cilium
   kubectl get gatewayclass cilium
   kubectl -n gateway get gateway lan
   cilium status   # if you have the cilium CLI installed
   ```

## LB IP pool

`192.168.4.240-192.168.4.250` — carve-out outside the UniFi DHCP pool.
Change in `lb-pool.yaml` if you need to grow it.
