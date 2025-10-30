# Development Scripts

This directory contains development and validation scripts for shared pipeline features.

## Files

### `validate-integration.sh`
Quick integration test for the Bitbucket Deployment Variables API feature. Tests:
- Fallback method functionality
- Environment mapping logic  
- Build script integration

Usage:
```bash
./scripts/dev/validate-integration.sh
```

### `validate-bitbucket-api.sh`  
Comprehensive validation script for the Bitbucket API utilities. Tests:
- Function definitions
- Credential validation
- Build args conversion
- API connectivity (if credentials available)

Usage:
```bash
./scripts/dev/validate-bitbucket-api.sh
```

## Purpose

These scripts are located in `scripts/dev/` to avoid confusion with the actual pipeline test stage scripts in `scripts/test/` (which contain `test-node.sh` and `test-python.sh` for running tests in CI/CD pipelines).

## Related Documentation

See [BITBUCKET-DEPLOYMENT-API.md](../../BITBUCKET-DEPLOYMENT-API.md) for complete setup and usage instructions for the Bitbucket Deployment Variables API integration.
