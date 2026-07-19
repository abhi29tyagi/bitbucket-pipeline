# Utility Scripts

This directory contains reusable utility functions for shared pipeline operations.

## Files

### `lib.sh`
Common logging and utility functions used across all pipeline scripts.

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

### `bitbucket-api.sh`
Bitbucket API integration for fetching deployment variables.

**Key Features:**
- **Opt-in by default**: Requires `USE_BITBUCKET_DEPLOYMENT_VARS=true` repository variable
- **Automatic fallback**: Falls back to traditional `VAR_<env>` environment variables
- **Bearer token auth**: Uses `BITBUCKET_ACCESS_TOKEN` (same as PR comments)
- **Environment-aware**: Automatically maps branches to deployment environments

**Functions:**
- `fetch_deployment_variables()` - Fetch deployment variables for an environment
- `get_build_args_with_api()` - Get build arguments with API or fallback to env vars
- `validate_api_credentials()` - Check if API credentials are available
- `test_api_connectivity()` - Test connection to Bitbucket API

**Configuration:**
The feature is **disabled by default** to ensure backward compatibility. To enable:

1. Set repository variable: `USE_BITBUCKET_DEPLOYMENT_VARS = true`
2. Ensure `BITBUCKET_ACCESS_TOKEN` is configured
3. Add deployment variables in Repository Settings → Deployments

**Usage:**
```bash
# Automatically used by build-node.sh
source "shared-pipelines/scripts/utils/bitbucket-api.sh"
BUILD_ARGS=$(get_build_args_with_api "dev")
```

**Default Behavior:**
- `USE_BITBUCKET_DEPLOYMENT_VARS` defaults to `false`
- Existing repositories continue using environment variables
- No breaking changes for current consumers
- Opt-in migration path for new functionality

See [BITBUCKET-DEPLOYMENT-API.md](../../BITBUCKET-DEPLOYMENT-API.md) for detailed documentation.

## Design Principles

1. **Backward Compatibility**: New features default to off; existing workflows unaffected
2. **Opt-In Migration**: Consumers can adopt new features via repository variables
3. **Graceful Degradation**: Always fall back to working methods
4. **Clear Logging**: Log actions and decisions for debugging
5. **Reusability**: Functions designed for use across multiple scripts
