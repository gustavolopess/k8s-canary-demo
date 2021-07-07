istioctl install --skip-confirmation

kubectl apply --filename https://raw.githubusercontent.com/istio/istio/release-1.8/samples/addons/prometheus.yaml

kubectl apply --kustomize github.com/weaveworks/flagger/kustomize/istio

kubectl create namespace nestjs-canary-demo

kubectl label namespace nestjs-canary-demo istio-injection=enabled

kubectl -n nestjs-canary-demo apply -f k8s/hpa.yaml

kubectl -n nestjs-canary-demo apply -f k8s/deployments_samples/app-v0-0-1.yaml

kubectl -n nestjs-canary-demo apply -f k8s/latency-metric.yaml

kubectl -n nestjs-canary-demo apply -f k8s/flagger-canary.yaml
kubectl -n nestjs-canary-demo apply -f k8s/istio-gateway.yaml 

# Get ingress host
export INGRESS_PORT=$(kubectl \
    --namespace istio-system \
    get service istio-ingressgateway \
    --output jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')

export INGRESS_HOST=$(minikube ip):$INGRESS_PORT

kubectl -n nestjs-canary-demo describe canary

# In another terminal
# for i in {1..10}; do 
#     curl -H "Host: nestjs-canary.demo.com" http://$INGRESS_HOST/error/0
#     sleep 0.25
# done
# should see mixed versions 0.0.1 and 0.0.2 after some time, and then turns into only 0.0.2

kubectl -n nestjs-canary-demo describe virtualservice # the weight between canary and primary should been changing in time

