# microK8s bootstrap copyroght henry webb 2024
# ####
# ####

set -euo pipefail

declare -a TEMP_DIRS=()

cleanup_temp_dirs() {
    local temp_dir

    for temp_dir in "${TEMP_DIRS[@]:-}"; do
        if [ -n "${temp_dir}" ] && [ -d "${temp_dir}" ]; then
            rm -rf "${temp_dir}"
        fi
    done
}

trap cleanup_temp_dirs EXIT

create_temp_dir() {
    local temp_dir

    temp_dir="$(mktemp -d)"
    TEMP_DIRS+=("${temp_dir}")
    echo "Created temporary directory: ${temp_dir}" >&2
    printf '%s\n' "${temp_dir}"
}

require_commands() {
    local missing=0
    local command_name

    for command_name in kubectl mktemp base64; do
        if ! command -v "${command_name}" >/dev/null 2>&1; then
            echo "❌   Error: required command '${command_name}' is not installed."
            missing=1
        fi
    done

    if [ "${missing}" -ne 0 ]; then
        exit 1
    fi
}

require_cluster_access() {
    if ! kubectl get namespace default >/dev/null 2>&1; then
        echo "❌   Error: kubectl cannot reach the target cluster."
        exit 1
    fi
}

wait_for_secret() {
    local namespace="$1"
    local name="$2"
    local timeout="${3:-120}"
    local elapsed=0

    echo "Waiting for secret ${name} in namespace ${namespace}..."

    while ! kubectl get secret "${name}" -n "${namespace}" >/dev/null 2>&1; do
        if [ "${elapsed}" -ge "${timeout}" ]; then
            echo "❌   Error: secret ${name} in namespace ${namespace} did not become available within ${timeout}s."
            exit 1
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done
}


# Creates a returned line to be used to separate console logs!
# ####
# ####

emptyline(){
    printf '\n'
}

# Function to validate required variables
# ####
# ####

validate_variables() {
    local missing_variables=0
    
    if [ -z "$AKEYLESS_ACCESS_ID" ]; then
        echo "❌   Error: AKEYLESS_ACCESS_ID is not set!"
        missing_variables=1
    fi
    
    if [ -z "$AKEYLESS_ACCESS_SECRET_KEY" ]; then
        echo "❌   Error: AKEYLESS_ACCESS_SECRET_KEY is not set!"
        missing_variables=1
    fi
    
    if [ $missing_variables -eq 1 ]; then
        echo "⚠️    Please set the required variables and try again."
        exit 1
    fi

    echo "✅ All required variables are set."
    emptyline
}


# Function to wait for a deployment to be ready

wait_for_deployment() {
    echo "Waiting for deployment $1 in namespace $2 to be ready..."
    kubectl wait --for=condition=available --timeout=300s "deployment/$1" -n "$2"
}


waiting() {
    local seconds=$1
    echo "Starting countdown for $seconds seconds..."
    while [ $seconds -gt 0 ]; do
        printf "\rTime remaining: %02d seconds" $seconds
        sleep 1
        ((seconds--))
    done
    printf "\rCountdown complete!                   \n"
}


create_namespace_if_not_exists() {
    if ! kubectl get namespace "$1" >/dev/null 2>&1; then
        echo "Creating namespace: $1"
        kubectl create namespace "$1"
    else
        echo "Namespace $1 already exists"
    fi
}

# TEMP_DIR

temp_dir() {
    # Create a temporary directory for Kustomize files
    TEMP_DIR="$(create_temp_dir)"
}

# install cert-manager

install_cert_manager() {
    echo "Installing cert-manager..."
    
    # Create the namespace first
    create_namespace_if_not_exists cert-manager
    
    # Apply the cert-manager manifest
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml
    
    echo "Waiting for cert-manager pods to be ready..."
    # Wait for all cert-manager deployments
    kubectl wait --namespace cert-manager \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/instance=cert-manager \
      --timeout=120s

    # Wait specifically for the main components
    kubectl wait --namespace cert-manager \
      --for=condition=Available=True deployment \
      --selector=app.kubernetes.io/instance=cert-manager \
      --timeout=120s

    # Wait for the webhook to be ready
    echo "Waiting for cert-manager-webhook..."
    kubectl wait --namespace cert-manager \
      --for=condition=Available=True deployment \
      --selector=app.kubernetes.io/name=webhook \
      --timeout=120s

    # Optional: Verify the webhook is properly configured
    echo "Verifying webhook configuration..."
    kubectl get validatingwebhookconfigurations cert-manager-webhook

    echo "✅ - cert-manager installation complete"
    emptyline
}

