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

The script now exposes three profiles:

- `microk8s-prod` for the current production bootstrap flow
- `microk8s-lab` for a second microk8s-like environment with separate defaults
- `local-test` for disposable local validation without the load balancer stack

Each profile can be overridden through environment variables, but the operator
does not need to edit the script to switch between environments.

The root Argo CD `Application` is now treated as infrastructure-as-code: the
script selects a tracked `cluster/<profile>/app-of-apps.yaml` manifest from the
cluster repo and applies that file directly instead of rendering inline YAML.
The bootstrap repo resolves the cluster repo checkout relative to the workspace
by default and exposes `BOOTSTRAP_CLUSTER_REPO_ROOT` when that layout differs.

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
