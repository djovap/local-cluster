# Local K8s Development Environment

A complete local Kubernetes development environment using Kind (Kubernetes in Docker) with OIDC integration, ArgoCD, Prometheus monitoring, and Forgejo Git platform & Packages registry.

## 🚀 Quick Start

```bash
# Clone the repository (if not already done)
git clone https://github.com/djovap/local-cluster.git

cd local-cluster

# Start the complete development environment
make start
```

**Note**: The cluster takes approximately **10-15 minutes** to fully start and initialize all services. This includes downloading container images, configuring services, and waiting for all pods to become ready.

## 📋 Prerequisites

Before starting, ensure you have the following tools installed on your system and sufficient system resources available.

### System Requirements

The Kind cluster requires significant system resources to run all components smoothly:

| Resource          | Minimum | Recommended | Notes                                           |
| ----------------- | ------- | ----------- | ----------------------------------------------- |
| **CPU**           | 4 cores | 8+ cores    | Multi-core recommended for better performance   |
| **RAM**           | 8 GB    | 16+ GB      | More RAM allows for larger workloads            |
| **Disk Space**    | 20 GB   | 50+ GB      | For Docker images, logs, and persistent volumes |
| **Docker Memory** | 6 GB    | 12+ GB      | Allocate in Docker Desktop settings             |

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

### Email Testing

- **Mailpit**: Email and SMTP testing tool with API for developers

### Monitoring & Observability

- **Prometheus**: Metrics collection and alerting
- **Grafana**: Dashboards and visualization
- **AlertManager**: Alert routing and management

### Service Access

| Service          | URL                           | Purpose               |
| ---------------- | ----------------------------- | --------------------- |
| **AlertManager** | localhost:9093 (port-forward) | Alert management      |
| **ArgoCD**       | http://argocd.localhost       | GitOps platform       |
| **Dex OIDC**     | http://dex.localhost          | Identity provider     |
| **Forgejo**      | http://forgejo.localhost      | Git platform          |
| **Grafana**      | http://grafana.localhost      | Monitoring dashboards |
| **LDAP Admin**   | http://ldap.localhost         | LDAP management UI    |
| **Mailpit**      | http://mailpit.localhost      | Email testing UI      |
| **Prometheus**   | localhost:9090 (port-forward) | Metrics server        |

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
- Install Mailpit email testing tool

**⏱️ Expected Duration**: The complete setup process takes approximately **10-15 minutes** depending on your system resources and internet connection speed.

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
- **LDAP Admin**: http://ldap.localhost (LDAP management interface)
- **Mailpit**: http://mailpit.localhost (Email testing interface)

### 4. Email Testing with Mailpit

Mailpit provides a complete email testing solution for your development environment:

#### SMTP Configuration for Applications

Configure your applications to use Mailpit as their SMTP server:

```yaml
# Example SMTP configuration
smtp:
  host: "mailpit-service.mailpit.svc.cluster.local"
  port: 1025
  secure: false
  auth:
    enabled: false
```

#### Email Testing Features

- **Web Interface**: View, search, and test emails at http://mailpit.localhost
- **SMTP Server**: Receive emails from any application at `mailpit-service.mailpit.svc.cluster.local:1025`
- **API Access**: Automated email testing via REST API
- **HTML Preview**: Test email rendering across different clients
- **Link Testing**: Verify links in emails work correctly
- **Spam Testing**: Check email spam scores

#### Usage Examples

```bash
# Test SMTP connection with telnet
telnet mailpit-service.mailpit.svc.cluster.local 1025

# Send test email with curl
curl -X POST http://mailpit.localhost/api/v1/send \
  -H "Content-Type: application/json" \
  -d '{
    "from": "test@example.com",
    "to": ["dev@local.dev"],
    "subject": "Test Email",
    "text": "This is a test email from Mailpit"
  }'
```

### 5. LDAP Directory Service

OpenLDAP provides a complete directory service for user authentication and authorization:

#### LDAP Configuration for Applications

Configure your applications to use OpenLDAP for authentication:

```yaml
# Example LDAP configuration
ldap:
  # Use headless service to connect directly to the pod
  host: "openldap-0.openldap-headless.ldap.svc.cluster.local"
  port: 389
  secure: false
  bindDN: "cn=admin,dc=ldap,dc=localhost"
  bindPassword: "password"
  baseDN: "dc=ldap,dc=localhost"
  userSearchBase: "ou=people,dc=ldap,dc=localhost"
  groupSearchBase: "ou=groups,dc=ldap,dc=localhost"
```

#### LDAP Directory Features

- **Web Interface**: Manage users and groups at http://ldap.localhost
- **LDAP Server**: Internal directory access at `openldap.ldap.svc.cluster.local:389`
- **User Management**: Pre-configured users and groups for development
- **Group-based Access**: Support for role-based access control
- **phpLDAPadmin**: Web-based LDAP administration interface

#### LDAP Directory Structure

