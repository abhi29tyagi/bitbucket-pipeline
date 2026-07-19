# OWASP ZAP Security Scanning Integration

## Overview

OWASP ZAP (Zed Attack Proxy) is a dynamic application security testing (DAST) tool that scans running web applications for security vulnerabilities. This integration allows you to automatically scan your deployed applications (both frontend and backend) and publish results to SonarQube.

## Features

- ✅ **Dynamic Application Scanning**: Scans running applications at runtime
- ✅ **Frontend & Backend Support**: Works with any HTTP/HTTPS endpoint
- ✅ **Multiple Report Formats**: HTML, JSON, XML, and SARIF
- ✅ **SonarQube Integration**: Automatically converts results to SonarQube format
- ✅ **Configurable Alert Levels**: Control build failure based on severity
- ✅ **Spider + Active Scanning**: Comprehensive security testing

## When to Use

- **After Deployment**: Run ZAP scans after your application is deployed to DEV, UAT, or PROD
- **Frontend Applications**: Scan React, Vue, Angular, Next.js, or any static site
- **Backend APIs**: Scan REST APIs, GraphQL endpoints, or any HTTP service
- **Integration Testing**: Include in your CI/CD pipeline for continuous security testing

## Requirements

1. **Target URL**: The application must be deployed and accessible via HTTP/HTTPS
2. **Docker**: ZAP runs in a Docker container
3. **Network Access**: Runner must be able to access the target URL
4. **SonarQube** (optional): For publishing results

## Configuration Variables

### Required

- `TARGET_URL`: The URL to scan (e.g., `https://api.example.com` or `https://app.example.com`)

### Optional

- `ZAP_IMAGE`: ZAP Docker image (default: `ghcr.io/zaproxy/zaproxy:stable`)
- `ZAP_PORT`: Port for ZAP API (default: `8080`)
- `ZAP_TIMEOUT`: Scan timeout in seconds (default: `300` = 5 minutes)
- `ZAP_ALERT_LEVEL`: Minimum severity to fail build - `High`, `Medium`, `Low`, or `Informational` (default: `Medium`)
- `ZAP_CONTEXT_NAME`: Context name for ZAP (default: `Application`)
- `ENABLE_ZAP_SCAN`: Enable/disable ZAP scanning (default: `false`)

## Usage Examples

### 1. Basic Scan (Manual Step)

Add to your pipeline after deployment:

```yaml
- step:
    name: 🔒 OWASP ZAP Security Scan
    deployment: uat  # or dev, prod
    script:
      - |
        TARGET_URL="${DOMAIN_NAME_UAT:-https://uat-api.example.com}"
        export TARGET_URL
        
        if [ -d "shared-pipelines" ]; then
          git clone git@bitbucket.org:protocol33/shared-pipelines.git || true
        fi
        
        chmod +x shared-pipelines/scripts/security/zap-scan.sh
        bash shared-pipelines/scripts/security/zap-scan.sh
    artifacts:
      - zap-report.html
      - zap-report.json
      - zap-report.sarif
```

### 2. Scan with SonarQube Integration

```yaml
- step:
    name: 🔒 OWASP ZAP Security Scan
    deployment: uat
    script:
      - |
        TARGET_URL="${DOMAIN_NAME_UAT:-https://uat-api.example.com}"
        export TARGET_URL
        ZAP_ALERT_LEVEL="Medium"  # Fail on High or Medium
        export ZAP_ALERT_LEVEL
        
        # Run ZAP scan
        chmod +x shared-pipelines/scripts/security/zap-scan.sh
        bash shared-pipelines/scripts/security/zap-scan.sh
        
        # Convert to SonarQube format
        chmod +x shared-pipelines/scripts/security/zap-import-to-sonar.sh
        bash shared-pipelines/scripts/security/zap-import-to-sonar.sh
    artifacts:
      - zap-report.sarif
      - sonar-issues-zap.json
```

### 3. Frontend Application Scan

