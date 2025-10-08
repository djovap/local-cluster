#!/bin/bash

# =============================================================================
# Kind (Kubernetes In Docker) Development Environment Setup
# =============================================================================
# This script creates a complete local development environment using Kind
# with OIDC integration, ArgoCD, Prometheus, and all services
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="dev-local"
KUBECONFIG_PATH="$HOME/.kube/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Prerequisites check
REQUIRED_TOOLS=(
    "kind"
    "kubectl"
    "helm"
    "docker"
    "git"
    "curl"
)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

step() {
    echo -e "\n${PURPLE}========================================${NC}"
    echo -e "${PURPLE}STEP: $1${NC}"
    echo -e "${PURPLE}========================================${NC}\n"
}

wait_for_pods() {
    local namespace=$1
    local timeout=${2:-300}
    info "Waiting for pods in namespace '$namespace' to be ready (timeout: ${timeout}s)..."
    kubectl wait --for=condition=ready pod --all -n "$namespace" --timeout="${timeout}s" || {
        warn "Some pods in namespace '$namespace' are not ready yet"
        kubectl get pods -n "$namespace"
    }
}

wait_for_deployment() {
    local deployment=$1
    local namespace=$2
    local timeout=${3:-300}
    info "Waiting for deployment '$deployment' in namespace '$namespace' to be ready..."
    kubectl wait --for=condition=available --timeout="${timeout}s" deployment/"$deployment" -n "$namespace"
}

# Wait for StatefulSet to be ready
wait_for_statefulset() {
    local statefulset=$1
    local namespace=$2
    local timeout=${3:-300}
    info "Waiting for statefulset '$statefulset' in namespace '$namespace' to be ready..."
    kubectl wait --for=condition=ready --timeout="${timeout}s" pod -l app="$statefulset" -n "$namespace"
}

# Copy template file with variable substitution
copy_template() {
    local template_file=$1
    local destination_file=$2
    local substitute_vars=${3:-false}
    
    if [ ! -f "$template_file" ]; then
        error "Template file not found: $template_file"
    fi
    
    # Create destination directory if it doesn't exist
    mkdir -p "$(dirname "$destination_file")"
    
    if [ "$substitute_vars" = "true" ]; then
        # Perform variable substitution
        sed "s|__PROJECT_ROOT__|$PROJECT_ROOT|g" "$template_file" > "$destination_file"
    else
        # Simple copy
        cp "$template_file" "$destination_file"
    fi
    
    log "✓ Copied template: $(basename "$template_file") -> $(basename "$destination_file")"
}

# Retry function with exponential backoff
retry_with_backoff() {
    local max_attempts=$1
    shift
    local cmd="$@"
    local attempt=1
    local delay=1
    
    while [ $attempt -le $max_attempts ]; do
        info "Attempt $attempt/$max_attempts: $cmd"
        if eval "$cmd"; then
            log "✓ Command succeeded on attempt $attempt"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            error "Command failed after $max_attempts attempts: $cmd"
        fi
        
        warn "Command failed on attempt $attempt. Retrying in ${delay}s..."
        sleep $delay
        attempt=$((attempt + 1))
        delay=$((delay * 2))
    done
}

# Enhanced wait for pods function with better error reporting
wait_for_pods_enhanced() {
    local namespace=$1
    local timeout=${2:-300}
    local selector=${3:-""}
    
    info "Waiting for pods in namespace '$namespace' to be ready (timeout: ${timeout}s)..."
    
    # Build kubectl command
    local kubectl_cmd="kubectl wait --for=condition=ready pod --all -n $namespace --timeout=${timeout}s"
    if [ -n "$selector" ]; then
        kubectl_cmd="kubectl wait --for=condition=ready pod -l $selector -n $namespace --timeout=${timeout}s"
    fi
    
    if ! $kubectl_cmd; then
        warn "Some pods in namespace '$namespace' are not ready yet"
        info "Pod status in namespace '$namespace':"
        kubectl get pods -n "$namespace" -o wide || true
        info "Recent events in namespace '$namespace':"
        kubectl get events -n "$namespace" --sort-by='.lastTimestamp' | tail -10 || true
        return 1
    fi
    
    log "✓ All pods in namespace '$namespace' are ready"
}

# Check if namespace exists
namespace_exists() {
    local namespace=$1
    kubectl get namespace "$namespace" >/dev/null 2>&1
}

