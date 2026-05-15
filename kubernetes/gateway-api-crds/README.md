# gateway-api-crds

Cilium's Gateway API implementation requires the upstream CRDs to be
installed in the cluster. We use the **experimental** release, not the
standard one, because Cilium 1.16+ requires `TLSRoute` which is only in
the experimental channel. The manifest is ~1.6MB — too large to apply
via `kubernetes_manifest` from tofu — so we install it directly with
kubectl, pinned to a version.

```sh
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/experimental-install.yaml
```

Apply this **before** running `tofu apply` in `../../tofu/talos/` —
Cilium's chart requires the CRDs to be present at install time.

## Verify

```sh
kubectl get crd | grep gateway.networking.k8s.io
```

Expected: `gatewayclasses`, `gateways`, `httproutes`, `referencegrants`,
`grpcroutes`, `tlsroutes`, `tcproutes`, `udproutes`,
`backendlbpolicies`, `backendtlspolicies`.
