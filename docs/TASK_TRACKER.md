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

## 2026-03-23 Repository Credential Refresh

- [x] Add a regression test that proves `add-gitlab-repos` waits for repo ExternalSecrets and refreshes Argo CD.
- [x] Teach `add-gitlab-repos` to wait for repository credential sync before finishing.
- [x] Restart `argocd-repo-server` and hard-refresh `app-of-apps` after repository credentials change.

## 2026-03-23 Local-Test App Alignment

- [x] Add a regression test that proves the `local-test` profile points `app-of-apps` at `applications/local-test`.
- [x] Stop `local-test` from reconciling the full `applications/dev` stack on disposable clusters.
- [x] Document the dedicated local-test app-of-apps path in the operator README.

## 2026-03-23 Fresh Cluster Cert-Manager Readiness

- [x] Reproduce the clean-cluster `full-install` failure on `minikube`.
- [x] Add a regression test that fails if `install_cert_manager` falls back to selector-based pod waits.
- [x] Switch cert-manager readiness to deterministic deployment waits so fresh installs do not fail with `no matching resources found`.

## 2026-03-23 App-Of-Apps IaC

- [x] Add regressions that fail unless bootstrap applies a tracked app-of-apps manifest by profile.
- [x] Replace inline root `Application` rendering in `bootstrap.sh` with tracked manifest application.
- [x] Document the cluster-repo root manifest path as the bootstrap source of truth.

## 2026-03-23 Remaining Wait Hardening

- [x] Add regressions for the remaining selector-based external-secrets waits and tracked app-of-apps add/remove actions.
- [x] Switch external-secrets readiness from pod selectors to named deployment waits.
- [x] Remove the fixed app-of-apps sleeps and make add/remove operate directly on the tracked manifest path.
- [x] Switch MetalLB readiness from a pod selector to explicit controller and speaker workload waits.

## 2026-03-23 Uninstall Hardening

- [x] Add regressions for the cert-manager, external-secrets, and Argo CD uninstall paths.
- [x] Replace broad Argo CD force-delete behavior with tracked manifest deletion plus namespace-deletion waits.
- [x] Delete Argo CD `Application` resources and clear stuck finalizers before uninstalling the Argo CD control plane.
- [x] Remove the dead `waiting()` helper and consolidate uninstall polling on `wait_for_namespace_deletion()`.

## 2026-03-23 Local-Test-Plus Profile

- [x] Add regressions that fail unless bootstrap exposes a tracked `local-test-plus` profile.
- [x] Add a disposable `local-test-plus` root manifest in the cluster repo for a wider minikube-safe child-app set.
- [x] Document the difference between `local-test` and `local-test-plus` for operators.

## 2026-03-24 Bootstrap Rehearsal Reliability

- [x] Add a regression test that fails unless bootstrap can load Akeyless credentials from macOS Keychain when the shell variables are unset.
- [x] Add a dedicated `minikube` rehearsal script that tears the cluster down, brings it back up, runs `local-test-plus`, and captures failure diagnostics.
- [x] Document the Keychain fallback and the destructive rehearsal entrypoint so operators can rerun the exact reliability check.
- [x] Run repeated destructive `minikube` rehearsals and fix any failures they expose.
- [x] Reproduce the uninstall/reinstall path on a live `minikube` cluster instead of inferring reliability from install-only rehearsal.
- [x] Add a regression test that fails unless `install-secret-store` waits for webhook CA bundle injection before creating webhook-validated custom resources.
- [x] Block `install-secret-store` on cert-manager and external-secrets webhook CA bundle injection so immediate reinstall no longer fails with webhook trust errors.