# Create namespace if it doesn't exist
ensure_namespace() {
    local namespace=$1
    if ! namespace_exists "$namespace"; then
        info "Creating namespace: $namespace"
        kubectl create namespace "$namespace" || error "Failed to create namespace: $namespace"
    else
        info "Namespace '$namespace' already exists"
    fi
}

# Load Docker image into Kind cluster (helper for image pull issues)
load_image_to_kind() {
    local image=$1
    local cluster_name=${2:-$CLUSTER_NAME}
    
    info "Loading image '$image' into Kind cluster '$cluster_name'..."
    if docker image inspect "$image" >/dev/null 2>&1; then
        kind load docker-image "$image" --name "$cluster_name"
        log "✓ Image '$image' loaded into Kind cluster"
    else
        warn "Image '$image' not found locally. Pull it first with: docker pull $image"
        return 1
    fi
}

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

check_prerequisites() {
    step "Checking prerequisites"
    
    local missing_tools=()
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        else
            log "✓ $tool is installed"
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        error "Missing required tools: ${missing_tools[*]}
Please install them first:
- kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation
- kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl/
- helm: https://helm.sh/docs/intro/install/
- docker: https://docs.docker.com/get-docker/
- git: https://git-scm.com/downloads"
    fi
    
    # Check Docker is running
    if ! docker info &> /dev/null; then
        error "Docker is not running. Please start Docker Desktop."
    fi
    log "✓ Docker is running"
    
    # Check if cluster already exists
    if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        warn "Kind cluster '$CLUSTER_NAME' already exists"
        read -p "Do you want to delete and recreate it? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kind delete cluster --name "$CLUSTER_NAME"
            log "✓ Deleted existing cluster"
        else
            info "Using existing cluster"
            return
        fi
    fi
}

# =============================================================================
# KIND CLUSTER CONFIGURATION
# =============================================================================

create_kind_config() {
    step "Verifying Kind cluster configuration"
    
    # Substitute variables in the existing config file
    if [ -f "$PROJECT_ROOT/configs/kind-config.yaml" ]; then
        # Perform variable substitution in place
        sed -i.bak "s|__PROJECT_ROOT__|$PROJECT_ROOT|g" "$PROJECT_ROOT/configs/kind-config.yaml"
        rm -f "$PROJECT_ROOT/configs/kind-config.yaml.bak"
        log "✓ Kind configuration variables updated"
    else
        error "Kind configuration not found at $PROJECT_ROOT/configs/kind-config.yaml"
    fi
}

# =============================================================================
# KIND CLUSTER CREATION
# =============================================================================

create_kind_cluster() {
    step "Creating Kind cluster"
    
    if ! kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        info "Creating Kind cluster with OIDC configuration..."
        retry_with_backoff 3 "kind create cluster --config '$PROJECT_ROOT/configs/kind-config.yaml'"
        log "✓ Kind cluster '$CLUSTER_NAME' created"
    else
        log "✓ Kind cluster '$CLUSTER_NAME' already exists"
    fi
    
    # Set kubectl context and verify cluster is accessible
    info "Setting kubectl context and verifying cluster access..."
    retry_with_backoff 3 "kubectl cluster-info --context 'kind-$CLUSTER_NAME'"
    
    log "✓ Cluster ready"
}

# =============================================================================
# INGRESS NGINX SETUP
# =============================================================================

