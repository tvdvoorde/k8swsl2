apt-get -y update
apt-get -y install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
apt-get -y update
apt-get -y install docker-ce docker-ce-cli containerd.io

# ETCD KUBERNETES
wget -q --show-progress --https-only --timestamping "https://github.com/coreos/etcd/releases/download/v3.3.9/etcd-v3.3.9-linux-amd64.tar.gz"
tar -xvf etcd-v3.3.9-linux-amd64.tar.gz
mv etcd-v3.3.9-linux-amd64/etcd* /usr/local/bin/
wget -q --show-progress --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/v1.14.0/bin/linux/amd64/kube-apiserver" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.14.0/bin/linux/amd64/kube-controller-manager" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.14.0/bin/linux/amd64/kube-scheduler" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.14.0/bin/linux/amd64/kubectl" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.14.0/bin/linux/amd64/kube-proxy" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.14.0/bin/linux/amd64/kubelet"
chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl kubelet kube-proxy
mv kube-apiserver kube-controller-manager kube-scheduler kubectl kubelet kube-proxy /usr/local/bin/
iptables -P FORWARD ACCEPT
mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes 
wget -q --show-progress --https-only --timestamping "https://github.com/containernetworking/plugins/releases/download/v0.7.5/cni-plugins-amd64-v0.7.5.tgz"
tar -xzvf cni-plugins-amd64-v0.7.5.tgz --directory /opt/cni/bin/

### apt-get update
### apt-get install -y socat conntrack ipset docker.io

cd ~

openssl genrsa -out ca-key.pem 2048
openssl req -x509 -new -nodes -key ca-key.pem -subj "/CN=Kubernetes" -days 10000 -out ca.pem
openssl genrsa -out kubernetes-key.pem 2048

INSTANCE=$(hostname -s)

