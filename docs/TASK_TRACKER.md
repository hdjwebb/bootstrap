# Task Tracker

## 2026-03-23 Bootstrap Hardening

- [x] Add runtime hardening checks and regression tests.
- [x] Harden script execution, temp cleanup, and readiness handling.
- [x] Replace manual `main()` toggling with an explicit action interface.
- [x] Update docs so the bootstrap flow is understandable and repeatable.

## 2026-03-23 Bootstrap Profiles

- [x] Add a regression test that proves profile selection configures the script.
- [x] Introduce explicit `microk8s-prod`, `microk8s-lab`, and `local-test` profiles.
- [x] Move MetalLB, Argo CD domain, GitLab secret-path, and app-of-apps settings behind profile defaults.
- [x] Document the supported profiles and their override points.

## 2026-03-23 Minikube Smoke Test

- [x] Run the `local-test` profile against a live `minikube` cluster.
- [x] Fix `install_argocd` so it creates the `argocd` namespace before applying manifests.
- [x] Add a regression test that proves namespace creation happens before the Argo CD apply step.

## 2026-03-23 Secret-Backed Local Validation

- [x] Load the Akeyless API key from macOS Keychain and validate the local shell environment.
- [x] Verify the Akeyless `ClusterSecretStore` becomes `Ready=True` on `minikube`.
- [x] Remove the dead secret lookup in `add-app-of-apps` that produced a misleading operator error.
- [x] Confirm the remaining local failure is missing GitLab secret items in Akeyless, not a bootstrap shell bug.
