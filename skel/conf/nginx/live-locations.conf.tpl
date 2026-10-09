location /hls/ {
    types { application/vnd.apple.mpegurl m3u8; video/mp2t ts; }
    root "@RUN@/live";
    add_header Cache-Control "no-cache" always;
    add_header Access-Control-Allow-Origin "*" always;
}
location /dash/ {
    types { application/dash+xml mpd; video/mp4 mp4 m4s; audio/mp4 m4a; }
    root "@RUN@/live";
    add_header Cache-Control "no-cache" always;
    add_header Access-Control-Allow-Origin "*" always;
}
