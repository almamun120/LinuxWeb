rtmp {
    server {
        listen @RTMP_PORT@;
        chunk_size 4096;
        application live {
            live on;
            record off;
            hls on;
            hls_path "@RUN@/live/hls";
            hls_fragment 3s;
            hls_playlist_length 30s;
            hls_cleanup on;
            dash on;
            dash_path "@RUN@/live/dash";
            dash_fragment 3s;
            dash_playlist_length 30s;
            dash_cleanup on;
        }
    }
}
