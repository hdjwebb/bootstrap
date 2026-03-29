# Component Version Audit

This document tracks the bootstrap and disposable-cluster component versions we
have pinned locally, the current latest upstream release, and the upgrade plan.

## Bootstrap-Managed Direct Manifests

| Component | Current Before Slice | Latest Upstream | Slice Status | Upstream |
| --- | --- | --- | --- | --- |
| Argo CD | `v2.12.3` | `v3.3.6` | upgraded in bootstrap slice 1 | [Argo CD releases](https://github.com/argoproj/argo-cd/releases/latest) |
| cert-manager | `v1.16.1` | `v1.20.1` | upgraded in bootstrap slice 1 | [cert-manager releases](https://github.com/cert-manager/cert-manager/releases/latest) |
| Envoy Gateway | `v1.1.0` | `v1.7.1` | upgraded in bootstrap slice 1 | [Envoy Gateway releases](https://github.com/envoyproxy/gateway/releases/latest) |
| MetalLB | `v0.14.8` | `v0.15.3` | upgraded in bootstrap slice 1 | [MetalLB releases](https://github.com/metallb/metallb/releases/latest) |
| metrics-server | `latest/download` | `v0.8.1` | already tracks latest download URL | [metrics-server releases](https://github.com/kubernetes-sigs/metrics-server/releases/latest) |

## GitOps / Helm-Managed Components

| Component | Current | Latest Upstream | Notes |
| --- | --- | --- | --- |
| external-secrets chart/app | `v0.10.4` in bootstrap direct install, `v0.17.0` in kube-components values | `v2.2.0` | major migration, requires overlay and bootstrap patch review |
| CloudNativePG chart/app | `0.24.0` / `1.24.x` | `0.27.1` / `1.28.1` | bounded chart upgrade slice |
| Grafana k8s-monitoring chart | `3.5.7` | `4.0.0` | major schema change, needs rendered-manifest refresh and overlay review |
| kube-prometheus-stack chart | `82.14.1` | `82.15.1` | low-risk chart bump inside monitoring slice |
| Alloy Operator | `1.4.0` via rendered manifests | `v1.14.2` for standalone Alloy project, subchart version needs regeneration via k8s-monitoring | upgrade together with k8s-monitoring slice |

## Planned Order

1. Bootstrap direct-version slice
2. CloudNativePG slice
3. Monitoring/Alloy minor-safe slice
4. Major migration slice for External Secrets
5. Destructive `minikube` rehearsal on the fully upgraded stack
