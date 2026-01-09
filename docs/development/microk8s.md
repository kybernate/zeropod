# Developing on MicroK8s

## Cluster Setup

### Single Node Setup
```bash
# Install MicroK8s
sudo snap install microk8s --classic

# Enable required addons (including registry)
sudo microk8s enable dns storage registry

# Wait for readiness
sudo microk8s status --wait-ready

# Alias kubectl (optional)
sudo snap alias microk8s.kubectl kubectl
```

### Multi-Node Setup
1. On the **primary node**: `microk8s add-node`
2. Run the generated `microk8s join ...` command on the **worker nodes**.

## Build and Push Images

MicroK8s provides a registry addon on port `32000`. You can push to it using the node's IP.

```bash
# If running locally on the node:
export REGISTRY=localhost:32000
# If remote, use the node's IP (ensure port 32000 is open or use SSH tunnel)
export REGISTRY=<NODE_IP>:32000
export NAMESPACE=ctrox
export TAG=dev

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

## Troubleshooting

- **Check Installer Logs:** `kubectl logs -n zeropod-system -l app.kubernetes.io/name=zeropod-node -c installer`
- **Check Manager Logs:** `kubectl logs -n zeropod-system -l app.kubernetes.io/name=zeropod-node -c manager`
- **Inspect Shim Logs (on node):**
  ```bash
  # For MicroK8s
  journalctl -u snap.microk8s.daemon-containerd | grep zeropod
  ```