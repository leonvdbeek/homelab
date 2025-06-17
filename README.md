# homelab
Homelab config files

To get Tofu running:
```
eval $(ssh-agent)
ssh-add ~/.ssh/id_....
tofu init
tofu plan
tofu apply
```

To create first kustomize stuff
```
kustomize build --enable-helm ../k8s/ | kubectl apply -f - 
```

To create a Sealed Secret
```
kubectl -n <namespace> create secret generic <name> --dry-run=client --from-literal <name>=<secretValue> --output json | kubeseal --format yaml | tee <fileName>.yaml
```

Notes:
When Kubevip can not get IPs:
kubectl label namespace kube-vip pod-security.kubernetes.io/enforce=privileged --overwrite