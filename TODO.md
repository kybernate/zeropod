# Documentation & Configuration Improvement Plan

# Documentation & Configuration Improvement Plan

## 1. Documentation Organization Strategy

Instead of a monolithic `DEVELOPMENT.md`, we will structure documentation into a clean hierarchy within the `docs/` folder, following naming conventions.

### **Proposed Hierarchy**
```text
docs/
├── architecture/
│   ├── overview.md       (Moved from ARCHITECTURE.md)
│   └── diagrams/         (Optional: any future detailed diagrams)
├── development/
│   ├── index.md          (General prerequisites, 'Getting Started', dev flow)
│   ├── kind.md           (Kind-specific setup & workflows)
│   ├── k3s.md            (K3s setup, --tls-san, local registry instructions)
│   ├── microk8s.md       (MicroK8s setup, registry addon instructions)
│   └── mac_m1.md         (Special handling for M1/Silicon macs)
└── configuration/        (Existing config docs)
```

### **Root Files**
- `DEVELOPMENT.md`: Replace with a brief pointer/index linking to `docs/development/index.md` and the sub-guides.
- `ARCHITECTURE.md`: Move content to `docs/architecture/overview.md` and remove this file.
- `README.md`: Update links to point to the new locations.

## 2. Dev Environment Parameterization (Preventing Accidental Commits)

## 2. Dev Environment Parameterization (Preventing Accidental Commits)

The current workflow requires modifying versioned `kustomization.yaml` files to set image tags or local registry/runtime flags.

**Proposed Solution: "Local Dev Overlay" Pattern**

Instead of editing `config/k3s/kustomization.yaml` directly, we should support a `.gitignore`'d local configuration overlay.

### **Implementation Plan**

1.  **Ignore Local Configs**: Add `config/dev/` to `.gitignore`.
2.  **Create Boilerplate**: Create a script or Make target (e.g., `make setup-dev-config`) that generates a `config/dev/kustomization.yaml`.
    - This file will `resources: ["../config/k3s"]` (or microk8s).
    - It allows the user to use `kustomize edit set image` *on this local file* without affecting the repository.
3.  **Update Workflows**:
    - Update `DEVELOPMENT.md` to use this new path: `kubectl apply -k config/dev`.

## 3. Action Items
- [ ] **Create Directory Structure**:
  - `mkdir -p docs/development`
  - `mkdir -p docs/architecture`
- [ ] **Migrate Architecture Docs**:
  - Move `ARCHITECTURE.md` to `docs/architecture/overview.md`.
  - Update `README.md` links.
  - Delete `ARCHITECTURE.md`.
- [ ] **Migrate Development Docs**:
  - Extract `kind` instructions from `docs/development.md` -> `docs/development/kind.md`.
  - Extract M1 Mac instructions -> `docs/development/mac_m1.md`.
  - Extract K3s instructions from `DEVELOPMENT.md` -> `docs/development/k3s.md`.
  - Extract MicroK8s instructions from `DEVELOPMENT.md` -> `docs/development/microk8s.md`.
  - Create `docs/development/index.md` with general prereqs and flow (build/push logic).
- [ ] **Cleanup**:
  - Replace root `DEVELOPMENT.md` with a simple index file pointing to `docs/development/`.
  - Delete old `docs/development.md`.
- [ ] **Gitignore Update**: Add `config/dev/` to `.gitignore`.
- [ ] **Scripting**: Create `hack/setup-dev.sh` to generate a local kustomize overlay (`config/dev`) based on user selection.
- [ ] **Doc Update**: Ensure new guides reference using `kubectl apply -k config/dev` instead of editing tracked files.
