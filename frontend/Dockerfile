# Lightweight Nginx Web Server for Flutter Web (Local Docker & Heroku Container Registry)
FROM nginx:alpine

# Copy custom Nginx configuration with SPA routing and API reverse proxy
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy prebuilt web bundle
COPY build/web /usr/share/nginx/html

EXPOSE 80

# Health check (uses dynamic $PORT on Heroku, defaults to 80 locally)
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD sh -c 'wget -q -O - http://127.0.0.1:${PORT:-80}/healthz || exit 1'

# Replace listen port with $PORT (if provided by Heroku) and optional $BACKEND_UPSTREAM before starting Nginx
CMD ["/bin/sh", "-c", "PORT_VAL=${PORT:-80}; sed -i \"s/listen 80;/listen ${PORT_VAL};/g\" /etc/nginx/conf.d/default.conf && sed -i \"s/listen \\[::\\]:80;/listen [::]:${PORT_VAL};/g\" /etc/nginx/conf.d/default.conf && if [ -n \"$BACKEND_UPSTREAM\" ]; then sed -i \"s|http://backend:8000|${BACKEND_UPSTREAM}|g\" /etc/nginx/conf.d/default.conf; fi && nginx -g 'daemon off;'"]
