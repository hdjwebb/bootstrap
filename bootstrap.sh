# K8s bootstrap copyright henry webb 2024
# ####
# ####

set -euo pipefail

declare -a TEMP_DIRS=()
declare -a ACTIONS=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BOOTSTRAP_PROFILE="${BOOTSTRAP_PROFILE:-microk8s-prod}"
ARGOCD_ACCESS_MODE=""
INSTALL_ENVOY=""
INSTALL_METALLB=""
INSTALL_ARGOCD_DOMAIN_SECRET=""
METALLB_ADDRESS_POOL=""
DOMAIN_SECRET_REMOTE_KEY=""
GITLAB_COMPONENTS_REPO_AUTH_KEY=""
GITLAB_CLUSTER_REPO_AUTH_KEY=""
GITLAB_REGISTRY_AUTH_KEY=""
GITLAB_PAGES_HELM_REPO_KEY=""
HELM_REGISTRY_URL=""
CLUSTER_REPO_ROOT="${BOOTSTRAP_CLUSTER_REPO_ROOT:-${WORKSPACE_ROOT}/GitLab/ifpossible-sre/Clusters/microK8s}"
APP_OF_APPS_MANIFEST_PATH=""
APP_OF_APPS_MANIFEST_FILE=""
PROFILE_APP_NAMESPACES="${BOOTSTRAP_PROFILE_APP_NAMESPACES:-}"
ARGOCD_HOSTNAME_PREFIX="${BOOTSTRAP_ARGOCD_HOSTNAME_PREFIX:-argocd}"
ARGOCD_PORT_FORWARD_PORT="${BOOTSTRAP_ARGOCD_PORT_FORWARD_PORT:-8080}"
BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCOUNT="${BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCOUNT:-${USER:-}}"
BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCESS_ID_SERVICE="${BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCESS_ID_SERVICE:-akeyless-access-id}"
BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCESS_KEY_SERVICE="${BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCESS_KEY_SERVICE:-akeyless-access-key}"

die() {
    echo "❌   Error: $*" >&2
    exit 1
}

log_step() {
    echo "==> $*"
}

log_wait_heartbeat() {
    local description="$1"
    local elapsed="$2"
    local timeout="$3"
    local resource_hint="${4:-}"

    if [ -n "${resource_hint}" ]; then
        echo "⏳   ${description} still waiting (${elapsed}s/${timeout}s): ${resource_hint}" >&2
    else
        echo "⏳   ${description} still waiting (${elapsed}s/${timeout}s)" >&2
    fi
}

wait_for_predicate_with_heartbeat() {
    local description="$1"
    local timeout="${2:-120}"
    local interval="${3:-5}"
    local resource_hint="${4:-}"
    local elapsed=0

    shift 4

    while true; do
        if "$@"; then
            return 0
        fi

        if [ "${elapsed}" -ge "${timeout}" ]; then
            die "${description} did not become ready within ${timeout}s."
        fi

        log_wait_heartbeat "${description}" "${elapsed}" "${timeout}" "${resource_hint}"
        sleep "${interval}"
        elapsed=$((elapsed + interval))
    done
}

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
    wait_for_predicate_with_heartbeat \
        "secret ${name} in namespace ${namespace}" \
        "${timeout}" \
        5 \
        "namespace=${namespace} resource=secret/${name}" \
        secret_is_present "${namespace}" "${name}"
}

wait_for_externalsecret_ready() {
    local namespace="$1"
    local name="$2"
    local timeout="${3:-120}"
    wait_for_predicate_with_heartbeat \
        "ExternalSecret ${name} in namespace ${namespace}" \
        "${timeout}" \
        5 \
        "namespace=${namespace} resource=externalsecret/${name}" \
        externalsecret_is_ready "${namespace}" "${name}"
}

wait_for_namespace_deletion() {
    local namespace="$1"
    local timeout="${2:-180}"
    wait_for_predicate_with_heartbeat \
        "namespace ${namespace} to be deleted" \
        "${timeout}" \
        5 \
        "namespace=${namespace}" \
        namespace_is_deleted "${namespace}"
}

wait_for_profile_app_namespaces_deletion() {
    local namespace

    if [ -z "${PROFILE_APP_NAMESPACES}" ]; then
        return 0
    fi

    for namespace in ${PROFILE_APP_NAMESPACES}; do
        wait_for_namespace_deletion "${namespace}" 180
    done
}

wait_for_webhook_ca_bundle() {
    local resource_kind="$1"
    local resource_name="$2"
    local timeout="${3:-120}"
    wait_for_predicate_with_heartbeat \
        "${resource_kind} ${resource_name} CA bundle injection" \
        "${timeout}" \
        5 \
        "resource=${resource_kind}/${resource_name}" \
        webhook_ca_bundle_injected "${resource_kind}" "${resource_name}"
}

