# microK8s bootstrap copyroght henry webb 2024
# ####
# ####


# Creates a returned line to be used to separate console logs!
# ####
# ####

emptyline(){
    echo "\n"
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
    kubectl wait --for=condition=available --timeout=300s deployment/$1 -n $2
}

# Function to create namespace if it doesn't exist

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
    if ! kubectl get namespace "$1" &> /dev/null; then
        echo "Creating namespace: $1"
        kubectl create namespace "$1"
    else
        echo "Namespace $1 already exists"
    fi
}

# TEMP_DIR

temp_dir() {
    # Create a temporary directory for Kustomize files
    TEMP_DIR=$(mktemp -d)
    echo "Created temporary directory: $TEMP_DIR"
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
    TEMP_DIR=$(mktemp -d)
    echo "Created temporary directory: $TEMP_DIR"

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
    TEMP_DIR=$(mktemp -d)
    echo "Created temporary directory: $TEMP_DIR"

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

    echo "Waiting for secret to become available..."
    sleep 10  # Wait for 10 seconds to ensure secret is available

    # Verify the secret exists before proceeding
    kubectl get secret domain -n argocd

    # Create a temporary directory for Kustomize files
    TEMP_DIR=$(mktemp -d)
    echo "Created temporary directory: $TEMP_DIR"

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


get_argocd_password() {

  echo "Bootstrap process completed!"
  echo "ArgoCD should now be accessible via the configured hostname "
  echo "argocd.$(kubectl get secret domain -n argocd -o jsonpath="{.data.domain}" | base64 -d)"
  emptyline
  echo "Retrieved the ArgoCD admin password: "
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
  emptyline

}
# Main execution
main() {


# Call the validation function
  validate_variables

# UNINSTALL
  # uninstall_cert_manager
  # uninstall_external_secrets

# INSTALL
  # install_cert_manager
  # install_external_secrets
  # install_secret_clusterStore_external_secrets
  # install_envoy
  # install_metallb
  # install_argocd_secret
  install_argocd
  get_argocd_password


}

# Run the main function
main