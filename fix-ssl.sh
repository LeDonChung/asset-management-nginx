#!/bin/bash

# Script khắc phục vấn đề SSL - sử dụng nginx config đơn giản trước

set -e

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Khắc phục SSL Setup ===${NC}"

# Dừng tất cả containers
echo -e "${YELLOW}Dừng containers hiện tại...${NC}"
docker-compose down

# Backup nginx config hiện tại
echo -e "${YELLOW}Backup nginx config...${NC}"
cp nginx.conf nginx.conf.ssl-backup

# Tạo nginx config đơn giản chỉ cho HTTP và acme-challenge
cat > nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        server_name api.codeshare.id.vn socket.codeshare.id.vn asset.codeshare.id.vn;
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        location / {
            return 200 'OK - Ready for SSL';
            add_header Content-Type text/plain;
        }
    }
}
EOF

echo -e "${GREEN}Tạo nginx config tạm thời cho SSL challenge...${NC}"

# Tạo thư mục certbot
mkdir -p ./certbot/conf
mkdir -p ./certbot/www

# Start nginx với config đơn giản
echo -e "${GREEN}Khởi động nginx với config tạm thời...${NC}"
docker-compose up -d nginx

# Chờ nginx khởi động
sleep 5

# Tạo SSL certificates
echo -e "${GREEN}Tạo SSL certificates...${NC}"
docker run --rm \
    -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
    -v "$(pwd)/certbot/www:/var/www/certbot" \
    --network asset-management-nginx_asset-management-network \
    certbot/certbot certonly --webroot --webroot-path=/var/www/certbot \
    --email ledonchung12a2@gmail.com --agree-tos --no-eff-email \
    -d api.codeshare.id.vn -d socket.codeshare.id.vn -d asset.codeshare.id.vn

# Khôi phục nginx config với SSL
echo -e "${GREEN}Khôi phục nginx config với SSL...${NC}"
cp nginx.conf.ssl-backup nginx.conf

# Reload nginx với SSL config
echo -e "${GREEN}Reload nginx với SSL...${NC}"
docker-compose up -d nginx

# Start auto-renewal
echo -e "${GREEN}Khởi động auto-renewal...${NC}"
docker-compose up -d certbot-renewal

echo -e "${GREEN}=== SSL Setup hoàn thành! ===${NC}"
echo -e "${YELLOW}Test SSL:${NC}"
echo -e "  curl -I https://api.codeshare.id.vn"
echo -e "  curl -I https://socket.codeshare.id.vn"
echo -e "  curl -I https://asset.codeshare.id.vn"
