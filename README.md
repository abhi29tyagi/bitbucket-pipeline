# Shared Pipelines Library

A comprehensive CI/CD pipeline library for Bitbucket Pipelines with support for Node.js, Python, Docker, Traefik, and multi-environment deployments.

📖 **[Production Deployment Checklist](PRODUCTION-CHECKLIST.md)** - Complete guide for deploying to UAT/Prod with different repository types.

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
- **`general-pipeline-ci-node`** - Node only: lint, test, build & push image (no Traefik/compose deploy; for K8s/GitOps)
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

# Cisco Umbrella (optional, mirrors internal DNS entries)
UMBRELLA_ORG_ID=8263853                       # See Umbrella dashboard URL
UMBRELLA_API_KEY=umbrella-api-key
UMBRELLA_API_SECRET=umbrella-api-secret
UMBRELLA_DNS_FORWARDERS=10.25.9.9,10.25.9.10  # Resolver IPs Umbrella should forward to
# Optional fine-tuning:
# UMBRELLA_DESCRIPTION="Auto-managed by shared-pipelines"
# UMBRELLA_STRICT_MODE=true   # Fail pipeline when Umbrella API is down (default is false)
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

# Internal-only service (no Traefik, no Cloudflare Tunnel):
IS_INTERNAL_SERVICE=true  # Deploy as internal service only; no public routing (Traefik) and no Cloudflare Tunnel
                          # Container is reachable only from other containers on shared Docker networks / host

# ⚠️ IMPORTANT: Set the appropriate flag BEFORE deploying to UAT/Prod!
# These flags control deployment flow and production routing behavior.

# Promotion Flow (for non-static frontends like Next.js SSR, Nuxt, etc.):
ENABLE_PROMOTE=true     # Enable promote flow (skip PROD rebuild, promote from UAT)
                        # Use this for non-static frontends that should promote like backends
                        # but still use Traefik routing (not Cloudflare Tunnel)
                        # Example: Next.js SSR, Nuxt SSR, Remix, etc.

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

# Security Scanning
ENABLE_ZAP_SCAN=true  # Enable OWASP ZAP security scan after UAT deployment (when the pipeline gate is enabled)
                      # Scans deployed application and uploads results to SonarQube
                      # Requires DOMAIN_NAME_UAT to be set. Note: In the pipeline the gate may be commented out so the step runs whenever the UAT pipeline includes it.

# Cross-repo Peer Triggers (for multi-repo previews)
PEER_REPO_SLUGS=backend-api,auth-service  # Comma-separated list (or PEER_REPO_SLUG for single repo)

# Pre-build Command (for monorepo shared directories)
# ⚠️ IMPORTANT: Docker's build context does NOT follow symlinks outside the build context.
# Use 'cp -r' to copy directories instead of 'ln -s' for symlinks.
PRE_BUILD_COMMAND="cp -r /home/devadmin/with-zone/h-mall-shared ./h-mall-shared && rm -rf ./h-mall-shared/node_modules ./h-mall-shared/.git ./h-mall-shared/.env*"
```

**Environment-Scoped Build Args (for static frontends):**

**Note:** Use `USE_DEPLOYMENT_VARS=true` for both build and deployment stages. The old variable `USE_BITBUCKET_DEPLOYMENT_VARS` is still supported for backward compatibility.

There are two methods to provide environment-specific build arguments:

**Method 1: Bitbucket Deployment Variables API (Recommended)**
```bash
# Set USE_DEPLOYMENT_VARS=true (or USE_BITBUCKET_DEPLOYMENT_VARS=true for backward compatibility)
# Then configure in Repository Settings → Deployments:

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
- ✅ Per-environment override: `USE_DEPLOYMENT_VARS_DEV`, `USE_DEPLOYMENT_VARS_UAT`, `USE_DEPLOYMENT_VARS_PROD` override the global flag for that environment

See [BITBUCKET-DEPLOYMENT-API.md](BITBUCKET-DEPLOYMENT-API.md) for complete setup instructions.

#### Deployment Environment Variables (Set in Bitbucket deployment environments):

**For `preview` Deployment Environment (optional - or use with `USE_DEPLOYMENT_VARS=true`):**

If using the **Deployment Variables API** (`USE_DEPLOYMENT_VARS=true` or `USE_BITBUCKET_DEPLOYMENT_VARS=true` for backward compatibility), you can centralize ALL preview configuration here:

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
# If NOT using USE_DEPLOYMENT_VARS (or USE_BITBUCKET_DEPLOYMENT_VARS), set these as repository variables:
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

