# Shared Pipelines Scripts

This directory contains shared scripts used by the pipelines. It is organized by responsibility.

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
│   ├── pr_comment.sh           # Adds PR comment with preview URL
│   └── nginx/
│       ├── certbot_cloudflare.sh           # Initial cert setup
│       ├── certbot_cloudflare_renew.sh     # Cert renewal + cron
│       ├── nginx_common.sh                 # Shared nginx functions
│       ├── nginx_enable_site.sh            # Enable preview site
│       ├── nginx_disable_site.sh           # Disable preview site
│       └── preview-proxy.conf              # Nginx template
├── sonar/
│   └── import-docker-scout-to-sonar.sh    # Converts Scout SARIF to Sonar format
└── utils/
    └── lib.sh                             # Logging, retries, error handling
```

## Key Scripts

### Lint/Test/Build (Auto-detect)
- Called by smart wrapper steps in pipeline
- Auto-detect Node.js vs Python based on project files
- Handle dependency installation, execution, and reporting

### DNS Management
- **dns_create.sh / dns_delete.sh**: Route to Cloudflare or Internal DNS based on `ENVIRONMENT`
- **Cloudflare**: Public DNS for prod frontends
- **Internal BIND**: Private DNS for dev/UAT/admin panels
- **setup_tunnel.sh**: Automates Cloudflare Named Tunnel creation via API

### Traefik & Certificates
- **certbot_cloudflare.sh**: Initial wildcard cert setup
- **certbot_cloudflare_renew.sh**: Renewal + cron installation (stable paths)

### Utilities
- **lib.sh**: Shared functions for logging, retries, and error handling

## Environment Variables

**Required (set in Bitbucket):**
- `INTERNAL_DNS_SERVER`, `INTERNAL_DNS_TSIG_KEY_NAME`, `INTERNAL_DNS_TSIG_KEY`
- `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`
- `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `DOCKERHUB_ORGNAME`

**See [Main README](../README.md) for complete variable documentation.**
