#!/bin/bash

# =============================================================================
# Local Development Environment Cleanup
# =============================================================================
# This script cleans up all resources created by the development environment
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="dev-local"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"


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
    echo -e "${PURPLE}CLEANUP: $1${NC}"
    echo -e "${PURPLE}========================================${NC}\n"
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

cleanup_namespaces() {
    step "Cleaning up Kubernetes namespaces"
    
    if ! command -v kubectl &> /dev/null; then
        warn "kubectl not found, skipping namespace cleanup"
        return 0
    fi
    
    local namespaces=("monitoring" "dex" "ldap" "argocd" "forgejo" "mailpit")
    
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &> /dev/null; then
            info "Deleting namespace: $ns"
            kubectl delete namespace "$ns" --timeout=120s --ignore-not-found=true || warn "Failed to delete namespace $ns"
            log "✓ Namespace $ns deleted"
        else
            info "Namespace $ns not found"
        fi
    done
}

cleanup_kind_cluster() {
    step "Cleaning up Kind cluster"
    
    if ! command -v kind &> /dev/null; then
        warn "Kind not found, skipping cluster cleanup"
        return 0
    fi
    
    if kind get clusters 2>/dev/null | grep -q "^$CLUSTER_NAME$"; then
        info "Deleting Kind cluster '$CLUSTER_NAME'..."
        kind delete cluster --name "$CLUSTER_NAME" || warn "Failed to delete Kind cluster"
        log "✓ Kind cluster '$CLUSTER_NAME' deleted"
    else
        info "Kind cluster '$CLUSTER_NAME' not found"
    fi
}

cleanup_config_backups() {
    step "Cleaning up configuration backups"
    
    # Restore kind-config.yaml if backup exists
    if [ -f "$PROJECT_ROOT/configs/kind-config.yaml.bak" ]; then
        mv "$PROJECT_ROOT/configs/kind-config.yaml.bak" "$PROJECT_ROOT/configs/kind-config.yaml"
        log "✓ Kind configuration restored from backup"
    else
        info "No kind-config backup found"
    fi
}

cleanup_docker_resources() {
    step "Cleaning up Docker resources"
    
    if ! command -v docker &> /dev/null; then
        warn "Docker not found, skipping Docker cleanup"
        return 0
    fi
    
    # Remove any dangling volumes created by kind
    info "Cleaning up Docker volumes..."
    if docker volume ls -q -f name="$CLUSTER_NAME" | grep -q .; then
        docker volume ls -q -f name="$CLUSTER_NAME" | xargs docker volume rm || warn "Failed to remove some Docker volumes"
        log "✓ Docker volumes cleaned"
    else
        info "No Docker volumes found for cluster"
    fi
    
    # Clean up any stopped containers related to the cluster
    info "Cleaning up stopped containers..."
    if docker ps -a -q -f name="$CLUSTER_NAME" | grep -q .; then
        docker ps -a -q -f name="$CLUSTER_NAME" | xargs docker rm -f || warn "Failed to remove some containers"
        log "✓ Stopped containers cleaned"
    else
        info "No stopped containers found"
    fi
}

cleanup_kubeconfig() {
    step "Cleaning up kubeconfig"
    
    local kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"
    
    if [ -f "$kubeconfig" ] && command -v kubectl &> /dev/null; then
        info "Removing kind context from kubeconfig..."
        
        # Remove the kind context
        if kubectl config get-contexts "kind-$CLUSTER_NAME" &> /dev/null; then
            kubectl config delete-context "kind-$CLUSTER_NAME" || warn "Failed to delete context"
            log "✓ Removed context: kind-$CLUSTER_NAME"
        fi
        
        # Remove the kind cluster config
        if kubectl config get-clusters "kind-$CLUSTER_NAME" &> /dev/null; then
            kubectl config delete-cluster "kind-$CLUSTER_NAME" || warn "Failed to delete cluster config"
            log "✓ Removed cluster config: kind-$CLUSTER_NAME"
        fi
        
        # Remove the kind user
        if kubectl config get-users "kind-$CLUSTER_NAME" &> /dev/null; then
            kubectl config delete-user "kind-$CLUSTER_NAME" || warn "Failed to delete user config"
            log "✓ Removed user config: kind-$CLUSTER_NAME"
        fi
    else
        info "No kubeconfig found or kubectl not available"
    fi
}

