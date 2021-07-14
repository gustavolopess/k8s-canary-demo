# install docker
sudo apt-get remove -y docker docker-engine docker.io containerd runc 
sudo apt-get update -y
sudo apt-get install -y \
apt-transport-https \
ca-certificates \
curl \
gnupg \
lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# install minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
sudo apt install -y conntrack

# start minikube
minikube start --vm-driver docker  --cpus max  --memory 8192 --force

# install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl


# install istioctl
curl -L https://istio.io/downloadIstio | sh -
cd istio-1.10.2
export PATH=$PWD/bin:$PATH
cd ..

istioctl install --skip-confirmation

# download this repo
sudo apt install unzip
curl -LO https://github.com/gustavolopess/k8s-canary-demo/archive/refs/heads/main.zip
unzip main.zip
cd k8s-canary-demo-main

kubectl apply --filename https://raw.githubusercontent.com/istio/istio/release-1.8/samples/addons/prometheus.yaml

kubectl apply --kustomize github.com/weaveworks/flagger/kustomize/istio

kubectl create namespace nestjs-canary-demo

kubectl label namespace nestjs-canary-demo istio-injection=enabled

kubectl -n nestjs-canary-demo apply -f k8s/hpa.yaml

kubectl -n nestjs-canary-demo apply -f k8s/deployments_samples/app-v0-0-1.yaml

kubectl -n nestjs-canary-demo apply -f k8s/latency-metric.yaml

kubectl -n nestjs-canary-demo apply -f k8s/flagger-canary.yaml
kubectl -n nestjs-canary-demo apply -f k8s/istio-gateway.yaml 

# create authorizations
kubectl -n nestjs-canary-demo apply -f k8s/authorizations.yaml
kubectl auth can-i --as=system:serviceaccount:nestjs-canary-demo:github-actions-deployer list canary
kubectl auth can-i --as=system:serviceaccount:nestjs-canary-demo:github-actions-deployer list deployment

kubectl -n nestjs-canary-demo describe canary

# In another terminal
# for i in {1..10}; do 
#     curl -H "Host: nestjs-canary.demo.com" http://$INGRESS_HOST/error/0
#     sleep 0.25
# done
# should see mixed versions 0.0.1 and 0.0.2 after some time, and then turns into only 0.0.2

kubectl -n nestjs-canary-demo describe virtualservice # the weight between canary and primary should been changing in time

# Get ingress host
export INGRESS_PORT=$(kubectl \
    --namespace istio-system \
    get service istio-ingressgateway \
    --output jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')

export INGRESS_HOST=$(minikube ip):$INGRESS_PORT

export SERVICEACCOUNT_SECRET=$(kubectl describe serviceaccount -n nestjs-canary-demo \
    | grep Tokens | grep github-actions-deployer | awk '{print $2}') 

export SERVICEACCOUNT_TOKEN=$(\
    kubectl describe secret -n nestjs-canary-demo $SERVICEACCOUNT_SECRET | grep "token:" | awk '{print $2}'
)

echo -e "Env commands: \n\n\
export CLUSTER_PORT=$INGRESS_PORT\n\n\
export CLUSTER_HOST=http://ec2-54-91-87-13.compute-1.amazonaws.com:$INGRESS_PORT \n\n\
export SERVICEACCOUNT_TOKEN=$SERVICEACCOUNT_TOKEN \n\n\
export NAMESPACE_SERVICEACCOUNT=github-actions-deployer \n\n\
export NAMESPACE=nestjs-canary-demo\n\n"