install_ingress_nginx() {
    step "Installing Ingress NGINX"
    
    # Install ingress-nginx
    info "Deploying Ingress NGINX controller..."
    retry_with_backoff 3 "kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml"
    
    # Wait for ingress controller deployment to be ready
    info "Waiting for Ingress NGINX controller deployment to be ready..."
    wait_for_deployment "ingress-nginx-controller" "ingress-nginx" 300
    
    # Wait for admission webhook to be ready (critical for ingress creation)
    info "Waiting for Ingress NGINX admission webhook to be ready..."
    local webhook_ready=false
    local max_attempts=60  # Increased from 30 to 60 (5 minutes total)
    local attempt=1
    
    while [ $attempt -le $max_attempts ] && [ "$webhook_ready" = false ]; do
        info "Checking admission webhook readiness (attempt $attempt/$max_attempts)..."
        
        # Check if validating webhook configuration exists
        if ! kubectl get validatingwebhookconfiguration ingress-nginx-admission >/dev/null 2>&1; then
            warn "ValidatingWebhookConfiguration not found yet, waiting 5s..."
            sleep 5
            attempt=$((attempt + 1))
            continue
        fi
        
        # Check if admission webhook service exists and has endpoints
        if ! kubectl get service -n ingress-nginx ingress-nginx-controller-admission >/dev/null 2>&1; then
            warn "Admission webhook service not found yet, waiting 5s..."
            sleep 5
            attempt=$((attempt + 1))
            continue
        fi
        
        # Check if admission webhook pod is ready
        if ! kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.phase}' | grep -q "Running"; then
            warn "Admission webhook pod not running yet, waiting 5s..."
            sleep 5
            attempt=$((attempt + 1))
            continue
        fi
        
        # Check if service has endpoints (pod is actually serving)
        local endpoints
        endpoints=$(kubectl get endpoints -n ingress-nginx ingress-nginx-controller-admission -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
        if [ -z "$endpoints" ]; then
            warn "Admission webhook service has no endpoints yet, waiting 5s..."
            sleep 5
            attempt=$((attempt + 1))
            continue
        fi
        
        # Final test: try to actually contact the webhook service
        info "Testing webhook connectivity..."
        if kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- nc -z ingress-nginx-controller-admission.ingress-nginx.svc.cluster.local 443 2>/dev/null; then
            # Give webhook service extra time to be fully ready for TLS
            info "Webhook service is responding"
            sleep 15
            webhook_ready=true
            log "✓ Ingress NGINX admission webhook is ready"
        else
            warn "Webhook service not responding yet, waiting 10s..."
            sleep 10
            attempt=$((attempt + 1))
        fi
    done
    
    if [ "$webhook_ready" = false ]; then
        warn "Admission webhook may not be fully ready after $max_attempts attempts"
        info "You may need to retry Dex installation if it fails due to webhook issues"
        info "To manually check webhook status:"
        info "  kubectl get pods -n ingress-nginx"
        info "  kubectl get endpoints -n ingress-nginx ingress-nginx-controller-admission"
    fi
    
    log "✓ Ingress NGINX installed and ready"
}

# =============================================================================
# COREDNS LOCALHOST CONFIGURATION
# =============================================================================

configure_localhost_dns() {
    step "Configuring CoreDNS for .localhost domain resolution"
    
    # Wait for ingress controller service to be ready and have a ClusterIP
    info "Waiting for ingress controller service to be ready..."
    local ingress_ip=""
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ] && [ -z "$ingress_ip" ]; do
        info "Waiting for ingress controller service IP (attempt $attempt/$max_attempts)..."
        ingress_ip=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
        
        if [ -n "$ingress_ip" ] && [ "$ingress_ip" != "None" ]; then
            break
        fi
        
        sleep 5
        attempt=$((attempt + 1))
    done
    
    if [ -z "$ingress_ip" ] || [ "$ingress_ip" = "None" ]; then
        error "Could not get ingress controller ClusterIP after $max_attempts attempts"
    fi
    
    info "Ingress controller ClusterIP: $ingress_ip"
    
    # Create CoreDNS configuration patch
    info "Patching CoreDNS to resolve .localhost domains via ingress controller..."
    
    # Create temporary patch file
    cat > /tmp/coredns-patch.yaml << EOF
data:
  Corefile: |
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
            ttl 30
        }
        hosts {
            ${ingress_ip} dex.localhost
            ${ingress_ip} argocd.localhost
            ${ingress_ip} grafana.localhost
            ${ingress_ip} forgejo.localhost
            ${ingress_ip} mailpit.localhost
            ${ingress_ip} ldap.localhost
            fallthrough
        }
        prometheus :9153
        forward . /etc/resolv.conf {
            max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
EOF
    
    # Apply CoreDNS configuration with retry
    retry_with_backoff 3 "kubectl patch configmap coredns -n kube-system --patch-file /tmp/coredns-patch.yaml"
    
    # Restart CoreDNS deployment to pick up new configuration
    info "Restarting CoreDNS deployment..."
    kubectl rollout restart deployment coredns -n kube-system
    kubectl rollout status deployment coredns -n kube-system --timeout=300s
    
    # Wait a moment for DNS to propagate
    info "Waiting for DNS configuration to propagate..."
    sleep 10
    
    # Clean up temporary files
    rm -f /tmp/coredns-patch.yaml
    
    log "✓ CoreDNS configured to resolve .localhost domains via ingress ($ingress_ip)"
}

# =============================================================================
# DEX OIDC CONFIGURATION
# =============================================================================

