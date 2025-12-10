#!/bin/bash

# Script đơn giản setup SSL cho Asset Management System
# Tạo 3 certificates riêng biệt, không có auto-renewal

set -e

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DOMAINS=(
    "asset.codeshare.id.vn"
    "api.codeshare.id.vn"
    "socket.codeshare.id.vn"
)
EMAIL="ledonchung12a2@gmail.com"
STAGING=0  # Set to 1 for testing

echo -e "${BLUE}================================================================${NC}"
echo -e "${GREEN}    Asset Management SSL Setup - Simple Version${NC}"
echo -e "${BLUE}================================================================${NC}"
echo -e "${YELLOW}Domains: ${DOMAINS[*]}${NC}"
echo -e "${YELLOW}Email: $EMAIL${NC}"
echo -e "${BLUE}================================================================${NC}"

# Kiểm tra Docker
echo -e "${GREEN}[1/6] Kiểm tra Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker không được cài đặt!${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Docker OK${NC}"

# Dừng containers cũ
echo -e "${GREEN}[2/6] Dừng containers...${NC}"
docker-compose down 2>/dev/null || true
echo -e "${GREEN}✅ Containers đã dừng${NC}"

# Tạo thư mục cần thiết
echo -e "${GREEN}[3/6] Tạo thư mục certbot...${NC}"
mkdir -p ./certbot/conf
mkdir -p ./certbot/www
echo -e "${GREEN}✅ Thư mục đã tạo${NC}"

# Backup nginx config gốc
echo -e "${GREEN}[4/6] Backup nginx config...${NC}"
if [ -f "nginx.conf" ]; then
    sudo cp nginx.conf nginx.conf.ssl-backup 2>/dev/null || cp nginx.conf nginx.conf.ssl-backup
    echo -e "${GREEN}✅ Đã backup nginx.conf${NC}"
fi

# Tạo nginx config tạm thời chỉ cho HTTP và acme-challenge
echo -e "${GREEN}[5/6] Tạo nginx config tạm thời...${NC}"
cat > nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    client_max_body_size 10M;
    
    # Upstream backends
    upstream asset_backend {
        server 178.128.123.115:3002;
    }

    upstream api_backend {
        server 178.128.123.115:3000;
    }

    upstream socket_backend {
        server 178.128.123.115:3001;
    }
    

    # Temporary HTTP-only config for SSL challenge
    server {
        listen 80;
        server_name asset.codeshare.id.vn api.codeshare.id.vn socket.codeshare.id.vn;
        
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

# Start nginx với config tạm thời
echo -e "${GREEN}[6/6] Khởi động nginx tạm thời...${NC}"
docker-compose up -d --no-deps nginx
sleep 10
echo -e "${GREEN}✅ Nginx đã khởi động${NC}"

# Tạo SSL certificates (mỗi domain một certificate riêng)
echo -e "${GREEN}[7/7] Tạo SSL certificates...${NC}"
CERTBOT_BASE_ARGS="certonly --webroot --webroot-path=/var/www/certbot --email $EMAIL --agree-tos --no-eff-email --non-interactive"

if [ $STAGING -eq 1 ]; then
    CERTBOT_BASE_ARGS="$CERTBOT_BASE_ARGS --staging"
    echo -e "${YELLOW}⚠️  Sử dụng staging environment (testing)${NC}"
fi

# Tạo certificate riêng cho từng domain
FAILED=0
for domain in "${DOMAINS[@]}"; do
    echo -e "${YELLOW}Đang tạo certificate cho: $domain${NC}"
    
    docker run --rm \
        -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
        -v "$(pwd)/certbot/www:/var/www/certbot" \
        certbot/certbot $CERTBOT_BASE_ARGS -d $domain
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Certificate cho $domain đã tạo thành công!${NC}"
    else
        echo -e "${RED}❌ Tạo certificate cho $domain thất bại!${NC}"
        FAILED=1
    fi
    
    # Đợi 5 giây giữa các request để tránh rate limit
    if [ "$domain" != "${DOMAINS[-1]}" ]; then
        echo -e "${YELLOW}Đợi 5 giây trước khi tạo certificate tiếp theo...${NC}"
        sleep 5
    fi
done

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ Tất cả SSL certificates đã tạo thành công!${NC}"
else
    echo -e "${RED}❌ Một số certificates thất bại!${NC}"
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
    echo -e "${RED}⚠️  Không tìm thấy nginx.conf.ssl-backup!${NC}"
    echo -e "${YELLOW}Vui lòng tự cấu hình nginx.conf với SSL certificates${NC}"
fi

# Restart nginx với SSL config
echo -e "${GREEN}Khởi động lại nginx với SSL...${NC}"
docker-compose up -d nginx

echo -e "${BLUE}================================================================${NC}"
echo -e "${GREEN}🎉 SSL Setup hoàn thành thành công! 🎉${NC}"
echo -e "${BLUE}================================================================${NC}"
echo -e "${YELLOW}Các domain đã được cấu hình SSL:${NC}"
for domain in "${DOMAINS[@]}"; do
    echo -e "  ✅ https://$domain"
done

echo -e ""
echo -e "${YELLOW}Certificates được tạo tại:${NC}"
echo -e "  ./certbot/conf/live/asset.codeshare.id.vn/"
echo -e "  ./certbot/conf/live/api.codeshare.id.vn/"
echo -e "  ./certbot/conf/live/socket.codeshare.id.vn/"

echo -e ""
echo -e "${YELLOW}Kiểm tra SSL:${NC}"
echo -e "  curl -I https://asset.codeshare.id.vn"
echo -e "  curl -I https://api.codeshare.id.vn"
echo -e "  curl -I https://socket.codeshare.id.vn"

echo -e ""
echo -e "${YELLOW}Kiểm tra nginx:${NC}"
echo -e "  docker-compose exec nginx nginx -t"
echo -e "  docker-compose logs nginx"

echo -e ""
echo -e "${YELLOW}Renew certificates thủ công (khi cần):${NC}"
echo -e "  docker run --rm -v \$(pwd)/certbot/conf:/etc/letsencrypt -v \$(pwd)/certbot/www:/var/www/certbot certbot/certbot renew"
echo -e "  docker-compose restart nginx"

echo -e "${BLUE}================================================================${NC}"
