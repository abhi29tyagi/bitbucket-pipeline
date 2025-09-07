# Pipeline Configurations

This directory contains ready-to-use pipeline configuration files for different CI/CD platforms.

## Available Configurations

### Bitbucket
- `bitbucket/` - Bitbucket pipeline files

### Jenkins
- `jenkins/` - Jenkins pipeline files

### Azure DevOps
- `azure-devops/` - Azure DevOps pipeline YAML files

## Usage

Copy the relevant configuration files to your project and customize them as needed for your specific requirements.

## Naming Convention

Pipeline files should follow this naming pattern:
- `{platform}-{purpose}-{environment}.yml` (e.g., `github-actions-build-production.yml`)
- `{platform}-{purpose}.yml` (e.g., `gitlab-ci-test.yml`)
