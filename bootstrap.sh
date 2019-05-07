#!/bin/bash
set -e

export HOME=/root

IP=$(ip addr show ens4 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
echo $IP > /etc/oldip

hostname kubernetes
hostnamectl set-hostname kubernetes
sed -i 's/localhost$/localhost kubernetes/' /etc/hosts

ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

echo "waiting 180 seconds for cloud-init to update /etc/apt/sources.list"
timeout 180 /bin/bash -c \
  'until stat /var/lib/cloud/instance/boot-finished 2>/dev/null; do echo waiting ...; sleep 1; done'

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y install \
    git curl wget \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    conntrack \
    jq vim nano emacs joe \
    inotify-tools \
    socat make golang-go \
    docker.io \
    unzip \
    bash-completion

# Install kubernetes utilities
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y kubectl
apt-mark hold kubectl

apt-get -y remove sshguard

curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get > get_helm.sh
chmod 700 get_helm.sh && ./get_helm.sh && rm ./get_helm.sh

systemctl daemon-reload

systemctl enable docker
systemctl start docker

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--node-name=kubernetes" sh -

mkdir -p /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config

kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

kubectl -n kube-system create serviceaccount tiller
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller