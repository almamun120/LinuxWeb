@IFROOT_HASH@user @RUN_USER@ @RUN_GROUP@;
worker_processes auto;
pid "@RUN@/nginx.pid";
error_log "@LOGS@/nginx-error.log" warn;
include "@RUN@/nginx/main.d/*.conf";

events { worker_connections 4096; }

http {
    include "@ROOT@/nginx/conf/mime.types";
    default_type application/octet-stream;
    client_body_temp_path "@RUN@/tmp/client_body";
    proxy_temp_path       "@RUN@/tmp/proxy";
    fastcgi_temp_path     "@RUN@/tmp/fastcgi";
    uwsgi_temp_path       "@RUN@/tmp/uwsgi";
    scgi_temp_path        "@RUN@/tmp/scgi";
    access_log "@LOGS@/nginx-access.log";

    sendfile on; tcp_nopush on; keepalive_timeout 65; server_tokens off;
    client_max_body_size 128m;
    lua_package_path "@ROOT@/nginx/lua/?.lua;;";

    gzip on; gzip_comp_level 5; gzip_vary on; gzip_proxied any;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;
    brotli on; brotli_comp_level 5;
    brotli_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_trusted_certificate "@ROOT@/etc/cacert.pem";

    proxy_cache_path "@RUN@/cache/proxy" levels=1:2 keys_zone=lsrv_cache:50m max_size=1g inactive=60m use_temp_path=off;

    # GeoIP2 উদাহরণ (`lsrv geoip update` চালিয়ে আনকমেন্ট করুন):
    # geoip2 "@DATA@/geoip/dbip-country-lite.mmdb" { $geoip2_country_code country iso_code; }

    include "@RUN@/nginx/sites/*.conf";
}
