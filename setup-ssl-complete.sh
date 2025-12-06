#!/bin/bash

# Script hoàn chỉnh setup SSL cho Asset Management System
# Domain: codeshare.id.vn
# Email: ledonchung12a2@gmail.com

set -e

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DOMAINS=(
    "api.codeshare.id.vn"
    "socket.codeshare.id.vn"
    "asset.codeshare.id.vn"
)
EMAIL="ledonchung12a2@gmail.com"
STAGING=0  # Set to 1 for testing

echo -e "${BLUE}================================================================${NC}"
echo -e "${GREEN}    Asset Management SSL Setup - Complete Script${NC}"
echo -e "${BLUE}================================================================${NC}"
echo -e "${YELLOW}Domains: ${DOMAINS[*]}${NC}"
echo -e "${YELLOW}Email: $EMAIL${NC}"
echo -e "${BLUE}================================================================${NC}"

# Kiểm tra Docker
echo -e "${GREEN}[1/8] Kiểm tra Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker không được cài đặt!${NC}"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Docker Compose không được cài đặt!${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Docker OK${NC}"

# Dừng containers cũ
echo -e "${GREEN}[2/8] Dừng containers cũ (nếu có)...${NC}"
docker-compose down 2>/dev/null || true
echo -e "${GREEN}✅ Containers đã dừng${NC}"

# Tạo thư mục cần thiết
echo -e "${GREEN}[3/8] Tạo thư mục certbot...${NC}"
mkdir -p ./certbot/conf
mkdir -p ./certbot/www
echo -e "${GREEN}✅ Thư mục đã tạo${NC}"

# Backup nginx config gốc
echo -e "${GREEN}[4/8] Backup nginx config...${NC}"
if [ -f "nginx.conf" ]; then
    cp nginx.conf nginx.conf.ssl-backup
    echo -e "${GREEN}✅ Đã backup nginx.conf${NC}"
fi

# Tạo nginx config tạm thời chỉ cho HTTP và acme-challenge
echo -e "${GREEN}[5/8] Tạo nginx config tạm thời...${NC}"
cat > nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    client_max_body_size 10M;
    
    # Upstream backends
    upstream api_backend {
        server 209.97.171.45:3000;
    }

    upstream socket_backend {
        server 209.97.171.45:3001;
    }

    upstream asset_backend {
        server 209.97.171.45:3002;
    }

    # Temporary HTTP-only config for SSL challenge
    server {
        listen 80;
        server_name api.codeshare.id.vn socket.codeshare.id.vn asset.codeshare.id.vn;
        
        # Let's Encrypt challenge path
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
            try_files $uri $uri/ =404;
        }
        
        # Temporary response for other requests
        location / {
            return 200 'SSL Setup in progress... Please wait.';
            add_header Content-Type text/plain;
        }
    }

    # Default server
    server {
        listen 80 default_server;
        server_name _;
        return 444;
    }
}
EOF
echo -e "${GREEN}✅ Config tạm thời đã tạo${NC}"

# Start nginx với config tạm thời (không start certbot để tránh xung đột)
echo -e "${GREEN}[6/8] Khởi động nginx tạm thời...${NC}"
docker-compose up -d --no-deps nginx
sleep 10
echo -e "${GREEN}✅ Nginx đã khởi động${NC}"

# Tạo SSL certificates
echo -e "${GREEN}[7/8] Tạo SSL certificates...${NC}"
CERTBOT_ARGS="certonly --webroot --webroot-path=/var/www/certbot --email $EMAIL --agree-tos --no-eff-email --non-interactive --force-renewal"

if [ $STAGING -eq 1 ]; then
    CERTBOT_ARGS="$CERTBOT_ARGS --staging"
    echo -e "${YELLOW}⚠️  Sử dụng staging environment (testing)${NC}"
fi

# Thêm tất cả domains
for domain in "${DOMAINS[@]}"; do
    CERTBOT_ARGS="$CERTBOT_ARGS -d $domain"
done

# Chạy certbot
echo -e "${YELLOW}Đang tạo certificates...${NC}"
docker run --rm \
    -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
    -v "$(pwd)/certbot/www:/var/www/certbot" \
    --network asset-management-nginx_asset-management-network \
    certbot/certbot $CERTBOT_ARGS

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SSL certificates đã tạo thành công!${NC}"
else
    echo -e "${RED}❌ Tạo SSL certificates thất bại!${NC}"
    echo -e "${YELLOW}Khôi phục nginx config gốc...${NC}"
    if [ -f "nginx.conf.ssl-backup" ]; then
        cp nginx.conf.ssl-backup nginx.conf
    fi
    exit 1
fi

# Khôi phục nginx config với SSL
echo -e "${GREEN}[8/8] Cấu hình nginx với SSL...${NC}"
if [ -f "nginx.conf.ssl-backup" ]; then
    cp nginx.conf.ssl-backup nginx.conf
    echo -e "${GREEN}✅ Đã khôi phục config SSL${NC}"