externalsecret_is_ready() {
    local namespace="$1"
    local name="$2"
    local ready_status=""

    ready_status="$(kubectl get externalsecret "${name}" -n "${namespace}" -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].status}" 2>/dev/null || true)"
    [ "${ready_status}" = "True" ]
}

secret_is_present() {
    local namespace="$1"
    local name="$2"

    kubectl get secret "${name}" -n "${namespace}" >/dev/null 2>&1
}

namespace_is_deleted() {
    local namespace="$1"
    local deletion_timestamp=""

    if ! kubectl get namespace "${namespace}" >/dev/null 2>&1; then
        return 0
    fi

    deletion_timestamp="$(kubectl get namespace "${namespace}" -o jsonpath="{.metadata.deletionTimestamp}" 2>/dev/null || true)"
    if [ -n "${deletion_timestamp}" ]; then
        clear_namespace_resource_finalizers "${namespace}"
    fi

    return 1
}

clear_namespace_resource_finalizers() {
    local namespace="$1"
    local resource_type=""
    local resource_name=""

    while read -r resource_type; do
        [ -n "${resource_type}" ] || continue

        while read -r resource_name; do
            [ -n "${resource_name}" ] || continue
            kubectl patch "${resource_name}" -n "${namespace}" --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
        done < <(kubectl get -n "${namespace}" "${resource_type}" -o name --ignore-not-found 2>/dev/null || true)
    done < <(kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null || true)
}

webhook_ca_bundle_injected() {
    local resource_kind="$1"
    local resource_name="$2"
    local ca_bundle=""

    ca_bundle="$(kubectl get "${resource_kind}" "${resource_name}" -o jsonpath="{.webhooks[0].clientConfig.caBundle}" 2>/dev/null || true)"
    [ -n "${ca_bundle}" ]
}

