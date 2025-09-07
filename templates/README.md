# Pipeline Templates

This directory contains reusable pipeline templates that can be extended and customized for specific projects.

## Template Categories

### Build Templates
- `build/` - Templates for building applications
- `test/` - Templates for running tests
- `deploy/` - Templates for deployment workflows

### Language-Specific Templates
- `nodejs/` - Node.js application pipelines
- `python/` - Python application pipelines
- `java/` - Java application pipelines
- `dotnet/` - .NET application pipelines

### Platform-Specific Templates
- `kubernetes/` - Kubernetes deployment templates
- `docker/` - Docker build and push templates
- `aws/` - AWS deployment templates

## Using Templates

1. Copy the template file to your project
2. Replace placeholder values with your specific configuration
3. Customize the workflow as needed for your use case

## Template Variables

Templates use the following common variables:
- `{{PROJECT_NAME}}` - Your project name
- `{{BRANCH_NAME}}` - Git branch name
- `{{ENVIRONMENT}}` - Deployment environment
- `{{REGISTRY_URL}}` - Container registry URL
