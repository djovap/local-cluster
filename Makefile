# =============================================================================
# Kappsul Local Development Environment
# =============================================================================
# This Makefile provides easy commands to manage the local Kubernetes
# development environment using Kind with OIDC integration, ArgoCD, 
# Prometheus, and all services.
# =============================================================================

# Configuration
CLUSTER_NAME := dev-local
SCRIPT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
SCRIPTS_DIR := $(SCRIPT_DIR)/scripts
CONFIGS_DIR := $(SCRIPT_DIR)/configs

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
PURPLE := \033[0;35m
CYAN := \033[0;36m
NC := \033[0m

# Default target
.DEFAULT_GOAL := help

# =============================================================================
# HELP TARGET
# =============================================================================

.PHONY: help
help: ## Show this help message
	@printf "$(CYAN)Kappsul Local Development Environment$(NC)\n"
	@printf "$(CYAN)=====================================$(NC)\n"
	@printf "\n"
	@printf "$(BLUE)Available commands:$(NC)\n"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\n"
	@printf "$(BLUE)Quick Start:$(NC)\n"
	@printf "  make start    # Start the complete development environment\n"
	@printf "  make clean    # Clean up all resources\n"
	@printf "  make status   # Check current status\n"
	@printf "\n"

# =============================================================================
# MAIN TARGETS
# =============================================================================

.PHONY: start
start: ## Start the complete development environment
	@printf "$(PURPLE)🚀 Starting Kappsul Local Development Environment$(NC)\n"
	@printf "$(PURPLE)================================================$(NC)\n"
	@printf "\n"
	@chmod +x $(SCRIPTS_DIR)/setup-dev-env.sh
	@$(SCRIPTS_DIR)/setup-dev-env.sh
	@printf "\n"
	@printf "$(GREEN)✅ Development environment is ready!$(NC)\n"
	@printf "$(BLUE)Run 'make status' to check the status of all services$(NC)\n"

.PHONY: clean
clean: ## Clean up all development environment resources
	@printf "$(PURPLE)🧹 Cleaning up Kappsul Local Development Environment$(NC)\n"
	@printf "$(PURPLE)===================================================$(NC)\n"
	@printf "\n"
	@chmod +x $(SCRIPTS_DIR)/cleanup-dev-env.sh
	@$(SCRIPTS_DIR)/cleanup-dev-env.sh --force
	@printf "\n"
	@printf "$(GREEN)✅ Cleanup complete!$(NC)\n"

.PHONY: status
status: ## Check the status of all services
	@printf "$(CYAN)📊 Kappsul Development Environment Status$(NC)\n"
	@printf "$(CYAN)==========================================$(NC)\n"
	@printf "\n"
	@printf "$(BLUE)Kind Cluster Status:$(NC)\n"
	@if command -v kind >/dev/null 2>&1; then \
		if kind get clusters 2>/dev/null | grep -q "^$(CLUSTER_NAME)$$"; then \
			printf "  $(GREEN)✓$(NC) Kind cluster '$(CLUSTER_NAME)' is running\n"; \
		else \
			printf "  $(YELLOW)⚠$(NC) Kind cluster '$(CLUSTER_NAME)' not found\n"; \
		fi; \
	else \
		printf "  $(YELLOW)⚠$(NC) Kind not installed\n"; \
	fi
	@printf "\n"
	@printf "$(BLUE)Kubernetes Context:$(NC)\n"
	@if command -v kubectl >/dev/null 2>&1; then \
		CURRENT_CONTEXT=$$(kubectl config current-context 2>/dev/null || echo "none"); \
		if [ "$$CURRENT_CONTEXT" = "kind-$(CLUSTER_NAME)" ]; then \
			printf "  $(GREEN)✓$(NC) Using context: $$CURRENT_CONTEXT\n"; \
		else \
			printf "  $(YELLOW)⚠$(NC) Current context: $$CURRENT_CONTEXT (expected: kind-$(CLUSTER_NAME))\n"; \
		fi; \
	else \
		printf "  $(YELLOW)⚠$(NC) kubectl not installed\n"; \
	fi
	@printf "\n"
	@printf "$(BLUE)Service Status:$(NC)\n"
	@if command -v kubectl >/dev/null 2>&1; then \
		for ns in dex ldap monitoring argocd forgejo; do \
			if kubectl get namespace $$ns >/dev/null 2>&1; then \
				POD_COUNT=$$(kubectl get pods -n $$ns --no-headers 2>/dev/null | wc -l); \
				READY_COUNT=$$(kubectl get pods -n $$ns --no-headers 2>/dev/null | grep -c "Running\|Completed" || echo "0"); \
				if [ "$$POD_COUNT" -gt 0 ]; then \
					printf "  $(GREEN)✓$(NC) $$ns: $$READY_COUNT/$$POD_COUNT pods ready\n"; \
				else \
					printf "  $(YELLOW)⚠$(NC) $$ns: No pods found\n"; \
				fi; \
			else \
				printf "  $(YELLOW)⚠$(NC) $$ns: Namespace not found\n"; \
			fi; \
		done; \
	else \
		printf "  $(YELLOW)⚠$(NC) Cannot check service status (kubectl not available)\n"; \
	fi
	@printf "\n"
	@printf "$(BLUE)Access URLs:$(NC)\n"
	@printf "  🔗 OIDC Discovery: $(BLUE)http://dex.localhost/.well-known/openid-configuration$(NC)\n"
	@printf "  📊 Grafana Dashboard: $(BLUE)http://grafana.localhost$(NC)\n"
	@printf "  🚀 ArgoCD: $(BLUE)http://argocd.localhost$(NC)\n"
	@printf "  🐙 Forgejo: $(BLUE)http://forgejo.localhost$(NC)\n"

.PHONY: check-prerequisites
check-prerequisites: ## Check if all required tools are installed
	@printf "$(CYAN)🔧 Checking Prerequisites$(NC)\n"
	@printf "$(CYAN)=========================$(NC)\n"
	@printf "\n"
	@for tool in kind kubectl helm docker git curl; do \
		if command -v $$tool >/dev/null 2>&1; then \
			printf "  $(GREEN)✓$(NC) $$tool is installed\n"; \
		else \
			printf "  $(YELLOW)⚠$(NC) $$tool is not installed\n"; \
		fi; \
	done
	@printf "\n"
	@if docker info >/dev/null 2>&1; then \
		printf "  $(GREEN)✓$(NC) Docker is running\n"; \
	else \
		printf "  $(YELLOW)⚠$(NC) Docker is not running\n"; \
	fi

# =============================================================================
# PHONY TARGETS
# =============================================================================

.PHONY: all start clean status check-prerequisites