# uninstall cert-manager

uninstall_cert_manager() {
    echo "Uninstalling cert-manager..."
    
    # Delete all cert-manager resources
    kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml --ignore-not-found=true
    
    # Wait for pods to be terminated
    while kubectl get pods -n cert-manager 2>/dev/null | grep -q cert-manager; do
        echo "Waiting for cert-manager pods to terminate..."
        sleep 2
    done
    
    # Delete the namespace (this will delete any remaining resources in the namespace)
    kubectl delete namespace cert-manager --ignore-not-found=true
    
    echo "✅ - cert-manager uninstallation complete"
    emptyline
}


# install external secrets

install_external_secrets() {
    echo "Installing external-secrets..."
    create_namespace_if_not_exists external-secrets
    
    temp_dir
    # curl -L -o $TEMP_DIR/external-secrets.yaml https://github.com/external-secrets/external-secrets/releases/download/v0.10.4/external-secrets.yaml
    
    # # Mac-compatible sed commands
    # sed -i '' 's/namespace: default/namespace: external-secrets/g' $TEMP_DIR/external-secrets.yaml
    # sed -i '' 's/\.default\.svc/\.external-secrets\.svc/g' $TEMP_DIR/external-secrets.yaml
    # sed -i '' 's/namespace: "default"/namespace: "external-secrets"/g' $TEMP_DIR/external-secrets.yaml
    # sed -i '' 's/namespace=default/namespace=external-secrets/g' $TEMP_DIR/external-secrets.yaml
    
    
    # Create kustomization.yaml for External Secrets
    cat <<EOF > "$TEMP_DIR/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: external-secrets
resources:
 - https://github.com/external-secrets/external-secrets/releases/download/v0.10.4/external-secrets.yaml

patches:
 - target:
     group: apps
     version: v1
     kind: Deployment
     name: external-secrets-webhook
   patch: |
     - op: replace
       path: /spec/template/spec/containers/0/args
       value:
       - webhook
       - --metrics-addr=:8080
       - --port=10250
       - --cert-dir=/tmp/certs
       - --dns-name=external-secrets-webhook.external-secrets.svc
       - --healthz-addr=:8081

 - target:
     group: apps
     version: v1
     kind: Deployment
     name: external-secrets-cert-controller
   patch: |
     - op: replace
       path: /spec/template/spec/containers/0/args
       value:
       - certcontroller
       - --crd-requeue-interval=5m
       - --service-name=external-secrets-webhook
       - --service-namespace=external-secrets
       - --secret-name=external-secrets-webhook
       - --secret-namespace=external-secrets

 - target:
     kind: ServiceAccount
     name: external-secrets-cert-controller
   patch: |
    - op: replace
      path: /metadata/namespace
      value: external-secrets

images:
 - name: ghcr.io/external-secrets/external-secrets
   newTag: v0.10.4
EOF

    kubectl apply -k "$TEMP_DIR"
    rm -rf "$TEMP_DIR"
    
    echo "Waiting for external-secrets pods to be ready..."
    kubectl wait --namespace external-secrets \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/name=external-secrets \
      --timeout=90s

    echo "Waiting for external-secrets-cert-controller pods to be ready..."
    kubectl wait --namespace external-secrets \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/name=external-secrets-cert-controller \
      --timeout=90s

    echo "Waiting for external-secrets-webhook pods to be ready..."
    kubectl wait --namespace external-secrets \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/name=external-secrets-webhook  \
      --timeout=90s

    echo "✅ - external-secrets installation complete"
    emptyline
}


# create ClusterStore connection for aKeyless