cat > kubernetes.conf <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn
[ dn ]
C = NL
ST = ZH
L = Den Haag
O = IT
OU = IT
CN = kubernetes
[ req_ext ]
subjectAltName = @alt_names
[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = ${INSTANCE}
DNS.4 = localhost
IP.1 = 127.0.0.1
IP.2 = 10.96.0.1
[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
EOF

openssl req -new -key kubernetes-key.pem -out kubernetes.csr -config kubernetes.conf
openssl x509 -req -in kubernetes.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out kubernetes.pem -days 10000 -extensions v3_ext -extfile kubernetes.conf

ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

openssl genrsa -out service-account-key.pem 2048
openssl req -new -key service-account-key.pem -out service-account.csr -subj "/CN=service-accounts"
openssl x509 -req -in service-account.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out service-account.pem -days 10000 
openssl genrsa -out kube-controller-manager-key.pem 2048
openssl req -new -key kube-controller-manager-key.pem -out kube-controller-manager.csr -subj "/CN=system:kube-controller-manager/O=system:kube-controller-manager"
openssl x509 -req -in kube-controller-manager.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out kube-controller-manager.pem -days 10000 
openssl genrsa -out kube-proxy-key.pem 2048
openssl req -new -key kube-proxy-key.pem -out kube-proxy.csr -subj "/CN=system:kube-proxy/O=system:node-proxier"
openssl x509 -req -in kube-proxy.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out kube-proxy.pem -days 10000 
openssl genrsa -out kube-scheduler-key.pem 2048
openssl req -new -key kube-scheduler-key.pem -out kube-scheduler.csr -subj "/CN=system:kube-scheduler/O=system:kube-scheduler"
openssl x509 -req -in kube-scheduler.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out kube-scheduler.pem -days 10000 
openssl genrsa -out admin-key.pem 2048
openssl req -new -key admin-key.pem -out admin.csr -subj "/CN=admin/O=system:masters"
openssl x509 -req -in admin.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out admin.pem -days 10000 

INSTANCE=$(hostname -s)

openssl genrsa -out localhost-key.pem 2048
cat > localhost.conf <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn
[ dn ]
C = NL
ST = ZH
L = Den Haag
O = system:nodes
OU = IT
CN = system:node:${INSTANCE,,}
[ req_ext ]
subjectAltName = @alt_names
[ alt_names ]
DNS.1 = ${INSTANCE,,}
DNS.2 = localhost
IP.1 = 127.0.0.1
[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
EOF

openssl req -new -key localhost-key.pem -out localhost.csr -config localhost.conf
openssl x509 -req -in localhost.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out localhost.pem -days 10000 -extensions v3_ext -extfile localhost.conf

mkdir -p /var/lib/kubernetes/
mv /root/ca.pem \
  /root/ca-key.pem \
  /root/kubernetes-key.pem \
  /root/kubernetes.pem \
  /root/service-account-key.pem \
  /root/service-account.pem \
  /root/encryption-config.yaml \
  /var/lib/kubernetes/

kubectl config set-cluster singlenode \
  --certificate-authority=/var/lib/kubernetes/ca.pem \
  --embed-certs=true \
  --server=https://localhost:6443 \
  --kubeconfig=localhost.kubeconfig
kubectl config set-credentials system:node:${INSTANCE,,} \
  --client-certificate=localhost.pem \
  --client-key=localhost-key.pem \
  --embed-certs=true \
  --kubeconfig=localhost.kubeconfig
kubectl config set-context default \
  --cluster=singlenode \
  --user=system:node:${INSTANCE,,} \
  --kubeconfig=localhost.kubeconfig
kubectl config use-context default --kubeconfig=localhost.kubeconfig

kubectl config set-cluster singlenode \
  --certificate-authority=/var/lib/kubernetes/ca.pem \
  --embed-certs=true \
  --server=https://localhost:6443 \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config set-credentials system:kube-proxy \
  --client-certificate=kube-proxy.pem \
  --client-key=kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config set-context default \
  --cluster=singlenode \
  --user=system:kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

kubectl config set-cluster singlenode \
  --certificate-authority=/var/lib/kubernetes/ca.pem \
  --embed-certs=true \
  --server=https://localhost:6443 \
  --kubeconfig=kube-controller-manager.kubeconfig
kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=kube-controller-manager.pem \
  --client-key=kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-controller-manager.kubeconfig
kubectl config set-context default \
  --cluster=singlenode \
  --user=system:kube-controller-manager \
  --kubeconfig=kube-controller-manager.kubeconfig
kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-cluster singlenode \
  --certificate-authority=/var/lib/kubernetes/ca.pem \
  --embed-certs=true \
  --server=https://localhost:6443 \
  --kubeconfig=kube-scheduler.kubeconfig
kubectl config set-credentials system:kube-scheduler \
  --client-certificate=kube-scheduler.pem \
  --client-key=kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-scheduler.kubeconfig
kubectl config set-context default \
  --cluster=singlenode \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig
kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-cluster singlenode \
  --certificate-authority=/var/lib/kubernetes/ca.pem \
  --embed-certs=true \
  --server=https://localhost:6443 \
  --kubeconfig=admin.kubeconfig
kubectl config set-credentials admin \
  --client-certificate=admin.pem \
  --client-key=admin-key.pem \
  --embed-certs=true \
  --kubeconfig=admin.kubeconfig
kubectl config set-context default \
  --cluster=singlenode \
  --user=admin \
  --kubeconfig=admin.kubeconfig
kubectl config use-context default --kubeconfig=admin.kubeconfig

mv /root/kube-controller-manager.kubeconfig /var/lib/kubernetes/
mv /root/kube-scheduler.kubeconfig /var/lib/kubernetes/

mkdir -p /etc/etcd /var/lib/etcd
cp /var/lib/kubernetes/ca.pem \
        /var/lib/kubernetes/kubernetes-key.pem \
        /var/lib/kubernetes/kubernetes.pem \
        /etc/etcd/

start-stop-daemon --start --background --no-close --exec "/usr/local/bin/etcd" -- \
  --name localhost \
  --cert-file=/etc/etcd/kubernetes.pem \
  --key-file=/etc/etcd/kubernetes-key.pem \
  --trusted-ca-file=/etc/etcd/ca.pem \
  --client-cert-auth \
  --listen-client-urls https://localhost:2379 \
  --advertise-client-urls https://localhost:2379 \
  --data-dir=/var/lib/etcd >>"/var/log/etcd.log" 2>&1

start-stop-daemon --start --background --no-close --exec /usr/local/bin/kube-apiserver -- \
  --allow-privileged=true \
  --apiserver-count=1 \
  --audit-log-maxage=30 \
  --audit-log-maxbackup=1 \
  --audit-log-maxsize=100 \
  --audit-log-path=/var/log/audit.log  \
  --authorization-mode=Node,RBAC \
  --bind-address=0.0.0.0 \
  --client-ca-file=/var/lib/kubernetes/ca.pem  \
  --enable-admission-plugins=NodeRestriction,ServiceAccount \
  --enable-swagger-ui=true \
  --etcd-cafile=/var/lib/kubernetes/ca.pem \
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \
  --etcd-servers=https://localhost:2379 \
  --event-ttl=1h \
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \
  --kubelet-https=true \
  --runtime-config=api/all \
  --service-account-key-file=/var/lib/kubernetes/service-account.pem  \
  --service-cluster-ip-range=10.96.0.0/12 \
  --service-node-port-range=30000-32767 \
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \
  --v=2 >>"/var/log/kube-apiserver.log" 2>&1

start-stop-daemon --start --background --no-close --exec /usr/local/bin/kube-controller-manager -- \
  --address=0.0.0.0 \
  --cluster-cidr=10.32.0.0/12 \
  --cluster-name=kubernetes \
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \
  --leader-elect=true \
  --root-ca-file=/var/lib/kubernetes/ca.pem \
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \
  --service-cluster-ip-range=10.96.0.0/12 \
  --use-service-account-credentials=true \
  --v=2 >> "/var/log/kube-controller-manager" 2>&1

start-stop-daemon --start --background --no-close --exec /usr/local/bin/kube-scheduler -- \
  --kubeconfig=/var/lib/kubernetes/kube-scheduler.kubeconfig \
  --address=0.0.0.0 \
  --leader-elect=true \
  --v=2 >> "/var/log/kube-scheduler.log" 2>&1

cat <<EOF | kubectl apply --kubeconfig /root/admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

cat <<EOF | kubectl apply --kubeconfig /root/admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF

INSTANCE=$(hostname -s)
mv /root/localhost-key.pem \
   /root/localhost.pem \
   /var/lib/kubelet/
mv /root/localhost.kubeconfig /var/lib/kubelet/kubeconfig

kubectl get componentstatuses

cat <<EOF | sudo tee /etc/cni/net.d/10-bridge.conf
{
    "cniVersion": "0.3.1",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "10.32.0.0/12"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF

cat <<EOF | sudo tee /etc/cni/net.d/99-loopback.conf
{
    "cniVersion": "0.3.1",
    "type": "loopback"
}
EOF

cat <<EOF | tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.96.0.10"
podCIDR: "10.32.0.0/12"
resolvConf: "/etc/resolv.conf"
runtimeRequestTimeout: "15m"
EOF

mv /root/kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig

cat <<EOF | tee /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.96.0.0/12"
EOF

start-stop-daemon --start --background --no-close --exec /usr/local/bin/kube-proxy -- \
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml >> "/var/log/kube-proxy.log" 2>&1

service docker start

start-stop-daemon --start --background --no-close --exec /usr/local/bin/kubelet -- \
  --config=/var/lib/kubelet/kubelet-config.yaml \
  --image-pull-progress-deadline=2m \
  --kubeconfig=/var/lib/kubelet/kubeconfig \
  --network-plugin=cni \
  --register-node=true \
  --tls-cert-file=/var/lib/kubelet/localhost.pem \
  --tls-private-key-file=/var/lib/kubelet/localhost-key.pem \
  --fail-swap-on=false \
  --v=2  >> "/var/log/kubelet.log" 2>&1

kubectl get nodes

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:coredns
rules:
- apiGroups:
  - ""
  resources:
  - endpoints
  - services
  - pods
  - namespaces
  verbs:
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:coredns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:coredns
subjects:
- kind: ServiceAccount
  name: coredns
  namespace: kube-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
        } 
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/name: "CoreDNS"
spec:
  replicas: 1
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
    spec:
      priorityClassName: system-cluster-critical
      serviceAccountName: coredns
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
      nodeSelector:
        beta.kubernetes.io/os: linux
      containers:
      - name: coredns
        image: coredns/coredns:1.5.0
        imagePullPolicy: IfNotPresent
        resources:
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        args: [ "-conf", "/etc/coredns/Corefile" ]
        volumeMounts:
        - name: config-volume
          mountPath: /etc/coredns
          readOnly: true
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        - containerPort: 9153
          name: metrics
          protocol: TCP
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            add:
            - NET_BIND_SERVICE
            drop:
            - all
          readOnlyRootFilesystem: true
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /ready
            port: 8181
            scheme: HTTP
      dnsPolicy: Default
      volumes:
        - name: config-volume
          configMap:
            name: coredns
            items:
            - key: Corefile
              path: Corefile
---
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  annotations:
    prometheus.io/port: "9153"
    prometheus.io/scrape: "true"
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: "CoreDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: 10.96.0.10
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
  - name: metrics
    port: 9153
    protocol: TCP
EOF

iptables -P FORWARD ACCEPT

kubectl get componentstatuses
kubectl get pods -o wide -A
kubectl get nodes 
kubectl run nginx --image=nginx --port=80 --restart=Never
kubectl get pods -o wide -A
kubectl expose pod nginx --type=ClusterIP
kubectl run busybox --image=busybox:1.28 -it --restart=Never -- sleep 3600
# kubectl exec busybox -it -- nslookup nginx
