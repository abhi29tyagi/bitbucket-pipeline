# Shared Pipelines Library

A comprehensive CI/CD pipeline library for Bitbucket Pipelines with support for Node.js, Python, Docker, Traefik, and multi-environment deployments.

📖 **[Production Deployment Checklist](PRODUCTION-CHECKLIST.md)** - Complete guide for deploying to UAT/Prod with different repository types.

## 📌 Assumptions & Architecture

This pipeline library is designed with specific assumptions about your infrastructure and deployment environment:

### 🏗️ Deployment Architecture

- **VM-Based Deployments**: Designed to run on virtual machines (VMs) using Docker Compose
  - **Not Kubernetes**: This pipeline targets container deployments that don't require orchestration complexity
  - **Docker Compose**: Uses docker-compose for multi-container applications
  - **Direct Container Deployment**: Containers deploy directly on VMs without container orchestration

### 🌐 DNS & Network Infrastructure

- **Internal DNS (BIND Server)**: Used for dev/UAT environments and admin panels
  - Requires internal BIND DNS server with TSIG keys
  - Private/internal access for non-production environments
  
- **Public DNS (Cloudflare)**: Used for production frontends
  - Cloudflare DNS for public-facing applications
  - Cloudflare Tunnel for backends without public IPs
  - Cloudflare Workers for webhook integration

### 🔧 CI/CD Platform

- **Bitbucket Pipelines**: Primary CI/CD platform
  - **Self-Hosted Runners**: Heavy reliance on self-hosted runners for:
    - Fast CI execution
    - Parallel pipeline steps
    - Docker socket access
    - Access to internal infrastructure
  
  - **Cloud Runners**: Used as fallback for lightweight CI tasks (lint, test)
  - **Bitbucket API**: Uses Bitbucket API for deployment variables and webhook integration

### 🐳 Container & Registry

- **Docker**: Container platform
  - Multi-stage builds
  - Docker Scout for vulnerability scanning
  - Docker Compose for orchestration
  
- **Docker Hub**: Primary container registry
  - Image storage and distribution
  - Tag-based promotion workflow

### 🔍 Quality & Security Tools

- **SonarQube**: Code quality analysis
  - Centralized SonarQube instance
  - Integration with Docker Scout vulnerabilities
  
- **Docker Scout**: Container vulnerability scanning
  - SARIF reporting
  - Integration with SonarQube

### 🔐 Reverse Proxy & SSL

- **Traefik**: Reverse proxy and load balancer
  - Automatic TLS certificate management
  - Let's Encrypt integration
  - Cloudflare DNS challenge for wildcard certificates

### 💻 Supported Runtimes

- **Node.js**: JavaScript/TypeScript applications
  - npm, yarn, pnpm package managers
  - ESLint for linting
  - Jest for testing
  
- **Python**: Python applications
  - pip, poetry, pipenv support
  - Ruff/Flake8 for linting
  - pytest for testing

### ⚡ CI vs CD Separation

- **CI Components**: Can be used standalone without CD
  - Lint, test, build, scan stages work independently
  - No dependency on deployment infrastructure for CI
  
- **CD Components**: Require specific infrastructure
  - Deployment targets (VMs)
  - DNS servers (BIND or Cloudflare)
  - Traefik for routing
  - Docker daemon access

### 🔌 External Dependencies

- **Cloudflare**: Multiple services
  - DNS management for production
  - Tunnel service for backend services
  - Workers for webhook handling
  
- **Let's Encrypt**: SSL certificate authority
  - Automatic certificate provisioning
  - Wildcard certificates via DNS challenge

## 📑 Table of Contents