kubectl_error_is_retryable() {
    local output="$1"

    case "${output}" in
        *"connect: connection refused"*|*"unexpected EOF"*|*"connection reset by peer"*|*"i/o timeout"*|*"TLS handshake timeout"*|*"Service Unavailable"*|*"service unavailable"*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

kubectl_manifest_delete_error_is_ignorable() {
    local output="$1"

    case "${output}" in
        *"unable to recognize "*|*"the server could not find the requested resource"*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

run_kubectl_with_retry() {
    local max_attempts="${BOOTSTRAP_KUBECTL_RETRY_ATTEMPTS:-5}"
    local retry_delay="${BOOTSTRAP_KUBECTL_RETRY_DELAY_SECONDS:-2}"
    local attempt=1
    local output=""
    local exit_code=0

    while true; do
        set +e
        output="$(kubectl "$@" 2>&1)"
        exit_code=$?
        set -e

        if [ "${exit_code}" -eq 0 ]; then
            if [ -n "${output}" ]; then
                printf '%s\n' "${output}"
            fi
            return 0
        fi

        if ! kubectl_error_is_retryable "${output}" || [ "${attempt}" -ge "${max_attempts}" ]; then
            if [ -n "${output}" ]; then
                printf '%s\n' "${output}" >&2
            fi
            return "${exit_code}"
        fi

        printf '%s\n' "${output}" >&2
        echo "Retrying kubectl $1 after transient transport failure (${attempt}/${max_attempts})..." >&2
        sleep "${retry_delay}"
        attempt=$((attempt + 1))
    done
}

run_kubectl_delete_with_retry_or_ignore_missing_apis() {
    local max_attempts="${BOOTSTRAP_KUBECTL_RETRY_ATTEMPTS:-5}"
    local retry_delay="${BOOTSTRAP_KUBECTL_RETRY_DELAY_SECONDS:-2}"
    local attempt=1
    local saw_retryable_failure=0
    local output=""
    local exit_code=0

    while true; do
        set +e
        output="$(kubectl delete "$@" 2>&1)"
        exit_code=$?
        set -e

        if [ "${exit_code}" -eq 0 ]; then
            if [ -n "${output}" ]; then
                printf '%s\n' "${output}"
            fi
            return 0
        fi

        if [ "${saw_retryable_failure}" -eq 1 ] && kubectl_manifest_delete_error_is_ignorable "${output}"; then
            if [ -n "${output}" ]; then
                printf '%s\n' "${output}" >&2
            fi
            echo "Continuing after manifest delete reported missing APIs during teardown..." >&2
            return 0
        fi

        if kubectl_error_is_retryable "${output}" && [ "${attempt}" -lt "${max_attempts}" ]; then
            saw_retryable_failure=1
            if [ -n "${output}" ]; then
                printf '%s\n' "${output}" >&2
            fi
            echo "Retrying kubectl delete after transient transport failure (${attempt}/${max_attempts})..." >&2
            sleep "${retry_delay}"
            attempt=$((attempt + 1))
            continue
        fi

        if [ -n "${output}" ]; then
            printf '%s\n' "${output}" >&2
        fi
        return "${exit_code}"
    done
}

delete_argocd_applications() {
    if ! kubectl get namespace argocd >/dev/null 2>&1; then
        return 0
    fi

    echo "Deleting Argo CD Application resources before uninstalling Argo CD..."
    kubectl delete applications.argoproj.io --all -n argocd --ignore-not-found=true --wait=false
    wait_for_predicate_with_heartbeat \
        "Argo CD Application resources to be deleted" \
        "${1:-180}" \
        5 \
        "namespace=argocd resource=applications.argoproj.io" \
        argocd_applications_deleted
}

delete_argocd_child_applications() {
    if ! kubectl get namespace argocd >/dev/null 2>&1; then
        return 0
    fi

    local child_apps=""

    child_apps="$(list_argocd_child_applications)"
    if [ -z "${child_apps}" ]; then
        return 0
    fi

    echo "Deleting child Argo CD applications managed by app-of-apps..."
    while read -r app; do
        [ -z "${app}" ] && continue
        kubectl delete "${app}" -n argocd --ignore-not-found=true --wait=false
    done <<< "${child_apps}"
    wait_for_predicate_with_heartbeat \
        "child Argo CD applications to be deleted" \
        "${1:-180}" \
        5 \
        "namespace=argocd annotation=argocd.argoproj.io/tracking-id startsWith app-of-apps:" \
        argocd_child_applications_deleted
}

argocd_applications_deleted() {
    local remaining_apps=""
    local app=""

    remaining_apps="$(kubectl get applications.argoproj.io -n argocd -o name 2>/dev/null || true)"

    if [ -z "${remaining_apps}" ]; then
        return 0
    fi

    for app in ${remaining_apps}; do
        kubectl patch "${app}" -n argocd --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
    done

    return 1
}

argocd_child_applications_deleted() {
    local remaining_apps=""

    remaining_apps="$(list_argocd_child_applications)"

    if [ -z "${remaining_apps}" ]; then
        return 0
    fi

    return 1
}

list_argocd_child_applications() {
    kubectl get applications.argoproj.io -n argocd \
        -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.annotations.argocd\.argoproj\.io/tracking-id}{"\n"}{end}' 2>/dev/null \
        | awk -F'|' '$2 ~ /^app-of-apps:/ {print "application.argoproj.io/" $1}'
}


# Creates a returned line to be used to separate console logs!
# ####
# ####

emptyline(){
    printf '\n'
}

configure_profile() {
    local profile_name="${1:-${BOOTSTRAP_PROFILE}}"

    BOOTSTRAP_PROFILE="${profile_name}"
    CLUSTER_REPO_ROOT="${BOOTSTRAP_CLUSTER_REPO_ROOT:-${WORKSPACE_ROOT}/GitLab/ifpossible-sre/Clusters/microK8s}"
    APP_OF_APPS_MANIFEST_PATH="${BOOTSTRAP_APP_OF_APPS_MANIFEST_PATH:-cluster/dev/app-of-apps.yaml}"
    GITLAB_COMPONENTS_REPO_AUTH_KEY="${BOOTSTRAP_GITLAB_COMPONENTS_REPO_AUTH_KEY:-/microk8s/gitlab-kubecomp-repo-auth}"
    GITLAB_CLUSTER_REPO_AUTH_KEY="${BOOTSTRAP_GITLAB_CLUSTER_REPO_AUTH_KEY:-/microk8s/gitlab-cluster-repo-auth}"
    GITLAB_REGISTRY_AUTH_KEY="${BOOTSTRAP_GITLAB_REGISTRY_AUTH_KEY:-/microk8s/gitlab-registry-auth}"
    GITLAB_PAGES_HELM_REPO_KEY="${BOOTSTRAP_GITLAB_PAGES_HELM_REPO_KEY:-/microk8s/gitlab-pages-helm-repo}"
    HELM_REGISTRY_URL="${BOOTSTRAP_HELM_REGISTRY_URL:-registry.gitlab.com/ifpossible-sre/charts}"
    ARGOCD_HOSTNAME_PREFIX="${BOOTSTRAP_ARGOCD_HOSTNAME_PREFIX:-argocd}"
    ARGOCD_PORT_FORWARD_PORT="${BOOTSTRAP_ARGOCD_PORT_FORWARD_PORT:-8080}"
    PROFILE_APP_NAMESPACES="${BOOTSTRAP_PROFILE_APP_NAMESPACES:-}"

    case "${profile_name}" in
        microk8s-prod)
            ARGOCD_ACCESS_MODE="gateway"
            INSTALL_ENVOY="true"
            INSTALL_METALLB="true"
            INSTALL_ARGOCD_DOMAIN_SECRET="true"
            DOMAIN_SECRET_REMOTE_KEY="${BOOTSTRAP_DOMAIN_SECRET_KEY:-/microk8s/domain}"
            METALLB_ADDRESS_POOL="${BOOTSTRAP_METALLB_ADDRESS_POOL:-192.168.0.220-192.168.0.229}"
            ;;
        microk8s-lab)
            ARGOCD_ACCESS_MODE="gateway"
            INSTALL_ENVOY="true"
            INSTALL_METALLB="true"
            INSTALL_ARGOCD_DOMAIN_SECRET="true"
            DOMAIN_SECRET_REMOTE_KEY="${BOOTSTRAP_DOMAIN_SECRET_KEY:-/microk8s-lab/domain}"
            METALLB_ADDRESS_POOL="${BOOTSTRAP_METALLB_ADDRESS_POOL:-192.168.0.230-192.168.0.239}"
            APP_OF_APPS_MANIFEST_PATH="${BOOTSTRAP_APP_OF_APPS_MANIFEST_PATH:-cluster/lab/app-of-apps.yaml}"
            ;;
        local-test)
            ARGOCD_ACCESS_MODE="port-forward"
            INSTALL_ENVOY="false"
            INSTALL_METALLB="false"
            INSTALL_ARGOCD_DOMAIN_SECRET="false"
            DOMAIN_SECRET_REMOTE_KEY=""
            METALLB_ADDRESS_POOL=""
            APP_OF_APPS_MANIFEST_PATH="${BOOTSTRAP_APP_OF_APPS_MANIFEST_PATH:-cluster/local-test/app-of-apps.yaml}"
            ;;
        local-test-plus)
            ARGOCD_ACCESS_MODE="port-forward"
            INSTALL_ENVOY="false"
            INSTALL_METALLB="false"
            INSTALL_ARGOCD_DOMAIN_SECRET="false"
            DOMAIN_SECRET_REMOTE_KEY=""
            METALLB_ADDRESS_POOL=""
            APP_OF_APPS_MANIFEST_PATH="${BOOTSTRAP_APP_OF_APPS_MANIFEST_PATH:-cluster/local-test-plus/app-of-apps.yaml}"
            PROFILE_APP_NAMESPACES="${BOOTSTRAP_PROFILE_APP_NAMESPACES:-alloy cnpg envoy-gateway-system metallb-system monitoring}"
            ;;
        *)
            die "unknown profile '${profile_name}'. Expected one of: microk8s-prod, microk8s-lab, local-test, local-test-plus."
            ;;
    esac
}

