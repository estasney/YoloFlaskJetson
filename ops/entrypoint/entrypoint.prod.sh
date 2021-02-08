#!/usr/bin/env sh
set -e

# Get the maximum upload file size for Nginx, default to 0: unlimited
USE_NGINX_MAX_UPLOAD=${NGINX_MAX_UPLOAD:-0}

# Get the number of workers for Nginx, default to 1
USE_NGINX_WORKER_PROCESSES=${NGINX_WORKER_PROCESSES:-1}

# Set the max number of connections per worker for Nginx, if requested
# Cannot exceed worker_rlimit_nofile, see NGINX_WORKER_OPEN_FILES below
NGINX_WORKER_CONNECTIONS=${NGINX_WORKER_CONNECTIONS:-1024}

# Get the listen port for Nginx, default to 80

#======================================
#          /etc/nginx/nginx.conf
#======================================

content='user  nginx;\n'
# Set the number of worker processes in Nginx
content=$content"worker_processes ${USE_NGINX_WORKER_PROCESSES};\n"
content=$content'pid        /var/run/nginx.pid;\n\n'
content=$content'events {\n'
content=$content"    worker_connections ${NGINX_WORKER_CONNECTIONS};\n"
content=$content'}\n'
content=$content'http {\n'
content=$content'    include       /etc/nginx/mime.types;\n'
content=$content'    default_type  application/octet-stream;\n'
content=$content'    log_format  main  '"'\$remote_addr - [\$time_local] \"\$request\" '\n"
content=$content'                      '"'\$status \$body_bytes_sent \"\$http_referer\" '\n"
content=$content'                      '"'\"\$http_user_agent\" \"\$http_x_forwarded_for\"';\n"
content=$content'    access_log  /var/log/nginx/access.log  main;\n'
content=$content'    error_log  /var/log/nginx/error.log warn;\n'
content=$content'    sendfile   on;\n'
content=$content'    keepalive_timeout  65;\n'
content=$content'    include /etc/nginx/conf.d/*.conf;\n'
content=$content'    gzip on;\n'
content=$content'    gzip_types application/xml application/json text/css text/javascript application/javascript;\n'
content=$content'    gzip_vary on;\n'
content=$content'    gzip_comp_level 6;\n'
content=$content'    gzip_min_length 500;\n'
content=$content'}\n'
content=$content'daemon off;\n'

# Save generated /etc/nginx/nginx.conf
printf "$content" > /etc/nginx/nginx.conf

# Generate Nginx config for maximum upload file size
printf "client_max_body_size $USE_NGINX_MAX_UPLOAD;\n" > /etc/nginx/conf.d/upload.conf

# Remove default Nginx config from Alpine
printf "" > /etc/nginx/conf.d/default.conf

# Copy static folders
cp -r /app/flaskyolo/static /www
chmod 755 $(find /www -type d)
chmod 644 $(find /www -type f)

exec "$@"