else
    # Tạo config SSL hoàn chỉnh nếu không có backup
    cat > nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    client_max_body_size 10M;
    
    upstream api_backend {
        server 209.97.171.45:3000;
    }

    upstream socket_backend {
        server 209.97.171.45:3001;
    }

    upstream asset_backend {
        server 209.97.171.45:3002;
    }

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=general:10m rate=5r/s;

    # SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # API Service - HTTP to HTTPS redirect
    server {
        listen 80;
        server_name api.codeshare.id.vn;
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        location / {
            return 301 https://$server_name$request_uri;
        }
    }

    # API Service - HTTPS
    server {
        listen 443 ssl http2;
        server_name api.codeshare.id.vn;

        ssl_certificate /etc/letsencrypt/live/api.codeshare.id.vn/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/api.codeshare.id.vn/privkey.pem;

        location / {
            limit_req zone=api burst=20 nodelay;
            
            proxy_pass http://api_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # CORS headers
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
            add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization";
            
            if ($request_method = 'OPTIONS') {
                add_header Access-Control-Allow-Origin *;
                add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
                add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization";
                add_header Access-Control-Max-Age 1728000;
                add_header Content-Type 'text/plain; charset=utf-8';
                add_header Content-Length 0;
                return 204;
            }
        }
    }

    # Socket Service - HTTP to HTTPS redirect
    server {
        listen 80;
        server_name socket.codeshare.id.vn;
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        location / {
            return 301 https://$server_name$request_uri;
        }
    }

    # Socket Service - HTTPS
    server {
        listen 443 ssl http2;
        server_name socket.codeshare.id.vn;

        ssl_certificate /etc/letsencrypt/live/socket.codeshare.id.vn/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/socket.codeshare.id.vn/privkey.pem;

        location / {
            limit_req zone=general burst=10 nodelay;
            
            proxy_pass http://socket_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # WebSocket support
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_cache_bypass $http_upgrade;
            proxy_buffering off;
            proxy_read_timeout 86400;
        }
    }

    # Asset Service - HTTP to HTTPS redirect
    server {
        listen 80;
        server_name asset.codeshare.id.vn;
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        location / {
            return 301 https://$server_name$request_uri;
        }
    }

    # Asset Service - HTTPS
    server {
        listen 443 ssl http2;
        server_name asset.codeshare.id.vn;

        ssl_certificate /etc/letsencrypt/live/asset.codeshare.id.vn/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/asset.codeshare.id.vn/privkey.pem;

        location / {
            limit_req zone=general burst=15 nodelay;
            
            proxy_pass http://asset_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # WebSocket support
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_cache_bypass $http_upgrade;
            
            # CORS headers
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
            add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization";
            
            if ($request_method = 'OPTIONS') {
                add_header Access-Control-Allow-Origin *;
                add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
                add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization";
                add_header Access-Control-Max-Age 1728000;
                add_header Content-Type 'text/plain; charset=utf-8';
                add_header Content-Length 0;
                return 204;
            }
            
            proxy_buffering off;
            proxy_read_timeout 86400;
        }
    }

    # Default server block
    server {
        listen 80 default_server;
        listen 443 ssl default_server;
        server_name _;
        
        ssl_certificate /etc/letsencrypt/live/api.codeshare.id.vn/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/api.codeshare.id.vn/privkey.pem;
        
        return 444;
    }
}
EOF
    echo -e "${GREEN}✅ Đã tạo config SSL hoàn chỉnh${NC}"
fi

# Restart nginx với SSL config
echo -e "${GREEN}Khởi động lại nginx với SSL...${NC}"
docker-compose up -d nginx

# Start auto-renewal service
echo -e "${GREEN}Khởi động auto-renewal service...${NC}"
docker-compose up -d certbot-renewal

echo -e "${BLUE}================================================================${NC}"
echo -e "${GREEN}🎉 SSL Setup hoàn thành thành công! 🎉${NC}"
echo -e "${BLUE}================================================================${NC}"
echo -e "${YELLOW}Các domain đã được cấu hình SSL:${NC}"
for domain in "${DOMAINS[@]}"; do
    echo -e "  ✅ https://$domain"
done

echo -e ""
echo -e "${YELLOW}Kiểm tra SSL:${NC}"
echo -e "  curl -I https://api.codeshare.id.vn"
echo -e "  curl -I https://socket.codeshare.id.vn"
echo -e "  curl -I https://asset.codeshare.id.vn"

echo -e ""
echo -e "${YELLOW}Kiểm tra nginx:${NC}"
echo -e "  docker-compose exec nginx nginx -t"
echo -e "  docker-compose logs nginx"

echo -e ""
echo -e "${GREEN}✅ Certificates sẽ tự động renew mỗi 12 giờ${NC}"
echo -e "${BLUE}================================================================${NC}"