require_profile_settings() {
    if [ -z "${CLUSTER_REPO_ROOT}" ]; then
        die "CLUSTER_REPO_ROOT is empty after configuring profile ${BOOTSTRAP_PROFILE}."
    fi

    if [ ! -d "${CLUSTER_REPO_ROOT}" ]; then
        die "CLUSTER_REPO_ROOT ${CLUSTER_REPO_ROOT} does not exist."
    fi

    if [ -z "${APP_OF_APPS_MANIFEST_PATH}" ]; then
        die "APP_OF_APPS_MANIFEST_PATH is empty after configuring profile ${BOOTSTRAP_PROFILE}."
    fi

    APP_OF_APPS_MANIFEST_FILE="${CLUSTER_REPO_ROOT}/${APP_OF_APPS_MANIFEST_PATH}"

    if [ ! -f "${APP_OF_APPS_MANIFEST_FILE}" ]; then
        die "app-of-apps manifest ${APP_OF_APPS_MANIFEST_FILE} does not exist."
    fi

    if [ "${INSTALL_METALLB}" = "true" ] && [ -z "${METALLB_ADDRESS_POOL}" ]; then
        die "METALLB_ADDRESS_POOL must be set for profile ${BOOTSTRAP_PROFILE}."
    fi

    if [ "${INSTALL_ARGOCD_DOMAIN_SECRET}" = "true" ] && [ -z "${DOMAIN_SECRET_REMOTE_KEY}" ]; then
        die "DOMAIN_SECRET_REMOTE_KEY must be set for profile ${BOOTSTRAP_PROFILE}."
    fi
}

parse_cli_args() {
    ACTIONS=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --profile)
                shift
                [ "$#" -gt 0 ] || die "--profile requires a value."
                BOOTSTRAP_PROFILE="$1"
                ;;
            --profile=*)
                BOOTSTRAP_PROFILE="${1#*=}"
                ;;
            help|-h|--help)
                ACTIONS+=("help")
                ;;
            *)
                ACTIONS+=("$1")
                ;;
        esac

        shift
    done
}

