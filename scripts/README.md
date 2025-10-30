# Shared Pipelines Scripts

This directory contains shared scripts used by the pipelines. It is organized by responsibility.

## 📑 Table of Contents

- [Structure](#structure)
- [Script Categories](#script-categories)
  - [Lint/Test/Build Scripts](#lint-test-build-scripts)
  - [DNS Management Scripts](#dns-management-scripts)
  - [Traefik & SSL Certificates](#traefik-ssl-certificates)
  - [Preview Environment Scripts](#preview-environment-scripts)
  - [SonarQube Integration](#sonarqube-integration)
  - [Utility Scripts](#utility-scripts)
  - [Development & Validation Scripts](#development-validation-scripts)
- [Environment Variables](#environment-variables)
- [Quick Reference](#quick-reference)

## Structure

```
scripts/
├── lint/
│   ├── lint-node.sh            # Node.js linting (ESLint)
│   └── lint-python.sh          # Python linting (Ruff/Flake8)
├── test/
│   ├── test-node.sh            # Node.js testing (Jest)
│   └── test-python.sh          # Python testing (pytest)
├── build/
│   ├── build-node.sh           # Node.js Docker build
│   └── build-python.sh         # Python Docker build
├── dns/
│   ├── dns_create.sh           # Dispatcher: routes to Cloudflare or Internal DNS
│   ├── dns_delete.sh           # Dispatcher: routes to Cloudflare or Internal DNS
│   ├── cloudflare/
│   │   ├── cf_create_dns.sh    # Creates Cloudflare DNS A records
│   │   ├── cf_delete_dns.sh    # Deletes Cloudflare DNS records
│   │   └── setup_tunnel.sh     # Automates Cloudflare Tunnel setup (Named Tunnels)
│   └── internal/
│       ├── internal_dns_create.sh  # Creates BIND DNS records via nsupdate
│       └── internal_dns_delete.sh  # Deletes BIND DNS records
├── preview/
│   ├── allocate_port.sh        # Allocates ports for preview environments
│   └── pr_comment.sh           # Adds PR comment with preview URL
├── traefik/
│   ├── certbot_cloudflare.sh           # Initial wildcard cert setup
│   └── certbot_cloudflare_renew.sh     # Cert renewal + cron
├── sonar/
│   └── import-docker-scout-to-sonar.sh    # Converts Scout SARIF to Sonar format
├── dev/
│   ├── validate-integration.sh    # Integration test for Deployment Variables API
│   └── validate-bitbucket-api.sh  # Validation for Bitbucket API utilities
└── utils/
    ├── lib.sh                # Logging, retries, error handling
    └── bitbucket-api.sh      # Bitbucket API integration for deployment variables
```

## Script Categories

### Lint/Test/Build Scripts

Auto-detection scripts that handle linting, testing, and building for Node.js and Python projects.

**Key Features:**
- **Auto-detect** Node.js vs Python based on project files
- **Smart execution** with proper dependency management
- **Integrated reporting** for test coverage and lint results

**Scripts:**
- `lint-node.sh` - ESLint for Node.js projects
- `lint-python.sh` - Ruff/Flake8 for Python projects
- `test-node.sh` - Jest testing with coverage
- `test-python.sh` - pytest with coverage
- `build-node.sh` - Docker image building for Node.js
- `build-python.sh` - Docker image building for Python

### DNS Management Scripts

Comprehensive DNS management for both public (Cloudflare) and private (Internal BIND) DNS systems.

#### DNS Dispatchers
- **`dns_create.sh`** - Routes to Cloudflare or Internal DNS based on environment
- **`dns_delete.sh`** - Deletes DNS records from the appropriate system

#### Cloudflare DNS
- **`cf_create_dns.sh`** - Creates Cloudflare DNS A records for public domains
- **`cf_delete_dns.sh`** - Deletes Cloudflare DNS records
- **`setup_tunnel.sh`** - Automates Cloudflare Named Tunnel creation via API

**Use Cases:**
- **Cloudflare**: Public DNS for production frontends
- **Internal BIND**: Private DNS for dev/UAT/admin panels

### Traefik & SSL Certificates

SSL certificate management with Traefik using Let's Encrypt and Cloudflare DNS challenges.

#### Files
- **`certbot_cloudflare.sh`** - Obtain wildcard certificates using Cloudflare DNS
- **`certbot_cloudflare_renew.sh`** - Automated certificate renewal

#### Prerequisites

**Required Variables:**
- `CLOUDFLARE_API_TOKEN` - Cloudflare API token with DNS:Edit permissions
- `DOMAIN_NAME` - Base domain (e.g., example.com)
- `FQDN` - Fully qualified domain name (e.g., internal.example.com)

**Optional Variables:**
- `CERTBOT_EMAIL` - Email for Let's Encrypt registration
- `CERTBOT_STAGING` - Set to "1" for staging environment
- `CERTBOT_FORCE_PROD` - Set to "1" to force production certificates

#### Pipeline Integration

**Initial Traefik Setup:**
```bash
./scripts/traefik/certbot_cloudflare.sh
```

**Automated Renewal:**
```bash
./scripts/traefik/certbot_cloudflare_renew.sh
```

#### Debug Commands

**Check Certificate Status:**
```bash
# List certificates
docker run --rm -v /etc/letsencrypt:/etc/letsencrypt certbot/dns-cloudflare certificates

# Check specific certificate
docker run --rm -v /etc/letsencrypt:/etc/letsencrypt certbot/dns-cloudflare certificates --cert-name internal.example.com
```

**Test Certificate Renewal:**
```bash
# Dry run (safe test)
docker run --rm \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/log/letsencrypt:/var/log/letsencrypt \
  -v /etc/letsencrypt/cloudflare:/cloudflare \
  certbot/dns-cloudflare renew --dry-run --no-random-sleep-on-renew
```

**Check Certificate Expiry:**
```bash
# Check expiry
openssl x509 -in /etc/letsencrypt/live/internal.example.com/cert.pem -noout -dates

# Test HTTPS
curl -I https://internal.example.com
```

#### Common Issues

**Missing Cloudflare Credentials**
- **Error**: "File not found: /cloudflare/credentials.ini"
- **Solution**: Verify credentials directory is mounted correctly

**Certificate Not Due for Renewal**
- **Symptom**: "Certificate not due for renewal"
- **Solution**: Normal if certificate is valid for >30 days

### Preview Environment Scripts

Scripts for managing preview environments in pull requests.

**Scripts:**
- `allocate_port.sh` - Allocates unique ports for preview deployments
- `pr_comment.sh` - Adds comments to PRs with preview URLs

**Usage:**
These scripts are automatically called by the preview pipeline stages.

### SonarQube Integration

- **`import-docker-scout-to-sonar.sh`** - Converts Docker Scout SARIF reports to SonarQube format
- Imports security vulnerabilities into SonarQube analysis
- Automatically runs in quality gate stages

### Utility Scripts

Shared utility functions used across all pipeline scripts.

#### `lib.sh`

Common logging and utility functions.

**Functions:**
- `log_info()` - Log informational messages
- `log_warn()` - Log warning messages
- `log_error()` - Log error messages
- `retry()` - Retry a command with exponential backoff
- `require_vars()` - Validate required variables are set

**Usage:**
```bash
source "$(dirname "${BASH_SOURCE[0]}")/../utils/lib.sh"
log_info "Starting process..."
require_vars BITBUCKET_WORKSPACE BITBUCKET_REPO_SLUG
```

#### `bitbucket-api.sh`

Bitbucket API integration for fetching deployment variables.

**Key Features:**
- **Opt-in by default**: Requires `USE_BITBUCKET_DEPLOYMENT_VARS=true`
- **Automatic fallback**: Falls back to traditional `VAR_<env>` environment variables
- **Bearer token auth**: Uses `BITBUCKET_ACCESS_TOKEN`
- **Environment-aware**: Automatically maps branches to deployment environments

**Functions:**
- `fetch_deployment_variables()` - Fetch deployment variables for an environment
- `get_build_args_with_api()` - Get build arguments with API or fallback to env vars
- `validate_api_credentials()` - Check if API credentials are available
- `test_api_connectivity()` - Test connection to Bitbucket API

**Configuration:**
1. Set repository variable: `USE_BITBUCKET_DEPLOYMENT_VARS=true`
2. Ensure `BITBUCKET_ACCESS_TOKEN` is configured
3. Add deployment variables in Repository Settings → Deployments

**Usage:**
```bash
source "shared-pipelines/scripts/utils/bitbucket-api.sh"
BUILD_ARGS=$(get_build_args_with_api "dev")
```

**Default Behavior:**
- `USE_BITBUCKET_DEPLOYMENT_VARS` defaults to `false`
- Existing repositories continue using environment variables
- No breaking changes for current consumers
- Opt-in migration path for new functionality

See [BITBUCKET-DEPLOYMENT-API.md](../BITBUCKET-DEPLOYMENT-API.md) for detailed documentation.

### Development & Validation Scripts

Scripts for developing and testing shared pipeline features.

#### `validate-integration.sh`

Quick integration test for the Bitbucket Deployment Variables API feature.

**Tests:**
- Fallback method functionality
- Environment mapping logic
- Build script integration

**Usage:**
```bash
./scripts/dev/validate-integration.sh
```

#### `validate-bitbucket-api.sh`

Comprehensive validation script for the Bitbucket API utilities.

**Tests:**
- Function definitions
- Credential validation
- Build args conversion
- API connectivity (if credentials available)

**Usage:**
```bash
./scripts/dev/validate-bitbucket-api.sh
```

**Purpose:**
Located in `scripts/dev/` to avoid confusion with pipeline test scripts in `scripts/test/` (which run actual tests in CI/CD).

## Environment Variables

### Required (set in Bitbucket)

**DNS Configuration:**
- `INTERNAL_DNS_SERVER` - Internal BIND DNS server
- `INTERNAL_DNS_TSIG_KEY_NAME` - TSIG key name for DNS updates
- `INTERNAL_DNS_TSIG_KEY` - TSIG key value
- `CLOUDFLARE_API_TOKEN` - Cloudflare API token
- `CLOUDFLARE_ACCOUNT_ID` - Cloudflare account ID

**Docker Hub:**
- `DOCKERHUB_USERNAME` - Docker Hub username
- `DOCKERHUB_TOKEN` - Docker Hub access token
- `DOCKERHUB_ORGNAME` - Docker Hub organization name

**Bitbucket API:**
- `BITBUCKET_ACCESS_TOKEN` - OAuth token for API calls

**Certificates:**
- `DOMAIN_NAME` - Base domain (e.g., example.com)
- `FQDN` - Fully qualified domain name

### Optional

**Certificate Management:**
- `CERTBOT_EMAIL` - Email for Let's Encrypt registration
- `CERTBOT_STAGING` - Set to "1" for staging environment
- `CERTBOT_FORCE_PROD` - Set to "1" to force production certificates

**Bitbucket Deployment Variables:**
- `USE_BITBUCKET_DEPLOYMENT_VARS` - Enable Deployment Variables API (default: false)

**See [Main README](../README.md) for complete variable documentation.**

## Quick Reference

### Essential Commands

**Certificate Management:**
```bash
# Check certificates
docker run --rm -v /etc/letsencrypt:/etc/letsencrypt certbot/dns-cloudflare certificates

# Test renewal
docker run --rm \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/log/letsencrypt:/var/log/letsencrypt \
  -v /etc/letsencrypt/cloudflare:/cloudflare \
  certbot/dns-cloudflare renew --dry-run --no-random-sleep-on-renew

# Check expiry
openssl x509 -in /etc/letsencrypt/live/internal.example.com/cert.pem -noout -dates
```

### File Locations

**Certificates:**
- `/etc/letsencrypt/live/internal.example.com/` - Certificate files
- `/etc/letsencrypt/cloudflare/credentials.ini` - Cloudflare credentials
- `/var/log/letsencrypt/letsencrypt.log` - Certificate logs

### Design Principles

1. **Backward Compatibility**: New features default to off; existing workflows unaffected
2. **Opt-In Migration**: Consumers can adopt new features via repository variables
3. **Graceful Degradation**: Always fall back to working methods
4. **Clear Logging**: Log actions and decisions for debugging
5. **Reusability**: Functions designed for use across multiple scripts

## Related Documentation

- [Main README](../README.md) - Complete pipeline documentation
- [BITBUCKET-DEPLOYMENT-API.md](../BITBUCKET-DEPLOYMENT-API.md) - Deployment Variables API setup
