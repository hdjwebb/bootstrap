# bootstrap

Bootstrap a Kubernetes cluster with the core platform components required for
the current GitOps flow. The script is now profile-aware so the same entrypoint
can target:

- `microk8s-prod`
- `microk8s-lab`
- `local-test`

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
./bootstrap.sh --profile microk8s-prod install-argocd-secret install-argocd add-gitlab-repos add-app-of-apps
./bootstrap.sh --profile microk8s-lab full-install
./bootstrap.sh --profile local-test full-install
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

## Profiles

### `microk8s-prod`

- enables `envoy` and `metallb`
- creates the Argo CD domain `ExternalSecret`
- defaults the domain secret key to `/microk8s/domain`
- defaults the MetalLB pool to `192.168.0.220-192.168.0.229`

### `microk8s-lab`

- enables `envoy` and `metallb`
- creates the Argo CD domain `ExternalSecret`
- defaults the domain secret key to `/microk8s-lab/domain`
- defaults the MetalLB pool to `192.168.0.230-192.168.0.239`

### `local-test`

- skips `envoy`
- skips `metallb`
- skips the Argo CD domain `ExternalSecret`
- exposes Argo CD through `kubectl port-forward` instructions instead of a
  Gateway hostname

## Profile Overrides

These environment variables let you keep the profile behavior while overriding
the cluster-specific values:

- `BOOTSTRAP_PROFILE`
- `BOOTSTRAP_METALLB_ADDRESS_POOL`
- `BOOTSTRAP_DOMAIN_SECRET_KEY`
- `BOOTSTRAP_APP_OF_APPS_REPO_URL`
- `BOOTSTRAP_APP_OF_APPS_TARGET_REVISION`
- `BOOTSTRAP_APP_OF_APPS_PATH`
- `BOOTSTRAP_GITLAB_COMPONENTS_REPO_AUTH_KEY`
- `BOOTSTRAP_GITLAB_CLUSTER_REPO_AUTH_KEY`
- `BOOTSTRAP_GITLAB_REGISTRY_AUTH_KEY`
- `BOOTSTRAP_GITLAB_PAGES_HELM_REPO_KEY`
- `BOOTSTRAP_HELM_REGISTRY_URL`
- `BOOTSTRAP_ARGOCD_HOSTNAME_PREFIX`
- `BOOTSTRAP_ARGOCD_PORT_FORWARD_PORT`

## Required Environment

`install-secret-store` and `full-install` require:

- `AKEYLESS_ACCESS_ID`
- `AKEYLESS_ACCESS_SECRET_KEY`

The script also expects `kubectl` to be configured for the target cluster.

## Hardening Notes

- strict shell mode is enabled
- the script is source-safe, which makes it testable without executing `main()`
- temporary directories are tracked and cleaned up on exit
- the script validates required commands and cluster access before running
- `help` no longer requires cluster access
- Argo CD secret reads now wait on the secret instead of relying on a fixed sleep
- repository/bootstrap operations are action-driven rather than enabled by editing `main()`
- Argo CD exposure, MetalLB address pools, Akeyless secret paths, and the
  app-of-apps source are all profile-driven instead of hard-coded inline