install_secret_clusterStore_external_secrets() {

    # Create a temporary directory for Kustomize files
    temp_dir

    # Create secret.yaml for External Secrets
    cat <<EOF > "$TEMP_DIR/akeylessSecret.yaml"
apiVersion: v1
kind: Secret
metadata:
    name: akeyless-secret-creds
    namespace: external-secrets
type: Opaque
stringData:
# data:
    accessId: $AKEYLESS_ACCESS_ID
    accessType: "api_key"
    accessTypeParam: $AKEYLESS_ACCESS_SECRET_KEY
EOF

    cat <<EOF > "$TEMP_DIR/akeylessClusterStore.yaml"
# Cluster-wide SecretStore
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: akeyless-cluster-secret-store
spec:
  provider:
    akeyless:
      akeylessGWApiURL: "https://api.akeyless.io"
      authSecretRef:
        secretRef:
          accessID:
            name: akeyless-secret-creds
            key: accessId
            namespace: external-secrets  # Specify the namespace of the Secret
          accessType:
            name: akeyless-secret-creds
            key: accessType
            namespace: external-secrets  # Specify the namespace of the Secret
          accessTypeParam:
            name: akeyless-secret-creds
            key: accessTypeParam
            namespace: external-secrets  # Specify the namespace of the Secret
EOF

  cat <<EOF > "$TEMP_DIR/clusterIssuer.yaml"
# Clusterissuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: certymccertface
spec:
  selfSigned: {}
EOF

    kubectl apply -f "$TEMP_DIR/clusterIssuer.yaml"
    kubectl apply -f "$TEMP_DIR/akeylessSecret.yaml"
    kubectl apply -f "$TEMP_DIR/akeylessClusterStore.yaml"

    echo "✅ - clusterStore external_secrets created"

}

install_envoy() {
    echo "Installing Envoy Gateway..."
# Install Envoy Gateway
kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/v1.1.0/install.yaml --server-side

wait_for_deployment envoy-gateway envoy-gateway-system


# Apply Gateway and HTTPRoute configurations
 kubectl apply -f - <<EOF
---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-gateway
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: tunnel-gateway
  namespace: envoy-gateway-system
spec:
  gatewayClassName: envoy-gateway
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
EOF

    echo "✅ - Envoy Gateway installation completed!"
    emptyline
}

install_metallb() {
    echo "Installing MetalLB..."

    # Create namespace
    create_namespace_if_not_exists metallb-system

    # Apply MetalLB manifest (which includes CRDs)
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

    echo "Waiting for MetalLB CRDs to be established..."
    kubectl wait --for condition=established --timeout=60s crd/ipaddresspools.metallb.io
    kubectl wait --for condition=established --timeout=60s crd/l2advertisements.metallb.io

    echo "Waiting for MetalLB controller to be ready..."
    kubectl wait --namespace metallb-system \
                 --for=condition=ready pod \
                 --selector=app=metallb \
                 --timeout=90s

    # Create a temporary directory for custom resources
    TEMP_DIR="$(create_temp_dir)"

    # Create ipPools.yaml
    cat <<EOF > "$TEMP_DIR/ipPools.yaml"
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.0.220-192.168.0.229
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-advertise-all-pools
  namespace: metallb-system
spec: {}
EOF

    # Apply custom resources
    kubectl apply -f "$TEMP_DIR/ipPools.yaml"

    # Clean up the temporary directory
    rm -rf "$TEMP_DIR"

    echo "MetalLB installation completed!"
    emptyline
}

install_argocd_secret() {

    # Create namespace
    create_namespace_if_not_exists argocd

        # Create a temporary directory for Kustomize files
    TEMP_DIR="$(create_temp_dir)"

    # Create kustomization.yaml for ArgoCD
    cat <<EOF > "$TEMP_DIR/domainsecret.yaml"
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: domain
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: akeyless-cluster-secret-store
  target:
    name: domain
    creationPolicy: Owner
  data:
    - secretKey: domain
      remoteRef:
        key: /microk8s/domain
EOF

    # Apply custom resources
    kubectl apply -f "$TEMP_DIR/domainsecret.yaml"

    # Clean up the temporary directory
    rm -rf "$TEMP_DIR"

    echo "✅ - argocd Secret installation completed!"
    emptyline
}


