# Shared Pipelines (Reference)

Purpose: Keep pipeline logic abstracted and reusable. Copy these files into your dedicated `shared-pipelines` repository.

## Files
- `bitbucket-pipelines.yml`: Reusable Bitbucket Pipeline steps via YAML anchors (install, lint, test, SonarQube with quality gate, Docker build, Docker Scout, promote to UAT/Prod, deploy to Dev/UAT/Prod, preview deploy/teardown).
- `scripts/`: Shared scripts for Cloudflare DNS, Internal DNS (BIND), Nginx, Preview, CI utilities.

## How to Use (in application repos)
1. Keep your repo pipeline minimal, referencing the shared components (by copy or future include strategy).
2. See demo repository for a working example: [Demo Bitbucket repo](https://bitbucket.org/protocol33/test-ab)
3. Create self-hosted runners with the expected tags (below).

## Runner Tags (Create these on your runners)

**Workspace level** (already exist):
- `common.ci` &mdash; CI steps: install, lint, test, sonar, build, scout
- `preview.runner`

**Repository level** (to do):
- `dev.runner`
- `uat.runner`
- `prod.runner`

## Branch Logic (recommended)
- develop: SonarQube → Build → Docker Scout → Deploy Dev
- release/*: SonarQube → Promote latest→uat → Docker Scout → Deploy UAT
- main: SonarQube → Promote uat→production → Docker Scout (manual deploy)
- pull-requests: Install → Lint → Test → Sonar → Build → Scout → Preview deploy

## Environment Variables

Workspace variables (shared across repos):
- Shared Pipelines: `SHARED_PIPELINES_REPO` (default: `your-workspace/shared-pipelines`), `SHARED_PIPELINES_BRANCH` (default: `master`)
- SonarQube: `SONAR_HOST_URL`, `SONAR_TOKEN`, `SONAR_PROJECT_KEY`
- DockerHub: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `DOCKERHUB_ORGNAME`
- Preview comments (optional): `BITBUCKET_USERNAME`, `BITBUCKET_APP_PASSWORD` (API token)
- Cloudflare (prod + uat DNS):
  - Required: `CLOUDFLARE_API_TOKEN`
  - Global defaults (optional): `CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_DOMAIN`
  - Per-environment overrides (recommended, per repo):
    - Production: `CF_PROD_ZONE_ID`, `CF_PROD_DOMAIN`
    - UAT: `CF_UAT_ZONE_ID`, `CF_UAT_DOMAIN`
- Internal DNS (dev + preview DNS):
  - `INTERNAL_DNS_SERVER`, `INTERNAL_DNS_ZONE`, `INTERNAL_DNS_TSIG_KEY_NAME`, `INTERNAL_DNS_TSIG_KEY`
  - `PREVIEW_TARGET_IP`

Repository variables (per app/repo as needed):
- Dev DNS overrides (optional, per target machine): `DEV_TARGET_IP`, `DEV_SUBDOMAIN`, `DEV_ZONE`
  - Note: Internal DNS zones can differ per repo (e.g., `dev.domain.internal`), set `DEV_ZONE` accordingly.

## DNS Routing
- Production, UAT → Cloudflare (public DNS)
- Development, Preview → Internal BIND (private DNS)

## Package Managers in CI
- Install/Test/Build: npm (`npm ci`, `npm run test:coverage`, `npm run build`)
- Lint: Yarn (`yarn lint`) via `corepack enable` in CI step
- No `yarn.lock` required in repo for this setup; npm installs dependencies


## Notes
- Docker images are named as: `$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:<tag>`
- Production compose file path: `deploy/docker-compose.prod.yml`
- Preview deploy posts PR comments if Bitbucket variables are set


