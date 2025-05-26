kubectl run dnsutils --image=busybox:1.28 --restart=Never --command -- sleep 3600
kubectl exec -it dnsutils -- nslookup acrd01.privatelink.azurecr.io
