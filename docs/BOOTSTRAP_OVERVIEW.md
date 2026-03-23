# Bootstrap Overview

## Purpose

`bootstrap.sh` bootstraps a microK8s cluster with the core platform pieces
needed for the GitOps flow:

- `cert-manager`
- `external-secrets`
- Akeyless `ClusterSecretStore`
- `envoy`
- `metallb`
- `argocd`
- Argo CD GitLab repository credentials
- the app-of-apps `Application`

## Current Hardening Work

The script currently depends on ad-hoc sleeps, inline temp directories, and
manual toggling inside `main()`. The hardening work for this task is aimed at:

- predictable failure behavior
- safer temp file handling
- explicit dependency and cluster checks
- resource readiness checks instead of fixed sleeps
- clearer operator-facing workflow and docs
