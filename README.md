# Kappsul Local Development Environment

A complete local Kubernetes development environment using Kind (Kubernetes in Docker) with OIDC integration, ArgoCD, Prometheus monitoring, and Forgejo Git platform & Packages registry.

## 🚀 Quick Start

```bash
# Clone the repository (if not already done)
git clone https://github.com/djovap/local-cluster.git

cd local-cluster

# Start the complete development environment
make start
```

## 📋 Prerequisites

Before starting, ensure you have the following tools installed on your system:

### Required Tools

| Tool        | Purpose                        | Installation                                                                      |
| ----------- | ------------------------------ | --------------------------------------------------------------------------------- |
| **Docker**  | Container runtime for Kind     | [Docker Desktop](https://docs.docker.com/get-docker/)                             |
| **Kind**    | Kubernetes in Docker           | [Kind Installation](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) |
| **kubectl** | Kubernetes CLI                 | [kubectl Installation](https://kubernetes.io/docs/tasks/tools/install-kubectl/)   |
| **Helm**    | Package manager for Kubernetes | [Helm Installation](https://helm.sh/docs/intro/install/)                          |
| **Git**     | Version control                | [Git Installation](https://git-scm.com/downloads)                                 |
| **curl**    | HTTP client                    | Usually pre-installed                                                             |

### Verify Installation

```bash
# Check if all tools are installed
make check-prerequisites
```

## 🏗️ Architecture

The development environment consists of the following components:

### Core Infrastructure

- **Kind Cluster**: Local Kubernetes cluster running in Docker
- **Ingress NGINX**: HTTP ingress controller for external access
- **CoreDNS**: DNS resolution for .localhost domains

### Authentication & Authorization

- **Dex**: OIDC identity provider
- **OpenLDAP**: LDAP server for user management
- **RBAC**: Role-based access control for Kubernetes

### GitOps

- **ArgoCD**: GitOps continuous deployment
- **Forgejo**: Git platform with package registry

### Monitoring & Observability

- **Prometheus**: Metrics collection and alerting
- **Grafana**: Dashboards and visualization
- **AlertManager**: Alert routing and management

### Service Access

| Service          | URL                           | Purpose               |
| ---------------- | ----------------------------- | --------------------- |
| **Dex OIDC**     | http://dex.localhost          | Identity provider     |
| **ArgoCD**       | http://argocd.localhost       | GitOps platform       |
| **Grafana**      | http://grafana.localhost      | Monitoring dashboards |
| **Forgejo**      | http://forgejo.localhost      | Git platform          |
| **Prometheus**   | localhost:9090 (port-forward) | Metrics server        |
| **AlertManager** | localhost:9093 (port-forward) | Alert management      |

## 🎯 Getting Started

### 1. Start the Environment

```bash
# Clone the repository (if not already done)
git clone <repository-url>
cd local-cluster

# Start the complete development environment
make start
```

This will:

- Create a Kind Kubernetes cluster
- Install Ingress NGINX controller
- Configure DNS resolution for .localhost domains
- Deploy OpenLDAP for user management
- Set up Dex OIDC identity provider
- Install Prometheus monitoring stack
- Deploy ArgoCD for GitOps
- Install Forgejo Git platform

### 2. Verify Installation

```bash
# Check the status of all services
make status
```

### 3. Access Services

Once the environment is ready, you can access:

- **ArgoCD**: http://argocd.localhost (OIDC login required)
- **Grafana**: http://grafana.localhost (OIDC login required)
- **Forgejo**: http://forgejo.localhost (OIDC login available)

### 4. Test Users

The following test users are pre-configured (password: `password` for all):

| User             | Email             | Role        | Permissions         |
| ---------------- | ----------------- | ----------- | ------------------- |
| **Dev Admin 1**  | dev1@kappsul.dev  | super-admin | Full cluster access |
| **Dev Admin 2**  | dev2@kappsul.dev  | admin       | Full cluster access |
| **Regular User** | user1@kappsul.dev | user        | Read-only access    |

## 🛠️ Available Commands

### Main Commands

```bash
make start              # Start the complete development environment
make clean              # Clean up all resources
make status             # Check status of all services
make check-prerequisites # Check if all required tools are installed
```

### Help

```bash
make help               # Show all available commands
```

## 🔧 Configuration

### Configuration Files

All configuration files are located in the `configs/` directory:

- `kind-config.yaml`: Kind cluster configuration
- `dex-values.yaml`: Dex OIDC configuration
- `argocd-values.yaml`: ArgoCD configuration
- `prometheus-values.yaml`: Prometheus monitoring configuration
- `forgejo-values.yaml`: Forgejo Git platform configuration
- `openldap-values.yaml`: OpenLDAP server configuration

## 📦 Package Management

### Helm Package Registry

The environment includes a Helm package registry accessible via Forgejo:

```bash
# Login to the registry
helm registry login forgejo.localhost --username platform-admin --password password --insecure

# Push a chart
helm push mychart-1.0.0.tgz oci://forgejo.localhost/forge --plain-http

# Pull a chart
helm pull oci://forgejo.localhost/forge/mychart --version 1.0.0 --plain-http
```

### Git Repository

```bash
# Clone a repository
git clone http://@forgejo.localhost/forge/repo.git

# Push to repository
git push http://platform-admin:password@forgejo.localhost/forge/repo.git

# Set remote URL
git remote set-url origin http://forgejo.localhost/forge/repo.git
```

## 🔒 Security Considerations

### Development Only

⚠️ **This environment is for development purposes only and should not be used in production.**

---

**Happy developing! 🚀**
