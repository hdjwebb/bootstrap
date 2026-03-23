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
