# bootstrap

Bootstrap a Kubernetes cluster with the core platform components required for
the current GitOps flow. The script is now profile-aware so the same entrypoint
can target:

- `microk8s-prod`
- `microk8s-lab`
- `local-test`
- `local-test-plus`

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
./bootstrap.sh --profile local-test-plus full-install
./scripts/rehearse-minikube-local-test-plus.sh
BOOTSTRAP_REHEARSAL_CYCLES=5 ./scripts/rehearse-minikube-local-test-plus.sh
BOOTSTRAP_REHEARSAL_EXPECTED_APPS_TIMEOUT=1200 ./scripts/rehearse-minikube-local-test-plus.sh
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
- applies `cluster/local-test/app-of-apps.yaml`
- exposes Argo CD through `kubectl port-forward` instructions instead of a
  Gateway hostname
- intended for disposable clusters such as `minikube` where you want to verify
  the bootstrap flow without the production ingress/load-balancer stack

### `local-test-plus`

- keeps the same disposable access model as `local-test`
- skips `envoy`
- skips `metallb`
- skips the Argo CD domain `ExternalSecret`
- applies `cluster/local-test-plus/app-of-apps.yaml`
- reconciles a wider child-app set on disposable clusters:
  - `argocd`
  - `cert-manager`
  - `metrics-server`

## Profile Overrides

These environment variables let you keep the profile behavior while overriding
the cluster-specific values:

- `BOOTSTRAP_PROFILE`
- `BOOTSTRAP_CLUSTER_REPO_ROOT`
- `BOOTSTRAP_METALLB_ADDRESS_POOL`
- `BOOTSTRAP_DOMAIN_SECRET_KEY`
- `BOOTSTRAP_APP_OF_APPS_MANIFEST_PATH`
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

On macOS, the script can load those automatically from Keychain when the shell
variables are unset. By default it looks for:

- account: `${USER}`
- service: `akeyless-access-id`
- service: `akeyless-access-key`

You can override that lookup with:

- `BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCOUNT`
- `BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCESS_ID_SERVICE`
- `BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCESS_KEY_SERVICE`

The script also expects `kubectl` to be configured for the target cluster.

`add-app-of-apps` also expects a local checkout of the cluster repo. By default
it resolves that to:

```text
../GitLab/ifpossible-sre/Clusters/microK8s
```

relative to the bootstrap repo, and you can override it with
`BOOTSTRAP_CLUSTER_REPO_ROOT`.

## Hardening Notes

- strict shell mode is enabled
- the script is source-safe, which makes it testable without executing `main()`
- temporary directories are tracked and cleaned up on exit
- the script validates required commands and cluster access before running
- `help` no longer requires cluster access
- Argo CD secret reads now wait on the secret instead of relying on a fixed sleep
- cert-manager readiness now waits on the named deployments instead of selector-based pod discovery
- external-secrets readiness now waits on named deployments instead of pod selectors
- MetalLB readiness now waits on the controller deployment and speaker daemonset rather than a broad pod selector
- repository/bootstrap operations are action-driven rather than enabled by editing `main()`
- Argo CD exposure, MetalLB address pools, Akeyless secret paths, and the
  tracked app-of-apps manifest are all profile-driven instead of hard-coded inline
- app-of-apps add/remove now operate directly on the tracked root manifest rather than temp YAML plus fixed sleeps
- `add-gitlab-repos` now waits for the repository `ExternalSecret` objects to
  sync, restarts `argocd-repo-server`, and hard-refreshes `app-of-apps`
- `install-secret-store` now waits for cert-manager and external-secrets
  webhook CA bundle injection before creating webhook-validated custom
  resources, which prevents immediate uninstall/reinstall failures on
  disposable clusters
- manifest-based `kubectl apply/delete` steps now retry transport-level
  failures such as loopback apiserver connection refusals and unexpected EOFs,
  which prevents short-lived minikube control-plane disconnects from aborting
  teardown or reinstall
- uninstall manifest deletes now also tolerate follow-up missing-API discovery
  errors after a retryable partial teardown has already removed the referenced
  CRDs, so the script can continue to namespace cleanup instead of failing on a
  replayed delete
- uninstall paths now wait for namespace deletion instead of relying on broad
  force-delete fallbacks
- Argo CD uninstall now deletes `Application` resources and clears stuck Argo
  finalizers before removing the control plane
- namespace deletion waits now scrub lingering workload finalizers inside
  terminating namespaces, which keeps disposable operator namespaces like
  `alloy` from hanging `full-uninstall`
- removing the tracked root app now also waits for profile-owned workload
  namespaces to disappear before reinstall continues, which prevents
  `local-test-plus` from racing back into a terminating `alloy` namespace
- removing the tracked root app now also deletes child Argo CD `Application`
  objects labeled `app.kubernetes.io/instance=app-of-apps` and clears their
  finalizers before namespace waits begin, which keeps `full-uninstall` from
  stalling on still-managed disposable workloads
- `full-uninstall` now safely skips root app deletion when the Argo CD
  `Application` CRD is not installed, which matters for partial or failed local
  reinstalls
- manifest-based `kubectl apply/delete` operations now retry transient
  transport failures such as `connection refused` and `unexpected EOF`, which
  showed up during live cert-manager uninstall/reinstall testing on `minikube`
- long polling waits now emit heartbeat logs with elapsed time and the resource
  being waited on, so operators can distinguish a slow cluster from a hung run
- `scripts/rehearse-minikube-local-test-plus.sh` now gives the repo a single
  destructive rehearsal entrypoint that tears down `minikube`, boots a fresh
  cluster, runs `local-test-plus`, verifies the full disposable Argo app set
  (`alloy`, `app-of-apps`, `argocd`, `cert-manager`, `cnpg`, `envoy`,
  `metallb`, `metrics-server`, and `monitoring`) becomes `Synced/Healthy`,
  runs `full-uninstall`, verifies the managed namespaces and key CRDs are gone,
  then immediately reinstalls and verifies the stack again; if any phase fails
  it dumps pod/application/ExternalSecret diagnostics
- the rehearsal script now takes an exclusive lock per minikube profile so two
  destructive runs cannot overlap and invalidate the result
- the rehearsal script now gives the expected-app convergence phase a 900s
  default budget, and operators can override it with
  `BOOTSTRAP_REHEARSAL_EXPECTED_APPS_TIMEOUT` when a slower disposable cluster
  needs more headroom for large cold image pulls
- direct bootstrap component pins are now audited in
  [`docs/COMPONENT_VERSION_AUDIT.md`](./docs/COMPONENT_VERSION_AUDIT.md), and
  the bootstrap repo carries a regression that fails if the pinned upstream
  Argo CD, cert-manager, Envoy Gateway, or MetalLB versions drift from the
  intended slice
- the bootstrap and rehearsal wait loops now emit periodic heartbeats so long
  waits show elapsed time, timeout budget, and the resource they are waiting on
- the destructive rehearsal script now takes a single-run lock, so a second
  overlapping `local-test-plus` rehearsal fails fast instead of clobbering the
  same `minikube` cluster
