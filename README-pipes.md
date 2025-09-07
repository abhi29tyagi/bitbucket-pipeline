# Future: Docker-based Bitbucket Pipes

This document outlines how to migrate YAML components into versioned Bitbucket Pipes for maximum reuse and cleanliness.

## Why Pipes?
- Versioned, shareable components across repos
- Cleaner `bitbucket-pipelines.yml` (each step is a `pipe:` call)
- Independent testing and documentation

## Suggested Pipes
- `nodejs-install` (NPM_COMMAND)
- `nodejs-test` (TEST_COMMAND)
- `sonarqube-analysis` (SONAR_PROJECT_KEY)
- `docker-build` (DOCKER_IMAGE_NAME)
- `docker-scout` (DOCKER_IMAGE_NAME)
- `docker-promote` (FROM_TAG, TO_TAG)
- `docker-deploy` (DOCKER_IMAGE_NAME, ENVIRONMENT, DEPLOY_HOST)

## Example Usage
```yaml
pipelines:
  default:
    - step:
        name: Install
        script:
          - pipe: your-org/nodejs-install:1.0.0
            variables:
              NPM_COMMAND: 'ci'
```

## Migration Steps
1. Create `shared-pipes` repo with one folder per pipe (`pipes/<pipe-name>`).
2. Implement pipe logic and README per pipe.
3. Tag versions (e.g., `1.0.0`).
4. Replace YAML anchors with `pipe:` calls gradually.