```yaml
- step:
    name: 🔒 ZAP Scan Frontend
    deployment: preview
    script:
      - |
        # Load .env to get PREVIEW_DOMAIN or construct URL
        [ -f .env ] && set -a && . ./.env && set +a
        
        TARGET_URL="https://${PREVIEW_SLUG}.internal.${PREVIEW_DOMAIN_NAME}"
        export TARGET_URL
        ZAP_TIMEOUT="600"  # 10 minutes for frontend (more pages)
        export ZAP_TIMEOUT
        
        chmod +x shared-pipelines/scripts/security/zap-scan.sh
        bash shared-pipelines/scripts/security/zap-scan.sh
```

### 4. Backend API Scan

```yaml
- step:
    name: 🔒 ZAP Scan Backend API
    deployment: uat
    script:
      - |
        TARGET_URL="https://${DOMAIN_NAME_UAT}"
        export TARGET_URL
        ZAP_ALERT_LEVEL="High"  # Only fail on High severity
        ZAP_TIMEOUT="480"  # 8 minutes
        export ZAP_ALERT_LEVEL ZAP_TIMEOUT
        
        chmod +x shared-pipelines/scripts/security/zap-scan.sh
        bash shared-pipelines/scripts/security/zap-scan.sh
```

## Integration with Existing Pipeline

**Important**: ZAP scans run AFTER deployment (since the app must be running). This means they run AFTER the SonarQube scan step. Use `zap-upload-to-sonar.sh` to upload results separately.

### Option 1: Add to Deployment Step (After Deployment Completes)

Modify `&deploy-uat` or `&deploy-prod` to include ZAP scan after deployment:

```yaml
script:
  - |
    # ... existing deployment code ...
    
    # Wait for application to be ready
    sleep 30
    
    # Run ZAP scan if enabled
    if [ "${ENABLE_ZAP_SCAN:-false}" = "true" ]; then
      TARGET_URL="https://${DOMAIN_NAME_UAT}"
      export TARGET_URL
      
      if [ -d "shared-pipelines" ]; then
        git clone git@bitbucket.org:protocol33/shared-pipelines.git || true
      fi
      
      chmod +x shared-pipelines/scripts/security/zap-scan.sh
      bash shared-pipelines/scripts/security/zap-scan.sh || {
        echo "WARNING: ZAP scan failed, continuing..."
      }
    fi
```

### Option 2: Separate Step (Recommended)

Add a new step after deployment:

```yaml
- step: &zap-scan-uat
    name: 🔒 OWASP ZAP Security Scan (UAT)
    clone:
      enabled: false
    deployment: uat
    trigger: manual  # or automatic
    runs-on:
      - self.hosted
      - linux.shell
    script:
      - |
        # Restore artifacts if needed
        if [ -d ".consumer-repo-snapshot" ]; then
          rsync -a .consumer-repo-snapshot/ ./
          rm -rf .consumer-repo-snapshot
        fi
        
        if [ -d "shared-pipelines" ]; then
          git clone git@bitbucket.org:protocol33/shared-pipelines.git || true
        fi
        
        # Load .env for environment variables
        [ -f .env ] && set -a && . ./.env && set +a
        
        # Set target URL
        TARGET_URL="https://${DOMAIN_NAME_UAT}"
        export TARGET_URL
        ZAP_ALERT_LEVEL="${ZAP_ALERT_LEVEL:-Medium}"
        export ZAP_ALERT_LEVEL
        
        # Run ZAP scan
        chmod +x shared-pipelines/scripts/security/zap-scan.sh
        bash shared-pipelines/scripts/security/zap-scan.sh
        
        # Import to SonarQube
        chmod +x shared-pipelines/scripts/security/zap-import-to-sonar.sh
        bash shared-pipelines/scripts/security/zap-import-to-sonar.sh
    artifacts:
      - zap-report.html
      - zap-report.json
      - zap-report.sarif
      - sonar-issues-zap.json
```