setup_dex_oidc() {
    step "Setting up Dex OIDC"
    
    # Verify Dex configuration exists
    if [ ! -f "$PROJECT_ROOT/configs/dex-values.yaml" ]; then
        error "Dex configuration not found at $PROJECT_ROOT/configs/dex-values.yaml"
    fi
    
    # Check if local chart exists, otherwise use remote repo
    local dex_chart=""
    if ls "$PROJECT_ROOT/charts/setup/dex-"*.tgz 1> /dev/null 2>&1; then
        dex_chart=$(ls "$PROJECT_ROOT/charts/setup/dex-"*.tgz | head -1)
        info "Using local Dex chart: $dex_chart"
    else
        # Add Dex repo with retry
        info "Local Dex chart not found, adding remote repository..."
        retry_with_backoff 3 "helm repo add dex https://charts.dexidp.io"
        retry_with_backoff 3 "helm repo update"
        dex_chart="dex/dex"
        info "Using remote Dex chart: $dex_chart"
    fi
    
    # Create dex namespace
    ensure_namespace "dex"
    
    # Install Dex with retry
    info "Installing Dex OIDC provider..."
    local dex_install_cmd="helm upgrade --install dex '$dex_chart' -n dex --values '$PROJECT_ROOT/configs/dex-values.yaml' --timeout 5m"
    
    # Use retry with longer delay for webhook-related issues
    local attempt=1
    local max_attempts=5
    local delay=10
    
    while [ $attempt -le $max_attempts ]; do
        info "Attempt $attempt/$max_attempts: Installing Dex..."
        
        if eval "$dex_install_cmd"; then
            log "✓ Dex installation succeeded on attempt $attempt"
            break
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            error "Dex installation failed after $max_attempts attempts. Check if nginx admission webhook is ready."
        fi
        
        warn "Dex installation failed on attempt $attempt (likely webhook timing). Retrying in ${delay}s..."
        sleep $delay
        attempt=$((attempt + 1))
        
        # Check webhook status for better error messaging
        if ! kubectl get validatingwebhookconfiguration ingress-nginx-admission >/dev/null 2>&1; then
            warn "Nginx admission webhook configuration not found. Webhook may not be ready."
        fi
    done
    
    # Wait for Dex to be ready
    info "Waiting for Dex deployment to be ready..."
    if ! wait_for_deployment "dex" "dex" 300; then
        error "Dex deployment failed to become ready"
    fi
    
    log "✓ Dex OIDC installed and configured"
}

# =============================================================================
# OPENLDAP SETUP
# =============================================================================