argocd_gateway_enabled() {
    [ "${ARGOCD_ACCESS_MODE}" = "gateway" ]
}

argocd_domain() {
    kubectl get secret domain -n argocd -o jsonpath="{.data.domain}" | base64 --decode
}

argocd_hostname() {
    local domain_value

    if ! argocd_gateway_enabled; then
        printf 'http://127.0.0.1:%s\n' "${ARGOCD_PORT_FORWARD_PORT}"
        return 0
    fi

    if kubectl get secret domain -n argocd >/dev/null 2>&1; then
        domain_value="$(argocd_domain)"
    else
        domain_value="${BOOTSTRAP_FALLBACK_DOMAIN:-bootstrap.local}"
    fi

    printf '%s.%s\n' "${ARGOCD_HOSTNAME_PREFIX}" "${domain_value}"
}

restart_argocd_repo_server_if_present() {
    if kubectl get deployment argocd-repo-server -n argocd >/dev/null 2>&1; then
        echo "Restarting Argo CD repo-server to pick up refreshed repository credentials..."
        kubectl delete pod -l app.kubernetes.io/name=argocd-repo-server -n argocd
        kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-repo-server -n argocd --timeout=180s
    fi
}

refresh_argocd_application_if_present() {
    local application_name="$1"

    if kubectl get application "${application_name}" -n argocd >/dev/null 2>&1; then
        echo "Hard refreshing Argo CD application ${application_name}..."
        kubectl annotate application "${application_name}" -n argocd argocd.argoproj.io/refresh=hard --overwrite
    fi
}

argocd_application_crd_installed() {
    kubectl get crd applications.argoproj.io >/dev/null 2>&1
}

write_argocd_kustomization() {
    local temp_dir="$1"

    cat <<EOF > "${temp_dir}/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd

resources:
- https://raw.githubusercontent.com/argoproj/argo-cd/v3.3.6/manifests/install.yaml
EOF

    if argocd_gateway_enabled; then
        cat <<EOF >> "${temp_dir}/kustomization.yaml"
- httproute.yaml
EOF
    fi

    cat <<'EOF' >> "${temp_dir}/kustomization.yaml"

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
- patch: |-
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: argocd-redis
    spec:
      template:
        spec:
          containers:
          - name: redis
            image: mirror.gcr.io/library/redis:8.2.3-alpine
            imagePullPolicy: IfNotPresent
  target:
    kind: Deployment
    name: argocd-redis
EOF

    if argocd_gateway_enabled; then
        cat <<EOF > "${temp_dir}/httproute.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-route
  namespace: argocd
spec:
  parentRefs:
  - name: tunnel-gateway
    namespace: envoy-gateway-system
  hostnames:
  - "$(argocd_hostname)"
  rules:
  - backendRefs:
    - name: argocd-server
      port: 80
      kind: Service
EOF
    fi
}

# Function to validate required variables
# ####
# ####

validate_variables() {
    local missing_variables=0
    local loaded_from_keychain=0

    if [ -z "${AKEYLESS_ACCESS_ID:-}" ] || [ -z "${AKEYLESS_ACCESS_SECRET_KEY:-}" ]; then
        if load_akeyless_variables_from_keychain; then
            loaded_from_keychain=1
        fi
    fi

    if [ -z "${AKEYLESS_ACCESS_ID:-}" ]; then
        echo "❌   Error: AKEYLESS_ACCESS_ID is not set!"
        missing_variables=1
    fi
    
    if [ -z "${AKEYLESS_ACCESS_SECRET_KEY:-}" ]; then
        echo "❌   Error: AKEYLESS_ACCESS_SECRET_KEY is not set!"
        missing_variables=1
    fi
    
    if [ $missing_variables -eq 1 ]; then
        echo "⚠️    Please set the required variables and try again."
        exit 1
    fi

    if [ "${loaded_from_keychain}" -eq 1 ]; then
        echo "✅ Loaded Akeyless credentials from macOS Keychain."
    fi

    echo "✅ All required variables are set."
    emptyline
}

load_akeyless_variables_from_keychain() {
    local os_name
    local loaded=1

    os_name="$(uname -s 2>/dev/null || true)"

    if [ "${os_name}" != "Darwin" ]; then
        return 1
    fi

    if ! command -v security >/dev/null 2>&1; then
        return 1
    fi

    if [ -z "${BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCOUNT}" ]; then
        return 1
    fi

    if [ -z "${AKEYLESS_ACCESS_ID:-}" ]; then
        AKEYLESS_ACCESS_ID="$(
            security find-generic-password \
                -a "${BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCOUNT}" \
                -s "${BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCESS_ID_SERVICE}" \
                -w 2>/dev/null || true
        )"
        export AKEYLESS_ACCESS_ID
    fi

    if [ -z "${AKEYLESS_ACCESS_SECRET_KEY:-}" ]; then
        AKEYLESS_ACCESS_SECRET_KEY="$(
            security find-generic-password \
                -a "${BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCOUNT}" \
                -s "${BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCESS_KEY_SERVICE}" \
                -w 2>/dev/null || true
        )"
        export AKEYLESS_ACCESS_SECRET_KEY
    fi

    if [ -z "${AKEYLESS_ACCESS_ID:-}" ] || [ -z "${AKEYLESS_ACCESS_SECRET_KEY:-}" ]; then
        loaded=0
    fi

    [ "${loaded}" -eq 1 ]
}