## SonarQube Integration

### Step 1: Import ZAP Results

The `zap-import-to-sonar.sh` script converts ZAP SARIF results to SonarQube Generic External Issues format (`sonar-issues-zap.json`).

### Step 2: Publish to SonarQube

In your SonarQube scan step, import the ZAP issues:

```yaml
- step:
    name: 📊 SonarQube Analysis
    script:
      - |
        # ... existing SonarQube setup ...
        
        # Import ZAP results if available
        if [ -f "sonar-issues-zap.json" ]; then
          echo "Importing ZAP security findings to SonarQube..."
          # SonarQube will automatically pick up sonar-issues-zap.json
        fi
        
        # Run SonarQube scan
        sonar-scanner -Dsonar.externalIssuesReportPaths=sonar-issues-zap.json ...
```

### Step 3: Configure SonarQube

In SonarQube, ensure "Generic Issue Import" is enabled for your project. The issues will appear as external issues with the engine ID `zap`.

## Scan Types

### Spider Scan (Crawling)

- Discovers all URLs/pages in your application
- Follows links automatically
- Maps the application structure

### Active Scan (Security Testing)

- Tests discovered URLs for vulnerabilities
- Includes SQL injection, XSS, CSRF, and more
- Can take 5-30 minutes depending on application size

## Performance Considerations

- **Frontend Applications**: Can take 10-30 minutes (many pages)
- **Backend APIs**: Usually 5-15 minutes (fewer endpoints)
- **Large Applications**: Increase `ZAP_TIMEOUT` accordingly
- **Resource Usage**: ZAP uses CPU and memory; ensure runner has capacity

## Security Best Practices

1. **Scan in Staging First**: Don't scan production directly without testing
2. **Use Whitelists**: Configure ZAP to only scan specific paths
3. **Rate Limiting**: Be aware of application rate limits
4. **Authentication**: If your app requires auth, configure ZAP context
5. **Sensitive Data**: Don't scan endpoints with sensitive PII/PHI

## Troubleshooting

### ZAP fails to start

- Check Docker is running: `docker ps`
- Check port availability: `netstat -tuln | grep 8080`
- Review logs: `docker logs <zap-container-name>`

### Scan times out

- Increase `ZAP_TIMEOUT`
- Reduce scan scope (use context to limit URLs)
- Check network connectivity to target URL

### No results in SonarQube

- Verify `sonar-issues-zap.json` is generated
- Check SonarQube Generic Issue Import is enabled
- Ensure SARIF format is correct: `jq . zap-report.sarif`

### False Positives

- Review and tune ZAP alert filters
- Use ZAP context to exclude known false positives
- Adjust `ZAP_ALERT_LEVEL` to ignore lower severity

## Examples by Environment

### Development

```yaml
ENABLE_ZAP_SCAN=true
ZAP_ALERT_LEVEL=High  # Don't fail on medium/low
TARGET_URL=https://dev-api.example.com
```

### UAT

```yaml
ENABLE_ZAP_SCAN=true
ZAP_ALERT_LEVEL=Medium  # Fail on high/medium
TARGET_URL=https://uat-api.example.com
```

### Production

```yaml
ENABLE_ZAP_SCAN=true
ZAP_ALERT_LEVEL=High  # Only fail on critical issues
TARGET_URL=https://api.example.com
```

## Report Formats

- **zap-report.html**: Human-readable HTML report (best for manual review)
- **zap-report.json**: Detailed JSON with all findings and metadata
- **zap-report.xml**: XML format for CI/CD tools
- **zap-report.sarif**: SARIF format for SonarQube and other tools

## Further Reading

- [OWASP ZAP Documentation](https://www.zaproxy.org/docs/)
- [ZAP API Documentation](https://www.zaproxy.org/docs/api/)
- [SARIF Specification](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning)
- [SonarQube External Issues](https://docs.sonarsource.com/sonarqube/latest/analyzing-source-code/importing-external-issues/)

