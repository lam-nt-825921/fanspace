# Lightweight Nginx Web Server for Flutter Web
FROM nginx:alpine

# Copy custom Nginx configuration with SPA routing and API reverse proxy
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy prebuilt web bundle
COPY build/web /usr/share/nginx/html

EXPOSE 80

# Health check
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD wget -q -O - http://127.0.0.1/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
