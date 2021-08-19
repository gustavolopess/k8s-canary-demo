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

# apply prometheus to istio
kubectl apply --filename https://raw.githubusercontent.com/istio/istio/release-1.8/samples/addons/prometheus.yaml

# apply flagger to istio
kubectl apply --kustomize github.com/weaveworks/flagger/kustomize/istio

# create application's namespace
kubectl create namespace nestjs-canary-demo
# inject istio's sidecar on this namespace
kubectl label namespace nestjs-canary-demo istio-injection=enabled

# create the hpa
kubectl -n nestjs-canary-demo apply -f k8s/hpa.yaml

# create an istion's gateway and an flagger's canary into application's namesapce
kubectl -n nestjs-canary-demo apply -f k8s/flagger-canary.yaml
kubectl -n nestjs-canary-demo apply -f k8s/istio-gateway.yaml 


kubectl -n nestjs-canary-demo apply -f k8s/latency-metric.yaml

# create authorizations
kubectl -n nestjs-canary-demo apply -f k8s/authorizations.yaml
kubectl auth can-i --as=system:serviceaccount:nestjs-canary-demo:github-actions-deployer list canary
kubectl auth can-i --as=system:serviceaccount:nestjs-canary-demo:github-actions-deployer list deployment

kubectl -n nestjs-canary-demo describe canary

# deploy a first version
kubectl -n nestjs-canary-demo apply -f k8s/deployments_samples/app-v0-0-1.yaml
# wait deployment finish and then deploy a second version
kubectl -n nestjs-canary-demo apply -f k8s/deployments_samples/app-v0-0-2.yaml

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

# port forwarding (external -> loopback) with rinetd 
sudo apt-get install -y rinetd

# bind port 8443 to minikube and 8080 to application
echo "${NEWLINE}
# bindadress    bindport  connectaddress  connectport${NEWLINE}
#0.0.0.0         8443      $(minikube ip)   8443${NEWLINE}
0.0.0.0         8080      $(minikube ip)   $INGRESS_PORT${NEWLINE}

# logging information${NEWLINE}
logfile /var/log/rinetdn.log${NEWLINE}" > /etc/rinetd.conf

/etc/init.d/rinetd restart

echo -e "Env commands: \n\n\
export CLUSTER_PORT=8080\n\n\
export CLUSTER_HOST=https://ec2-3-80-38-40.compute-1.amazonaws.com:8443 \n\n\
export APPLICATION_URL=http://ec2-3-80-38-40.compute-1.amazonaws.com:8080/error/0 \n\n\
export SERVICEACCOUNT_TOKEN=$SERVICEACCOUNT_TOKEN \n\n\
export NAMESPACE_SERVICEACCOUNT=github-actions-deployer \n\n\
export NAMESPACE=nestjs-canary-demo\n\n"