show_cleanup_status() {
    step "Cleanup Status Check"
    
    # Check if cluster exists
    if command -v kind &> /dev/null && kind get clusters 2>/dev/null | grep -q "^$CLUSTER_NAME$"; then
        warn "Kind cluster '$CLUSTER_NAME' still exists"
    else
        log "✓ Kind cluster '$CLUSTER_NAME' removed"
    fi
    
    # Check Docker containers
    if command -v docker &> /dev/null && docker ps -a -q -f name="$CLUSTER_NAME" | grep -q .; then
        warn "Some Docker containers still exist"
    else
        log "✓ Docker containers cleaned"
    fi
    
    # Check kubeconfig
    if command -v kubectl &> /dev/null && kubectl config get-contexts "kind-$CLUSTER_NAME" &> /dev/null; then
        warn "Kind context still exists in kubeconfig"
    else
        log "✓ Kubeconfig cleaned"
    fi
}

show_usage() {
    cat << EOF
Usage: $0 [OPTION]

Clean up local development environment resources.

OPTIONS:
    --help              Show this help message
    --cluster-only      Only clean up Kind cluster (keep other resources)
    --config-only       Only clean up configuration files
    --docker-only       Only clean up Docker resources
    --all               Clean up everything (default)
    --status            Show cleanup status without performing cleanup
    --force             Skip confirmation prompts

EXAMPLES:
    # Full cleanup (default) with confirmation
    $0

    # Clean up everything without confirmation
    $0 --force

    # Only remove the Kind cluster
    $0 --cluster-only

    # Check what's still running
    $0 --status

CLEANUP ORDER:
    1. Kubernetes namespaces
    2. Kind cluster
    3. Configuration backups
    4. Docker resources
    5. Kubeconfig entries

EOF
}

confirm_cleanup() {
    echo -e "${YELLOW}This will remove all development environment resources including:${NC}"
    echo "  - Kind cluster: $CLUSTER_NAME"
    echo "  - Docker containers and volumes"
    echo "  - Kubeconfig entries"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

full_cleanup() {
    cleanup_namespaces
    cleanup_kind_cluster
    cleanup_config_backups
    cleanup_docker_resources
    cleanup_kubeconfig
    
    step "🧹 Cleanup Complete!"
    log "All development environment resources have been cleaned up"
    show_cleanup_status
}

main() {
    local option="${1:---all}"
    local force=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_usage
                exit 0
                ;;
            --force)
                force=true
                shift
                ;;
            --all)
                option="--all"
                shift
                ;;
            --cluster-only)
                option="--cluster-only"
                shift
                ;;
            --config-only)
                option="--config-only"
                shift
                ;;
            --docker-only)
                option="--docker-only"
                shift
                ;;
            --status)
                option="--status"
                shift
                ;;
            *)
                error "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
    
    case "$option" in
        --all)
            if [ "$force" = false ]; then
                confirm_cleanup
            fi
            full_cleanup
            ;;
        --cluster-only)
            if [ "$force" = false ]; then
                echo -e "${YELLOW}This will remove the Kind cluster: $CLUSTER_NAME${NC}"
                read -p "Are you sure? (y/N): " -r
                [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
            fi
            cleanup_kind_cluster
            cleanup_kubeconfig
            ;;
        --config-only)
            cleanup_config_backups
            cleanup_kubeconfig
            ;;
        --docker-only)
            cleanup_docker_resources
            ;;
        --status)
            show_cleanup_status
            ;;
        *)
            # Default behavior - full cleanup with confirmation
            if [ "$force" = false ]; then
                confirm_cleanup
            fi
            full_cleanup
            ;;
    esac
}

# Run main function
main "$@"