setup_openldap() {
    step "Setting up OpenLDAP"
    
    # Verify OpenLDAP configuration exists
    if [ ! -f "$PROJECT_ROOT/configs/openldap-values.yaml" ]; then
        error "OpenLDAP configuration not found at $PROJECT_ROOT/configs/openldap-values.yaml"
    fi
    
    # Check if local chart exists, otherwise use remote repo
    local openldap_chart=""
    if ls "$PROJECT_ROOT/charts/setup/openldap-stack-ha-"*.tgz 1> /dev/null 2>&1; then
        openldap_chart=$(ls "$PROJECT_ROOT/charts/setup/openldap-stack-ha-"*.tgz | head -1)
        info "Using local OpenLDAP chart: $openldap_chart"
    else
        # Add helm-openldap repo for OpenLDAP with retry
        info "Local OpenLDAP chart not found, adding remote repository..."
        retry_with_backoff 3 "helm repo add helm-openldap https://jp-gouin.github.io/helm-openldap"
        retry_with_backoff 3 "helm repo update"
        openldap_chart="helm-openldap/openldap-stack-ha"
        info "Using remote OpenLDAP chart: $openldap_chart"
    fi
    
    # Create ldap namespace
    ensure_namespace "ldap"
    
    # Install OpenLDAP with retry
    info "Installing OpenLDAP server..."
    retry_with_backoff 3 "helm upgrade --install openldap '$openldap_chart' -n ldap --values '$PROJECT_ROOT/configs/openldap-values.yaml'"
    
    # Wait for OpenLDAP to be ready (it's a StatefulSet, not a Deployment)
    info "Waiting for OpenLDAP statefulset to be ready..."
    if ! wait_for_statefulset "openldap" "ldap" 300; then
        warn "OpenLDAP statefulset not ready yet, but continuing..."
        info "Check OpenLDAP pod status: kubectl get pods -n ldap"
        info "Check OpenLDAP logs: kubectl logs -n ldap openldap-0"
    fi
    
    # Wait additional time for OpenLDAP to fully initialize and auto-load LDIF files
    info "Waiting for OpenLDAP to fully initialize and auto-load LDIF files..."
    sleep 15
    
    # Verify LDAP users were loaded automatically via LDAP_SEED_INTERNAL_LDIF_PATH
    info "Verifying LDAP users and groups were auto-loaded from custom LDIF files..."
    if kubectl exec -n ldap openldap-0 -- ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=ldap,dc=localhost" -w password -b "ou=people,dc=ldap,dc=localhost" "(mail=dev1@local.dev)" dn 2>&1 | grep -q "cn=developer1"; then
        log "✓ LDAP users and groups loaded successfully"
    else
        warn "LDAP users not found. LDIF auto-loading may have failed."
        info "Attempting manual load as fallback..."
        if kubectl exec -n ldap openldap-0 -- ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=ldap,dc=localhost" -w password -f /ldifs/01-users.ldif 2>&1 | grep -q "adding new entry"; then
            log "✓ LDAP users loaded manually"
        else
            warn "Manual load also failed. Users may already exist or check container logs."
        fi
    fi
    
    # Fix phpLDAPadmin configuration to use correct LDAP endpoint and domain
    info "Configuring phpLDAPadmin to connect to OpenLDAP..."
    if kubectl set env deployment/openldap-phpldapadmin -n ldap PHPLDAPADMIN_LDAP_HOSTS="#PYTHON2BASH:[{ 'openldap-0.openldap-headless.ldap.svc.cluster.local': [{'server': [{'tls': False},{'port':389}]},{'login': [{'bind_id': 'cn=admin,dc=ldap,dc=localhost'}]}]}]" >/dev/null 2>&1; then
        info "Waiting for phpLDAPadmin to restart with new configuration..."
        kubectl rollout status deployment/openldap-phpldapadmin -n ldap --timeout=60s >/dev/null 2>&1 || warn "phpLDAPadmin rollout may still be in progress"
        log "✓ phpLDAPadmin configured"
    else
        warn "Failed to configure phpLDAPadmin, you may need to configure it manually"
    fi
    
    log "✓ OpenLDAP installed and configured"
    
    # Display LDAP users information
    info "LDAP Users configured:"
    info "  - admin@local.dev / password (LDAP binding user)"
    info "  - dev1@local.dev / password (super-admins group - cluster-admin)"
    info "  - dev2@local.dev / password (admins group - cluster-admin)"
    info "  - user1@local.dev / password (users group - read-only via authenticated users)"
}

# =============================================================================
# PROMETHEUS MONITORING SETUP
# =============================================================================

setup_prometheus() {
    step "Setting up Prometheus monitoring stack"
    
    # Verify Prometheus configuration exists
    if [ ! -f "$PROJECT_ROOT/configs/prometheus-values.yaml" ]; then
        error "Prometheus configuration not found at $PROJECT_ROOT/configs/prometheus-values.yaml"
    fi
    
    # Check if local chart exists, otherwise use remote repo
    local prometheus_chart=""
    if ls "$PROJECT_ROOT/charts/setup/prometheus-"*.tgz 1> /dev/null 2>&1; then
        prometheus_chart=$(ls "$PROJECT_ROOT/charts/setup/prometheus-"*.tgz | head -1)
        info "Using local Prometheus chart: $prometheus_chart"
    else
        # Add Prometheus community repo
        info "Local Prometheus chart not found, adding remote repository..."
        retry_with_backoff 3 "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts"
        retry_with_backoff 3 "helm repo update"
        prometheus_chart="prometheus-community/kube-prometheus-stack"
        info "Using remote Prometheus chart: $prometheus_chart"
    fi
    
    # Create monitoring namespace
    ensure_namespace "monitoring"

    # Install Prometheus stack with retry
    info "Installing Prometheus monitoring stack (this may take a few minutes)..."
    retry_with_backoff 3 "helm upgrade --install prometheus '$prometheus_chart' -n monitoring --values '$PROJECT_ROOT/configs/prometheus-values.yaml' --timeout 15m"
    
    # Wait for Prometheus components to be ready
    info "Waiting for Prometheus operator to be ready..."
    if ! wait_for_deployment "prometheus-kube-prometheus-prometheus-operator" "monitoring" 300; then
        warn "Prometheus operator deployment not ready, but continuing..."
    fi
    
    info "Waiting for Prometheus server to be ready..."
    # Prometheus uses StatefulSet, so we need to wait differently
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=300s || warn "Prometheus server not ready yet"
    
    info "Waiting for Grafana to be ready..."
    if ! wait_for_deployment "prometheus-grafana" "monitoring" 300; then
        warn "Grafana deployment not ready, but continuing..."
    fi
    
    # Note: No custom ServiceMonitors needed - kube-prometheus-stack includes built-in monitoring
    info "Using built-in ServiceMonitors for comprehensive Kubernetes monitoring..."
    
    log "✓ Prometheus monitoring stack installed and configured"
    
    # Display monitoring access information
    info "Monitoring Access Information:"
    info "  - Grafana Dashboard: https://grafana.localhost (OIDC authentication required)"
    info "  - Prometheus UI: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
    info "  - AlertManager UI: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093"
    info ""
    info "Built-in Kubernetes Monitoring:"
    info "  ✓ Pod CPU/Memory usage (from kubelet/cAdvisor)"
    info "  ✓ Node resources (CPU, memory, disk, network)"
    info "  ✓ Kubernetes objects (deployments, services, ingress)"
    info "  ✓ Cluster health (API server, etcd, controller manager)"
    info "  ✓ Container metrics (restarts, status, resource limits)"
    info "  ⚠ Application-specific metrics require custom /metrics endpoints"
}

