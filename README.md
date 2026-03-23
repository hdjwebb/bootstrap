# bootstrap

Bootstrap a microK8s Kubernetes cluster with the core platform components
required for the current GitOps flow.

## What It Installs

- `cert-manager`
- `external-secrets`
- the Akeyless `ClusterSecretStore`
- `envoy`
- `metallb`
- `argocd`
- Argo CD GitLab repository credentials
- the app-of-apps `Application`

## Usage

Run the script with one or more explicit actions:

```bash
./bootstrap.sh install-cert-manager install-external-secrets install-secret-store
./bootstrap.sh install-argocd-secret install-argocd add-gitlab-repos add-app-of-apps
./bootstrap.sh full-install
```

Available actions:

- `install-cert-manager`
- `uninstall-cert-manager`
- `install-external-secrets`
- `uninstall-external-secrets`
- `install-secret-store`
- `install-envoy`
- `install-metallb`
- `install-argocd-secret`
- `install-argocd`
- `add-gitlab-repos`
- `add-app-of-apps`
- `remove-argocd-app`
- `uninstall-argocd`
- `get-argocd-password`
- `full-install`
- `full-uninstall`

## Required Environment

`install-secret-store` and `full-install` require:

- `AKEYLESS_ACCESS_ID`
- `AKEYLESS_ACCESS_SECRET_KEY`

The script also expects `kubectl` to be configured for the target cluster.

## Hardening Notes

- strict shell mode is enabled
- temporary directories are tracked and cleaned up on exit
- the script validates required commands and cluster access before running
- Argo CD secret reads now wait on the secret instead of relying on a fixed sleep
- repository/bootstrap operations are action-driven rather than enabled by
  editing `main()`
