#!/bin/bash

# Script to restart nginx with updated CORS configuration
# This fixes the duplicate CORS headers issue

echo "🔧 Restarting nginx with updated CORS configuration..."

# Test nginx configuration first
echo "📋 Testing nginx configuration..."
sudo nginx -t

if [ $? -eq 0 ]; then
    echo "✅ Nginx configuration is valid"
    
    # Reload nginx configuration
    echo "🔄 Reloading nginx..."
    sudo systemctl reload nginx
    
    if [ $? -eq 0 ]; then
        echo "✅ Nginx reloaded successfully"
        echo "🎉 CORS fix applied! The duplicate headers issue should be resolved."
        echo ""
        echo "📝 Changes made:"
        echo "   - Removed duplicate CORS headers from nginx.conf"
        echo "   - CORS is now handled exclusively by NestJS application"
        echo "   - This prevents the 'multiple values' error in Access-Control-Allow-Origin"
        echo ""
        echo "🧪 Please test your login functionality now."
    else
        echo "❌ Failed to reload nginx"
        exit 1
    fi
else
    echo "❌ Nginx configuration test failed"
    echo "Please check the configuration and try again"
    exit 1
fi
