#!/bin/bash

# Script để khởi tạo SSL certificates với Let's Encrypt
# Sử dụng cho domain codeshare.id.vn

set -e

# Màu sắc cho output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Domain configuration
DOMAINS=(
    "api.codeshare.id.vn"
    "socket.codeshare.id.vn"
    "asset.codeshare.id.vn"
)

EMAIL="ledonchung12a2@gmail.com"  # Thay đổi email của bạn
STAGING=0  # Set to 1 for testing

echo -e "${GREEN}=== Asset Management SSL Setup ===${NC}"
echo -e "${YELLOW}Domains: ${DOMAINS[*]}${NC}"
echo -e "${YELLOW}Email: $EMAIL${NC}"

# Kiểm tra Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker không được cài đặt!${NC}"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Docker Compose không được cài đặt!${NC}"
    exit 1
fi

# Tạo thư mục cần thiết
echo -e "${GREEN}Tạo thư mục certbot...${NC}"
mkdir -p ./certbot/conf
mkdir -p ./certbot/www

# Tạo dummy certificate để nginx có thể start
echo -e "${GREEN}Tạo dummy certificates...${NC}"
for domain in "${DOMAINS[@]}"; do
    mkdir -p "./certbot/conf/live/$domain"
    
    # Tạo dummy certificate
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
        -keyout "./certbot/conf/live/$domain/privkey.pem" \
        -out "./certbot/conf/live/$domain/fullchain.pem" \
        -subj "/CN=$domain" 2>/dev/null || {
        echo -e "${YELLOW}Không thể tạo dummy certificate cho $domain, tiếp tục...${NC}"
    }
done

# Start nginx với dummy certificates
echo -e "${GREEN}Khởi động nginx với dummy certificates...${NC}"
docker-compose up -d nginx

# Chờ nginx khởi động
echo -e "${YELLOW}Chờ nginx khởi động...${NC}"
sleep 10

# Xóa dummy certificates
echo -e "${GREEN}Xóa dummy certificates...${NC}"
for domain in "${DOMAINS[@]}"; do
    rm -rf "./certbot/conf/live/$domain"
done

echo -e "${YELLOW}Dừng container certbot cũ (nếu có)...${NC}"
docker stop asset-management-certbot >/dev/null 2>&1 || true
docker rm asset-management-certbot >/dev/null 2>&1 || true

# Tạo real certificates
echo -e "${GREEN}Tạo SSL certificates thật...${NC}"

CERTBOT_ARGS="certonly --webroot --webroot-path=/var/www/certbot --email $EMAIL --agree-tos --no-eff-email"

if [ $STAGING -eq 1 ]; then
    CERTBOT_ARGS="$CERTBOT_ARGS --staging"
    echo -e "${YELLOW}Sử dụng staging environment (testing)${NC}"
fi

# Thêm tất cả domains
for domain in "${DOMAINS[@]}"; do
    CERTBOT_ARGS="$CERTBOT_ARGS -d $domain"
done

# Chạy certbot
docker run --rm \
    -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
    -v "$(pwd)/certbot/www:/var/www/certbot" \
    --network asset-management-nginx_asset-management-network \
    certbot/certbot $CERTBOT_ARGS

# Reload nginx với certificates mới
echo -e "${GREEN}Reload nginx với SSL certificates...${NC}"
docker-compose exec nginx nginx -s reload

# Setup auto-renewal
echo -e "${GREEN}Khởi động service auto-renewal...${NC}"
docker-compose up -d certbot-renewal

echo -e "${GREEN}=== SSL Setup hoàn thành! ===${NC}"
echo -e "${YELLOW}Các domain đã được cấu hình SSL:${NC}"
for domain in "${DOMAINS[@]}"; do
    echo -e "  ✅ https://$domain"
done

echo -e "${YELLOW}Kiểm tra certificates:${NC}"
echo -e "  docker-compose exec nginx nginx -t"
echo -e "  docker-compose logs certbot"

echo -e "${YELLOW}Certificates sẽ tự động renew mỗi 12 giờ.${NC}"