- **Worker URL**: [`https://preview-teardown.weareonwork.com/bitbucket/pr-merged`](https://preview-teardown.weareonwork.com/bitbucket/pr-merged)
- **Bitbucket Webhook**: Repository → Settings → Webhooks
  - **URL**: `https://preview-teardown.weareonwork.com/bitbucket/pr-merged`
  - **Trigger**: Pull request: merged
- **Behavior**: The Worker invokes Bitbucket Pipelines API to run the consumer repo’s `manual-preview-teardown` custom pipeline on the PR’s destination branch.
- **Auth**: It uses an access token with `pipelines:write` and `repository:write` as the Worker secret `BITBUCKET_ACCESS_TOKEN`.

Notes:
- Only PRs merged into `dev` or `develop` are acted on.
- The teardown uses `shared-pipelines:main:manual-preview-teardown-traefik` and runs on `preview.runner`.

## 🏗️ Architecture

### A Typical Pipeline Flow (e.g. Preview Env)
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    Lint     │ -> │    Test     │ -> │    Build    │ -> │ DockerHub   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                                                                |
                                                                V
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Deploy    │ <- │   Traefik   │ <- │   SonarQube │ <- │    Docker   │
│    Env      │    │    Setup    │    │ QualityGate │    │    Scout    │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

### Environment Routing
- **Dev/UAT/Prod**: Traefik + Let's Encrypt certificates
- **Preview**: Traefik + dynamic routing per PR
- **DNS**: Cloudflare (public) + BIND (internal)

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

### How It Works
1. **Base file**: `docker-compose.yml` is always used as foundation
2. **Environment override**: `docker-compose.{env}.yml` if it exists
3. **Pipeline override**: `docker-compose.override.yml` is auto-generated with:
   - Correct Docker image tag (reads `${DEV_TAG}` / `${UAT_TAG}` / `${PROD_TAG}` from `.env` when present)
   - Traefik labels (to route traffic for http/https based hostnames)
   - Environment-specific variables

### Environment-Scoped Build Arguments (static builds)
See Configuration → Environment-Scoped Build Arguments for full details.

Image Tagging & Reuse
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
- **Toggle**: Dashboard is always enabled (Traefik started with `--api.dashboard=true`). A `TRAEFIK_DASHBOARD_ENABLED` variable is not yet implemented.
- **Security**: UFW firewall rules automatically configured

### Preview Environments
- **Routing**: Host-based routing via Traefik labels
- **Isolation**: Each PR gets unique compose project name
- **Networking**: Automatic Traefik network attachment

### Database Restore in Preview Environments

For preview deployments, you can automatically restore a database dump from your dev environment after containers start. This is useful for testing with realistic data without affecting dev.

#### Setup

Add these **Preview Deployment Variables** (Bitbucket → Deployments → preview environment) to enable database restore:

```bash
# Required
DB_TYPE=postgres              # postgres, mysql, mariadb, or mongodb
DB_SERVICE_NAME=db            # Name of database service in docker-compose.yml
DB_NAME=myapp                 # Database name to restore into
DB_DUMP_FROM_DEV=true         # Enables dump + restore from dev database
DEV_DB_SOURCE=dev-db://dev-db-host:5432   # Format: dev-db://host:port
DEV_DB_USER=postgres          # Dev database username
DEV_DB_PASSWORD=secret        # Dev database password
DEV_DB_NAME=myapp             # Dev database name

# Optional
DB_USER=postgres              # Default: postgres (postgres) or admin (mongodb)
DB_PASSWORD=secret            # Auto-detected from docker-compose if not set
DB_PORT=5432                  # Default: 5432 (postgres), 3306 (mysql), 27017 (mongodb)
DB_DUMP_COMPRESSION=auto      # auto, gzip, bzip2, xz, or none (default: auto-detect)
```

**⚠️ Important for Dev DB Connection:**
- **Connectivity Required**: Preview server must be able to reach dev DB host (network + firewall allow-list on the dev host side)
- **Test Connectivity**: Before deployment, test from preview server:
  ```bash
  # Test PostgreSQL (port 5432)
  telnet dev-db-host 5432
  # Or using nc (netcat)
  nc -zv dev-db-host 5432
  
  # Test MongoDB (port 27017)
  telnet dev-db-host 27017
  nc -zv dev-db-host 27017
  ```
- **If connectivity fails**: The script will error with clear instructions
- **Skip dump entirely**: If `DB_DUMP_FROM_DEV` is not set or false, dump is skipped (script exits cleanly)

#### How It Works

1. **Containers start**: `docker-compose up -d` brings up all services including database
2. **Database health check**: Script waits for database to be healthy (max 60s)
3. **Dump retrieval**: Downloads/fetches dump from configured source
4. **Database restore**: Drops existing database, recreates it, and restores dump
5. **App initialization**: Additional wait time for app to connect to restored database

#### Example docker-compose.yml

```yaml
services:
  app:
    image: myorg/myapp:latest
    depends_on:
      db:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql://postgres:secret@db:5432/myapp

  db:
    image: postgres:15
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: secret
    volumes:
      - db-data:/var/lib/postgresql/data

volumes:
  db-data:
```

#### Connectivity Requirements (for dev-db:// source)

Before using `dev-db://` source, ensure:

1. **Network Connectivity**: Preview server can reach dev DB host
   ```bash
   # Test from preview server
   telnet dev-db-host 5432    # PostgreSQL
   telnet dev-db-host 27017   # MongoDB
   ```

2. **Dev DB Firewall**: Ensure the dev database host allows inbound connections from the preview server's IP (configure UFW/security groups on the dev host)

3. **Dev DB Access**: Dev database must allow connections from preview server IP
   - PostgreSQL: Check `pg_hba.conf` and `postgresql.conf` (listen_addresses)
   - MongoDB: Check `mongod.conf` (bindIp) and firewall rules

4. **Client Tools**: Required tools must be installed on preview server (helpers auto-attempt `apt-get install`, but you can install manually if desired):
   - PostgreSQL: `postgresql-client` (provides `pg_dump`, `psql`, `pg_restore`)
      ```bash
      sudo apt-get update
      sudo apt-get install -y postgresql-client
      ```
   - MongoDB: `mongodb-database-tools` + `mongodb-mongosh`
      ```bash
      # Ubuntu / Debian (MongoDB repo)
      wget -qO - https://pgp.mongodb.com/server-6.0.asc | sudo tee /etc/apt/trusted.gpg.d/mongodb.asc
      echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -sc)/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
      sudo apt-get update
      sudo apt-get install -y mongodb-database-tools mongodb-mongosh
      ```
   - Connectivity utilities (already present on most systems, but verify):
      ```bash
      sudo apt-get install -y netcat-openbsd telnet
      ```

#### Notes

- **Preview only**: Database restore only runs when `TARGET_ENV=preview`
- **Dump flag required**: For `dev-db://` source, set `DB_DUMP_FROM_DEV=true` or dump is skipped
- **Non-blocking**: If restore fails, deployment continues (with warning)
- **Auto-cleanup**: Temporary dump files are automatically removed
- **Compression**: Automatically detects and handles gzip, bzip2, xz compression
- **PostgreSQL**: Supports both SQL dumps and custom format (pg_dump -Fc)
- **MongoDB**: Full support for archive format dumps (mongodump --archive)

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

### Setup

#### Production (Automatic)

For backend repos (`IS_BACKEND=true`), the `deploy-prod` step automatically:
- Creates or reuses a Named Tunnel via Cloudflare API.
- Generates credentials and ingress config.
- Creates/updates DNS CNAME (proxied).
- Runs cloudflared container (if not already running).

#### UAT (Optional via Flag)

For UAT backends, you can optionally use Cloudflare Tunnel instead of Traefik by setting:
```bash
USE_CLOUDFLARE_TUNNEL_UAT=true  # Enable Cloudflare Tunnel for UAT backends
IS_BACKEND=true                  # Required: must be a backend repo
```

When enabled, the `deploy-uat` step will:
- Skip Traefik setup (same as prod)
- Set up Cloudflare Tunnel with a separate container name (`cloudflared-backend-uat`)
- Use `TUNNEL_HOSTNAME_UAT` if set, otherwise falls back to `DOMAIN_NAME_UAT`

#### Required Variables (Repository or Deployment):

**Common**
```bash
CLOUDFLARE_API_TOKEN=your-api-token  # Scopes: Account Zero Trust Tunnels:Edit, DNS:Edit
CLOUDFLARE_ACCOUNT_ID=your-account-id
IS_BACKEND=true  # Required: must be a backend repo
```

**For Production:**
```bash
TUNNEL_HOSTNAME=be-api.prod.example.com  # Full hostname for your backend
APP_PORT=8000  # Container port (pipeline auto-publishes to host)
```

**For UAT (when `USE_CLOUDFLARE_TUNNEL_UAT=true`):**
```bash
TUNNEL_HOSTNAME_UAT=be-api.uat.example.com  # UAT-specific hostname (or use DOMAIN_NAME_UAT)
APP_PORT=8000  # Container port
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

### How It Works

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

### Troubleshooting

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

#### Internal DNS update returns `REFUSED`
- **Cause**: The BIND server rejected the dynamic update (usually missing TSIG permissions or zone not configured).
- **Fix**:
  1. In Webmin (DNS server UI), open `/etc/bind/named.conf.local` for editing under **Servers → BIND DNS Server***
  2. For the zone you are onboarding (e.g.; `homnifi.com`), ensure the zone stanza includes an update policy, for example:
     ```conf
     allow-update { key "tsig-key"; };
     ```
  3. Access the shell under **Tools → Command Shell**; and run the following commands:
     ```bash
     sudo named-checkconf
     # If `named-checkconf` reports an error, fix the syntax before reloading.
     sudo systemctl reload named
     ```
  4. Re-run the pipeline step; the dynamic A record update should now succeed.

- **Additional manual step**: For every new internal-only domain, add it in Cisco Umbrella.
  - ✅ **Now automated**: when `UMBRELLA_API_KEY`, `UMBRELLA_API_SECRET`, and `UMBRELLA_ORG_ID` are present, the pipeline automatically mirrors each BIND A record into Cisco Umbrella’s **Deployments → Configuration → Domain Management** list using `scripts/dns/umbrella/sync_internal_domain.sh`.
  - ⚙️ Configure Umbrella sync by setting:
    - `UMBRELLA_ORG_ID` – numeric org ID from the Umbrella dashboard URL.
    - `UMBRELLA_API_KEY` / `UMBRELLA_API_SECRET` – key pair with Deployments → Internal Domain **read/write** scope.
    - `UMBRELLA_DNS_FORWARDERS` – comma-separated resolver IPs Umbrella should forward to (defaults to `INTERNAL_DNS_SERVER` when omitted).
    - Optional: `UMBRELLA_DESCRIPTION`, `UMBRELLA_API_BASE`, `UMBRELLA_STRICT_MODE=true` (default false → warn only; set true to fail when Umbrella API is down).
  - 📒 The sync is idempotent: existing entries are updated in-place; new preview/dev/uat/prod hostnames are appended automatically.

#### Cloudflare Tunnel Debug (DNS and Reachability)
Use these quick checks with your hostname in `TUNNEL_HOSTNAME`:

```bash
# 1) Check DNS via Cloudflare resolver (bypasses local cache)
dig +short A ${TUNNEL_HOSTNAME} @1.1.1.1
dig +short AAAA ${TUNNEL_HOSTNAME} @1.1.1.1

# If your local resolver is stale, flush and retry (macOS)
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder

# 2) Verify HTTP reachability through Cloudflare
curl -I https://${TUNNEL_HOSTNAME}

# 3) Check tunnel container health on the server
docker logs -f cloudflared-backend

# 4) Verify backend service locally on the server
curl -I http://127.0.0.1:${APP_PORT:-8000}
```

Notes:
- Proxied CNAMEs are flattened by Cloudflare; use A/AAAA lookups to verify.
- HTTP 502 typically means DNS and tunnel are OK, but the backend at `127.0.0.1:${APP_PORT}` isn’t responding.

## 🔄 Cross-Repository Previews

Enable peer previews for frontend/backend coordination:

### Setup
```bash
# In your repo variables
PEER_REPO_SLUGS=frontend-repo,backend-repo
PEER_HOST_URLS=FRONTEND_URL.frontend-repo,BACKEND_URL.backend-repo
```

Note on where to set PEER_HOST_URLS
- Preview flow (static repos): set as Repository variables so values are available at build time.
- Preview flow (dynamic repos): set under the `preview` Deployment environment variables so PRs can override per-run.

### Behavior
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
SKIP_TEST=true          # Skip test stage (SKIP_TESTS also supported)
SKIP_BUILD=true         # Skip build stage
SKIP_SCOUT=true         # Skip Docker Scout
SKIP_SONAR=true         # Skip SonarQube (SONAR_SKIP also supported)
SKIP_SONAR_CLEANUP=true # Skip SonarQube project cleanup
```

## 🏷️ Repository Type Flags

Control deployment and routing behavior:

```bash
# Repository variables
IS_BACKEND=true         # Backend repo: promote flow, Cloudflare Tunnel in prod
IS_ADMIN_PANEL=true     # Admin panel: rebuild flow, internal DNS in prod + IP whitelist
```

### Behavior:

**UAT Environment:**
- All repos: Traefik routing + internal DNS

**Production Environment:**
- **Backend (`IS_BACKEND=true`)**: Promote flow, Cloudflare Tunnel, no public IP
- **Admin Panel (`IS_ADMIN_PANEL=true`)**: Rebuild flow, Traefik + internal DNS (private) + IP whitelist
- **Regular Frontend**: Rebuild flow, Traefik + Cloudflare DNS (public)

📖 **See [Production Checklist](PRODUCTION-CHECKLIST.md) for complete deployment flows and tag strategies.**

## 🔒 Admin Panel Security

Admin panels (`IS_ADMIN_PANEL=true`) are automatically secured with IP whitelisting:

### **IP Whitelist Ranges:**
- `10.0.0.0/8` - Private Class A networks
- `172.16.0.0/12` - Private Class B networks  
- `192.168.0.0/16` - Private Class C networks

### **How It Works:**
- **Automatic**: Pipeline detects `IS_ADMIN_PANEL=true` and applies IP restrictions
- **Traefik Middleware**: Uses `admin-ip-whitelist` middleware for access control
- **Internal Only**: Only accessible from internal/private networks
- **Public Blocked**: External internet traffic is automatically blocked

### **Security Model:**
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

#### "MongoDB/PostgreSQL connection timeout from containers"
- **Cause**: Database running on host, containers can't reach it via `localhost` or hostname
- **Problem**: Hardcoding Docker network IPs (e.g., `172.17.0.0/16`) breaks when Docker creates new networks
- **Solutions** (choose one):

  **Option 1: Use `extra_hosts` in docker-compose (Recommended)**
  ```yaml
  # In your docker-compose.yml or docker-compose.dev.yml
  services:
    your-app:
      extra_hosts:
        - "db-host:10.25.9.9"  # Maps db-host to host's private IP
      environment:
        - DATABASE_URL=mongodb://db-host:27017/mydb  # Use db-host instead of IP
  ```
  - **Pros**: Works regardless of Docker network changes, clean hostname
  - **Cons**: Requires updating connection strings to use `db-host`

  **Option 2: Use broader UFW rule (Covers all Docker networks)**
  ```bash
  
  # This allows Docker containers (FROM 172.16.0.0/12) to connect TO the host on port 27017
  sudo ufw allow from 172.16.0.0/12 to any port 27017 proto tcp comment "Docker networks to MongoDB"
  ```
  - **Pros**: Simple, covers all possible Docker networks (172.16.0.0 to 172.31.255.255)
  - **Cons**: Slightly less restrictive (but still private IP range)
  - **Note**: The rule `ALLOW IN 10.25.9.9` is NOT needed - that would allow traffic FROM the host IP, not TO it

  **Option 3: Bind database to 0.0.0.0 and use host IP**
  ```yaml
  # MongoDB config
  net:
    port: 27017
    bindIp: 0.0.0.0  # Listen on all interfaces
  ```
  ```bash
  # UFW rule for host IP
  sudo ufw allow 27017/tcp from 172.16.0.0/12 comment "Docker networks"
  sudo ufw allow 27017/tcp from 10.0.0.0/8 comment "Private networks"
  ```
  - **Pros**: Most flexible, works with any network
  - **Cons**: Database listens on all interfaces (ensure proper firewall rules)

  **Option 4: Dynamically detect Docker networks (Advanced)**
  ```bash
  # Script to auto-add UFW rules for all Docker networks
  for net in $(docker network ls --format "{{.ID}}"); do
    subnet=$(docker network inspect $net --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null)
    if [ -n "$subnet" ]; then
      sudo ufw allow 27017/tcp from $subnet comment "Docker network $net" || true
    fi
  done
  ```
  - **Pros**: Automatically adapts to new networks
  - **Cons**: Requires running script periodically or on network creation

**Recommended Approach**: Use **Option 1** (`extra_hosts`) + **Option 2** (broad UFW rule) for maximum reliability.

**Understanding UFW Rule Direction:**
- `ufw allow from 172.16.0.0/12 to any port 27017` = Allow FROM Docker networks TO host port 27017 ✅ (What you need)
- The host connects to MongoDB via `localhost` (127.0.0.1), not via its own private IP
- Containers connect to MongoDB via the host's private IP (`10.25.9.9:27017`)

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

This project is licensed under the LMNTO License - just kidding :)

## 🆘 Support

- **Documentation**: Check this README and inline comments
- **Issues**: Create GitHub issues for bugs or feature requests
- **Examples**: See the demo repository for working examples

---

**Happy Deploying! 🚀**