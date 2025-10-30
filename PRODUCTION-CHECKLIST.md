# Production Deployment Checklist

A comprehensive guide to deploying different repository types across environments using the shared pipelines library.

---

## 📋 Table of Contents

1. [Docker Tag Strategy](#docker-tag-strategy)
2. [Repository Type Flags](#repository-type-flags)
3. [Deployment Flow Overview](#deployment-flow-overview)
4. [Required Variables](#required-variables)
5. [Production Readiness Checks](#production-readiness-checks)
6. [Deployment Flows by Repository Type](#deployment-flows-by-repository-type)
7. [Hotfix Flow](#hotfix-flow)
8. [Decision Matrix](#decision-matrix)
9. [Quick Reference](#quick-reference)
10. [Common Mistakes](#common-mistakes)
11. [Related Documentation](#related-documentation)

---

## 🏷️ Docker Tag Strategy

### Tag Naming Convention

| Environment | Backend (Promote) | Frontend (Rebuild) |
|------------|-------------------|-------------------|
| **Dev** | `dev-4d2a96e4` (short commit) | `dev-4d2a96e4` (short commit) |
| **UAT** | `release-1.0.0` (from branch) | `release-1.0.0` (from branch) |
| **Prod** | `1.0.0` + `latest` (from `${VERSION}`) | `1.0.0` + `latest` (from `${VERSION}`) |
| **Hotfix** | `hotfix-1.2.1` (from branch) | `hotfix-1.2.1` (from branch) |
| **Hotfix→Prod** | `hotfix-1.2.1` + `latest` (VERSION=hotfix-1.2.1) | `hotfix-1.2.1` + `latest` (VERSION=hotfix-1.2.1) |
| **Preview** | `branch-jira-123` (from feature/*) | `branch-jira-123` (from feature/*) |

### Key Differences

**Backend (Promote Flow):**

- ✅ Same image promoted through environments
- ✅ Fast deployment (just retag and push)
- ✅ Guaranteed consistency (exact same code)
- ✅ Uses runtime environment variables

**Frontend (Rebuild Flow):**

- ⚠️ Fresh build for each environment
- ⚠️ Slower deployment (full rebuild)
- ⚠️ Slight variance risk (new build)
- ⚠️ Build-time variables baked into static assets

---

## 🏷️ Repository Type Flags

**⚠️ CRITICAL: Set these BEFORE deploying to UAT/Prod!**

These flags are **MANDATORY** repository variables that determine your deployment strategy and production routing. Choose ONE based on your repository type.

### IS_BACKEND=true

**Use for:** Backend services, APIs, microservices

**Effects:**

- ✅ Enables **promote** flow (dev → uat → prod with same image)
- ✅ Skips Traefik in production
- ✅ Uses Cloudflare Tunnel for secure access
- ✅ No public IP required
- ✅ Publishes host port for tunnel connectivity

**Required Additional Variables:**

- `TUNNEL_HOSTNAME` (for prod)
- `APP_PORT` must publish host port in docker-compose

### IS_ADMIN_PANEL=true

**Use for:** Admin panels, internal dashboards

**Effects:**

- ✅ Uses **rebuild** flow (fresh build per environment)
- ✅ Uses Internal DNS in production (instead of Cloudflare)
- ✅ Keeps admin panel on private network
- ✅ Still uses Traefik for routing
- ✅ Requires all environment-scoped build args

### No Flags (Regular Frontend)

**Use for:** Public-facing web applications

**Effects:**

- ✅ Uses **rebuild** flow (fresh build per environment)
- ✅ Uses Cloudflare DNS in production (public)
- ✅ Uses Traefik for routing
- ✅ Requires all environment-scoped build args
- ✅ Publicly accessible

---

**⚠️ WARNING:** Not setting the appropriate flag will result in:

- Wrong deployment strategy (promote vs rebuild)
- Wrong DNS configuration (Cloudflare vs Internal)
- Wrong routing setup (Traefik vs Tunnel)
- Production deployment failures

---

## 🔄 Deployment Flow Overview

### Backend Deployment (IS_BACKEND=true)

#### Dev → UAT (release/* branch)

```
1. Code merged to release/1.0.0
2. Pipeline: general-pipeline-release
3. Build step: SKIPPED (frontend only)
4. Promote-UAT step:
   ├─ Pulls: org/repo:dev-4d2a96e4
   ├─ Gets digest: sha256:abc...
   ├─ Tags: org/repo:release-1.0.0
   └─ Pushes: release-1.0.0
5. Scout: Vulnerability scan
6. Traefik Setup: Runs (internal DNS)
7. Deploy-UAT:
   ├─ Pulls: org/repo:release-1.0.0
   ├─ Traefik labels added
   └─ Deployed on UAT runner
```

#### UAT → Prod (main branch)

```
1. Release branch merged to main
2. Pipeline: general-pipeline-main
3. User sets: VERSION=1.0.0 (identifies which release)
4. Build step: SKIPPED (frontend only)
5. Promote-Prod step:
   ├─ Pulls: org/repo:release-1.0.0 (UAT tag)
   ├─ Gets digest: sha256:abc...
   ├─ Tags: org/repo:1.0.0 AND org/repo:latest
   └─ Pushes: 1.0.0 + latest
6. Scout: Vulnerability scan
7. Sonar: Code quality
8. Traefik Setup: SKIPPED (IS_BACKEND=true exits early)
9. Deploy-Prod:
   ├─ Checks if Cloudflare Tunnel running
   ├─ If not: auto-runs setup_tunnel.sh
   ├─ Pulls: org/repo:1.0.0
   ├─ NO Traefik labels (publishes port instead)
   └─ Deployed on Prod runner
```

**Traffic:** Client → Cloudflare Edge → Tunnel → Backend:8000

---

### Frontend Deployment (Static Build)

#### Dev → UAT (release/* branch)

```
1. Code merged to release/1.0.0
2. Pipeline: general-pipeline-release
3. Build step:
   ├─ Reads: API_BASE_URL from 'uat' deployment environment (or API_BASE_URL_uat fallback to repo vars)
   ├─ Builds with UAT vars
   ├─ Tags: org/repo:release-1.0.0
   └─ Pushes: release-1.0.0
4. Promote-UAT: SKIPPED (frontend rebuilds)
5. Scout: Vulnerability scan
6. Sonar: Code quality
7. Traefik Setup: Runs (internal DNS)
8. Deploy-UAT:
   ├─ Pulls: org/repo:release-1.0.0
   ├─ Traefik labels added
   └─ Deployed on UAT runner
```

#### UAT → Prod (main branch)

```
1. Release branch merged to main
2. Pipeline: general-pipeline-main
3. Build step:
   ├─ Reads: API_BASE_URL from 'prod' deployment environment (or API_BASE_URL_prod fallback to repo vars)
   ├─ Builds with Prod vars
   ├─ Tags: org/repo:1.0.0 AND org/repo:latest
   └─ Pushes: 1.0.0 + latest
4. Promote-Prod: SKIPPED (frontend rebuilds)
5. Scout: Vulnerability scan
6. Sonar: Code quality
7. Traefik Setup: Runs (Cloudflare DNS)
8. Deploy-Prod:
   ├─ Pulls: org/repo:1.0.0
   ├─ Traefik labels added
   └─ Deployed on Prod runner
```

**Traffic:** Client → Cloudflare DNS → Traefik → Frontend:80

---

### Admin Panel Deployment (IS_ADMIN_PANEL=true)

**Same as Regular Frontend, except:**

**Prod Traefik Setup:**

- ✅ Uses **Internal DNS** (not Cloudflare)
- ✅ Creates A record in BIND server
- ✅ Requires internal DNS variables

**Prod Deploy:**

- ✅ Only accessible via internal network
- ✅ Domain: admin.internal.example.com

**Traffic:** Internal Users → Internal DNS → Traefik → Admin:80

---

## 📝 Required Variables

### All Repositories (Workspace Variables)

```bash
# Docker Hub
DOCKERHUB_USERNAME=xxx
DOCKERHUB_TOKEN=xxx
DOCKERHUB_ORGNAME=xxx

# Bitbucket
BITBUCKET_ACCESS_TOKEN=xxx  # For peer triggers

# SonarQube
SONAR_HOST_URL=http://xxx
SONAR_TOKEN=xxx

# DNS & Domains
PREVIEW_DOMAIN_NAME=example.com
CLOUDFLARE_API_TOKEN=xxx
CLOUDFLARE_ACCOUNT_ID=xxx  # Required for Cloudflare Tunnel (backend repos)

# Internal DNS (for dev/uat/admin)
INTERNAL_DNS_SERVER=10.x.x.x
INTERNAL_DNS_TSIG_KEY_NAME=xxx
INTERNAL_DNS_TSIG_KEY=xxx
```

---

### Backend Repository (IS_BACKEND=true)

**Repository Variables (Required):**
```bash
IS_BACKEND=true
APP_PORT=8000

# Dev Environment
TARGET_IP_DEV=10.25.9.15
DOMAIN_NAME_DEV=api.dev.example.com

# UAT Environment  
TARGET_IP_UAT=10.25.9.16
DOMAIN_NAME_UAT=api.uat.example.com

# Prod Environment (Cloudflare Tunnel)
TUNNEL_HOSTNAME=api.prod.example.com
# Note: No TARGET_IP_PROD or DOMAIN_NAME_PROD needed (tunnel handles it)
# Note: CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN are in workspace variables
```

**Repository Variables (Optional):**
```bash
TUNNEL_CONTAINER_NAME=cloudflared-backend  # Defaults to cloudflared-backend
TUNNEL_SERVICE_URL=http://127.0.0.1:8000   # Defaults to http://127.0.0.1:${APP_PORT}
```

**Port Publishing:**

The pipeline automatically publishes `APP_PORT` to the host via `docker-compose.override.yml` for Cloudflare Tunnel connectivity. No manual port configuration needed in your base `docker-compose.yml` or `docker-compose.prod.yml`!

**Pipeline Variables (Set when triggering main branch pipeline):**
```bash
# Required for backend promotion to prod
VERSION=1.0.0  # Identifies which UAT release tag to promote (e.g., release-1.0.0)
```

---

### Admin Panel Repository (IS_ADMIN_PANEL=true)

**Repository Variables (Required):**
```bash
IS_ADMIN_PANEL=true
APP_PORT=80

# Dev Environment
TARGET_IP_DEV=10.25.9.15
DOMAIN_NAME_DEV=admin.dev.example.com

# UAT Environment
TARGET_IP_UAT=10.25.9.16
DOMAIN_NAME_UAT=admin.uat.example.com

# Prod Environment (Internal DNS)
TARGET_IP_PROD=10.25.9.17  # Internal IP
DOMAIN_NAME_PROD=admin.internal.example.com
```

**Environment-Scoped Build Args:**

**Method 1: Traditional (Default)** - Set as repository variables with suffixes:
```bash
API_BASE_URL_dev=https://dev.api.example.com
API_BASE_URL_uat=https://uat.api.example.com
API_BASE_URL_prod=https://api.internal.example.com  # Internal API
ADMIN_TITLE_dev=Dev Admin
ADMIN_TITLE_uat=UAT Admin
ADMIN_TITLE_prod=Production Admin
```

**Method 2: Bitbucket Deployment Variables API (Opt-In)**

Enable by setting: `USE_BITBUCKET_DEPLOYMENT_VARS=true`

Then add variables in **Repository Settings → Deployments → [environment]** (no suffixes):
```bash
# In 'dev' deployment environment:
API_BASE_URL=https://dev.api.example.com
ADMIN_TITLE=Dev Admin

# In 'uat' deployment environment:
API_BASE_URL=https://uat.api.example.com
ADMIN_TITLE=UAT Admin

# In 'prod' deployment environment:
API_BASE_URL=https://api.internal.example.com
ADMIN_TITLE=Production Admin
```

See [BITBUCKET-DEPLOYMENT-API.md](BITBUCKET-DEPLOYMENT-API.md) for details.

**Dockerfile Requirement:**
```dockerfile
# Declare build args
ARG API_BASE_URL
ARG ADMIN_TITLE

# Make available at runtime
ENV API_BASE_URL=${API_BASE_URL}
ENV ADMIN_TITLE=${ADMIN_TITLE}
```

---

### Regular Frontend Repository

**Repository Variables (Required):**
```bash
# No IS_BACKEND or IS_ADMIN_PANEL flags needed
APP_PORT=80

# Dev Environment
TARGET_IP_DEV=10.25.9.15
DOMAIN_NAME_DEV=app.dev.example.com

# UAT Environment
TARGET_IP_UAT=10.25.9.16
DOMAIN_NAME_UAT=app.uat.example.com

# Prod Environment (Public)
TARGET_IP_PROD=203.0.113.10  # Public IP
DOMAIN_NAME_PROD=app.example.com
```

**Environment-Scoped Build Args:**

**Method 1: Traditional (Default)** - Set as repository variables with suffixes:
```bash
API_BASE_URL_dev=https://dev.api.example.com
API_BASE_URL_uat=https://uat.api.example.com
API_BASE_URL_prod=https://api.example.com
FEATURE_FLAG_X_dev=true
FEATURE_FLAG_X_uat=true
FEATURE_FLAG_X_prod=false
```

**Method 2: Bitbucket Deployment Variables API (Opt-In)**

Enable by setting: `USE_BITBUCKET_DEPLOYMENT_VARS=true`

Then add variables in **Repository Settings → Deployments → [environment]** (no suffixes):
```bash
# In 'dev' deployment environment:
API_BASE_URL=https://dev.api.example.com
FEATURE_FLAG_X=true

# In 'uat' deployment environment:
API_BASE_URL=https://uat.api.example.com
FEATURE_FLAG_X=true

# In 'prod' deployment environment:
API_BASE_URL=https://api.example.com
FEATURE_FLAG_X=false
```

See [BITBUCKET-DEPLOYMENT-API.md](BITBUCKET-DEPLOYMENT-API.md) for details.

**Dockerfile Requirement:**
```dockerfile
# Declare build args
ARG API_BASE_URL
ARG FEATURE_FLAG_X

# Make available at runtime
ENV API_BASE_URL=${API_BASE_URL}
ENV FEATURE_FLAG_X=${FEATURE_FLAG_X}
```

---

## ✅ Production Readiness Checks

### Before Deploying to UAT

- [ ] Code merged to `release/X.X.X` branch
- [ ] **Backends:** Dev image exists (`dev-xxxxx` tag pushed)
- [ ] **Frontends:** Environment variables set for UAT (deployment variables or `*_uat` repo vars)
- [ ] `TARGET_IP_UAT` and `DOMAIN_NAME_UAT` configured
- [ ] UAT runner available with tag `uat.runner`
- [ ] Traefik setup completed on UAT machine
- [ ] Internal DNS server accessible

### Before Deploying to Production

#### All Repos:
- [ ] **Repository Type Flag Set** (`IS_BACKEND` OR `IS_ADMIN_PANEL` OR neither) ⚠️ MANDATORY
- [ ] Release branch tested in UAT
- [ ] Quality gates passed (SonarQube, Scout)
- [ ] `TARGET_IP_PROD` configured (if not backend)
- [ ] `DOMAIN_NAME_PROD` configured (if not backend)
- [ ] Prod runner available with tag `prod.runner`

#### Backend Repos (IS_BACKEND=true):
- [ ] `IS_BACKEND=true` set in repository variables
- [ ] **VERSION** variable set (e.g., `VERSION=1.0.0`) for main pipeline
- [ ] UAT release tag exists (`release-1.0.0`)
- [ ] `CLOUDFLARE_API_TOKEN` configured in **workspace** variables
- [ ] `CLOUDFLARE_ACCOUNT_ID` configured in **workspace** variables
- [ ] `TUNNEL_HOSTNAME` configured in repository variables (e.g., `api.prod.example.com`)
- [ ] `APP_PORT` configured (pipeline auto-publishes port via override)
- [ ] Cloudflare domain managed in Cloudflare account

#### Admin Panel (IS_ADMIN_PANEL=true):
- [ ] `IS_ADMIN_PANEL=true` set in repository variables
- [ ] `USE_BITBUCKET_DEPLOYMENT_VARS=true` with deployment variables configured (or fallback to `*_prod` repo vars)
- [ ] Internal DNS accessible from prod runner
- [ ] `INTERNAL_DNS_*` variables configured
- [ ] `TARGET_IP_PROD` points to internal/private IP
- [ ] Dockerfile declares and uses all build args

#### Regular Frontend:
- [ ] `USE_BITBUCKET_DEPLOYMENT_VARS=true` with deployment variables configured (or fallback to `*_prod` repo vars)
- [ ] `TARGET_IP_PROD` points to public IP
- [ ] Cloudflare DNS configured for domain
- [ ] Dockerfile declares and uses all build args

---

## 🔄 Deployment Flows by Repository Type

### 1. Backend Service (IS_BACKEND=true)

#### Example: REST API, Microservice

**Tag Flow:**
```
Dev:  org/api:dev-4d2a96e4
       ↓ (promote)
UAT:  org/api:release-1.0.0
       ↓ (promote)
Prod: org/api:1.0.0 + org/api:latest
```

**Deployment Steps:**

**Dev (develop/dev branch):**

1. Build Docker image
2. Tag as `dev-4d2a96e4`
3. Push to DockerHub
4. Scout scan
5. Traefik setup (internal DNS)
6. Deploy with Traefik labels

**UAT (release/1.0.0 branch):**

1. **Promote** (no rebuild): `dev-4d2a96e4` → `release-1.0.0`
2. Scout scan
3. Traefik setup (internal DNS)
4. Deploy with Traefik labels

**Prod (main branch, VERSION=1.0.0):**

1. **Promote** (no rebuild): `release-1.0.0` → `1.0.0` + `latest`
2. Scout scan
3. Sonar quality gate
4. **Traefik setup: SKIPPED** (backend uses tunnel)
5. **Cloudflare Tunnel**: Auto-setup if not running
6. Deploy **without Traefik labels**, publishes port

**Access:**

- Dev/UAT: `https://api.dev.example.com` (via Traefik)
- Prod: `https://api.prod.example.com` (via Cloudflare Tunnel)

**Key Point:** Exact same Docker image runs in all three environments!

---

### 2. Admin Panel (IS_ADMIN_PANEL=true)

#### Example: Internal Dashboard, Admin UI

**Tag Flow:**
```
Dev:  org/admin:dev-4d2a96e4 (built with dev vars)
       ↓ (rebuild)
UAT:  org/admin:release-1.0.0 (built with uat vars)
       ↓ (rebuild)
Prod: org/admin:1.0.0 (built with prod vars) + latest
```

**Deployment Steps:**

**Dev (develop/dev branch):**

1. Build with `*_dev` build args
2. Tag as `dev-4d2a96e4`
3. Push to DockerHub
4. Scout scan
5. Sonar quality gate
6. Traefik setup (internal DNS)
7. Deploy with Traefik labels

**UAT (release/1.0.0 branch):**

1. **Rebuild** with `*_uat` build args
2. Tag as `release-1.0.0`
3. Push to DockerHub
4. Scout scan
5. Sonar quality gate
6. Traefik setup (internal DNS)
7. Deploy with Traefik labels

**Prod (main branch):**

1. **Rebuild** with `*_prod` repo vars
2. Tag as `1.0.0` + `latest`
3. Push to DockerHub
4. Scout scan
5. Sonar quality gate
6. Traefik setup (**Internal DNS**, not Cloudflare)
7. Deploy with Traefik labels

**Access:**

- Dev: `https://admin.dev.example.com` (internal DNS)
- UAT: `https://admin.uat.example.com` (internal DNS)
- Prod: `https://admin.internal.example.com` (internal DNS, private network only)

**Key Point:** Rebuilds for each environment with different API URLs/config, but stays on private network!

---

### 3. Regular Frontend

#### Example: Public Web App, Marketing Site

**Tag Flow:**
```
Dev:  org/webapp:dev-4d2a96e4 (built with dev vars)
       ↓ (rebuild)
UAT:  org/webapp:release-1.0.0 (built with uat vars)
       ↓ (rebuild)
Prod: org/webapp:1.0.0 (built with prod vars) + latest
```

**Deployment Steps:**

**Dev (develop/dev branch):**

1. Build with `*_dev` build args
2. Tag as `dev-4d2a96e4`
3. Push to DockerHub
4. Scout scan
5. Sonar quality gate
6. Traefik setup (internal DNS)
7. Deploy with Traefik labels

**UAT (release/1.0.0 branch):**

1. **Rebuild** with `*_uat` build args
2. Tag as `release-1.0.0`
3. Push to DockerHub
4. Scout scan
5. Sonar quality gate
6. Traefik setup (internal DNS)
7. Deploy with Traefik labels

**Prod (main branch):**

1. **Rebuild** with `*_prod` repo vars
2. Tag as `1.0.0` + `latest`
3. Push to DockerHub
4. Scout scan
5. Sonar quality gate
6. Traefik setup (**Cloudflare DNS**, public)
7. Deploy with Traefik labels

**Access:**

- Dev: `https://app.dev.example.com` (internal DNS)
- UAT: `https://app.uat.example.com` (internal DNS)
- Prod: `https://app.example.com` (Cloudflare DNS, public)

**Key Point:** Rebuilds for each environment with different API URLs/config, publicly accessible in prod!

---

## 🔥 Hotfix Flow

For urgent production fixes:

### Workflow

**1. Create Hotfix Branch**
```bash
git checkout production-tag  # e.g., 1.2.0
git checkout -b hotfix/1.2.1
# Fix the bug
git commit -m "Fix critical issue"
git push origin hotfix/1.2.1
```

**2. Hotfix Pipeline Runs**
- Builds: `org/repo:hotfix-1.2.1`
- Scans with Scout & Sonar
- No auto-deployment (manual control)

**3. Merge to Main**
```bash
git checkout main
git merge hotfix/1.2.1
git push origin main
```

**4. Deploy to Production**

Trigger `main` branch pipeline with:
```
VERSION=hotfix-1.2.1
```

**Backend:** Promotes `hotfix-1.2.1` → `hotfix-1.2.1` + `latest`  
**Frontend:** Rebuilds with prod args → `hotfix-1.2.1` + `latest`

### Tag Comparison

**Regular Release:**
```
release/1.3.0 → release-1.3.0 → 1.3.0 + latest
```

**Hotfix:**
```
hotfix/1.2.1 → hotfix-1.2.1 → hotfix-1.2.1 + latest
```

**No Conflicts:**
- Regular release: `1.3.0` ✅
- Hotfix release: `hotfix-1.2.1` ✅
- Both can exist in DockerHub without collision

### Best Practices

- ✅ Always branch from the production tag you're fixing
- ✅ Use semantic versioning (increment patch: 1.2.0 → 1.2.1)
- ✅ Keep `hotfix-` prefix in version to distinguish from regular releases
- ✅ Test with Scout/Sonar before merging to main
- ✅ Document the hotfix in release notes
- ❌ Don't create `hotfix/1.2.1` if `release/1.2.1` already exists

---

## 🎯  Decision Matrix

| Type | Flag | Production Access | Domain| IP:Port | Key Variables |
|------|------|------------------|---------------|----------------|---------------|
| **Backend API** | `IS_BACKEND=true` | Cloudflare Tunnel | `${TUNNEL_HOSTNAME}` | `127.0.0.1:${APP_PORT}` | `IS_BACKEND`, `TUNNEL_HOSTNAME`, `APP_PORT` |
| **Admin Panel** | `IS_ADMIN_PANEL=true` | Internal DNS + IP Whitelist | `${DOMAIN_NAME_PROD}` | `${TARGET_IP_PROD}:80` | `IS_ADMIN_PANEL`, `DOMAIN_NAME_PROD`, `TARGET_IP_PROD`  |
| **Public Frontend** | No flags | Public DNS | `${DOMAIN_NAME_PROD}` | `${TARGET_IP_PROD}:80` | `DOMAIN_NAME_PROD`, `TARGET_IP_PROD` |
| **Static Site** | No flags | Public DNS | `${DOMAIN_NAME_PROD}` | `${TARGET_IP_PROD}:80` | `DOMAIN_NAME_PROD`, `TARGET_IP_PROD` |

---

## 🔍 Quick Reference

### Backend (IS_BACKEND=true)
```
✅ Promote flow
✅ No Traefik in prod
✅ Cloudflare Tunnel
✅ No public IP
✅ Runtime config
```

### Admin Panel (IS_ADMIN_PANEL=true)
```
✅ Rebuild flow
✅ Traefik in all envs
✅ Internal DNS in prod
✅ Private network only
✅ Build-time config
```

### Regular Frontend
```
✅ Rebuild flow
✅ Traefik in all envs
✅ Cloudflare DNS in prod
✅ Public access
✅ Build-time config
```

---

## 🚨 Common Mistakes

### ❌ Backend without IS_BACKEND flag
**Problem:** Backend gets rebuilt in UAT/Prod with static build flow
**Solution:** Set `IS_BACKEND=true`

### ❌ Admin panel accessible publicly
**Problem:** Forgot to set `IS_ADMIN_PANEL=true`
**Solution:** Set flag and redeploy with internal DNS

### ❌ Frontend missing build args
**Problem:** App shows wrong API URL in production
**Solution:** Set `USE_BITBUCKET_DEPLOYMENT_VARS=true` and configure deployment variables in Repository Settings → Deployments → prod environment (or fallback to `VARNAME_prod` repo vars)

### ❌ Backend missing VERSION for prod
**Problem:** Promote-prod fails: "VERSION not provided"
**Solution:** Set `VERSION=1.0.0` when running main pipeline

### ❌ Backend APP_PORT not set
**Problem:** Cloudflare Tunnel can't reach backend, or port not published
**Solution:** Set `APP_PORT` in repository variables - pipeline auto-publishes via override

### ❌ Missing UAT release tag
**Problem:** Promote-prod fails: "Failed to pull release-1.0.0"
**Solution:** Ensure UAT pipeline ran successfully and created release tag

---

## 📖 Related Documentation

- [Main README](README.md) - Full pipeline documentation
- [Bitbucket Deployment Variables API](BITBUCKET-DEPLOYMENT-API.md) - Opt-in feature for centralized environment configuration
- [Cloudflare Tunnel Setup](README.md#cloudflare-tunnel-backend-without-public-ip) - Detailed tunnel configuration
- [Traefik Integration](README.md#traefik-integration) - Reverse proxy setup
- [Cross-Repository Previews](README.md#cross-repository-previews) - Peer trigger configuration

---

**Questions?** Check the main README troubleshooting section or create an issue.

