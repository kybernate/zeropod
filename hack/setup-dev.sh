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
        ;;
    2)
        BASE_DIR="microk8s"
        ;;
    3)
        BASE_DIR="kind"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

# Create config/dev directory
mkdir -p config/dev

# Create kustomization.yaml
cat > config/dev/kustomization.yaml << EOF
resources:
  - ../$BASE_DIR

# Uncomment and modify the lines below to override image tags for local development
# images:
# - name: zeropod-installer
#   newTag: dev
# - name: zeropod-manager
#   newTag: dev
EOF

echo "Created config/dev/kustomization.yaml"
echo ""
echo "To deploy: kubectl apply -k config/dev"
echo ""
echo "Edit config/dev/kustomization.yaml to set local image tags as needed."