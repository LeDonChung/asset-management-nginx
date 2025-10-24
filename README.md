# Asset Management Nginx Configuration với SSL

Cấu hình nginx để proxy các service của hệ thống quản lý tài sản với hỗ trợ HTTPS/SSL.

## Cấu hình Service

- **API Service**: `34.158.42.23:3000` → `https://api.codeshare.id.vn`
- **Socket Service**: `34.158.42.23:3001` → `https://socket.codeshare.id.vn` 
- **Asset Service**: `34.158.42.23:3002` → `https://asset.codeshare.id.vn` (có hỗ trợ WebSocket)

## Tính năng

- ✅ Reverse proxy cho 3 service
- ✅ **HTTPS/SSL với Let's Encrypt**
- ✅ **Auto SSL certificate renewal**
- ✅ HTTP to HTTPS redirect
- ✅ Hỗ trợ WebSocket cho socket và asset service
- ✅ CORS headers cho API và Asset service
- ✅ Rate limiting bảo mật
- ✅ HTTP/2 support
- ✅ Docker support hoàn chỉnh

## Cách sử dụng

### 1. Cấu hình Email (Quan trọng!)

Trước khi chạy, **BẮT BUỘC** phải thay đổi email trong các file:
- `docker-compose.yml` (dòng 26): `your-email@example.com`
- `init-ssl.sh` (dòng 18): `your-email@example.com`
- `init-ssl.bat` (dòng 8): `your-email@example.com`

### 2. Setup SSL Certificates

#### Trên Linux/macOS:
```bash
cd asset-management-nginx
chmod +x init-ssl.sh
./init-ssl.sh
```

#### Trên Windows:
```cmd
cd asset-management-nginx
init-ssl.bat
```

### 3. Chạy thủ công (nếu cần)

```bash
cd asset-management-nginx
docker-compose up -d
```

### 4. Kiểm tra SSL

Sau khi setup, kiểm tra:
```bash
# Kiểm tra nginx config
docker-compose exec nginx nginx -t

# Xem logs certbot
docker-compose logs certbot

# Test SSL
curl -I https://api.codeshare.id.vn
curl -I https://socket.codeshare.id.vn
curl -I https://asset.codeshare.id.vn
```

## Cấu trúc thư mục

```
asset-management-nginx/
├── nginx.conf          # Cấu hình nginx với SSL
├── docker-compose.yml  # Docker compose với certbot
├── Dockerfile         # Docker build file
├── init-ssl.sh        # Script setup SSL (Linux/macOS)
├── init-ssl.bat       # Script setup SSL (Windows)
├── README.md          # Hướng dẫn này
└── certbot/           # SSL certificates (tự động tạo)
    ├── conf/          # Let's Encrypt config
    └── www/           # Webroot cho validation
```

## SSL Certificate Management

### Auto Renewal
- Certificates tự động renew mỗi 12 giờ
- Service `certbot-renewal` chạy liên tục
- Không cần can thiệp thủ công

### Manual Renewal (nếu cần)
```bash
# Renew certificates
docker-compose run --rm certbot renew

# Reload nginx
docker-compose exec nginx nginx -s reload
```

### Testing SSL (Staging)
Để test trước khi tạo real certificates:
1. Sửa `STAGING=1` trong `init-ssl.sh`
2. Chạy script
3. Sau khi test OK, sửa `STAGING=0` và chạy lại

## Bảo mật

- **Rate Limiting**: API (10 req/s), General (5 req/s)
- **SSL/TLS**: TLS 1.2, 1.3 với strong ciphers
- **HTTP/2**: Enabled cho performance
- **HSTS**: Có thể thêm nếu cần
- **Security Headers**: Có thể mở rộng

## Troubleshooting

### Lỗi thường gặp:

1. **Domain chưa point đến server**:
   ```bash
   # Kiểm tra DNS
   nslookup api.codeshare.id.vn
   ```

2. **Port 80/443 bị block**:
   ```bash
   # Kiểm tra firewall
   sudo ufw allow 80
   sudo ufw allow 443
   ```

3. **Certbot failed**:
   ```bash
   # Xem logs chi tiết
   docker-compose logs certbot
   ```

4. **Nginx không start**:
   ```bash
   # Test config
   docker-compose exec nginx nginx -t
   ```

## Lưu ý quan trọng

- **Email**: Phải thay đổi email thật trước khi chạy
- **DNS**: Đảm bảo tất cả subdomain đã point đến server
- **Firewall**: Mở port 80, 443
- **Backup**: Backup thư mục `certbot/conf` định kỳ
- **Monitoring**: Theo dõi logs để đảm bảo renewal hoạt động