install_argocd() {
    echo "Installing ArgoCD..."

    wait_for_secret argocd domain 120

    # Create a temporary directory for Kustomize files
    TEMP_DIR="$(create_temp_dir)"

    # Create kustomization.yaml for ArgoCD
    cat <<EOF > "$TEMP_DIR/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd

resources:
- https://raw.githubusercontent.com/argoproj/argo-cd/v2.12.3/manifests/install.yaml
- httproute.yaml


patches:
- patch: |-
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: argocd-cmd-params-cm
    data:
      server.insecure: "true"
  target:
    kind: ConfigMap
    name: argocd-cmd-params-cm
- patch: |-
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: argocd-cm
      namespace: argocd
      labels:
        app.kubernetes.io/name: argocd-cm
        app.kubernetes.io/part-of: argocd
    data:
      kustomize.buildOptions: |
        --enable-helm
  target:
    kind: ConfigMap
    name: argocd-cm

- target:
    group: gateway.networking.k8s.io
    version: v1
    kind: HTTPRoute
    name: argocd-route
    namespace: argocd
  patch: |
    - op: replace
      path: /spec/rules/0/matches/0/headers/0/value
      value: "argocd.$(kubectl get secret domain -n argocd -o jsonpath="{.data.domain}" | base64 --decode)"
EOF
    # Create httproute.yaml with valueFrom for the hostname
    cat <<EOF > "$TEMP_DIR/httproute.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-route
  namespace: argocd
spec:
  parentRefs:
  - name: tunnel-gateway
    namespace: envoy-gateway-system
  rules:
  - matches:
    - headers:
      - name: "Host"
        value: "meh"
    backendRefs:
    - name: argocd-server
      port: 80
      kind: Service
EOF

    # Create the namespace first
    # kubectl apply -f "$TEMP_DIR/namespace.yaml"


    # Install ArgoCD using kustomize
    kubectl apply -k "$TEMP_DIR"

    # Clean up the temporary directory
    rm -rf "$TEMP_DIR"

    echo "Waiting for ArgoCD server to be ready..."
    kubectl wait --namespace argocd \
                 --for=condition=available deployment \
                 --selector=app.kubernetes.io/name=argocd-server \
                 --timeout=300s

    echo "✅ - ArgoCD installation and configuration completed!"
    emptyline
}

add_gitlab_kube_comp_repo() {
    echo "Adding gitlab repo secret..."
    # Create a temporary directory for Kustomize files
    TEMP_DIR="$(create_temp_dir)"



    # Create kustomization.yaml for ArgoCD
    cat <<EOF > "$TEMP_DIR/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd

resources:
- gitlab-repos.yaml
EOF
    # Create external secret file for gitlab
      cat <<EOF > "$TEMP_DIR/gitlab-repos.yaml"
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: components-repo-secret
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: akeyless-cluster-secret-store
  target:
    name: gitlab-repo-components-secret
    creationPolicy: Owner
    template:
      type: Opaque
      metadata:
        labels:
          argocd.argoproj.io/secret-type: repository
      data:
        # Create a custom configuration using fetched values
        url: "{{ .url | toString }}"            # Repository URL
        username: "{{ .username | toString }}"  # Username
        password: "{{ .password | toString }}"  # Password
        name: gitlab-repo-components            # Logical repository name
        type: git                               # Repository type for ArgoCD
  data:
    - secretKey: url
      remoteRef:
        key: /microk8s/gitlab-kubecomp-repo-auth
        property: url
    - secretKey: username
      remoteRef:
        key: /microk8s/gitlab-kubecomp-repo-auth
        property: username
    - secretKey: password
      remoteRef:
        key: /microk8s/gitlab-kubecomp-repo-auth
        property: token
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cluster-repo-secret
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: akeyless-cluster-secret-store
  target:
    name: cluster-repo-secret
    creationPolicy: Owner
    template:
      type: Opaque
      metadata:
        labels:
          argocd.argoproj.io/secret-type: repository
      data:
        # Create a custom configuration using fetched values
        url: "{{ .url | toString }}"            # Repository URL
        username: "{{ .username | toString }}"  # Username
        password: "{{ .password | toString }}"  # Password
        name: cluster-repo-secret               # Logical repository name
        type: git                               # Repository type for ArgoCD
  data:
    - secretKey: url
      remoteRef:
        key: /microk8s/gitlab-cluster-repo-auth
        property: url
    - secretKey: username
      remoteRef:
        key: /microk8s/gitlab-cluster-repo-auth
        property: username
    - secretKey: password
      remoteRef:
        key: /microk8s/gitlab-cluster-repo-auth
        property: token
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: registry-secret
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: akeyless-cluster-secret-store
  target:
    name: gitlab-registry-secret
    creationPolicy: Owner
    template:
      type: Opaque
      metadata:
        labels:
          argocd.argoproj.io/secret-type: repository
      data:
        # Create a custom configuration using fetched values
        url: registry.gitlab.com/ifpossible-sre/charts       # Registry URL
        username: "{{ .username | toString }}"                        # Username
        password: "{{ .password | toString }}"                        # Password
        type: helm                                                    # Repository type for ArgoCD
  data:
    - secretKey: username
      remoteRef:
        key: /microk8s/gitlab-registry-auth
        property: username
    - secretKey: password
      remoteRef:
        key: /microk8s/gitlab-registry-auth
        property: password
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: public-pages-helm-repo
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: akeyless-cluster-secret-store
  target:
    name: public-pages-helm-repo
    creationPolicy: Owner
    template:
      type: Opaque
      metadata:
        labels:
          argocd.argoproj.io/secret-type: repository
      data:
        url: "{{ .url }}"
        type: helm
  data:
    - secretKey: url
      remoteRef:
        key: /microk8s/gitlab-pages-helm-repo
        property: url

EOF

    # Install ArgoCD using kustomize
    kubectl apply -k "$TEMP_DIR"

        # Clean up the temporary directory
    rm -rf "$TEMP_DIR"

    
}

