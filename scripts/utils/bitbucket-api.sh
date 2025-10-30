#!/bin/bash
set -euo pipefail

# Source lib.sh for logging and utilities
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-$0}")"
source "${SCRIPT_DIR}/lib.sh"

# Bitbucket API utility functions for fetching deployment variables

# Fetch environment UUID by slug
# Usage: fetch_environment_uuid <workspace> <repo_slug> <environment_slug>
# Returns: environment UUID (with braces)
fetch_environment_uuid() {
    local workspace="$1"
    local repo_slug="$2"
    local env_slug="$3"
    
    local api_url="https://api.bitbucket.org/2.0/repositories/${workspace}/${repo_slug}/environments/"
    
    log_info "Fetching environment UUID for: ${env_slug}"
    
    local response=$(curl -s \
        -H "Authorization: Bearer ${BITBUCKET_ACCESS_TOKEN}" \
        -H "Accept: application/json" \
        "$api_url" 2>/dev/null)
    
    # Extract UUID for matching slug
    local uuid=$(echo "$response" | jq -r ".values[] | select(.slug == \"${env_slug}\") | .uuid" 2>/dev/null)
    
    if [ -n "$uuid" ] && [ "$uuid" != "null" ]; then
        echo "$uuid"
        return 0
    else
        log_error "Environment '${env_slug}' not found"
        return 1
    fi
}

# Fetch deployment variables from a Bitbucket repository
# Usage: fetch_deployment_variables <workspace> <repo_slug> <environment_slug>
# Returns: Deployment variables as KEY=VALUE lines
fetch_deployment_variables() {
    local workspace="$1"
    local repo_slug="$2" 
    local environment="$3"
    
    require_vars workspace repo_slug environment
    
    # Validate required access token (matching pr_comment.sh pattern)
    : "${BITBUCKET_ACCESS_TOKEN:?Missing BITBUCKET_ACCESS_TOKEN}"
    
    # Step 1: Get environment UUID from slug
    log_info "Fetching deployment variables from ${workspace}/${repo_slug} environment: ${environment}"
    local env_uuid=$(fetch_environment_uuid "$workspace" "$repo_slug" "$environment")
    
    if [ -z "$env_uuid" ]; then
        log_error "Failed to get UUID for environment: ${environment}"
        return 1
    fi
    
    log_info "Environment UUID: ${env_uuid}"
    
    # Step 2: Fetch variables using UUID
    # URL-encode the UUID (braces need encoding)
    local encoded_uuid=$(echo "$env_uuid" | sed 's/{/%7B/g; s/}/%7D/g')
    local api_url="https://api.bitbucket.org/2.0/repositories/${workspace}/${repo_slug}/deployments_config/environments/${encoded_uuid}/variables"
    
    log_info "API URL: ${api_url}"
    
    # Fetch all pages of deployment variables (API returns paginated results)
    local all_vars=""
    local current_url="$api_url"
    local page=1
    
    while [ -n "$current_url" ]; do
        log_info "Fetching page $page..."
        
        local response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
            -H "Authorization: Bearer ${BITBUCKET_ACCESS_TOKEN}" \
            -H "Accept: application/json" \
            "$current_url" 2>/dev/null || echo "HTTPSTATUS:000")
        
        local http_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
        local body=$(echo "$response" | sed 's/HTTPSTATUS:[0-9]*$//')
        
        case "$http_code" in
            200)
                # Parse variables from this page (use .key for variable name, not .name)
                # Skip secured variables as they don't have accessible values via API
                # Trim whitespace from values to avoid shell word splitting issues
                local page_vars=$(echo "$body" | jq -r '.values[] | select(.secured != true) | "\(.key)=\(.value | gsub("^[[:space:]]+|[[:space:]]+$"; ""))"' 2>/dev/null)
                
                if [ -n "$page_vars" ]; then
                    all_vars="${all_vars}${page_vars}"$'\n'
                fi
                
                # Check for next page
                local next_url=$(echo "$body" | jq -r '.next // empty' 2>/dev/null)
                
                if [ -n "$next_url" ] && [ "$next_url" != "null" ]; then
                    current_url="$next_url"
                    ((page++))
                else
                    current_url=""
                fi
                ;;
            404)
                log_warn "No deployment variables found for environment: $environment"
                return 0
                ;;
            401|403)
                log_error "Authentication failed. Check your credentials"
                return 1
                ;;
            000)
                log_error "Failed to connect to Bitbucket API"
                return 1
                ;;
            *)
                log_error "API request failed with HTTP $http_code: $body"
                return 1
                ;;
        esac
    done
    
    if [ -n "$all_vars" ]; then
        local var_count=$(echo "$all_vars" | grep -c '=' || echo "0")
        log_info "Successfully fetched ${var_count} deployment variables (secured variables excluded)"
        echo "$all_vars"
        return 0
    else
        log_warn "No deployment variables found for environment: $environment"
        return 0
    fi
}