# =============================================================================
# ARGOCD SETUP
# =============================================================================

setup_argocd() {
    step "Setting up ArgoCD"
    
    # Verify ArgoCD configuration exists
    if [ ! -f "$PROJECT_ROOT/configs/argocd-values.yaml" ]; then
        error "ArgoCD configuration not found at $PROJECT_ROOT/configs/argocd-values.yaml"
    fi
    
    # Check if local chart exists, otherwise use remote repo
    local argocd_chart=""
    if ls "$PROJECT_ROOT/charts/setup/argocd-"*.tgz 1> /dev/null 2>&1; then
        argocd_chart=$(ls "$PROJECT_ROOT/charts/setup/argocd-"*.tgz | head -1)
        info "Using local ArgoCD chart: $argocd_chart"
    else
        # Add ArgoCD repo
        info "Local ArgoCD chart not found, adding remote repository..."
        retry_with_backoff 3 "helm repo add argo https://argoproj.github.io/argo-helm"
        retry_with_backoff 3 "helm repo update"
        argocd_chart="argo/argo-cd"
        info "Using remote ArgoCD chart: $argocd_chart"
    fi
    
    # Create argocd namespace
    ensure_namespace "argocd"
    
    # Note: TLS secrets not needed for HTTP-only setup
    
    # Install ArgoCD with retry
    info "Installing ArgoCD ..."
    retry_with_backoff 3 "helm upgrade --install argocd '$argocd_chart' -n argocd --values '$PROJECT_ROOT/configs/argocd-values.yaml' --timeout 10m"
    
    # Wait for ArgoCD components to be ready
    info "Waiting for ArgoCD server to be ready..."
    if ! wait_for_deployment "argocd-server" "argocd" 300; then
        warn "ArgoCD server deployment not ready, but continuing..."
    fi
    
    info "Waiting for ArgoCD application controller to be ready..."
    if ! wait_for_deployment "argocd-application-controller" "argocd" 300; then
        warn "ArgoCD application controller not ready, but continuing..."
    fi
    
    info "Waiting for ArgoCD repo server to be ready..."
    if ! wait_for_deployment "argocd-repo-server" "argocd" 300; then
        warn "ArgoCD repo server not ready, but continuing..."
    fi
    
    log "✓ ArgoCD installed and configured"
    
    # Display ArgoCD access information
    info "ArgoCD Access Information:"
    info "  - ArgoCD UI: https://argocd.localhost (OIDC authentication required)"
    info "  - CLI Login: argocd login argocd.localhost --sso"
    info "  - Port-forward: kubectl port-forward -n argocd svc/argocd-server 8080:80"
}

# =============================================================================
# FORGEJO SETUP
# =============================================================================