add_argocd_app_of_apps() {
    sleep 5
    echo "Adding ArgoCD application..."
    # Create a temporary directory for Kustomize files
    TEMP_DIR="$(create_temp_dir)"



    # Create kustomization.yaml for ArgoCD
    cat <<EOF > "$TEMP_DIR/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd

resources:
- argocd-app.yaml
EOF

    # Create App file for ArgoCD app
    cat <<EOF > "$TEMP_DIR/argocd-app.yaml"
# apiVersion: argoproj.io/v1alpha1
# kind: Application
# metadata:
#   name: argocd
#   namespace: argocd
# spec:
#   project: default
#   source:
#     repoURL: $(kubectl get secret gitlab-repo-components-secret -n argocd -o jsonpath="{.data.url}" | base64 --decode)
#     targetRevision: main
#     path: argocd
#   destination:
#     server: https://kubernetes.default.svc
#     namespace: argocd
#   syncPolicy:
#     automated:
#       prune: true
#       selfHeal: true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: platform
    app.kubernetes.io/name: app-of-apps
spec:
  project: default
  source:
    repoURL: https://gitlab.com/ifpossible-sre/clusters/microk8s.git
    targetRevision: main
    path: applications/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

    # Install ArgoCD using kustomize
    kubectl apply -k "$TEMP_DIR"

        # Clean up the temporary directory
    rm -rf "$TEMP_DIR"

}

remove_argocd_app() {
    sleep 5
    echo "Removing ArgoCD application..."
    # Create a temporary directory for Kustomize files
    TEMP_DIR="$(create_temp_dir)"



    # Create kustomization.yaml for ArgoCD
    cat <<EOF > "$TEMP_DIR/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd

resources:
- argocd-app.yaml
EOF

    # Create App file for ArgoCD app
    cat <<EOF > "$TEMP_DIR/argocd-app.yaml"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $(kubectl get secret gitlab-repo-components-secret -n argocd -o jsonpath="{.data.url}" | base64 --decode)
    targetRevision: main
    path: argocd
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

    # Remove ArgoCD using kustomize
    kubectl delete -k "$TEMP_DIR"

        # Clean up the temporary directory
    rm -rf "$TEMP_DIR"

    echo "ArgoCD app removed from argocd"

}