# Extract build arguments from deployment variables
# Usage: deployment_vars_to_build_args <deployment_vars_output>
deployment_vars_to_build_args() {
    local build_args=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"
            
            # Export for use in the build process
            export "$var_name=$var_value"
            
            # Add to build args if not empty
            [ -n "$var_value" ] && build_args="$build_args --build-arg $var_name=$var_value"
        fi
    done
    
    echo "$build_args"
}

# Get build arguments using Bitbucket API with fallback to environment variables
# Usage: get_build_args_with_api <target_env>
get_build_args_with_api() {
    local target_env="$1"
    require_vars target_env
    
    local build_args=""
    
    # Check if API integration is enabled (defaults to false - opt-in feature)
    if [ "${USE_BITBUCKET_DEPLOYMENT_VARS:-false}" = "true" ]; then
        log_info "Bitbucket deployment variables integration enabled (USE_BITBUCKET_DEPLOYMENT_VARS=true)"
        
        # Determine workspace and repo slug
        # BITBUCKET_WORKSPACE and BITBUCKET_REPO_SLUG are provided by Bitbucket Pipelines
        local workspace="${BITBUCKET_WORKSPACE:-}"
        local repo_slug="${BITBUCKET_REPO_SLUG:-}"
        
        log_info "Using workspace: ${workspace}, repo: ${repo_slug}"
        
        if [ -n "$workspace" ] && [ -n "$repo_slug" ]; then
            log_info "Attempting to fetch deployment variables via API"
            
            # Try to fetch deployment variables
            # Note: Error messages go to stderr (visible), only build args go to stdout (captured)
            if deployment_vars=$(fetch_deployment_variables "$workspace" "$repo_slug" "$target_env"); then
                if [ -n "$deployment_vars" ]; then
                    log_info "Using deployment variables from Bitbucket API"
                    build_args=$(echo "$deployment_vars" | deployment_vars_to_build_args)
                    echo "$build_args"
                    return 0
                else
                    log_warn "No deployment variables found via API for environment: $target_env"
                fi
            else
                log_warn "Failed to fetch deployment variables via API, falling back to environment variables"
            fi
        else
            log_warn "Missing BITBUCKET_WORKSPACE or BITBUCKET_REPO_SLUG, cannot use API"
        fi
    fi
    
    # Fallback to existing environment variable logic
    log_info "Using environment variable fallback method"
    
    local target_env_lower="${target_env,,}"  # lowercase
    local target_env_upper="${target_env^^}"  # uppercase
    
    while IFS='=' read -r var_name var_value; do
        case "$var_name" in
            *_"$target_env_lower"|*_"$target_env_upper")
                local base_name="${var_name%_*}"
                export "$base_name=$var_value"
                [ -n "$var_value" ] && build_args="$build_args --build-arg $base_name=$var_value"
            ;;
        esac
    done < <(env)
    
    echo "$build_args"
}

# Validate API credentials (matching pr_comment.sh pattern)
validate_api_credentials() {
    if [ -n "${BITBUCKET_ACCESS_TOKEN:-}" ]; then
        return 0
    else
        return 1
    fi
}

# Test API connectivity (matching pr_comment.sh pattern)
test_api_connectivity() {
    local workspace="${BITBUCKET_WORKSPACE:-}"
    
    if [ -z "$workspace" ]; then
        log_error "BITBUCKET_WORKSPACE not set"
        return 1
    fi
    
    # Validate required access token (matching pr_comment.sh pattern)
    : "${BITBUCKET_ACCESS_TOKEN:?Missing BITBUCKET_ACCESS_TOKEN}"
    
    local api_url="https://api.bitbucket.org/2.0/workspaces/${workspace}"
    local response
    local http_code
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Authorization: Bearer ${BITBUCKET_ACCESS_TOKEN}" \
        -H "Accept: application/json" \
        "$api_url" 2>/dev/null || echo "HTTPSTATUS:000")
    
    http_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    
    if [ "$http_code" = "200" ]; then
        log_info "API connectivity test successful"
        return 0
    else
        log_error "API connectivity test failed with HTTP $http_code"
        return 1
    fi
}