setup_forgejo() {
    step "Setting up Forgejo for Git platform"
    
    # Verify Forgejo configuration exists
    if [ ! -f "$PROJECT_ROOT/configs/forgejo-values.yaml" ]; then
        error "Forgejo configuration not found at $PROJECT_ROOT/configs/forgejo-values.yaml"
    fi
    
    # Check if local chart exists, otherwise use remote repo
    local forgejo_chart=""
    if ls "$PROJECT_ROOT/charts/setup/forgejo-"*.tgz 1> /dev/null 2>&1; then
        forgejo_chart=$(ls "$PROJECT_ROOT/charts/setup/forgejo-"*.tgz | head -1)
        info "Using local Forgejo chart: $forgejo_chart"
    else
        info "Local Forgejo chart not found, using remote OCI registry..."
        forgejo_chart="oci://code.forgejo.org/forgejo-helm/forgejo"
        info "Using remote Forgejo chart: $forgejo_chart"
    fi
    
    # Create forgejo namespace
    ensure_namespace "forgejo"
    
    # Install Forgejo with retry
    info "Installing Forgejo (this may take a few minutes)..."
    retry_with_backoff 3 "helm upgrade --install forgejo '$forgejo_chart' -n forgejo --values '$PROJECT_ROOT/configs/forgejo-values.yaml' --timeout 10m"
    
    # Wait for Forgejo components to be ready
    info "Waiting for Forgejo deployment to be ready..."
    if ! wait_for_deployment "forgejo" "forgejo" 300; then
        warn "Forgejo deployment not ready, but continuing..."
    fi
    
    info "Waiting for PostgreSQL to be ready..."
    if ! wait_for_deployment "forgejo-postgresql" "forgejo" 300; then
        warn "Forgejo PostgreSQL not ready, but continuing..."
    fi
    
    # Wait a bit for services to be fully ready
    info "Waiting for services to be fully ready..."
    sleep 30
    
    # Login to Helm registry
    info "Logging in to Forgejo Helm registry..."
    if command -v helm >/dev/null 2>&1; then
        if helm registry login forgejo.localhost --username platform-admin --password password --insecure >/dev/null 2>&1; then
            log "✓ Helm registry login successful"
        else
            warn "Helm registry login failed, you may need to login manually"
        fi
    else
        warn "Helm not found, skipping registry login"
    fi
    
    log "✓ Forgejo installed and configured"
    
    # Display Forgejo access information
    info "Forgejo Access Information:"
    info "  - Forgejo UI: http://forgejo.localhost (OIDC authentication available)"
    info "  - Direct access: kubectl port-forward -n forgejo svc/forgejo 3000:3000"
    info "  - Default admin user: platform-admin / password (if needed for initial setup)"
    info ""
    info "OIDC Authentication:"
    info "  ✓ Users can sign in with Dex OIDC"
    info "  ✓ Auto-registration enabled for OIDC users"
    info "  ✓ super-admins group gets admin privileges"
    info "  ✓ users group gets restricted access"
}

