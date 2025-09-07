# Shared Pipelines Scripts

This directory contains shared scripts used by the pipelines. It is organized by responsibility.

## Structure

```
scripts/
├── dns/
│   ├── dns_create.sh           # Dispatcher: creates DNS record (Cloudflare for prod/uat, Internal BIND for dev/preview)
│   ├── dns_delete.sh           # Dispatcher: deletes DNS record
│   ├── cloudflare/
│   │   ├── cf_create_dns.sh
│   │   └── cf_delete_dns.sh
│   └── internal/
│       ├── internal_dns_create.sh
│       └── internal_dns_delete.sh
├── preview/
│   ├── nginx/
│   │   ├── install_or_update_preview_proxy.sh   # Installs nginx and preview proxy template
│   │   ├── nginx_enable_site.sh                 # Generates per-host config for preview-{PR}.<zone>
│   │   └── nginx_disable_site.sh                # Removes per-host config
│   ├── pr_comment.sh                            # Adds PR comment with preview URL (optional)
│   ├── preview_deploy.sh                        # (optional) standalone example deploy script
│   └── preview_teardown.sh                      # (optional) standalone teardown script
├── sonar/
│   └── import-docker-scout-to-sonar.sh          # Imports Docker Scout SARIF into Sonar (if used)
└── utils/
    └── lib.sh                                   # Logging, retries, error handling
```

## Environment Variables

- Internal DNS (dev/preview): `INTERNAL_DNS_SERVER`, `INTERNAL_DNS_ZONE`, `INTERNAL_DNS_TSIG_KEY_NAME`, `INTERNAL_DNS_TSIG_KEY`
- Cloudflare (prod/uat): `CLOUDFLARE_API_TOKEN`, optional: `CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_DOMAIN`, plus `CF_PROD_*` and `CF_UAT_*` overrides
- Preview/Nginx: `PREVIEW_PORT_BASE` (default 40000), `NGINX_SITES_AVAILABLE`, `NGINX_SITES_ENABLED`, `NGINX_RELOAD_CMD`

## Usage in Pipelines

- Setup preview Nginx (one-time per host):
```
INTERNAL_DNS_ZONE="$INTERNAL_DNS_ZONE" \
NGINX_SITES_AVAILABLE=/etc/nginx/sites-available \
NGINX_SITES_ENABLED=/etc/nginx/sites-enabled \
NGINX_RELOAD_CMD="sudo nginx -s reload" \
./shared-pipelines/scripts/preview/nginx/install_or_update_preview_proxy.sh
```

- Enable preview site after deploy:
```
INTERNAL_DNS_ZONE="$INTERNAL_DNS_ZONE" \
NGINX_SITES_AVAILABLE=/etc/nginx/sites-available \
NGINX_SITES_ENABLED=/etc/nginx/sites-enabled \
NGINX_RELOAD_CMD="sudo nginx -s reload" \
./shared-pipelines/scripts/preview/nginx/nginx_enable_site.sh
```

- DNS create/delete dispatchers:
```
ENVIRONMENT=preview ./shared-pipelines/scripts/dns/dns_create.sh
ENVIRONMENT=preview ./shared-pipelines/scripts/dns/dns_delete.sh
```

All scripts use `utils/lib.sh` for logging and robust error handling.
