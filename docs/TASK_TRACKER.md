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
- [x] Tighten the destructive rehearsal so it verifies the full `local-test-plus` disposable app set, not just the original bootstrap-core subset.
- [x] Fix the destructive rehearsal failure-dump pod filter so failure diagnostics do not crash on an `awk` regex escaping bug.

## 2026-03-28 Bootstrap Operability Feedback

- [x] Add regression coverage for heartbeat output during long bootstrap waits.
- [x] Add regression coverage for rehearsal-script progress output and single-run locking.
- [x] Teach the bootstrap and rehearsal wait loops to emit periodic heartbeats with elapsed time, timeout budget, and the resource being waited on.
- [x] Prevent overlapping `local-test-plus` rehearsal runs from sharing the same destructive `minikube` cluster.

## 2026-03-24 Uninstall/Reinstall Reliability

- [x] Reproduce a live `full-uninstall` -> `full-install` failure on `minikube`.
- [x] Add a regression test that fails unless `remove-argocd-app` skips cleanly when the Argo `Application` CRD is absent.
- [x] Rerun the live uninstall/reinstall proof after the new Argo app-removal guard and fix the cert-manager webhook CA race it exposed.
- [x] Add a regression test that fails unless transient manifest transport failures are retried during cert-manager uninstall.
- [ ] Rerun the live uninstall/reinstall proof after manifest retry hardening and fix any next failure it exposes.
- [x] Reproduce the uninstall/reinstall path on a live `minikube` cluster instead of inferring reliability from install-only rehearsal.
- [x] Add a regression test that fails unless `install-secret-store` waits for webhook CA bundle injection before creating webhook-validated custom resources.
- [x] Block `install-secret-store` on cert-manager and external-secrets webhook CA bundle injection so immediate reinstall no longer fails with webhook trust errors.
- [x] Extend the destructive `minikube` rehearsal so each cycle proves `full-install`, `full-uninstall`, cleanup verification, and immediate reinstall on the same cluster.
- [x] Add coverage that fails unless the rehearsal script exercises uninstall plus reinstall, not just fresh-cluster bring-up.
- [x] Capture the transient cert-manager uninstall transport failure seen against the loopback minikube apiserver as a regression.
- [x] Retry retryable `kubectl apply/delete` transport failures so teardown does not abort on a short-lived apiserver disconnect or EOF.
- [x] Fix the shared kubectl retry helper so non-retryable errors still fail instead of being masked by the shell `if` exit-status edge case.
- [x] Tolerate missing-API discovery errors on replayed uninstall manifest deletes after a retryable partial teardown removes the relevant CRDs first.

## 2026-03-28 Operator Feedback Hardening

- [x] Add a regression that proves the shared bootstrap wait helper emits heartbeat output while polling.
- [x] Add a regression that proves the destructive minikube rehearsal refuses to start when another run already holds the lock.
- [x] Centralize bootstrap polling on a shared heartbeat helper so long waits surface elapsed time and the resource being waited on.
- [x] Guard the destructive minikube rehearsal with an exclusive per-profile lock so concurrent runs fail fast instead of corrupting validation.

## 2026-03-28 Namespace Finalizer Cleanup

- [x] Reproduce a live `full-uninstall` hang caused by operator-managed resources remaining in a terminating namespace.
- [x] Add a regression that proves terminating-namespace waits enumerate remaining namespaced resources and clear their finalizers.
- [x] Scrub lingering workload finalizers during namespace-deletion waits so disposable operator namespaces like `alloy` do not block teardown forever.

## 2026-03-29 Profile Namespace Cleanup

- [x] Reproduce the reinstall failure where `local-test-plus` raced back into an `alloy` namespace that was still terminating.
- [x] Add a regression that proves `remove-argocd-app` waits for profile-owned workload namespaces and clears lingering finalizers while they terminate.
- [x] Teach `local-test-plus` root app removal to wait for disposable workload namespaces like `alloy`, `cnpg`, `envoy-gateway-system`, `metallb-system`, and `monitoring` before the reinstall continues.

## 2026-03-29 Child App Teardown

- [x] Reproduce the uninstall failure where deleting the tracked root app left child Argo CD `Application` objects running and kept disposable namespaces active.
- [x] Add a regression that proves `remove-argocd-app` deletes the child `Application` objects labeled `app.kubernetes.io/instance=app-of-apps` and clears their finalizers before waiting on workload namespaces.
- [x] Teach root app removal to tear down child Argo CD applications before namespace waits so `full-uninstall` can progress from a healthy `local-test-plus` install.

## 2026-03-29 Component Upgrade Wave

- [x] Inventory the bootstrap and disposable-cluster component versions against current upstream releases.
- [x] Add regression coverage for the bootstrap repo's direct upstream version pins.
- [ ] Upgrade the remaining GitOps-managed components in atomic slices and prove each slice independently.
- [x] Upgrade bootstrap-managed direct manifest pins for Argo CD, cert-manager, Envoy Gateway, and MetalLB.
- [x] Upgrade the bootstrap External Secrets installer to `v2.2.0` and migrate generated manifests from `external-secrets.io/v1beta1` to `v1`.
