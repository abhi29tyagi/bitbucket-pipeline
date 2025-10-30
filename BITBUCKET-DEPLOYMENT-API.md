# Bitbucket Deployment Variables API Integration

This guide explains how to use the **optional** Bitbucket Deployment Variables API integration in your shared pipelines to centralize environment-specific build configuration.

## Overview

**Important**: This feature is **opt-in** via repository variables. By default (`USE_BITBUCKET_DEPLOYMENT_VARS=false`), all repositories continue using the existing environment variable method. **No changes are required for existing consumers.**

### What This Enables

Instead of managing environment variables with suffixes like `VAR_dev`, `VAR_prod` in your pipeline configuration, you can opt-in to store these variables as Deployment Variables in your Bitbucket repository and fetch them dynamically during the build process.

## Benefits

- **Centralized Configuration**: Environment variables are stored in your consumer repository, not in pipeline configuration
- **Dynamic Updates**: Change deployment variables without updating pipeline configuration
- **Environment-Specific**: Each environment (dev, prod, uat, preview) has its own set of variables
- **Secure**: Supports secured variables that won't be logged
- **Backward Compatible**: Falls back to the existing environment variable method

## Configuration

**Important**: This feature is **opt-in** and defaults to `false` in the shared pipeline. Existing consumers continue working without any changes.

### 1. Enable the Feature (Opt-In)

To enable the Bitbucket Deployment Variables integration, set this as a **repository variable** in your consumer repository:

**Repository Settings → Repository variables:**
```
USE_BITBUCKET_DEPLOYMENT_VARS = true
```


### 2. Authentication (Already Available)

Make sure the required access token is already configured in **Workspace variables** with required scope. No additional setup needed.

### 3. Repository Information

These variables are automatically available in Bitbucket Pipelines:
- `BITBUCKET_WORKSPACE` - Your workspace name
- `BITBUCKET_REPO_SLUG` - Your repository slug

## Setting Up Deployment Variables in Bitbucket

1. Go to your repository in Bitbucket
2. Navigate to **Repository settings** → **Deployments**
3. Create or edit an environment (e.g., `dev`, `prod`, `uat`, `preview`)
4. Add deployment variables with the names you want to use as build arguments

### Example Deployment Variables

For `dev` environment:
- `API_URL` = `https://api-dev.yourcompany.com`
- `DATABASE_URL` = `postgres://dev-db.yourcompany.com`
- `FEATURE_FLAGS` = `dev-features`

For `prod` environment:
- `API_URL` = `https://api.yourcompany.com`
- `DATABASE_URL` = `postgres://prod-db.yourcompany.com`
- `FEATURE_FLAGS` = `prod-features`

For `preview` environment (includes cross-repo peer URLs):
- `API_BASE_URL` = `https://preview-api.example.com`
- `FEATURE_FLAGS` = `debug,experimental`
- `PEER_HOST_URLS` = `VITE_API_BASE_URL.backend-api,VITE_AUTH_URL.auth-service`

**Note**: With deployment variables, ALL preview configuration (including `PEER_HOST_URLS` for cross-repo previews) can be centralized in the preview deployment environment!

## Environment Mapping

The build script determines the target environment based on:

- **Preview/PR builds**: Uses `preview` environment
- **Develop/dev branch**: Uses `dev` environment  
- **Release branches**: Uses `uat` environment
- **Main branch**: Uses `prod` environment
- **Hotfix branches**: Uses `prod` environment (forced)

You can override this by setting `TARGET_ENV` or `ENVIRONMENT` variables.

## Migration Guide

**Note**: Migration is **completely optional**. Existing repositories continue working without any changes.

### Current Method (Continues to Work)
Set repository variables with environment suffixes:
- `API_URL_dev=https://api-dev.yourcompany.com`
- `DATABASE_URL_dev=postgres://dev-db.yourcompany.com`

### New Method (Opt-In via Repository Variable)

**Step 1**: Add `USE_BITBUCKET_DEPLOYMENT_VARS = true` in Repository Settings → Repository variables

**Step 2**: Add deployment variables in Repository Settings → Deployments → dev environment:
- `API_URL` = `https://api-dev.yourcompany.com`
- `DATABASE_URL` = `postgres://dev-db.yourcompany.com`

The build script automatically detects the repository variable and fetches deployment variables from the API.

## Testing the Integration

You can validate the API integration using the provided validation script:

```bash
# Run the integration validation
./shared-pipelines/scripts/dev/validate-integration.sh
```

Or test individual API functions:

```bash
# Source the utilities
source shared-pipelines/scripts/utils/bitbucket-api.sh

# Test API connectivity
test_api_connectivity

# Fetch variables for a specific environment
fetch_deployment_variables "your-workspace" "your-repo" "dev"
```

## Troubleshooting

### Common Issues

1. **Authentication Failed (401/403)**
   - Verify your access token is correct and not expired
   - Ensure the token has the required repository permissions
   - Check that the token is properly set in your pipeline variables

2. **No Variables Found (404)**
   - Verify the environment name exists in your repository's deployment settings
   - Check that deployment variables are added to the correct environment
   - Environment names are case-sensitive

3. **API Connection Failed (000)**
   - Check network connectivity
   - Verify the Bitbucket API is accessible from your build environment

### Debugging

Enable verbose logging by setting:
```yaml
DEBUG_BITBUCKET_API: "true"
```

### Fallback Behavior

If the API integration fails, the system automatically falls back to the existing environment variable method. You'll see a warning message in the build logs.

## Security Considerations

1. **Use Secured Variables**: Always mark the access token as secured in your pipeline configuration
2. **Limit Permissions**: Access tokens should only have the minimum required repository permissions
3. **Secured Deployment Variables**: Variables marked as "secured" in Bitbucket deployment settings are **not accessible via the API** and will be skipped. 
4. **Token Rotation**: Regularly rotate your access tokens for security
5. **Build-Time Variables**: Build arguments get baked into static assets and are not truly secret. Only use non-sensitive configuration (URLs, feature flags, etc.) in deployment variables for builds.

## API Rate Limits

The Bitbucket API has rate limits. The integration includes retry logic with exponential backoff to handle temporary failures.

## Usage

**For Repositories Using API Integration (Opt-In)**:
1. Set `USE_BITBUCKET_DEPLOYMENT_VARS = true` in Repository Settings → Repository variables
2. Configure deployment variables in Repository Settings → Deployments → [environment]
3. **Note**: Secured deployment variables are not accessible via API - use repository variables for sensitive data

**For Repositories Using Traditional Method (Default)**:
No changes needed! Your existing pipelines continue to work with repository variables like `API_URL_dev`, `DATABASE_URL_dev`, etc.