# Function to wait for a deployment to be ready

wait_for_deployment() {
    wait_for_predicate_with_heartbeat \
        "deployment $1 in namespace $2 to be ready" \
        300 \
        5 \
        "namespace=$2 deployment/$1" \
        deployment_is_available "$1" "$2"
}

wait_for_daemonset_rollout() {
    wait_for_predicate_with_heartbeat \
        "daemonset $1 in namespace $2 to roll out" \
        300 \
        5 \
        "namespace=$2 daemonset/$1" \
        daemonset_is_ready "$1" "$2"
}

deployment_is_available() {
    local name="$1"
    local namespace="$2"
    local available_status=""

    available_status="$(kubectl get deployment "${name}" -n "${namespace}" -o jsonpath="{.status.conditions[?(@.type==\"Available\")].status}" 2>/dev/null || true)"
    [ "${available_status}" = "True" ]
}

daemonset_is_ready() {
    local name="$1"
    local namespace="$2"
    local desired=""
    local ready=""

    desired="$(kubectl get daemonset "${name}" -n "${namespace}" -o jsonpath="{.status.desiredNumberScheduled}" 2>/dev/null || true)"
    ready="$(kubectl get daemonset "${name}" -n "${namespace}" -o jsonpath="{.status.numberReady}" 2>/dev/null || true)"

    [ -n "${desired}" ] && [ "${desired}" = "${ready}" ]
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
    run_kubectl_with_retry apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.20.1/cert-manager.yaml
    
    echo "Waiting for cert-manager deployments to be ready..."
    wait_for_deployment cert-manager cert-manager
    wait_for_deployment cert-manager-cainjector cert-manager
    wait_for_deployment cert-manager-webhook cert-manager

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
    run_kubectl_delete_with_retry_or_ignore_missing_apis -f https://github.com/cert-manager/cert-manager/releases/download/v1.20.1/cert-manager.yaml --ignore-not-found=true

    kubectl delete namespace cert-manager --ignore-not-found=true --wait=false
    wait_for_namespace_deletion cert-manager 180
    
    echo "✅ - cert-manager uninstallation complete"
    emptyline
}


# install external secrets

install_external_secrets() {
    echo "Installing external-secrets..."
    create_namespace_if_not_exists external-secrets
    
    temp_dir
    # curl -L -o $TEMP_DIR/external-secrets.yaml https://github.com/external-secrets/external-secrets/releases/download/v2.2.0/external-secrets.yaml
    
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
 - https://github.com/external-secrets/external-secrets/releases/download/v2.2.0/external-secrets.yaml

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

EOF

    run_kubectl_with_retry apply --server-side -k "$TEMP_DIR"
    rm -rf "$TEMP_DIR"
    
    echo "Waiting for external-secrets deployments to be ready..."
    wait_for_deployment external-secrets external-secrets
    wait_for_deployment external-secrets-cert-controller external-secrets
    wait_for_deployment external-secrets-webhook external-secrets

    echo "✅ - external-secrets installation complete"
    emptyline
}

uninstall_external_secrets() {
    echo "Uninstalling external-secrets..."

    run_kubectl_delete_with_retry_or_ignore_missing_apis -f https://github.com/external-secrets/external-secrets/releases/download/v2.2.0/external-secrets.yaml --ignore-not-found=true
    kubectl delete namespace external-secrets --ignore-not-found=true --wait=false
    wait_for_namespace_deletion external-secrets 180

    echo "✅ - external-secrets uninstallation complete"
    emptyline
}


# create ClusterStore connection for aKeyless

install_secret_clusterStore_external_secrets() {
    wait_for_webhook_ca_bundle validatingwebhookconfiguration cert-manager-webhook 120
    wait_for_webhook_ca_bundle validatingwebhookconfiguration secretstore-validate 120
    wait_for_webhook_ca_bundle validatingwebhookconfiguration externalsecret-validate 120

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
apiVersion: external-secrets.io/v1
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

    run_kubectl_with_retry apply -f "$TEMP_DIR/clusterIssuer.yaml"
    run_kubectl_with_retry apply -f "$TEMP_DIR/akeylessSecret.yaml"
    run_kubectl_with_retry apply -f "$TEMP_DIR/akeylessClusterStore.yaml"

    echo "✅ - clusterStore external_secrets created"

}

install_envoy() {
    if [ "${INSTALL_ENVOY}" != "true" ]; then
        echo "Skipping Envoy Gateway for profile ${BOOTSTRAP_PROFILE}."
        emptyline
        return 0
    fi

    echo "Installing Envoy Gateway..."
# Install Envoy Gateway
run_kubectl_with_retry apply -f https://github.com/envoyproxy/gateway/releases/download/v1.7.1/install.yaml --server-side

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
    if [ "${INSTALL_METALLB}" != "true" ]; then
        echo "Skipping MetalLB for profile ${BOOTSTRAP_PROFILE}."
        emptyline
        return 0
    fi

    echo "Installing MetalLB..."

    # Create namespace
    create_namespace_if_not_exists metallb-system

    # Apply MetalLB manifest (which includes CRDs)
    run_kubectl_with_retry apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml

    echo "Waiting for MetalLB CRDs to be established..."
    kubectl wait --for condition=established --timeout=60s crd/ipaddresspools.metallb.io
    kubectl wait --for condition=established --timeout=60s crd/l2advertisements.metallb.io

    echo "Waiting for MetalLB workloads to be ready..."
    wait_for_deployment controller metallb-system
    wait_for_daemonset_rollout speaker metallb-system

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
  - ${METALLB_ADDRESS_POOL}
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
    run_kubectl_with_retry apply -f "$TEMP_DIR/ipPools.yaml"

    # Clean up the temporary directory
    rm -rf "$TEMP_DIR"

    echo "MetalLB installation completed!"
    emptyline
}

install_argocd_secret() {
    if [ "${INSTALL_ARGOCD_DOMAIN_SECRET}" != "true" ]; then
        echo "Skipping Argo CD domain ExternalSecret for profile ${BOOTSTRAP_PROFILE}."
        emptyline
        return 0
    fi

    # Create namespace
    create_namespace_if_not_exists argocd

        # Create a temporary directory for Kustomize files
    TEMP_DIR="$(create_temp_dir)"

    # Create kustomization.yaml for ArgoCD
    cat <<EOF > "$TEMP_DIR/domainsecret.yaml"
apiVersion: external-secrets.io/v1
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
        key: ${DOMAIN_SECRET_REMOTE_KEY}
EOF

    # Apply custom resources
    run_kubectl_with_retry apply -f "$TEMP_DIR/domainsecret.yaml"

    # Clean up the temporary directory
    rm -rf "$TEMP_DIR"

    echo "✅ - argocd Secret installation completed!"
    emptyline
}


install_argocd() {
    echo "Installing ArgoCD..."

    create_namespace_if_not_exists argocd

    if argocd_gateway_enabled; then
        wait_for_secret argocd domain 120
    fi

    # Create a temporary directory for Kustomize files
    TEMP_DIR="$(create_temp_dir)"

    write_argocd_kustomization "$TEMP_DIR"

    # Create the namespace first
    # kubectl apply -f "$TEMP_DIR/namespace.yaml"


    # Install ArgoCD using kustomize
    run_kubectl_with_retry apply --server-side -k "$TEMP_DIR"

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
apiVersion: external-secrets.io/v1
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
        key: ${GITLAB_COMPONENTS_REPO_AUTH_KEY}
        property: url
    - secretKey: username
      remoteRef:
        key: ${GITLAB_COMPONENTS_REPO_AUTH_KEY}
        property: username
    - secretKey: password
      remoteRef:
        key: ${GITLAB_COMPONENTS_REPO_AUTH_KEY}
        property: token
---
apiVersion: external-secrets.io/v1
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
        key: ${GITLAB_CLUSTER_REPO_AUTH_KEY}
        property: url
    - secretKey: username
      remoteRef:
        key: ${GITLAB_CLUSTER_REPO_AUTH_KEY}
        property: username
    - secretKey: password
      remoteRef:
        key: ${GITLAB_CLUSTER_REPO_AUTH_KEY}
        property: token
---
apiVersion: external-secrets.io/v1
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
        url: ${HELM_REGISTRY_URL}                                   # Registry URL
        username: "{{ .username | toString }}"                        # Username
        password: "{{ .password | toString }}"                        # Password
        type: helm                                                    # Repository type for ArgoCD
  data:
    - secretKey: username
      remoteRef:
        key: ${GITLAB_REGISTRY_AUTH_KEY}
        property: username
    - secretKey: password
      remoteRef:
        key: ${GITLAB_REGISTRY_AUTH_KEY}
        property: password
---
apiVersion: external-secrets.io/v1
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
        key: ${GITLAB_PAGES_HELM_REPO_KEY}
        property: url

EOF

    # Install ArgoCD using kustomize
    run_kubectl_with_retry apply -k "$TEMP_DIR"

    wait_for_externalsecret_ready argocd components-repo-secret 120
    wait_for_externalsecret_ready argocd cluster-repo-secret 120
    wait_for_externalsecret_ready argocd registry-secret 120
    wait_for_externalsecret_ready argocd public-pages-helm-repo 120
    restart_argocd_repo_server_if_present
    refresh_argocd_application_if_present app-of-apps

        # Clean up the temporary directory
    rm -rf "$TEMP_DIR"

    
}

add_argocd_app_of_apps() {
    echo "Adding ArgoCD application..."
    echo "Applying tracked app-of-apps manifest ${APP_OF_APPS_MANIFEST_FILE}..."
    run_kubectl_with_retry apply -f "${APP_OF_APPS_MANIFEST_FILE}"

}

remove_argocd_app() {
    echo "Removing ArgoCD application..."

    if ! argocd_application_crd_installed; then
        echo "Skipping ArgoCD application removal because the Application CRD is not installed."
        return 0
    fi

    echo "Deleting tracked app-of-apps manifest ${APP_OF_APPS_MANIFEST_FILE}..."
    run_kubectl_with_retry delete -f "${APP_OF_APPS_MANIFEST_FILE}" --ignore-not-found=true

    delete_argocd_child_applications 180
    wait_for_profile_app_namespaces_deletion

    echo "ArgoCD app removed from argocd"

}

uninstall_argocd() {
    echo "Uninstalling ArgoCD..."

    # Create a temporary directory for Kustomize files
    TEMP_DIR="$(create_temp_dir)"

    write_argocd_kustomization "$TEMP_DIR"

    delete_argocd_applications 180
    run_kubectl_delete_with_retry_or_ignore_missing_apis -k "$TEMP_DIR" --ignore-not-found=true
    kubectl delete namespace argocd --ignore-not-found=true --wait=false
    wait_for_namespace_deletion argocd 180

    # Clean up the temporary directory
    rm -rf "$TEMP_DIR"

    echo "✅ - ArgoCD uninstallation completed!"
    emptyline
}


get_argocd_password() {

  echo "Bootstrap process completed!"
  if argocd_gateway_enabled; then
    echo "ArgoCD should now be accessible via the configured hostname "
    echo "$(argocd_hostname)"
  else
    echo "ArgoCD is configured for local access."
    echo "Run: kubectl -n argocd port-forward svc/argocd-server ${ARGOCD_PORT_FORWARD_PORT}:80"
    echo "Then open: $(argocd_hostname)"
  fi
  emptyline
  echo "Retrieved the ArgoCD admin password: "
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
  emptyline

}

usage() {
  cat <<'EOF'
Usage:
  ./bootstrap.sh [--profile <name>] <action> [<action>...]

Profiles:
  microk8s-prod
  microk8s-lab
  local-test
  local-test-plus

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

Environment overrides:
  BOOTSTRAP_PROFILE
  BOOTSTRAP_CLUSTER_REPO_ROOT
  BOOTSTRAP_METALLB_ADDRESS_POOL
  BOOTSTRAP_DOMAIN_SECRET_KEY
  BOOTSTRAP_APP_OF_APPS_MANIFEST_PATH
  BOOTSTRAP_GITLAB_COMPONENTS_REPO_AUTH_KEY
  BOOTSTRAP_GITLAB_CLUSTER_REPO_AUTH_KEY
  BOOTSTRAP_GITLAB_REGISTRY_AUTH_KEY
  BOOTSTRAP_GITLAB_PAGES_HELM_REPO_KEY
  BOOTSTRAP_HELM_REGISTRY_URL
  BOOTSTRAP_ARGOCD_HOSTNAME_PREFIX
  BOOTSTRAP_ARGOCD_PORT_FORWARD_PORT
  BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCOUNT
  BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCESS_ID_SERVICE
  BOOTSTRAP_AKEYLESS_KEYCHAIN_ACCESS_KEY_SERVICE
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

  parse_cli_args "$@"
  if [ "$#" -eq 0 ]; then
    usage
    exit 1
  fi

  if [ "${#ACTIONS[@]}" -eq 0 ]; then
    usage
    exit 1
  fi

  if [ "${#ACTIONS[@]}" -eq 1 ] && [ "${ACTIONS[0]}" = "help" ]; then
    usage
    exit 0
  fi

  configure_profile "${BOOTSTRAP_PROFILE}"
  require_profile_settings
  require_commands
  require_cluster_access

  for action in "${ACTIONS[@]}"; do
    if action_requires_akeyless "$action"; then
      validate_variables
      break
    fi
  done

  run_action_sequence "${ACTIONS[@]}"

}

# Run the main function
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