uninstall_argocd() {
    echo "Uninstalling ArgoCD..."

    # Create a temporary directory for Kustomize files
    TEMP_DIR="$(create_temp_dir)"

    # Create kustomization.yaml for ArgoCD
    cat <<EOF > "$TEMP_DIR/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd

resources:
- https://raw.githubusercontent.com/argoproj/argo-cd/v2.12.3/manifests/install.yaml
- httproute.yaml


patches:
- patch: |-
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: argocd-cmd-params-cm
    data:
      server.insecure: "true"
  target:
    kind: ConfigMap
    name: argocd-cmd-params-cm

- target:
    group: gateway.networking.k8s.io
    version: v1
    kind: HTTPRoute
    name: argocd-route
    namespace: argocd
  patch: |
    - op: replace
      path: /spec/rules/0/matches/0/headers/0/value
      value: "argocd.$(kubectl get secret domain -n argocd -o jsonpath="{.data.domain}" | base64 --decode)"
EOF
    # Create httproute.yaml with valueFrom for the hostname
    cat <<EOF > "$TEMP_DIR/httproute.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-route
  namespace: argocd
spec:
  parentRefs:
  - name: tunnel-gateway
    namespace: envoy-gateway-system
  rules:
  - matches:
    - headers:
      - name: "Host"
        value: "meh"
    backendRefs:
    - name: argocd-server
      port: 80
      kind: Service
EOF

    # Create the namespace first
    # kubectl apply -f "$TEMP_DIR/namespace.yaml"


    # Install ArgoCD using kustomize
    kubectl delete -k "$TEMP_DIR"
    kubectl delete all --all -n argocd --force --grace-period=0
    kubectl delete namespace argocd --wait=false

    # Clean up the temporary directory
    rm -rf "$TEMP_DIR"

    echo "✅ - ArgoCD uninstallation completed!"
    emptyline
}


get_argocd_password() {

  echo "Bootstrap process completed!"
  echo "ArgoCD should now be accessible via the configured hostname "
  echo "argocd.$(kubectl get secret domain -n argocd -o jsonpath="{.data.domain}" | base64 -d)"
  emptyline
  echo "Retrieved the ArgoCD admin password: "
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
  emptyline

}

usage() {
  cat <<'EOF'
Usage:
  ./bootstrap.sh <action> [<action>...]

Actions:
  install-cert-manager
  uninstall-cert-manager
  install-external-secrets
  uninstall-external-secrets
  install-secret-store
  install-envoy
  install-metallb
  install-argocd-secret
  install-argocd
  add-gitlab-repos
  add-app-of-apps
  remove-argocd-app
  uninstall-argocd
  get-argocd-password
  full-install
  full-uninstall
  help
EOF
}

action_requires_akeyless() {
  local action="$1"

  case "$action" in
    install-secret-store|full-install)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

run_action_sequence() {
  local action

  for action in "$@"; do
    run_action "$action"
  done
}

run_action() {
  local action="$1"

  case "$action" in
    install-cert-manager)
      install_cert_manager
      ;;
    uninstall-cert-manager)
      uninstall_cert_manager
      ;;
    install-external-secrets)
      install_external_secrets
      ;;
    uninstall-external-secrets)
      uninstall_external_secrets
      ;;
    install-secret-store)
      install_secret_clusterStore_external_secrets
      ;;
    install-envoy)
      install_envoy
      ;;
    install-metallb)
      install_metallb
      ;;
    install-argocd-secret)
      install_argocd_secret
      ;;
    install-argocd)
      install_argocd
      ;;
    add-gitlab-repos)
      add_gitlab_kube_comp_repo
      ;;
    add-app-of-apps)
      add_argocd_app_of_apps
      ;;
    remove-argocd-app)
      remove_argocd_app
      ;;
    uninstall-argocd)
      uninstall_argocd
      ;;
    get-argocd-password)
      get_argocd_password
      ;;
    full-install)
      run_action_sequence \
        install-cert-manager \
        install-external-secrets \
        install-secret-store \
        install-envoy \
        install-metallb \
        install-argocd-secret \
        install-argocd \
        add-gitlab-repos \
        add-app-of-apps \
        get-argocd-password
      ;;
    full-uninstall)
      run_action_sequence \
        remove-argocd-app \
        uninstall-argocd \
        uninstall-external-secrets \
        uninstall-cert-manager
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      echo "❌   Error: unknown action '${action}'."
      usage
      exit 1
      ;;
  esac
}

# Main execution
main() {
  local action


  require_commands
  require_cluster_access
  if [ "$#" -eq 0 ]; then
    usage
    exit 1
  fi

  for action in "$@"; do
    if action_requires_akeyless "$action"; then
      validate_variables
      break
    fi
  done

  run_action_sequence "$@"

}

# Run the main function
main
