#!/bin/bash

# Setup script for local development overlay

set -e

echo "Zeropod Local Dev Setup"
echo "========================"
echo ""
echo "This script creates a local kustomize overlay in config/dev/"
echo "to avoid committing changes to versioned kustomization.yaml files."
echo ""

# Ask user for cluster type
echo "Select your cluster type:"
echo "1) k3s"
echo "2) microk8s"
echo "3) kind"
read -p "Enter choice (1-3): " choice

case $choice in
    1)
        BASE_DIR="k3s"
        REGISTRY="localhost:6443"
        ;;
    2)
        BASE_DIR="microk8s"
        REGISTRY="localhost:32000"
        ;;
    3)
        BASE_DIR="kind"
        REGISTRY="ghcr.io/ctrox"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

NAMESPACE=${NAMESPACE:-ctrox}

# Create config/dev directory
mkdir -p config/dev

# Create kustomization.yaml
cat > config/dev/kustomization.yaml << EOF
resources:
  - ../$BASE_DIR

# Images are overridden here to use the local registry.
# Note: The 'name' fields must match the transformed names from config/production/kustomization.yaml,
# since production already overrides the base images. Using the original names (e.g., 'installer' and 'manager')
# would not work because Kustomize applies transforms sequentially.
images:
- name: ghcr.io/ctrox/zeropod-installer
  newName: $REGISTRY/$NAMESPACE/zeropod-installer
  newTag: dev
- name: ghcr.io/ctrox/zeropod-manager
  newName: $REGISTRY/$NAMESPACE/zeropod-manager
  newTag: dev
EOF

echo "Created config/dev/kustomization.yaml"
echo ""
echo "To deploy: kubectl apply -k config/dev"
echo ""
echo "Edit config/dev/kustomization.yaml to set local image tags as needed."