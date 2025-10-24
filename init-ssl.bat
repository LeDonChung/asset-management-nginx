@echo off
REM Script để khởi tạo SSL certificates với Let's Encrypt cho Windows
REM Sử dụng cho domain codeshare.id.vn

setlocal enabledelayedexpansion

echo === Asset Management SSL Setup ===
echo Domains: api.codeshare.id.vn, socket.codeshare.id.vn, asset.codeshare.id.vn
echo Email: ledonchung12a2@gmail.com

REM Kiểm tra Docker
docker --version >nul 2>&1
if errorlevel 1 (
    echo Docker không được cài đặt!
    pause
    exit /b 1
)

docker-compose --version >nul 2>&1
if errorlevel 1 (
    echo Docker Compose không được cài đặt!
    pause
    exit /b 1
)

REM Tạo thư mục cần thiết
echo Tạo thư mục certbot...
if not exist "certbot\conf" mkdir certbot\conf
if not exist "certbot\www" mkdir certbot\www

REM Tạo dummy certificate để nginx có thể start
echo Tạo dummy certificates...
if not exist "certbot\conf\live\api.codeshare.id.vn" mkdir certbot\conf\live\api.codeshare.id.vn
if not exist "certbot\conf\live\socket.codeshare.id.vn" mkdir certbot\conf\live\socket.codeshare.id.vn
if not exist "certbot\conf\live\asset.codeshare.id.vn" mkdir certbot\conf\live\asset.codeshare.id.vn

REM Start nginx với dummy certificates
echo Khởi động nginx...
docker-compose up -d nginx

REM Chờ nginx khởi động
echo Chờ nginx khởi động...
timeout /t 10 /nobreak >nul

REM Tạo real certificates
echo Tạo SSL certificates...
docker run --rm ^
    -v "%cd%\certbot\conf:/etc/letsencrypt" ^
    -v "%cd%\certbot\www:/var/www/certbot" ^
    --network asset-management-nginx_asset-management-network ^
    certbot/certbot certonly --webroot --webroot-path=/var/www/certbot ^
    --email ledonchung12a2@gmail.com --agree-tos --no-eff-email ^
    -d api.codeshare.id.vn -d socket.codeshare.id.vn -d asset.codeshare.id.vn

REM Reload nginx với certificates mới
echo Reload nginx với SSL certificates...
docker-compose exec nginx nginx -s reload

REM Setup auto-renewal
echo Khởi động service auto-renewal...
docker-compose up -d certbot-renewal

echo === SSL Setup hoàn thành! ===
echo Các domain đã được cấu hình SSL:
echo   ✅ https://api.codeshare.id.vn
echo   ✅ https://socket.codeshare.id.vn
echo   ✅ https://asset.codeshare.id.vn

echo Kiểm tra certificates:
echo   docker-compose exec nginx nginx -t
echo   docker-compose logs certbot

echo Certificates sẽ tự động renew mỗi 12 giờ.
pause