setup_mailpit() {
    step "Setting up Mailpit Email Testing Tool"
    
    # Verify Mailpit configuration exists
    if [ ! -f "$PROJECT_ROOT/configs/mailpit-values.yaml" ]; then
        error "Mailpit configuration not found at $PROJECT_ROOT/configs/mailpit-values.yaml"
    fi
    
    # Check if local chart exists, otherwise use remote repo
    local mailpit_chart=""
    if ls "$PROJECT_ROOT/charts/setup/mailpit-"*.tgz 1> /dev/null 2>&1; then
        mailpit_chart=$(ls "$PROJECT_ROOT/charts/setup/mailpit-"*.tgz | head -1)
        info "Using local Mailpit chart: $mailpit_chart"
    else
        info "Local Mailpit chart not found, adding remote repository..."
        retry_with_backoff 3 "helm repo add jouve https://jouve.github.io/charts/"
        retry_with_backoff 3 "helm repo update"
        mailpit_chart="jouve/mailpit"
        info "Using remote Mailpit chart: $mailpit_chart"
    fi
    
    # Create mailpit namespace
    ensure_namespace "mailpit"
    
    # Install Mailpit with retry
    info "Installing Mailpit Email Testing Tool..."
    retry_with_backoff 3 "helm upgrade --install mailpit '$mailpit_chart' -n mailpit --values '$PROJECT_ROOT/configs/mailpit-values.yaml' --timeout 10m"
    
    # Wait for Mailpit to be ready
    info "Waiting for Mailpit deployment to be ready..."
    if ! wait_for_deployment "mailpit-service" "mailpit" 300; then
        error "Mailpit deployment failed to become ready"
    fi
    
    log "✓ Mailpit Email Testing Tool installed and configured"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Execute sequential setup steps (required dependencies)
    check_prerequisites
    create_kind_config
    create_kind_cluster
    install_ingress_nginx
    configure_localhost_dns
    
    # Execute parallel setup steps (helm installations that can run concurrently)
    info "Starting parallel installation of services..."
    
    # Run helm installations in parallel using background jobs
    local pids=()
    
    setup_openldap &
    pids+=($!)
    
    setup_dex_oidc &
    pids+=($!)
    
    setup_prometheus &
    pids+=($!)
    
    setup_argocd &
    pids+=($!)
    
    setup_forgejo &
    pids+=($!)
    
    setup_mailpit &
    pids+=($!)
    
    # Wait for all parallel jobs to complete
    info "Waiting for all parallel installations to complete..."
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=1
            error "One of the parallel installations failed (PID: $pid)"
        fi
    done
    
    if [ $failed -eq 1 ]; then
        error "Some parallel installations failed. Check the logs above."
    fi
    
    log "✓ All parallel installations completed successfully"
    
    # Display final summary
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}🎉 Local Development Environment Ready!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e ""
    echo -e "${CYAN}Access Information:${NC}"
    echo -e "  🔗 OIDC Discovery: ${BLUE}http://dex.localhost/.well-known/openid-configuration${NC}"
    echo -e "  📊 Grafana Dashboard: ${BLUE}http://grafana.localhost${NC} (OIDC required)"
    echo -e "  🚀 ArgoCD: ${BLUE}http://argocd.localhost${NC} (OIDC required)"
    echo -e "  🐙 Git Platform: ${BLUE}http://forgejo.localhost${NC} (OIDC available)"
    echo -e "  📧 Email Testing: ${BLUE}http://mailpit.localhost${NC} (Web UI)"
    echo -e ""
    echo -e "${CYAN}Test Users (password: 'password' for all):${NC}"
    echo -e "  👑 Dev Admin 1: ${YELLOW}dev1@local.dev${NC} (super-admin)"
    echo -e "  👑 Dev Admin 2: ${YELLOW}dev2@local.dev${NC} (admin)"
    echo -e "  👤 Regular User: ${YELLOW}user1@local.dev${NC}"
    echo -e ""
    echo -e "${CYAN}LDAP Directory Service:${NC}"
    echo -e "  🌐 phpLDAPadmin UI: ${BLUE}http://ldap.localhost${NC}"
    echo -e "  🔐 Login DN: ${YELLOW}cn=admin,dc=ldap,dc=localhost${NC}"
    echo -e "  🔑 Password: ${YELLOW}password${NC}"
    echo -e "  📂 Users Base DN: ${BLUE}ou=people,dc=ldap,dc=localhost${NC}"
    echo -e "  📂 Groups Base DN: ${BLUE}ou=groups,dc=ldap,dc=localhost${NC}"
    echo -e "  🔗 LDAP Server (for apps): ${BLUE}openldap-0.openldap-headless.ldap.svc.cluster.local:389${NC}"
    echo -e ""
    echo -e "${CYAN}Email Testing (Mailpit):${NC}"
    echo -e "  📧 SMTP Server: ${BLUE}mailpit-service.mailpit.svc.cluster.local:1025${NC} (for apps)"
    echo -e "  🌐 Web Interface: ${BLUE}http://mailpit.localhost${NC} (for developers)"
    echo -e ""
    echo -e "${CYAN}Helm Package Registry:${NC}"
    echo -e "  📦 Push Helm Chart: ${BLUE}helm push mychart-1.0.0.tgz oci://forgejo.localhost/forge --plain-http${NC}"
    echo -e "  📥 Pull Helm Chart: ${BLUE}helm pull oci://forgejo.localhost/forge/mychart --version 1.0.0 --plain-http${NC}"
    echo -e "  🔐 Registry Login: ${BLUE}helm registry login forgejo.localhost --username platform-admin --password password --insecure${NC}"
    echo -e "  🌐 Package Registry UI: ${BLUE}http://forgejo.localhost/forge/-/packages${NC}"
    echo -e ""
    echo -e "${CYAN}Git Repository:${NC}"
    echo -e "  📤 Git Push: ${BLUE}git push http://platform-admin:password@forgejo.localhost/forge/repo.git${NC}"
    echo -e "  📥 Git Clone: ${BLUE}git clone http://@forgejo.localhost/forge/repo.git${NC}"
    echo -e "  🔐 Git Remote: ${BLUE}git remote set-url origin http://forgejo.localhost/forge/repo.git${NC}"
    echo -e ""
    echo -e "${CYAN}Useful Commands:${NC}"
    echo -e "  Port-forward Prometheus: ${BLUE}kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090${NC}"
    echo -e "  Port-forward AlertManager: ${BLUE}kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093${NC}"
}
# Run main function
main "$@"