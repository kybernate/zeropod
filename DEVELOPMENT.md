# Zeropod Development Guide

This guide describes how to set up a development environment, install a Kubernetes cluster (MicroK8s or K3s), and deploy/test Zeropod from a local clone.

## 1. Prerequisites

Ensure you have the following tools installed on your local machine:

- **Go**: (v1.23+) For building binaries locally.
- **Docker**: For building and pushing images.
- **kubectl**: For interacting with the cluster.
- **Kustomize**: (Usually included in kubectl >= 1.21 via `kubectl apply -k`)

## 2. Cluster Setup

### Option A: MicroK8s (Single Node or 3-Node)

**Single Node Setup:**
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

**Multi-Node Setup:**
1. On the **primary node**: `microk8s add-node`
2. Run the generated `microk8s join ...` command on the **worker nodes**.

### Option B: K3s (Single Node or 3-Node)

**Single Node Setup:**
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

**Multi-Node Setup:**
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

---

## 3. Local Development Flow

### Build and Push Images
To test your local changes, you need to build the images and push them to a registry accessible by your cluster.

#### Using an External Registry (e.g., GHCR)
```bash
# Replace with your own registry/namespace
export REGISTRY=ghcr.io
export NAMESPACE=ctrox
export TAG=dev

# Build and push installer and manager
make push-dev REGISTRY=$REGISTRY NAMESPACE=$NAMESPACE TAG=$TAG
```

#### Using a Local Registry Addon

**For MicroK8s:**
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

**For K3s (Embedded Registry):**
If you enabled `--embedded-registry`, K3s can pull images directly from the local containerd store of any node. You can simplify this by pushing to a "dummy" local registry or using `k3s ctr image import`.

> [!TIP]
> **Authentication & Security:**
> - **External Registries (GHCR, etc.):** You must run `docker login <registry>` before pushing.
> - **Local Cluster Registries:** These are usually **unauthenticated** but run over HTTP (insecure). To push from your local machine, you must add the registry to your Docker daemon's `insecure-registries` list:
>   ```json
>   // /etc/docker/daemon.json
>   {
>     "insecure-registries": ["<NODE_IP>:32000", "<NODE_IP>:<REGISTRY_PORT>"]
>   }
>   ```
>   Then restart Docker: `sudo systemctl restart docker`.
Alternatively, deploy a standard registry:
```bash
# Deploy a simple registry inside K3s
kubectl create deployment registry --image=registry:2
kubectl expose deployment registry --port=5000 --type=NodePort
# Find the NodePort
export REGISTRY_PORT=$(kubectl get svc registry -o jsonpath='{.spec.ports[0].nodePort}')
export REGISTRY=<NODE_IP>:$REGISTRY_PORT
```

> [!TIP]
> When using a local registry with HTTP (no TLS), you must allow insecure registries in your Docker/Containerd config.

### Deploy Zeropod to the Cluster

Zeropod uses Kustomize for deployment. Choose the path that matches your runtime.

**For K3s:**
```bash
cd config/k3s
kustomize edit set image installer=$REGISTRY/$NAMESPACE/zeropod-installer:$TAG
kustomize edit set image manager=$REGISTRY/$NAMESPACE/zeropod-manager:$TAG
kubectl apply -k .
```

**For MicroK8s:**
```bash
cd config/microk8s
kustomize edit set image installer=$REGISTRY/$NAMESPACE/zeropod-installer:$TAG
kustomize edit set image manager=$REGISTRY/$NAMESPACE/zeropod-manager:$TAG
kubectl apply -k .
```

---

## 4. Testing with an Example App

Once Zeropod is installed (check `kubectl get pods -n zeropod-system`), you can test it with the `http-echo` example:

```bash
# Apply the example pod
kubectl apply -f config/examples/pod.yaml

# Wait for it to be ready
kubectl get pod http-echo -w

# Test the echo service (port 8080)
# Port-forward to your local machine
kubectl port-forward pod/http-echo 8080:8080 &

# Initial request (will wake up the pod if it's scaled down)
curl localhost:8080

# Observe the logs in a separate terminal
kubectl logs -f http-echo
```

## 5. Troubleshooting

- **Check Installer Logs:** `kubectl logs -n zeropod-system -l app.kubernetes.io/name=zeropod-node -c installer`
- **Check Manager Logs:** `kubectl logs -n zeropod-system -l app.kubernetes.io/name=zeropod-node -c manager`
- **Inspect Shim Logs (on node):**
  ```bash
  # For MicroK8s
  journalctl -u snap.microk8s.daemon-containerd | grep zeropod
  # For K3s
  journalctl -u k3s | grep zeropod
  ```
