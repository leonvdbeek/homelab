# kube-prometheus-stack

[`prometheus-community/kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
running inside the Talos cluster — exposes a NodePort on `:30090` so the
central Grafana on the portainer host can scrape it as a second datasource
(no in-cluster Grafana, no in-cluster Alertmanager).

`values.yaml` is the source of truth for chart values. `kustomization.yaml`
inflates the chart via kustomize's `helmCharts:` field, so the manifest
build is fully declarative.

## Apply

```sh
kustomize build --enable-helm . \
  | kubectl apply --server-side --force-conflicts -f -
```

`--server-side` is required: the rendered output exceeds the client-side
annotation size limit. CRDs land in the same pass; if that pass races them
against the ServiceMonitor/PrometheusRule resources, just rerun once.

## Verify

```sh
kubectl -n monitoring get pods,svc
curl -s http://192.168.4.61:30090/-/ready
```

## Talos quirks already encoded in values.yaml

- `kubeProxy.enabled: false` (Talos uses Cilium, no kube-proxy)
- `kubeEtcd.enabled: false` (etcd metrics aren't exposed by default)
- `kubeControllerManager` and `kubeScheduler` endpoints pinned to the node
  IPs; `serviceMonitor.https: true + insecureSkipVerify: true`
- Namespace labelled `pod-security.../enforce: privileged` so node-exporter's
  hostNetwork/hostPID/hostPath/hostPort pods are admitted

## Uninstall

```sh
kubectl delete ns monitoring
kubectl get crd -o name | grep monitoring.coreos.com | xargs kubectl delete
```
