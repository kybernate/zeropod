# Developing on K3s

## Cluster Setup

### Single Node Setup
```bash
# Install K3s (with embedded registry and TLS SAN for remote access)
curl -sfL https://get.k3s.io | sh -s - --embedded-registry --tls-san <NODE_IP_OR_DNS>

# Set KUBECONFIG
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sudo chmod 644 $KUBECONFIG
```

> [!NOTE]
> The `--embedded-registry` flag (v1.31+) enables a peer-to-peer registry mirror on port 6443. For older versions, see the "Using a Local Registry" section below.
> The `--tls-san` flag adds the node's external IP or DNS to the API server certificate, which is required for secure access from your local dev machine.

### Multi-Node Setup
1. On the **primary node**: Follow the "Single Node Setup" above (using `--tls-san`). Then get the token:
   `sudo cat /var/lib/rancher/k3s/server/node-token`
2. On **worker nodes**:
   ```bash
   # Workers do NOT require the --tls-san flag (it is server-side only)
   curl -sfL https://get.k3s.io | K3S_URL=https://<SERVER_IP>:6443 \
     K3S_TOKEN=<NODE_TOKEN> sh -
   ```

> [!IMPORTANT]
> The `--tls-san` parameter is only required on **server nodes**. It ensures that the cluster's API certificate includes the address used by agents and external clients (like your dev machine) to reach the server.

## Build and Push Images

**For K3s (Embedded Registry):**

```bash
# If running locally on the node:
export REGISTRY=localhost:6443
# If remote, use the node's IP (ensure port 6443 is open or use SSH tunnel)
export REGISTRY=<NODE_IP>:6443
export NAMESPACE=ctrox
export TAG=dev

make push-dev REGISTRY=$REGISTRY NAMESPACE=$NAMESPACE TAG=$TAG
```

## Deploy

To avoid editing tracked files, use a local overlay:

```bash
# Create local overlay
hack/setup-dev.sh  # Select k3s

# Edit config/dev/kustomization.yaml to set image tags if needed
# Then deploy
kubectl apply -k config/dev
```

Alternatively, for direct editing (not recommended for commits):

```bash
cd config/k3s
kustomize edit set image installer=$REGISTRY/$NAMESPACE/zeropod-installer:$TAG
kustomize edit set image manager=$REGISTRY/$NAMESPACE/zeropod-manager:$TAG
kubectl apply -k .
```

## Troubleshooting

- **Check Installer Logs:** `kubectl logs -n zeropod-system -l app.kubernetes.io/name=zeropod-node -c installer`
- **Check Manager Logs:** `kubectl logs -n zeropod-system -l app.kubernetes.io/name=zeropod-node -c manager`
- **Inspect Shim Logs (on node):**
  ```bash
  # For K3s
  journalctl -u k3s | grep zeropod
  ```