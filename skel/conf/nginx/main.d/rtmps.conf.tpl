# RTMPS = TLS টার্মিনেট করে লোকাল RTMP-তে পাঠানো
stream {
    server {
        listen @BIND@:@RTMPS_PORT@ ssl;
        ssl_certificate     "@DATA@/ssl/default.crt";
        ssl_certificate_key "@DATA@/ssl/default.key";
        ssl_protocols TLSv1.2 TLSv1.3;
        proxy_pass 127.0.0.1:@RTMP_PORT@;
    }
}