- [📑 Table of Contents](#table-of-contents)
- [📌 Assumptions & Architecture](#assumptions-architecture)
- [🚀 Quick Start](#quick-start)
  - [1. Enable Shared Pipelines in Your Repo](#enable-shared-pipelines-in-your-repo)
  - [2. Understanding YAML Imports](#understanding-yaml-imports)
  - [3. Set Up Required Variables](#set-up-required-variables)
  - [4. Create Self-Hosted Runners](#create-self-hosted-runners)
  - [5. Set Up Deployment Environments](#set-up-deployment-environments)
- [📋 Features](#features)
  - [✅ Supported Technologies](#supported-technologies)
  - [✅ Environments](#environments)
  - [✅ Pipeline Stages](#pipeline-stages)
  - [PR-Merged → Auto Teardown (Cloudflare Worker)](#pr-merged-auto-teardown-cloudflare-worker)
- [🏗️ Architecture](#architecture)
  - [A Typical Pipeline Flow (e.g. Preview Env)](#a-typical-pipeline-flow-e-g-preview-env)
  - [Environment Routing](#environment-routing)
  - [Decision Matrix by Environment](#decision-matrix-by-environment)
- [🐳 Docker Compose Support](#docker-compose-support)
  - [File Structure](#file-structure)
  - [How Docker Compose Works](#how-docker-compose-works)
  - [Image Tagging & Reuse](#image-tagging-reuse)
- [🔧 Configuration](#configuration)
  - [Package.json Scripts (Node.js)](#package-json-scripts-node-js)
  - [Python Requirements](#python-requirements)
  - [Dockerfile Best Practices](#dockerfile-best-practices)
  - [Environment-Scoped Build Arguments (static builds)](#environment-scoped-build-arguments-static-builds)
- [🌐 Traefik Integration](#traefik-integration)
  - [Automatic TLS](#automatic-tls)
  - [Dashboard Access](#dashboard-access)
  - [Preview Environments](#preview-environments)
  - [Dev/UAT/Prod Routing](#dev-uat-prod-routing)
- [🔐 Cloudflare Tunnel (Backend without Public IP)](#cloudflare-tunnel-backend-without-public-ip)
  - [Why Use Cloudflare Tunnel?](#why-use-cloudflare-tunnel)
  - [Cloudflare Tunnel Setup](#cloudflare-tunnel-setup)
  - [Backend Docker Compose Requirements](#backend-docker-compose-requirements)
  - [How Cloudflare Tunnel Works](#how-cloudflare-tunnel-works)
  - [Frontend Integration](#frontend-integration)
  - [Cloudflare Tunnel Troubleshooting](#cloudflare-tunnel-troubleshooting)
- [🔄 Cross-Repository Previews](#cross-repository-previews)
  - [Cross-Repository Setup](#cross-repository-setup)
  - [Cross-Repository Behavior](#cross-repository-behavior)
  - [Feature Gate](#feature-gate)
  - [Peer Host URLs Format](#peer-host-urls-format)
  - [Trigger Loop Prevention](#trigger-loop-prevention)
- [🔥 Hotfix Flow](#hotfix-flow)
  - [Workflow](#workflow)
  - [Tags](#tags)
- [🚫 Stage Bypass Flags](#stage-bypass-flags)
- [🏷️ Repository Type Flags](#repository-type-flags)
  - [Repository Type Behavior](#repository-type-behavior)
- [🔒 Admin Panel Security](#admin-panel-security)
  - [IP Whitelist Ranges](#ip-whitelist-ranges)
  - [How It Works](#how-it-works)
  - [Security Model](#security-model)
- [📊 Quality Gates](#quality-gates)
  - [SonarQube Integration](#sonarqube-integration)
  - [Docker Scout](#docker-scout)
- [🛠️ Troubleshooting](#troubleshooting)
  - [Common Issues](#common-issues)
  - [Debug Commands](#debug-commands)
- [🔍 Verifying Docker Scout Integration in SonarQube](#verifying-docker-scout-integration-in-sonarqube)
  - [How to Check Docker Scout Results in SonarQube:](#how-to-check-docker-scout-results-in-sonarqube)
  - [What You Should See:](#what-you-should-see)
  - [Pipeline Logs to Check:](#pipeline-logs-to-check)
  - [Troubleshooting Docker Scout Integration:](#troubleshooting-docker-scout-integration)
- [📚 Examples](#examples)
  - [Example 1: Backend API (with auto-detection)](#example-1-backend-api-with-auto-detection)
  - [Example 2: Frontend App (with auto-detection)](#example-2-frontend-app-with-auto-detection)
  - [Example 3: Admin Panel](#example-3-admin-panel)
  - [Example 4: Hotfix Deployment](#example-4-hotfix-deployment)
- [🤝 Contributing](#contributing)
- [📄 License](#license)
- [🆘 Support](#support)

## 🚀 Quick Start

### 1. Enable Shared Pipelines in Your Repo

Create a minimal `bitbucket-pipelines.yml` file that imports shared pipeline components:

```yaml
# Clean Bitbucket Pipeline using YAML Components
# This file references shared pipeline components using YAML anchors
# All complex logic is abstracted in shared-pipelines repository.

pipelines:

  custom:
    manual-preview-teardown:
      import: shared-pipelines:main:manual-preview-teardown-traefik

  branches:
    dev*:
      import: shared-pipelines:main:general-pipeline-develop
    
    release/*:
      import: shared-pipelines:main:general-pipeline-release

    hotfix/*:
      import: shared-pipelines:main:general-pipeline-hotfix

    main:
      import: shared-pipelines:main:general-pipeline-main

    feature/*:
       import: shared-pipelines:main:general-pipeline-feature-traefik

  pull-requests:
    '**':
      import: shared-pipelines:main:general-pipeline-pr-traefik
```

### 2. Understanding YAML Imports

The shared pipelines use Bitbucket's YAML import feature to reference pipeline components:

**Branch Pipelines:**

- **`general-pipeline-develop`** - Dev pipeline (auto-detects Node.js/Python, lint, test, build, deploy)
- **`general-pipeline-release`** - UAT pipeline (auto-detects: backend promotes, frontend rebuilds)
- **`general-pipeline-main`** - Prod pipeline (auto-detects: backend promotes, frontend rebuilds)
- **`general-pipeline-hotfix`** - Hotfix pipeline (build only - no deploy)
- **`general-pipeline-pr-traefik`** - Preview pipeline with Traefik (auto-detects project type)

**Manual Triggers (custom pipelines):**

- **`manual-preview-teardown-traefik`** - Clean up preview environments

**Note:** All pipelines auto-detect Node.js vs Python and backend vs frontend - no manual selection needed!

### 3. Set Up Required Variables

#### Workspace Variables (Set once for all repos):
```bash
# SonarQube
SONAR_HOST_URL=https://your-sonar-instance.com
SONAR_TOKEN=your-sonar-token

# Docker Hub
DOCKERHUB_USERNAME=your-dockerhub-username
DOCKERHUB_TOKEN=your-dockerhub-token
DOCKERHUB_ORGNAME=your-org-name

# Bitbucket API
BITBUCKET_ACCESS_TOKEN=your-bitbucket-oauth-token

# DNS & Domains
PREVIEW_DOMAIN_NAME=your-domain.com
CLOUDFLARE_API_TOKEN=your-cloudflare-token
CLOUDFLARE_ACCOUNT_ID=your-cloudflare-account-id  # Required for Cloudflare Tunnel (backend repos)
INTERNAL_DNS_SERVER=your-internal-dns-server
INTERNAL_DNS_TSIG_KEY_NAME=your-tsig-key-name
INTERNAL_DNS_TSIG_KEY=your-tsig-key
```

#### Repository Variables (Set per repo):

**Required:**
```bash
# Environment IPs (required for all repos except IS_BACKEND=true in prod)
# Supports both UPPERCASE and lowercase suffixes (e.g., TARGET_IP_DEV or TARGET_IP_dev)
TARGET_IP_DEV=1.2.3.4
TARGET_IP_UAT=5.6.7.8
TARGET_IP_PROD=9.10.11.12  # Not needed if IS_BACKEND=true (uses Cloudflare Tunnel)

# Environment Domains (required for all repos except IS_BACKEND=true in prod)
# Supports both UPPERCASE and lowercase suffixes (e.g., DOMAIN_NAME_DEV or DOMAIN_NAME_dev)
DOMAIN_NAME_DEV=my-app.dev.your-domain.com  # Full FQDN or base domain
DOMAIN_NAME_UAT=uat.your-domain.com
DOMAIN_NAME_PROD=your-domain.com  # Not needed if IS_BACKEND=true (uses TUNNEL_HOSTNAME)

# App Configuration (required)
APP_PORT=3000  # Port your app listens on inside container
```

**Repository Type Flags (MUST be set before UAT/Prod):**
```bash
# Choose ONE of these flags based on your repository type:
IS_BACKEND=true         # Backend/API: Enable promote flow, Cloudflare Tunnel in prod
IS_ADMIN_PANEL=true     # Admin Panel: Use internal DNS in prod (private access) + IP whitelist
# (No flag)             # Regular Frontend: Public access, Cloudflare DNS in prod

# ⚠️ IMPORTANT: Set the appropriate flag BEFORE deploying to UAT/Prod!
# These flags control deployment flow and production routing behavior.
```

**Backend-Specific (Required if IS_BACKEND=true):**
```bash
TUNNEL_HOSTNAME=api.prod.example.com  # For Cloudflare Tunnel in prod
TUNNEL_CONTAINER_NAME=cloudflared-backend  # Optional, defaults to cloudflared-backend
TUNNEL_SERVICE_URL=http://127.0.0.1:8000  # Optional, defaults to APP_PORT

# Note: Pipeline auto-publishes APP_PORT via docker-compose.override.yml
# No need to manually add port mappings in your docker-compose.yml
```

**Optional (Stage Control):**
```bash
# Stage Bypass Flags
SKIP_LINT=true
SKIP_TESTS=true
SKIP_BUILD=true
SKIP_SCOUT=true
SKIP_SONAR=true

# Cross-repo Peer Triggers (for multi-repo previews)
PEER_REPOS=backend-api,auth-service  # Comma-separated list
```

**Environment-Scoped Build Args (for static frontends):**

There are two methods to provide environment-specific build arguments:

**Method 1: Bitbucket Deployment Variables API (Recommended)**
```bash
# Set USE_BITBUCKET_DEPLOYMENT_VARS=true, then configure in Repository Settings → Deployments:

# In 'dev' deployment environment:
API_BASE_URL=https://dev.api.example.com

# In 'uat' deployment environment:
API_BASE_URL=https://uat.api.example.com

# In 'prod' deployment environment:
API_BASE_URL=https://api.example.com

# Important: Dockerfile must declare these args:
#   ARG API_BASE_URL
#   ENV API_BASE_URL=${API_BASE_URL}
```

**Method 2: Traditional (Fallback) - Pipeline Variables with Suffixes**
```bash
# Define VAR_<env> to inject VAR as a Docker --build-arg for that environment
# Supported envs: preview, dev, uat, prod
# Supports both lowercase (_dev) and uppercase (_DEV) suffixes
API_BASE_URL_dev=https://dev.api.example.com
API_BASE_URL_uat=https://uat.api.example.com
API_BASE_URL_prod=https://api.example.com
```

**Benefits of Deployment Variables:**
- ✅ Centralized configuration per environment
- ✅ No `VAR_<env>` suffix management in pipeline YAML
- ✅ Dynamic updates without pipeline changes
- ✅ Automatically falls back to Method 2 if disabled

See [BITBUCKET-DEPLOYMENT-API.md](BITBUCKET-DEPLOYMENT-API.md) for complete setup instructions.

#### Deployment Environment Variables (Set in Bitbucket deployment environments):

**For `preview` Deployment Environment (optional - or use with `USE_BITBUCKET_DEPLOYMENT_VARS=true`):**

If using the **Deployment Variables API** (`USE_BITBUCKET_DEPLOYMENT_VARS=true`), you can centralize ALL preview configuration here:

```bash
# In Repository Settings → Deployments → preview environment:

# Regular build args (no _preview suffix needed!)
API_BASE_URL=https://preview-api.example.com
FEATURE_FLAGS=debug,experimental

# Cross-repo Peer URLs (for multi-repo previews)
# Format: VARIABLE_NAME.peer-repo-slug
PEER_HOST_URLS=VITE_API_BASE_URL.backend-api,VITE_AUTH_URL.auth-service
```

**Benefits of using Deployment Variables for preview:**
- ✅ All preview config in one place
- ✅ No need for `_preview` suffixes
- ✅ Includes both build args AND peer URLs
- ✅ Centralized management in deployment settings

**Traditional Method (Repository Variables):**
```bash
# If NOT using USE_BITBUCKET_DEPLOYMENT_VARS, set these as repository variables:
API_BASE_URL_preview=https://preview-api.example.com
PEER_HOST_URLS=VITE_API_BASE_URL.backend-api,VITE_AUTH_URL.auth-service
```

### 4. Create Self-Hosted Runners

Set up runners with these tags:
- **Workspace level**: `common.ci`, `preview.runner`
- **Repository level**: `dev.runner`, `uat.runner`, `prod.runner`

### 5. Set Up Deployment Environments

**Important**: Create these exact deployment environments in your Bitbucket repository settings:

- **`dev`** - Development environment
- **`uat`** - UAT environment  
- **`prod`** - Production environment
- **`preview`** - Preview environment (for PR deployments)

**Environment Names Must Match Exactly:**

- ✅ `dev` (not `development` or `dev-env`)
- ✅ `uat` (not `staging` or `test`)
- ✅ `prod` (not `production` or `live`)
- ✅ `preview` (not `preview-env` or `pr-preview`)

## 📋 Features

### ✅ Supported Technologies
- **Node.js**: npm, yarn, pnpm support
- **Python**: pip, poetry, pipenv support
- **Docker**: Multi-stage builds, image scanning
- **Traefik**: Reverse proxy with automatic TLS
- **DNS**: Cloudflare (public) + BIND (internal)
- **Quality**: SonarQube, ESLint, pytest, Jest

### ✅ Environments
- **Development**: `develop`/`dev` branches → Dev environment
- **UAT**: `release/*` branches → UAT environment  
- **Production**: `main` branch → Production environment
- **Preview**: Pull requests → Preview environments

### ✅ Pipeline Stages
- **Lint**: Auto-detects project type → ESLint (Node.js) or Ruff/Flake8 (Python)
- **Test**: Auto-detects project type → Jest (Node.js) or pytest (Python) with coverage
- **Build**: Auto-detects project type → Docker image creation and tagging
- **Scan**: Docker Scout vulnerability scanning
- **Quality**: SonarQube code analysis
- **Promote**: Backend-only → Promotes images across environments
- **Deploy**: Environment-specific deployments
- **Preview**: PR-based preview environments

### 🔔 PR-Merged → Auto Teardown (Cloudflare Worker)

Bitbucket cannot reach the internal webhook URL, So using a public Cloudflare Worker as the webhook endpoint to trigger teardown when a PR is merged into `dev`/`develop`.

- **Worker URL**: [`https://preview-teardown.v-p-16d.workers.dev/bitbucket/pr-merged`](https://preview-teardown.v-p-16d.workers.dev/bitbucket/pr-merged)
- **Bitbucket Webhook**: Repository → Settings → Webhooks
  - **URL**: `https://preview-teardown.v-p-16d.workers.dev/bitbucket/pr-merged`
  - **Trigger**: Pull request: merged
- **Behavior**: The Worker invokes Bitbucket Pipelines API to run the consumer repo’s `manual-preview-teardown` custom pipeline on the PR’s destination branch.
- **Auth**: It uses an access token with `pipelines:write` and `repository:write` as the Worker secret `BITBUCKET_ACCESS_TOKEN`.

Notes:
- Only PRs merged into `dev` or `develop` are acted on.
- The teardown uses `shared-pipelines:main:manual-preview-teardown-traefik` and runs on `preview.runner`.

## 🏗️ Architecture

### Complete Pipeline Flow

#### Stage 1: Quality Assurance (Parallel Execution)
```
┌──────────────────────────────────────────────────────────────────┐
│                        Code Push/PR                              │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             ▼
                ┌────────────────────────┐
                │  Setup Shared Pipelines│
                └────────────┬───────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
                ▼                         ▼
        ┌──────────────┐         ┌──────────────┐
        │  Auto-Detect │         │  Auto-Detect │
        │   Project    │         │   Project    │
        │     Type     │         │     Type     │
        └──────┬───────┘         └──────┬───────┘
               │                        │
               ▼                        ▼
┌──────────────────────────┐  ┌──────────────────────────┐
│  Node.js (package.json)  │  │  Python (pyproject.toml) │
└──────────────────────────┘  └──────────────────────────┘
```

#### Stage 2: CI Pipeline (Quality Gates)
```
                    ┌────────────────────┐
                    │   Shared Setup     │
                    │  (Clone & Env)     │
                    └──────────┬─────────┘
                               │
                    ┌──────────┴──────────┐
                    │                     │
                    ▼                     ▼
        ┌──────────────────┐   ┌──────────────────┐
        │   Lint Stage     │   │   Lint Stage     │
        │  (ESLint/Node)   │   │  (Ruff/Python)   │
        └────────┬─────────┘   └────────┬─────────┘
                 │                     │
                 └──────────┬──────────┘
                            │
                    ┌───────┴────────┐
                    │                │
                    ▼                ▼
        ┌──────────────────┐   ┌──────────────────-┐
        │   Test Stage     │   │    Test Stage     │
        │  (Jest+Coverage) │   │ (pytest+Coverage) │
        └────────┬─────────┘   └────────┬─────────-┘
                 │                     │
                 └──────────┬──────────┘
                            │
                    ┌───────┴────────┐
                    │                │
                    ▼                ▼
        ┌──────────────────┐   ┌──────────────────┐
        │  Build Stage     │   │  Build Stage     │
        │ (Docker Node)    │   │(Docker Python)   │
        └────────┬─────────┘   └────────┬─────────┘
                 │                     │
                 └──────────┬──────────┘
                            │
                            ▼
        ┌───────────────────────────────────┐
        │         Build Stage               │
        │     (Image Tag & Push)            │
        └───────────────┬───────────────────┘
                        │
                        ▼
        ┌───────────────────────────────────┐
        │        Scan Stage                 │
        │  (Docker Scout + SonarQube)       │
        │  ↘ Quality Gate Check → Continue  │
        └───────────────┬───────────────────┘
                        │
                ┌───────┴───────┐
                │               │
                ▼               ▼
       ┌───────────┐   ┌───────────┐
       │  Backend  │   │  Frontend │
       │  Promote  │   │  Rebuild  │
       └───────────┘   └───────────┘
```

#### Stage 3: Deployment Flow (Environment-Specific)
```
Backend Flow (Promote):
┌─────────┐   Promote   ┌─────────┐   Promote   ┌─────────┐
│   Dev   │────────────>│   UAT   │────────────>│  Prod   │
│ Tagged  │   Retag     │ Tagged  │   Retag     │ + Latest│
└─────────┘             └─────────┘             └─────────┘

Frontend Flow (Rebuild):
┌─────────┐   Build     ┌─────────┐   Build     ┌─────────┐
│   Dev   │────────────>│   UAT   │────────────>│  Prod   │
│ Config  │             │ Config  │             │ + Latest│
└─────────┘             └─────────┘             └─────────┘
```

#### Complete Deployment Architecture
```
┌────────────────────────────────────────────────────────────┐
│                        Bitbucket                           │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Consumer Repository → bitbucket-pipelines.yml       │  │
│  │  Import: shared-pipelines:main:general-pipeline-*    │  │
│  └────────────────┬─────────────────────────────────────┘  │
└───────────────────┼────────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────────────────────┐
│              Shared Pipelines (This Repo)                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  bitbucket-pipelines.yml (3867 lines)                │  │
│  │  ├── Setup & Clone Steps                             │  │
│  │  ├── Lint Steps (Cloud + Self-Hosted)                │  │
│  │  ├── Test Steps (Cloud + Self-Hosted)                │  │
│  │  ├── Build Steps                                     │  │
│  │  ├── Scan Steps (Docker Scout)                       │  │
│  │  ├── Quality Gate (SonarQube)                        │  │
│  │  ├── Deploy Steps                                    │  │
│  │  └── Teardown (Preview only - PR merged)             │  │
│  └───────────────────┬──────────────────────────────────┘  │
└──────────────────────┼─────────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│   DockerHub  │ │  SonarQube   │ │   Traefik    │
│  Registry    │ │  Analysis    │ │   Reverse    │
│              │ │              │ │   Proxy      │
└──────┬───────┘ └──────────────┘ └──────┬───────┘
       │                                 │
       ▼                                 ▼
┌──────────────────────────────────────────────┐
│           Deployment Infrastructure          │
│                                              │
│    ┌────────┐  ┌────────┐  ┌────────┐        │
│    │  Dev   │  │  UAT   │  │  Prod  │        │
│    │  VM    │  │  VM    │  │  VM    │        │
│    └───┬────┘  └───┬────┘  └───┬────┘        │
│        │           │           │             │
│        └───────────┴───────────┘             │
│                    │                         │
│                    ▼                         │
│            ┌─────────────────┐               │
│            │  Docker Compose │               │
│            │   Containers    │               │
│            └─────────────────┘               │
└──────────────────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  BIND DNS    │ │ Cloudflare   │ │   Users      │
│  (Internal)  │ │ (Public)     │ │  Access      │
└──────────────┘ └──────────────┘ └──────────────┘
```

### Runner Allocation Strategy
```
┌─────────────────────────────────────────────────────────────┐
│                  Pipeline Trigger                           │
│      (Branch Push, PR, Manual, Scheduled)                   │
└───────────────────┬─────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
        ▼                       ▼
┌───────────────┐     ┌───────────────────┐
│ Cloud Runners │     │ Self-Hosted       │
│ (Atlassian)   │     │ Runners (Custom)  │
├───────────────┤     ├───────────────────┤
│ • Fast setup  │     │ • Docker socket   │
│ • No cache    │     │ • Persistent cache│
│ • Limited     │     │ • Internal access │
│   resources   │     │ • Fast execution  │
│               │     │ • Parallel stages │
│ Tasks:        │     │                   │
│ • Lint        │     │ Tasks:            │
│ • Test        │     │ • Build           │
│ (Optional)    │     │ • Deploy          │
└───────────────┘     │ • SSL setup       │
                      │ • DNS updates     │
                      └───────────────────┘
```

### Environment Routing Architecture
```
User Request Flow by Environment:

Production (Public):
Backend (Cloudflare Tunnel):
┌─────────┐     DNS   ┌──────────────┐    Cloudflare  ┌─────────────┐
│  User   │──────────>│ Cloudflare   │    Tunnel      │  Backend    │
│ Browser │           │   Edge       │───────────────>│  Container  │
└─────────┘           └──────────────┘                └─────────────┘

Frontend (Traefik):
┌─────────┐     DNS   ┌──────────────┐    Traefik     ┌─────────────┐
│  User   │──────────>│ Cloudflare   │    Reverse     │  Frontend   │
│ Browser │           │   Edge       │───────────────>│  Container  │
└─────────┘           └──────────────┘   Proxy (443)  └─────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  Cloudflare DNS │
                    │  (proxied=true) │
                    └─────────────────┘

Dev/UAT (Internal):
Backend & Frontend (Both via Traefik):
┌─────────┐     Internal  ┌──────────────┐  Traefik   ┌──────────┐
│Internal │     DNS (BIND)│  Traefik     │  Routing   │Container │
│  User   │──────────────>│   Proxy      │───────────>│          │
└─────────┘               └──────────────┘            └──────────┘
                             │
                             ▼
                    ┌────────────────────┐
                    │ Let's Encrypt Cert │
                    │  (Wildcard *.dev)  │
                    └────────────────────┘

Preview (PR-based):
Backend & Frontend (Both via Traefik):
┌─────────┐   Dynamic DNS   ┌──────────────┐  Traefik  ┌──────────┐
│Developer│────────────────>│   Traefik    │  Routing  │Preview   │
│  via    │  preview-123    │   Proxy      │──────────>│Container │
│  URL    │  internal.xyz   └──────────────┘           └──────────┘
└─────────┘                                             
                 ┌─────────────────────────────────┐
                 │ PR-specific domain & isolation  │
                 └─────────────────────────────────┘
```

### 🎯 Decision Matrix by Environment



| Environment | Access Method | Domain | Target IP | Key Variables |
|-------------|---------------|--------|-----------|---------------|
| **preview** | Traefik on Preview Server | `${PREVIEW_KEY}-${REPO_SLUG}.internal.${PREVIEW_DOMAIN_NAME}` | Preview Server | `PREVIEW_DOMAIN_NAME` |
| **dev**     | Traefik + Internal DNS | `${DOMAIN_NAME_DEV}` | `${TARGET_IP_DEV}` | `DOMAIN_NAME_DEV`, `TARGET_IP_DEV` |
| **uat**     | Traefik + Internal DNS | `${DOMAIN_NAME_UAT}` | `${TARGET_IP_UAT}` | `DOMAIN_NAME_UAT`, `TARGET_IP_UAT` |
| **prod**    | [Production Checklist](PRODUCTION-CHECKLIST.md)


#### Notes:
- **Preview**: One-time setup already configured
- **Dev/UAT**: Simple Traefik routing with internal DNS
- **Prod**: Complex routing with Cloudflare Tunnel, IP whitelisting, and public DNS

## 🐳 Docker Compose Support

The pipeline automatically selects the appropriate Docker Compose file:

### File Structure
```
your-repo/
├── docker-compose.yml          # Base compose file (required)
├── docker-compose.dev.yml      # Dev-specific overrides (optional)
├── docker-compose.uat.yml      # UAT-specific overrides (optional)
├── docker-compose.prod.yml     # Production-specific overrides (optional)
├── docker-compose.preview.yml  # Preview-specific overrides (optional)
```

### How Docker Compose Works
1. **Base file**: `docker-compose.yml` is always used as foundation
2. **Environment override**: `docker-compose.{env}.yml` if it exists
3. **Pipeline override**: `docker-compose.override.yml` is auto-generated with:
   - Correct Docker image tag (reads `${DEV_TAG}` / `${UAT_TAG}` / `${PROD_TAG}` from `.env` when present)
   - Traefik labels (to route traffic for http/https based hostnames)
   - Environment-specific variables

### Image Tagging & Reuse
- Build stage computes and writes image tags into `.env` (appended if present):
  - `DEV_TAG=$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:dev-<short_commit>`
  - `UAT_TAG=$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:<release_tag>`
  - `PROD_TAG=$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:<version>`
- Deploy stages prefer these variables to pull/run the exact image that was built.

## 🔧 Configuration

### Package.json Scripts (Node.js)
```json
{
  "scripts": {
    "lint": "eslint \"src/**/*.{ts,tsx,js}\" --max-warnings=0",
    "lint:ci": "eslint \"src/**/*.{ts,tsx,js}\" --max-warnings=0",
    "test:ci": "jest --ci --coverage",
    "test": "npm run test:ci",
    "build": "npm run build:prod"
  }
}
```

### Python Requirements
```txt
# requirements.txt or pyproject.toml
pytest>=7.0.0
pytest-cov>=4.0.0
ruff>=0.1.0
```

### Dockerfile Best Practices
```Dockerfile
# Multi-stage build
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:18-alpine AS runtime
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
```

### Environment-Scoped Build Arguments (static builds)
- Define repository variables with an environment suffix; the pipeline picks the correct one at build time and passes it as a Docker `--build-arg` automatically.
- Naming convention: `VAR_<env>=value`
  - Supported `<env>` values: `preview`, `dev`, `uat`, `prod`
  - Examples (Repository variables):
    - `API_BASE_URL_preview=https://preview.api.example.com`
    - `API_BASE_URL_dev=https://dev.api.example.com`
    - `API_BASE_URL_uat=https://uat.api.example.com`
    - `API_BASE_URL_prod=https://api.example.com`
- The build step determines `TARGET_ENV` (`preview`, `dev`, `uat`, or `prod`), normalizes `VAR_<env>` to `VAR`, and injects it as `--build-arg VAR=<value>`.
- Explicitly consume build args in your Dockerfile:
```Dockerfile
    # At the top of the relevant stage
    ARG API_BASE_URL
    # Optionally make it available at runtime
    ENV API_BASE_URL=${API_BASE_URL}
```

## 🌐 Traefik Integration

### Automatic TLS
- **Wildcard certificates** via Let's Encrypt + Cloudflare DNS
- **Multi-domain support** for different repositories
- **Automatic renewal** via cron jobs

### Dashboard Access
- **URL**: `http://traefik.{domain}:8080`
- **Toggle**: Set `TRAEFIK_DASHBOARD_ENABLED=false` to disable
- **Security**: UFW firewall rules automatically configured

### Preview Environments
- **Routing**: Host-based routing via Traefik labels
- **Isolation**: Each PR gets unique compose project name
- **Networking**: Automatic Traefik network attachment

### Dev/UAT/Prod Routing
- Dev deploy uses `DOMAIN_NAME_DEV` directly in Traefik router rule: `Host(\`${DOMAIN_NAME_DEV}\`)`.
- If `DOMAIN_NAME_DEV` is a base domain (not a full FQDN), provide the full FQDN in `DOMAIN_NAME_DEV` to avoid ambiguity. The pipeline no longer computes a host rule variable.

## 🔐 Cloudflare Tunnel (Backend without Public IP)

For production/UAT backend services that cannot rely on internal BIND DNS and have no public IP, use Cloudflare Tunnel to securely expose your backend.

### Why Use Cloudflare Tunnel?
- **No public IP required**: Backend stays private; Cloudflare edge handles ingress.
- **No BIND dependency**: Works in prod/UAT where internal DNS isn't available.
- **Secure**: TLS termination at Cloudflare edge; tunnel traffic is encrypted.
- **Simple**: No VPN or complex networking; just run cloudflared container.

### Cloudflare Tunnel Setup

For backend repos (`IS_BACKEND=true`), the `deploy-prod` step automatically:
- Creates or reuses a Named Tunnel via Cloudflare API.
- Generates credentials and ingress config.
- Creates/updates DNS CNAME (proxied).
- Runs cloudflared container (if not already running).

#### Required Variables (Repository or Deployment):
```bash
CLOUDFLARE_API_TOKEN=your-api-token  # Scopes: Account Zero Trust Tunnels:Edit, DNS:Edit
CLOUDFLARE_ACCOUNT_ID=your-account-id
TUNNEL_HOSTNAME=be-api.prod.example.com  # Full hostname for your backend
APP_PORT=8000  # Container port (pipeline auto-publishes to host)
```

#### Optional Variables:
```bash
TUNNEL_NAME=be-api  # Defaults to first part of TUNNEL_HOSTNAME (e.g., be-api from be-api.prod.example.com)
TUNNEL_SERVICE_URL=http://127.0.0.1:8000  # Overrides default (http://127.0.0.1:${APP_PORT})
TUNNEL_SECRET=<base64-secret>  # 32-byte base64; auto-generated if creating new tunnel
TUNNEL_CONTAINER_NAME=cloudflared-backend  # Default container name
TUNNEL_IMAGE=cloudflare/cloudflared:latest  # Cloudflared image
```

### Backend Docker Compose Requirements

Set `APP_PORT` in your repository variables - the pipeline will automatically publish the port to the host via `docker-compose.override.yml`:

```bash
# Repository Variables
APP_PORT=8000  # Your backend's container port
```

**No manual port publishing needed!** The pipeline automatically generates:
```yaml
# Auto-generated in docker-compose.override.yml
services:
  your-app:
    ports:
      - "8000:8000"  # Auto-published for Cloudflare Tunnel
```

### How Cloudflare Tunnel Works

1. **Pipeline runs `deploy-prod` step** for backend repo (`IS_BACKEND=true`).
2. **Deploy checks if tunnel is running**; if not, auto-runs setup script.
3. **Script creates/reuses Named Tunnel** via Cloudflare API.
4. **Credentials written** to `/etc/cloudflared/<tunnel-id>.json`.
5. **Ingress config** maps `TUNNEL_HOSTNAME` → `http://127.0.0.1:${APP_PORT}`.
6. **DNS CNAME created** (proxied): `be-api.prod.example.com` → `<tunnel-id>.cfargotunnel.com`.
7. **cloudflared container starts**, connecting to Cloudflare edge.
8. **Backend deploys** with published port for tunnel access.
9. **Traffic flows**: Client → Cloudflare edge → Tunnel → Backend (localhost:8000).

### Frontend Integration

- **Direct**: FE calls `https://be-api.prod.example.com` (Cloudflare edge).
- **Via Traefik**: FE Traefik proxies to `https://be-api.prod.example.com` (see Traefik Integration for routing setup).
- **Via Kong**: Kong proxies to `https://be-api.prod.example.com`.

### Cloudflare Tunnel Troubleshooting

#### "APP_PORT is not set"
- **Cause**: Neither `APP_PORT` nor `TUNNEL_SERVICE_URL` provided.
- **Fix**: Set `APP_PORT` in repository variables or provide `TUNNEL_SERVICE_URL` directly.

#### "Could not resolve Cloudflare zone"
- **Cause**: API token lacks DNS:Edit scope or domain not in Cloudflare.
- **Fix**: Ensure domain is managed by Cloudflare and API token has correct scopes.

#### "Tunnel container exits immediately"
- **Cause**: Invalid credentials or tunnel deleted from Cloudflare dashboard.
- **Fix**: Check `docker logs cloudflared-backend`. Re-run setup step to recreate tunnel.

#### Backend not reachable via tunnel
- **Cause**: Backend port not published, or incorrect `APP_PORT`.
- **Fix**: Ensure `ports:` section in docker-compose matches `APP_PORT`. Check `docker ps` for port mappings.

## 🔄 Cross-Repository Previews

Enable peer previews for frontend/backend coordination:

### Cross-Repository Setup
```bash
# In your repo variables
PEER_REPO_SLUGS=frontend-repo,backend-repo
PEER_HOST_URLS=FRONTEND_URL.frontend-repo,BACKEND_URL.backend-repo
```

Note on where to set PEER_HOST_URLS
- Preview flow (static repos): set as Repository variables so values are available at build time.
- Preview flow (dynamic repos): set under the `preview` Deployment environment variables so PRs can override per-run.

### Cross-Repository Behavior
- **Automatic triggers**: Peer repos deploy when source repo builds
- **URL sharing**: Cross-service URLs automatically computed
- **Isolation**: Each repo maintains separate preview environment
- **Loop prevention**: `TRIGGER_SOURCE` variable prevents infinite trigger loops

### Feature Gate
- **Manual trigger**: Feature pipelines include a manual gate to prevent unnecessary runs
- **Peer bypass**: Peer-triggered runs bypass the manual gate using `TRIGGER_SOURCE`
- **Variable passing**: Peer triggers pass `PR_ID`, `PEER_SLUG`, `PEER_IMAGE`, and `TRIGGER_SOURCE`

### Peer Host URLs Format
```bash
# Format: VARIABLE_NAME.repo-slug
PEER_HOST_URLS=FRONTEND_URL.frontend-repo,BACKEND_URL.backend-repo,API_URL.api-repo

# Generated URLs:
# FRONTEND_URL=https://preview-123-frontend-repo.internal.your-domain.com
# BACKEND_URL=https://preview-123-backend-repo.internal.your-domain.com
# API_URL=https://preview-123-api-repo.internal.your-domain.com
```

### Trigger Loop Prevention
- **Source tracking**: `TRIGGER_SOURCE` variable tracks which repo initiated the trigger
- **Loop detection**: If `TRIGGER_SOURCE` is set, peer triggers are skipped
- **Manual override**: Manual runs can proceed even with `TRIGGER_SOURCE` set

## 🔥 Hotfix Flow

Quick path for urgent production fixes:

```yaml
# Add to bitbucket-pipelines.yml
pipelines:
  branches:
    hotfix/*:
      import: shared-pipelines:main:general-pipeline-hotfix
```

### Workflow

```bash
# 1. Create from production version
git checkout production-tag
git checkout -b hotfix/1.2.1

# 2. Fix, commit, push → builds org/repo:hotfix-1.2.1

# 3. Merge to main
git merge hotfix/1.2.1 --into main

# 4. Deploy: Trigger main pipeline with VERSION=hotfix-1.2.1
```

### Tags

- **Hotfix:** `hotfix-1.2.1` (keeps prefix)
- **Regular:** `1.2.1` (no prefix)
- **No conflicts!** Both can exist in production

**See [Production Checklist](PRODUCTION-CHECKLIST.md#hotfix-flow) for detailed workflow.**

## 🚫 Stage Bypass Flags

Skip stages without editing pipeline:

```bash
# Repository variables
SKIP_LINT=true          # Skip lint stage
SKIP_TEST=true          # Skip test stage  
SKIP_BUILD=true         # Skip build stage
SKIP_SCOUT=true         # Skip Docker Scout
SKIP_SONAR=true         # Skip SonarQube
```

## 🏷️ Repository Type Flags

Control deployment and routing behavior:

```bash
# Repository variables
IS_BACKEND=true         # Backend repo: promote flow, Cloudflare Tunnel in prod
IS_ADMIN_PANEL=true     # Admin panel: rebuild flow, internal DNS in prod + IP whitelist
```

### Repository Type Behavior

**UAT Environment:**
- All repos: Traefik routing + internal DNS

**Production Environment:**
- **Backend (`IS_BACKEND=true`)**: Promote flow, Cloudflare Tunnel, no public IP
- **Admin Panel (`IS_ADMIN_PANEL=true`)**: Rebuild flow, Traefik + internal DNS (private) + IP whitelist
- **Regular Frontend**: Rebuild flow, Traefik + Cloudflare DNS (public)

📖 **See [Production Checklist](PRODUCTION-CHECKLIST.md) for complete deployment flows and tag strategies.**

## 🔒 Admin Panel Security

Admin panels (`IS_ADMIN_PANEL=true`) are automatically secured with IP whitelisting:

### IP Whitelist Ranges
- `10.0.0.0/8` - Private Class A networks
- `172.16.0.0/12` - Private Class B networks  
- `192.168.0.0/16` - Private Class C networks

### How It Works
- **Automatic**: Pipeline detects `IS_ADMIN_PANEL=true` and applies IP restrictions
- **Traefik Middleware**: Uses `admin-ip-whitelist` middleware for access control
- **Internal Only**: Only accessible from internal/private networks
- **Public Blocked**: External internet traffic is automatically blocked

### Security Model
```
admin.internal.example.com:
├── DNS: Internal BIND server → Internal IP
├── SSL: Wildcard certificate (*.example.com)
├── Access: IP whitelist (10.x.x.x, 172.16-31.x.x, 192.168.x.x)
└── Result: Internal access only, no public exposure
```

## 📊 Quality Gates

### SonarQube Integration
- **Automatic scanning** on every build
- **Quality gates** with configurable thresholds
- **Coverage reporting** from test stages
- **Security scanning** via Docker Scout integration

### Docker Scout
- **Vulnerability scanning** of built images
- **SBOM generation** for compliance
- **SARIF reporting** for security tools
- **Critical/Major alerts** in pipeline logs
- **SonarQube integration** - Docker Scout vulnerabilities appear in SonarQube under "Vulnerabilities" section with "External Source: docker-scout" tag

## 🛠️ Troubleshooting

### Common Issues

#### "Missing required variable: ENVIRONMENT"
- **Cause**: Environment not detected from branch
- **Fix**: Check branch naming (develop/dev/main/release/*)

#### "Application not accessible via Traefik"
- **Cause**: Missing Traefik labels or wrong service name
- **Fix**: 
  - Ensure service name in compose file matches `BITBUCKET_REPO_SLUG`
  - Don't add Traefik labels manually - pipeline injects them
  - Check `APP_PORT` is set correctly (default: 80)

#### "Traefik labels not working"
- **Cause**: Manual Traefik labels in compose file
- **Fix**: Remove all `traefik.*` labels from your compose files - pipeline adds them automatically

#### "Port conflicts in preview deployments"
- **Cause**: Publishing host ports in compose files
- **Fix**: Remove `ports:` section from app service - Traefik routes via Docker network

#### "Service name mismatch errors"
- **Cause**: Compose service name doesn't match repository slug
- **Fix**: Use `${BITBUCKET_REPO_SLUG}` as service name or let pipeline override it

#### "APP_PORT not set correctly"
- **Cause**: Application listening on non-standard port
- **Fix**: Set `APP_PORT` environment variable to match your app's listening port
  ```bash
  # For Node.js apps on port 3000
  APP_PORT=3000
  
  # For Python apps on port 8000  
  APP_PORT=8000
  ```
Note: Dev deploy defaults to `APP_PORT=80` if not provided.

#### "UFW rule already exists"
- **Cause**: Firewall rules already configured
- **Fix**: This is normal, pipeline continues

#### "Certificate already exists"
- **Cause**: Let's Encrypt certificate already issued
- **Fix**: This is normal, pipeline reuses existing cert

#### "Traefik dashboard not accessible"
- **Cause**: Dashboard not enabled or wrong URL
- **Fix**: Access via `http://traefik.{domain}:8080` or `http://traefik.{domain}`

#### "DNS record creation failed"
- **Cause**: Missing DNS variables or wrong environment
- **Fix**: Set required variables:
  - For dev: `INTERNAL_DNS_SERVER`, `INTERNAL_DNS_TSIG_KEY_NAME`, `INTERNAL_DNS_TSIG_KEY`
  - For uat/prod: `CLOUDFLARE_API_TOKEN`

### Debug Commands
```bash
# Check Traefik status
docker ps | grep traefik
docker logs traefik

# Check certificates
ls -la /etc/ssl/traefik-certs/
ls -la /etc/letsencrypt/live/

# Check DNS records
nslookup your-domain.com
dig your-domain.com
```

## 🔍 Verifying Docker Scout Integration in SonarQube

### How to Check Docker Scout Results in SonarQube:

1. **Navigate to your project in SonarQube**
2. **Go to "Issues" tab**
3. **Filter by "External Source: docker-scout"**
4. **Check "Vulnerabilities" section**

### What You Should See:

- **External Source**: `docker-scout`
- **Engine ID**: `docker-scout`
- **Rule ID**: `docker-scout` (or specific CVE ID)
- **Severity**: `CRITICAL`, `MAJOR`, `MINOR`, or `INFO`
- **Type**: `VULNERABILITY`
- **File Path**: `Dockerfile`, `package.json`, or other project files

### Pipeline Logs to Check:

```bash
# Look for these messages in the SonarQube stage:
"Importing Docker Scout results into Sonar..."
"Found X security findings; generating sonar-issues.json"
"Wrote sonar-issues.json with X external issues"
```

### Troubleshooting Docker Scout Integration:

#### "Docker Scout report or import script not found"
- **Cause**: SARIF file not generated or script missing
- **Fix**: Check if Docker Scout stage ran successfully

#### "No security findings in SARIF file"
- **Cause**: No vulnerabilities found in Docker image
- **Fix**: This is normal - no action needed

#### "External issues will be associated to project root"
- **Cause**: No canonical project file found (Dockerfile, package.json, etc.)
- **Fix**: Ensure you have at least one of: `Dockerfile`, `package.json`, `pyproject.toml`, `requirements.txt`, `README.md`

#### Docker Scout issues not appearing in SonarQube
- **Cause**: SonarQube not processing external issues
- **Fix**: 
  1. Check SonarQube version supports external issues
  2. Verify `sonar-issues.json` was generated
  3. Check SonarQube logs for import errors

#### "Feature Flow Gate" blocking peer triggers
- **Cause**: Manual gate preventing automatic peer triggers
- **Fix**: Peer triggers automatically bypass the gate using `TRIGGER_SOURCE` variable

#### Peer triggers not working
- **Cause**: Missing or incorrect peer configuration
- **Fix**: 
  1. Set `PEER_REPO_SLUGS` or `PEER_REPO_SLUG` with target repo slugs
  2. Ensure `BITBUCKET_ACCESS_TOKEN` has `pipelines:write` scope
  3. Check target repos have matching branch names
  4. Verify `TRIGGER_SOURCE` is not set (prevents loops)

#### Peer host URLs not generated
- **Cause**: Incorrect `PEER_HOST_URLS` format
- **Fix**: Use format `VARIABLE_NAME.repo-slug` (e.g., `FRONTEND_URL.frontend-repo`)

## 📚 Examples

### Example 1: Backend API (with auto-detection)
```yaml
# bitbucket-pipelines.yml
pipelines:
  branches:
    dev*:
      import: shared-pipelines:main:general-pipeline-develop
    release/*:
      import: shared-pipelines:main:general-pipeline-release
    main:
      import: shared-pipelines:main:general-pipeline-main
  pull-requests:
    '**':
      import: shared-pipelines:main:general-pipeline-pr-traefik
```

**Repository Variables:**
```bash
IS_BACKEND=true
APP_PORT=8000
TUNNEL_HOSTNAME=api.prod.example.com  # For Cloudflare Tunnel in prod
```

### Example 2: Frontend App (with auto-detection)
```yaml
# bitbucket-pipelines.yml  
pipelines:
  branches:
    dev*:
      import: shared-pipelines:main:general-pipeline-develop
    release/*:
      import: shared-pipelines:main:general-pipeline-release
    main:
      import: shared-pipelines:main:general-pipeline-main
  pull-requests:
    '**':
      import: shared-pipelines:main:general-pipeline-pr-traefik
```

**Repository Variables:**
```bash
APP_PORT=80
# Use deployment variables (recommended) or fallback to:
# API_BASE_URL_dev=https://dev.api.example.com
# API_BASE_URL_uat=https://uat.api.example.com
# API_BASE_URL_prod=https://api.example.com
```

### Example 3: Admin Panel
```yaml
# Same pipeline imports as above
```

**Repository Variables:**
```bash
IS_ADMIN_PANEL=true
APP_PORT=80
# Use deployment variables (recommended) or fallback to:
# API_BASE_URL_dev=https://dev.api.example.com
# API_BASE_URL_uat=https://uat.api.example.com
# API_BASE_URL_prod=https://api.internal.example.com  # Private
```

**Note:** Pipelines now auto-detect Node.js vs Python - no need for `-python` variants!

### Example 4: Hotfix Deployment

**Pipeline Configuration:**
```yaml
pipelines:
  branches:
    hotfix/*:
      import: shared-pipelines:main:general-pipeline-hotfix
    main:
      import: shared-pipelines:main:general-pipeline-main
```

**Workflow:**
```bash
# 1. Create hotfix from production tag
git checkout 1.2.0  # Current production version
git checkout -b hotfix/1.2.1
# Fix bug, commit, push

# 2. Hotfix pipeline builds: org/repo:hotfix-1.2.1

# 3. Merge to main
git checkout main
git merge hotfix/1.2.1

# 4. Trigger main pipeline with VERSION=hotfix-1.2.1
# Backend: Promotes hotfix-1.2.1 → hotfix-1.2.1 + latest
# Frontend: Rebuilds → hotfix-1.2.1 + latest
```

**Result in Production:**

- Regular releases: `1.0.0`, `1.3.0` (no prefix)
- Hotfix releases: `hotfix-1.2.1`, `hotfix-2.0.1` (with prefix)
- No tag conflicts!

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with a sample repository
5. Submit a pull request

## 📄 License

This project is licensed under the..  - just kidding :)

## 🆘 Support

- **Documentation**: Check this README and inline comments
- **Issues**: Create GitHub issues for bugs or feature requests
- **Examples**: See the demo repository for working examples

---

**Happy Deploying! 🚀**