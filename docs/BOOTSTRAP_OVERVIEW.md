# Bootstrap Overview

## Purpose

`bootstrap.sh` bootstraps a Kubernetes cluster with the core platform pieces
needed for the GitOps flow:

- `cert-manager`
- `external-secrets`
- Akeyless `ClusterSecretStore`
- `envoy`
- `metallb`
- `argocd`
- Argo CD GitLab repository credentials
- the app-of-apps `Application`

## Profiles

The script now exposes four profiles:

- `microk8s-prod` for the current production bootstrap flow
- `microk8s-lab` for a second microk8s-like environment with separate defaults
- `local-test` for disposable local validation without the load balancer stack
- `local-test-plus` for disposable local validation with a wider but still minikube-safe child-app set

Each profile can be overridden through environment variables, but the operator
does not need to edit the script to switch between environments.

The root Argo CD `Application` is now treated as infrastructure-as-code: the
script selects a tracked `cluster/<profile>/app-of-apps.yaml` manifest from the
cluster repo and applies that file directly instead of rendering inline YAML.
The bootstrap repo resolves the cluster repo checkout relative to the workspace
by default and exposes `BOOTSTRAP_CLUSTER_REPO_ROOT` when that layout differs.

On macOS, the bootstrap can now source the Akeyless API key from Keychain when
`AKEYLESS_ACCESS_ID` and `AKEYLESS_ACCESS_SECRET_KEY` are not already exported.
That keeps local rehearsal usable without pushing long-lived secrets into shell
startup files.

The repo also now carries a destructive rehearsal script,
`scripts/rehearse-minikube-local-test-plus.sh`, which is intended to be the
standard repeatability check for disposable local clusters. It tears down
`minikube`, starts a fresh cluster, runs `local-test-plus`, waits for the
expected Argo applications to converge, and dumps application, ExternalSecret,
and pod diagnostics if anything fails.

Recent reinstall investigation also exposed that webhook-serving deployments can
be `Available` before their admission CA bundles are injected. The bootstrap now
waits for the cert-manager and external-secrets validating webhook CA bundles
before it creates webhook-validated custom resources, which removes the
reinstall race seen immediately after a destructive teardown.

## Current Hardening Work

The script currently depends on ad-hoc sleeps, inline temp directories, and
manual toggling inside `main()`. The hardening work for this task is aimed at:

- predictable failure behavior
- safer temp file handling
- explicit dependency and cluster checks
- resource readiness checks instead of fixed sleeps
- clearer operator-facing workflow and docs
- profile-driven cluster settings instead of hard-coded environment values
- tracked bootstrap manifests instead of imperative inline app-of-apps rendering
- destructive rehearsal coverage that exercises full teardown and bring-up on a
  disposable cluster instead of relying only on static shell tests