```
dc=ldap,dc=localhost                          # Base DN
├── ou=people,dc=ldap,dc=localhost            # Users organizational unit
│   ├── cn=developer1,ou=people,dc=ldap,dc=localhost
│   ├── cn=developer2,ou=people,dc=ldap,dc=localhost
│   └── cn=user1,ou=people,dc=ldap,dc=localhost
└── ou=groups,dc=ldap,dc=localhost            # Groups organizational unit
    ├── cn=super-admins,ou=groups,dc=ldap,dc=localhost
    ├── cn=admins,ou=groups,dc=ldap,dc=localhost
    └── cn=users,ou=groups,dc=ldap,dc=localhost
```

#### Usage Examples

```bash
# Test LDAP connection with ldapsearch (use headless service)
ldapsearch -x -H ldap://openldap-0.openldap-headless.ldap.svc.cluster.local:389 \
  -D "cn=admin,dc=ldap,dc=localhost" -w password \
  -b "dc=ldap,dc=localhost" "(objectClass=person)"

# List all users
ldapsearch -x -H ldap://openldap-0.openldap-headless.ldap.svc.cluster.local:389 \
  -D "cn=admin,dc=ldap,dc=localhost" -w password \
  -b "ou=people,dc=ldap,dc=localhost" "(objectClass=person)" cn mail

# Search for a specific user by email
ldapsearch -x -H ldap://openldap-0.openldap-headless.ldap.svc.cluster.local:389 \
  -D "cn=admin,dc=ldap,dc=localhost" -w password \
  -b "ou=people,dc=ldap,dc=localhost" "(mail=dev1@local.dev)"

# List all groups
ldapsearch -x -H ldap://openldap-0.openldap-headless.ldap.svc.cluster.local:389 \
  -D "cn=admin,dc=ldap,dc=localhost" -w password \
  -b "ou=groups,dc=ldap,dc=localhost" "(objectClass=groupOfNames)"
```

### 6. Test Users

The following test users are pre-configured (password: `password` for all):

| User             | Email           | Role        | Permissions         |
| ---------------- | --------------- | ----------- | ------------------- |
| **Dev Admin 1**  | dev1@local.dev  | super-admin | Full cluster access |
| **Dev Admin 2**  | dev2@local.dev  | admin       | Full cluster access |
| **Regular User** | user1@local.dev | user        | Read-only access    |

### 7. Git Forge Organization

The Forgejo Git platform automatically creates a **"forge"** organization with the following setup:

#### Organization Structure

- **Name**: `forge`
- **Visibility**: Public
- **Purpose**: Default organization for projects and packages

#### OIDC User Roles in "forge" Organization

| User             | Email           | Organization Role | Permissions                                      |
| ---------------- | --------------- | ----------------- | ------------------------------------------------ |
| **Dev Admin 1**  | dev1@local.dev  | **Owner**         | Full access to all repositories and packages     |
| **Dev Admin 2**  | dev2@local.dev  | **Developer**     | Write access to repositories, package management |
| **Regular User** | user1@local.dev | **Viewer**        | Read-only access to repositories and packages    |

#### Available Repositories

- **Git Repository**: `http://forgejo.localhost/forge/repo.git`
- **Package Registry**: `http://forgejo.localhost/forge/-/packages`
- **Helm Charts**: `oci://forgejo.localhost/forge/`

#### Teams in "forge" Organization

- **owners**: Full administrative access
- **developers**: Write access to repositories and packages
- **viewers**: Read-only access to repositories and packages

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
- `mailpit-values.yaml`: Mailpit email testing configuration

### Local Helm Charts

The `charts/setup/` directory contains local copies of all Helm charts used in the setup:

| Chart          | Version | Purpose                |
| -------------- | ------- | ---------------------- |
| **dex**        | 0.24.0  | OIDC Identity Provider |
| **openldap**   | 2.0.4   | LDAP Server            |
| **prometheus** | 77.13.0 | Monitoring Stack       |
| **argocd**     | 8.5.8   | GitOps Platform        |
| **forgejo**    | 14.0.3  | Git Platform           |
| **mailpit**    | 0.28.0  | Email Testing Tool     |

#### Using Local Charts

The setup script automatically uses local charts when available, falling back to remote repositories if not found. This ensures:

- **Faster setup**: No need to download charts during each setup
- **Version consistency**: Always uses the exact same chart versions
- **Offline capability**: Can work without internet access after initial download

## 📦 Package Management

### Helm Package Registry

The environment includes a Helm package registry accessible via Forgejo:

```bash
# Login to the registry
helm registry login forgejo.localhost --username platform-admin --password password --insecure

# Push a chart to forge organization
helm push mychart-1.0.0.tgz oci://forgejo.localhost/forge --plain-http

# Pull a chart from forge organization
helm pull oci://forgejo.localhost/forge/mychart --version 1.0.0 --plain-http

# Access package registry UI
http://forgejo.localhost/forge/-/packages
```

**Note**: Since this is a development environment using HTTP instead of HTTPS, all Helm operations with the OCI registry must include the `--plain-http` flag.

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

**Happy cloud-native developing! 🚀**
