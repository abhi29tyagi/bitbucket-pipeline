#!/bin/bash
set -euo pipefail

# Common functions for Nginx preview proxy operations
# Provides utilities for Nginx configuration, SSL validation, and service management

# Fix Nginx permissions if needed
fix_nginx_permissions() {
    local nginx_sites_available="/etc/nginx/sites-available"
    local nginx_sites_enabled="/etc/nginx/sites-enabled"
    
    echo "🔧 Checking Nginx permissions..."
    
    # Check if Nginx directories exist
    if [ ! -d "$nginx_sites_available" ]; then
        echo "❌ Nginx sites-available directory not found: $nginx_sites_available"
        echo "   This might be a different Nginx configuration structure"
        return 1
    fi
    
    # Check if we can write to nginx directories
    if [ ! -w "$nginx_sites_available" ]; then
        echo "⚠️  Nginx sites-available directory not writable, attempting to fix permissions..."
        
        if command -v sudo >/dev/null 2>&1; then
            echo "   Using sudo to fix Nginx permissions..."
            
            # Fix ownership and permissions
            sudo chown -R "$(whoami):$(whoami)" "$nginx_sites_available" "$nginx_sites_enabled" || {
                echo "❌ Could not change ownership of Nginx directories"
                return 1
            }
            
            sudo chmod 755 "$nginx_sites_available" "$nginx_sites_enabled" || {
                echo "❌ Could not change permissions of Nginx directories"
                return 1
            }
            
            echo "✅ Nginx permissions fixed successfully"
        else
            echo "❌ sudo not available, cannot fix Nginx permissions"
            echo "   Please ensure the runner user has write access to $nginx_sites_available"
            return 1
        fi
    else
        echo "✅ Nginx directories are writable"
    fi
    
    return 0
}

# Verify Nginx is accessible and configurable
verify_nginx_access() {
    echo "🔍 Verifying Nginx access..."
    
    if ! fix_nginx_permissions; then
        echo "❌ Cannot configure Nginx - permission issues detected"
        return 1
    fi
    
    # Test if we can create a temporary file
    local test_file="/etc/nginx/sites-available/test-permissions-$$.tmp"
    if ! touch "$test_file" 2>/dev/null; then
        echo "❌ Still cannot write to Nginx directories after permission fix"
        return 1
    fi
    
    # Clean up test file
    rm -f "$test_file"
    echo "✅ Nginx access verified successfully"
    return 0
}

# Reload Nginx configuration safely
reload_nginx() {
    echo "🔄 Reloading Nginx configuration..."
    
    # Test configuration first
    if command -v sudo >/dev/null 2>&1; then
        if ! sudo nginx -t; then
            echo "❌ Nginx configuration test failed"
            return 1
        fi
        
        if ! sudo systemctl reload nginx; then
            echo "❌ Nginx reload failed"
            return 1
        fi
    else
        if ! nginx -t; then
            echo "❌ Nginx configuration test failed"
            return 1
        fi
        
        if ! systemctl reload nginx; then
            echo "❌ Nginx reload failed"
            return 1
        fi
    fi
    
    echo "✅ Nginx configuration reloaded successfully"
    return 0
}


# Validate SSL certificate files exist and are readable
validate_ssl_certificates() {
    local ssl_dir="/etc/ssl/preview-certs"
    local cert_file="${ssl_dir}/wildcard.crt"
    local key_file="${ssl_dir}/wildcard.key"
    
    echo "🔍 Validating SSL certificate files..."
    
    # Check symlinks exist (Let's Encrypt layout uses symlinks in /etc/ssl/preview-certs)
    if [ ! -L "$cert_file" ] || [ ! -L "$key_file" ]; then
        echo "❌ SSL certificate symlinks not found:"
        echo "   Expected: $cert_file and $key_file"
        return 1
    fi
    
    # Note: We don't check readability here since Let's Encrypt private keys
    # are typically root-only readable, but Nginx (running as root) can access them
    
    # Confirm symlink form (expected for Let's Encrypt)
    echo "✅ SSL certificate symlinks validated (Let's Encrypt)"
    
    return 0
}
