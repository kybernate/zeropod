# Development

This guide describes how to set up a development environment and deploy/test Zeropod from a local clone.

## Prerequisites

Ensure you have the following tools installed on your local machine:

- **Go**: (v1.23+) For building binaries locally.
- **Docker**: For building and pushing images.
- **kubectl**: For interacting with the cluster.
- **Kustomize**: (Usually included in kubectl >= 1.21 via `kubectl apply -k`)

## Cluster Setup

See the specific guides for your preferred cluster:
- [Kind](./kind.md)
- [MicroK8s](./microk8s.md)
- [K3s](./k3s.md)
- [M1 Mac](./mac_m1.md)

## Local Development Flow

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

See the specific cluster guides for local registry setup.

### Deploy Zeropod to the Cluster

Zeropod uses Kustomize for deployment. To avoid committing changes to versioned files, use a local overlay:

```bash
# Run the setup script to create config/dev/
hack/setup-dev.sh

# Edit config/dev/kustomization.yaml to set image tags
# Then deploy
kubectl apply -k config/dev
```

Choose the path that matches your runtime and follow the instructions in the specific cluster guide.