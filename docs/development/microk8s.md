# Developing on MicroK8s

## Cluster Setup

### Single Node Setup
```bash
# Install MicroK8s
sudo snap install microk8s --classic --channel=latest/stable
sudo usermod -aG microk8s $USER
newgrp microk8s

# Enable required addons (including registry)
sudo microk8s enable dns storage registry

# Wait for readiness
sudo microk8s status --wait-ready

# Alias kubectl (optional)
sudo snap alias microk8s.kubectl kubectl
```

### Configure kubectl Access from Client

After successful MicroK8s installation on the remote server/cluster, run the following command on the server to get the kubeconfig:

```bash
microk8s config
```

Copy the output to your local machine's `~/.kube/config` file. If necessary, adjust the IP address in the config to match the server's external IP.

### Multi-Node Setup
1. On the **primary node**: `microk8s add-node`
2. Run the generated `microk8s join ...` command on the **worker nodes**.

## Build and Push Images

MicroK8s provides a registry addon on port `32000`. You can push to it using the node's IP.

### Set Environment Variables

```bash
# If running locally on the node:
export REGISTRY=localhost:32000
# If remote, use the node's IP (ensure port 32000 is open or use SSH tunnel)
export REGISTRY=<NODE_IP>:32000
export NAMESPACE=ctrox
export TAG=dev
```

### Configure Client for Insecure Registry

Since the MicroK8s registry runs over HTTP without TLS, you need to configure your local Docker daemon to allow insecure registries.

```bash
# Activate insecure registries on the client
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "insecure-registries": ["$REGISTRY"]
}
EOF

sudo systemctl restart docker

# Optional: arm64 builder setup
docker run --privileged --rm tonistiigi/binfmt --install all

mkdir -p ~/.config/buildkit
cat > ~/.config/buildkit/buildkitd.toml <<EOF
[registry."$REGISTRY"]
  http = true
  insecure = true
EOF

docker buildx rm multi 2>/dev/null || true
docker buildx create --name multi --driver docker-container --use --config ~/.config/buildkit/buildkitd.toml
docker buildx inspect --bootstrap
```

### Build and Push Images

Now you can build and push the images:

```bash
make build-criu REGISTRY=$REGISTRY NAMESPACE=$NAMESPACE
make push-dev REGISTRY=$REGISTRY NAMESPACE=$NAMESPACE TAG=$TAG
```

## Deploy

To avoid editing tracked files, use a local overlay:

```bash
# Create local overlay
hack/setup-dev.sh  # Select microk8s

# Edit config/dev/kustomization.yaml to set image tags if needed
# Then deploy
kubectl apply -k config/dev
```

Alternatively, for direct editing (not recommended for commits):

```bash
cd config/microk8s
kustomize edit set image installer=$REGISTRY/$NAMESPACE/zeropod-installer:$TAG
kustomize edit set image manager=$REGISTRY/$NAMESPACE/zeropod-manager:$TAG
kubectl apply -k .
```

## Label Nodes

By default, Zeropod will only be installed on nodes with the label `zeropod.ctrox.dev/node=true`. After applying the manifest, label your node(s) accordingly:

```bash
kubectl label node <node-name> zeropod.ctrox.dev/node=true
```

## Troubleshooting

- **Check Installer Logs:** `kubectl logs -n zeropod-system -l app.kubernetes.io/name=zeropod-node -c installer`
- **Check Manager Logs:** `kubectl logs -n zeropod-system -l app.kubernetes.io/name=zeropod-node -c manager`
- **Inspect Shim Logs (on node):**
  ```bash
  # For MicroK8s
  journalctl -u snap.microk8s.daemon-containerd | grep zeropod
  ```