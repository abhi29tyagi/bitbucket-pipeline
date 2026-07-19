# Traefik SSL Certificate Management

Scripts for managing SSL certificates with Traefik using Let's Encrypt and Cloudflare DNS challenges.

## 📁 Files

- **`certbot_cloudflare.sh`** - Obtain wildcard certificates using Cloudflare DNS
- **`certbot_cloudflare_renew.sh`** - Automated certificate renewal

## 🔧 Prerequisites

### Required Variables:
- `CLOUDFLARE_API_TOKEN` - Cloudflare API token with DNS:Edit permissions
- `DOMAIN_NAME` - Base domain (e.g., homnifi.com)
- `FQDN` - Fully qualified domain name (e.g., internal.homnifi.com)

### Optional Variables:
- `CERTBOT_EMAIL` - Email for Let's Encrypt registration
- `CERTBOT_STAGING` - Set to "1" for staging environment
- `CERTBOT_FORCE_PROD` - Set to "1" to force production certificates

## 🚀 Pipeline Integration

These scripts are designed to run within Bitbucket Pipeline stages:

### Initial Traefik Setup
```bash
# Pipeline stage will call:
./certbot_cloudflare.sh
```

### Automated Renewal
```bash
# Pipeline stage will call:
./certbot_cloudflare_renew.sh
```

## 🔍 Pipeline Debug Commands

### Check Certificate Status
```bash
# List certificates
docker run --rm -v /etc/letsencrypt:/etc/letsencrypt certbot/dns-cloudflare certificates

# Check specific certificate
docker run --rm -v /etc/letsencrypt:/etc/letsencrypt certbot/dns-cloudflare certificates --cert-name internal.homnifi.com
```

### Test Certificate Renewal
```bash
# Dry run (safe test)
docker run --rm \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/log/letsencrypt:/var/log/letsencrypt \
  -v /etc/letsencrypt/cloudflare:/cloudflare \
  certbot/dns-cloudflare renew --dry-run --no-random-sleep-on-renew
```

### Check Certificate Expiry
```bash
# Check expiry
openssl x509 -in /etc/letsencrypt/live/internal.homnifi.com/cert.pem -noout -dates

# Test HTTPS
curl -I https://internal.homnifi.com
```

## 🐳 Docker Commands

### Renew Certificates
```bash
# Renew all certificates
docker run --rm \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/log/letsencrypt:/var/log/letsencrypt \
  -v /etc/letsencrypt/cloudflare:/cloudflare \
  certbot/dns-cloudflare renew

# Renew specific certificate
docker run --rm \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/log/letsencrypt:/var/log/letsencrypt \
  -v /etc/letsencrypt/cloudflare:/cloudflare \
  certbot/dns-cloudflare renew --cert-name internal.homnifi.com
```

### Create New Certificate
```bash
# Create wildcard certificate
docker run --rm \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /etc/letsencrypt/cloudflare:/cloudflare \
  certbot/dns-cloudflare certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /cloudflare/credentials.ini \
  -d "*.internal.homnifi.com" \
  -d "internal.homnifi.com"
```

## 🚨 Common Issues

### Missing Cloudflare Credentials
**Error**: "File not found: /cloudflare/credentials.ini"

**Solution**: Mount credentials directory
```bash
# Check credentials exist
ls -la /etc/letsencrypt/cloudflare/credentials.ini

# Test with proper mounts
docker run --rm \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/log/letsencrypt:/var/log/letsencrypt \
  -v /etc/letsencrypt/cloudflare:/cloudflare \
  certbot/dns-cloudflare renew --dry-run --no-random-sleep-on-renew
```

### Certificate Not Due for Renewal
**Symptom**: "Certificate not due for renewal"

**Solution**: Normal if certificate is valid for >30 days
```bash
# Check expiry
openssl x509 -in /etc/letsencrypt/live/internal.homnifi.com/cert.pem -noout -dates
```

## 📋 Quick Reference

### Essential Commands
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
openssl x509 -in /etc/letsencrypt/live/internal.homnifi.com/cert.pem -noout -dates
```

### File Locations
- **Certificates**: `/etc/letsencrypt/live/internal.homnifi.com/`
- **Credentials**: `/etc/letsencrypt/cloudflare/credentials.ini`
- **Logs**: `/var/log/letsencrypt/letsencrypt.log`
