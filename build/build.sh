#!/usr/bin/env bash
# Portable web stack builder.  ব্যবহার: build.sh [deps|quictls|luajit|nginx|php|mysql|node|cloudflared|assemble|finish|package|all]
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO/build/versions.env"

WORK="${WORK:-$REPO/.work}"; DL="$WORK/dl"; SRC="$WORK/src"; DEPS="$WORK/deps"
DIST="${DIST:-$REPO/dist}"; STAGE="$DIST/lsrv"
JOBS="${JOBS:-$(nproc)}"
FAKE=/__lsrv__            # শুধু বিল্ড-টাইম prefix; রানটাইমে কখনো ব্যবহার হয় না
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  NODE_ARCH=x64;   CF_ARCH=amd64 ;;
  aarch64) NODE_ARCH=arm64; CF_ARCH=arm64 ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac
mkdir -p "$DL" "$SRC" "$DEPS" "$STAGE"
command -v gcc-11 >/dev/null 2>&1 && export CC=gcc-11 CXX=g++-11

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }
fetch(){ [ -s "$2" ] || curl -fL --retry 3 --retry-delay 3 -o "$2" "$1"; }
gitget(){ # url ref dir
  [ -d "$3/.git" ] && return 0
  git clone --depth 1 --recurse-submodules --shallow-submodules ${2:+--branch "$2"} "$1" "$3"
}

# ------------------------------------------------------------------ deps
cmd_deps() {
  [ "$(id -u)" = 0 ] || { warn "deps needs root, skipping"; return 0; }
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends software-properties-common ca-certificates gnupg \
    curl git jq xz-utils file patchelf python3-pip build-essential pkg-config autoconf automake libtool \
    bison re2c perl unzip gettext binutils
  add-apt-repository -y ppa:ubuntu-toolchain-r/test
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends gcc-11 g++-11 libstdc++6 \
    zlib1g-dev libxml2-dev libsqlite3-dev libcurl4-openssl-dev libssl-dev libonig-dev libpng-dev \
    libjpeg-dev libfreetype6-dev libwebp-dev libzip-dev libsodium-dev libicu-dev libbz2-dev libxslt1-dev \
    libreadline-dev libgmp-dev libargon2-dev libmaxminddb-dev libaio1 libnuma1 libtinfo6 libxml2-dev
  pip3 install --quiet cmake          # নতুন cmake (nginx-otel/brotli এর জন্য)
  export CC=gcc-11 CXX=g++-11
}

# ------------------------------------------------------------------ quictls (HTTP/3 এর জন্য)
cmd_quictls() {
  [ -f "$DEPS/quictls/lib/libssl.a" ] && return 0
  log "quictls $QUICTLS_REF"
  gitget https://github.com/quictls/openssl "$QUICTLS_REF" "$SRC/quictls"
  ( cd "$SRC/quictls"
    ./config --prefix="$DEPS/quictls" --libdir=lib --openssldir=/etc/ssl no-shared no-tests -fPIC
    make -j"$JOBS"; make install_sw )
}

cmd_luajit() {
  [ -f "$DEPS/luajit/lib/libluajit-5.1.so" ] && return 0
  log "luajit2"
  gitget https://github.com/openresty/luajit2 "$LUAJIT_REF" "$SRC/luajit2"
  make -C "$SRC/luajit2" -j"$JOBS" PREFIX="$DEPS/luajit" install
}

# ------------------------------------------------------------------ nginx
cmd_nginx() {
  cmd_quictls; cmd_luajit
  log "nginx $NGINX_VERSION"
  fetch "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz" "$DL/nginx-$NGINX_VERSION.tar.gz"
  fetch "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.gz" "$DL/pcre2.tgz"
  fetch "https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION/zlib-$ZLIB_VERSION.tar.gz" "$DL/zlib.tgz"
  rm -rf "$SRC/nginx-$NGINX_VERSION" "$SRC/pcre2" "$SRC/zlib"
  tar -xzf "$DL/nginx-$NGINX_VERSION.tar.gz" -C "$SRC"
  mkdir -p "$SRC/pcre2" "$SRC/zlib"
  tar -xzf "$DL/pcre2.tgz" -C "$SRC/pcre2" --strip-components=1
  tar -xzf "$DL/zlib.tgz"  -C "$SRC/zlib"  --strip-components=1

  gitget https://github.com/google/ngx_brotli                   "$BROTLI_REF"     "$SRC/ngx_brotli"
  gitget https://github.com/sergey-dryabzhinsky/nginx-rtmp-module "$RTMP_REF"     "$SRC/nginx-rtmp"
  gitget https://github.com/leev/ngx_http_geoip2_module         "$GEOIP2_REF"     "$SRC/ngx_geoip2"
  gitget https://github.com/nginx/njs                           "$NJS_REF"        "$SRC/njs"
  gitget https://github.com/openresty/lua-nginx-module          "$LUA_NGINX_REF"  "$SRC/lua-nginx-module"
  gitget https://github.com/simpl/ngx_devel_kit                 "$NGX_DEVEL_KIT_REF" "$SRC/ngx_devel_kit"
  gitget https://github.com/openresty/lua-resty-core            ""                "$SRC/lua-resty-core"
  gitget https://github.com/openresty/lua-resty-lrucache        ""                "$SRC/lua-resty-lrucache"

  # brotli static lib (upstream README অনুযায়ী)
  ( cd "$SRC/ngx_brotli/deps/brotli" && mkdir -p out && cd out &&
    cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_C_FLAGS="-O2 -fPIC" \
          -DCMAKE_INSTALL_PREFIX=./installed .. &&
    cmake --build . --config Release --target brotlienc -j"$JOBS" )

  export LUAJIT_LIB="$DEPS/luajit/lib" LUAJIT_INC="$DEPS/luajit/include/luajit-2.1"
  local NGX="$SRC/nginx-$NGINX_VERSION"
  ( cd "$NGX"
    ./configure --prefix="$FAKE/nginx" \
      --with-cc-opt="-O2 -fPIC -fstack-protector-strong -Wno-error -Wno-deprecated-declarations -I$DEPS/quictls/include" \
      --with-ld-opt="-L$DEPS/quictls/lib -L$LUAJIT_LIB -Wl,-rpath,$LUAJIT_LIB -Wl,-z,relro -Wl,-z,now" \
      --with-compat --with-threads --with-file-aio \
      --with-pcre="$SRC/pcre2" --with-pcre-jit --with-zlib="$SRC/zlib" \
      --with-http_ssl_module --with-http_v2_module --with-http_v3_module \
      --with-http_realip_module --with-http_gzip_static_module --with-http_gunzip_module \
      --with-http_stub_status_module --with-http_sub_module --with-http_addition_module \
      --with-http_auth_request_module --with-http_secure_link_module --with-http_slice_module \
      --with-http_mp4_module --with-http_flv_module --with-http_random_index_module \
      --with-stream --with-stream_ssl_module --with-stream_ssl_preread_module --with-stream_realip_module \
      --add-module="$SRC/ngx_devel_kit" --add-module="$SRC/lua-nginx-module" \
      --add-module="$SRC/ngx_brotli" --add-module="$SRC/nginx-rtmp" \
      --add-module="$SRC/ngx_geoip2" --add-module="$SRC/njs/nginx"
    make -j"$JOBS"
    rm -rf "$WORK/inst-nginx"; make install DESTDIR="$WORK/inst-nginx" )
  rm -rf "$STAGE/nginx"; mv "$WORK/inst-nginx$FAKE/nginx" "$STAGE/nginx"
  rm -f "$STAGE"/nginx/conf/*.default
  make -C "$SRC/lua-resty-core"     install LUA_LIB_DIR="$STAGE/nginx/lua"
  make -C "$SRC/lua-resty-lrucache" install LUA_LIB_DIR="$STAGE/nginx/lua"
  mkdir -p "$STAGE/nginx/modules"

  if [ "${ENABLE_OTEL:-1}" = 1 ]; then
    ( log "nginx-otel (best effort)"
      gitget https://github.com/nginx/nginx-otel "" "$SRC/nginx-otel"
      mkdir -p "$SRC/nginx-otel/build" && cd "$SRC/nginx-otel/build" &&
      cmake -DCMAKE_BUILD_TYPE=Release -DNGX_OTEL_NGINX_BUILD_DIR="$NGX/objs" \
            -DOPENSSL_ROOT_DIR="$DEPS/quictls" -DgRPC_SSL_PROVIDER=package .. &&
      make -j"$JOBS" &&
      install -D ngx_otel_module.so "$STAGE/nginx/modules/ngx_otel_module.so"
    ) || warn "nginx-otel বিল্ড হয়নি — বাকি স্ট্যাক ঠিক আছে, শুধু otel মডিউল নেই"
  fi
  install -D "$DEPS/quictls/bin/openssl" "$STAGE/openssl/bin/openssl"
}

# ------------------------------------------------------------------ php (প্রতিটি ভার্সন আলাদা)
php_one() {
  local mm="$1" full inst
  full="$(curl -fsSL "https://www.php.net/releases/index.php?json&version=$mm" | jq -r '.version // empty')"
  [ -n "$full" ] || die "PHP $mm এর ভার্সন পাওয়া যায়নি"
  log "php $full"
  fetch "https://www.php.net/distributions/php-$full.tar.xz" "$DL/php-$full.tar.xz"
  rm -rf "$SRC/php-$full"; tar -xJf "$DL/php-$full.tar.xz" -C "$SRC"
  inst="$WORK/inst-php-$mm"; rm -rf "$inst"
  ( cd "$SRC/php-$full"
    ./configure --prefix="$FAKE/php/$mm" --with-config-file-path="$FAKE/php/$mm/etc" --disable-all \
      --enable-cli --enable-fpm --disable-cgi --disable-phpdbg --without-pear --with-pic \
      --enable-opcache --enable-mbstring --enable-bcmath --enable-calendar --enable-exif --enable-ftp \
      --enable-pcntl --enable-sockets --enable-soap --enable-intl --enable-gd \
      --enable-ctype --enable-dom --enable-fileinfo --enable-filter --enable-hash --enable-iconv \
      --enable-json --enable-libxml --enable-mysqlnd --enable-pdo --enable-phar --enable-posix \
      --enable-session --enable-simplexml --enable-tokenizer --enable-xml --enable-xmlreader --enable-xmlwriter \
      --with-openssl --with-curl --with-zlib --with-bz2 --with-zip --with-xsl --with-sodium --with-gmp \
      --with-readline --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd --with-pdo-sqlite --with-sqlite3 \
      --with-jpeg --with-freetype --with-webp --with-password-argon2 --with-libxml
    make -j"$JOBS"; make install INSTALL_ROOT="$inst" )
  rm -rf "$STAGE/php/$mm"; mkdir -p "$STAGE/php"; mv "$inst$FAKE/php/$mm" "$STAGE/php/$mm"
  local d="$STAGE/php/$mm"
  mkdir -p "$d/ext"; mv "$d"/lib/php/extensions/*/* "$d/ext/"
  rm -rf "$d"/{include,man,etc,var,lib/php,php} "$d"/bin/{php-config,phpize,pecl} 2>/dev/null || true
}
cmd_php() { local v; for v in $PHP_VERSIONS; do php_one "$v"; done; }

# ------------------------------------------------------------------ mysql / node / cloudflared (prebuilt)
cmd_mysql() {
  log "mysql $MYSQL_VERSION"
  local a="$ARCH" mm="${MYSQL_VERSION%.*}" f base flavor got=""
  for flavor in "-minimal" ""; do
    f="mysql-$MYSQL_VERSION-linux-glibc2.28-$a$flavor.tar.xz"
    [ -s "$DL/$f" ] && { got="$f"; break; }
    for base in "https://cdn.mysql.com/Downloads/MySQL-$mm" "https://downloads.mysql.com/archives/get/p/23/file"; do
      if curl -fL --retry 2 -o "$DL/$f" "$base/$f"; then got="$f"; break 2; fi
      rm -f "$DL/$f"
    done
  done
  [ -n "$got" ] || die "MySQL $MYSQL_VERSION ডাউনলোড হয়নি (MYSQL_VERSION বদলে দেখুন)"
  rm -rf "$STAGE/mysql"; mkdir -p "$STAGE/mysql"
  tar -xJf "$DL/$got" -C "$STAGE/mysql" --strip-components=1
  rm -rf "$STAGE"/mysql/{mysql-test,docs,man,include,support-files}
  find "$STAGE/mysql/bin" -type f ! \( -name mysqld -o -name mysql -o -name mysqldump -o -name mysqladmin \
        -o -name mysqlcheck -o -name mysqlimport -o -name mysqlbinlog \) -delete
}
cmd_node() {
  log "node $NODE_MAJOR"
  local v; v="$(curl -fsSL https://nodejs.org/dist/index.json | jq -r --arg m "v$NODE_MAJOR." '[.[]|select(.version|startswith($m))][0].version')"
  [ -n "$v" ] && [ "$v" != null ] || die "node $NODE_MAJOR পাওয়া যায়নি"
  fetch "https://nodejs.org/dist/$v/node-$v-linux-$NODE_ARCH.tar.xz" "$DL/node-$v.tar.xz"
  rm -rf "$STAGE/node"; mkdir -p "$STAGE/node"
  tar -xJf "$DL/node-$v.tar.xz" -C "$STAGE/node" --strip-components=1
  rm -rf "$STAGE"/node/{include,share/doc,share/man}
}
cmd_cloudflared() {
  log "cloudflared"
  rm -f "$DL/cloudflared"
  fetch "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$CF_ARCH" "$DL/cloudflared"
  install -D -m755 "$DL/cloudflared" "$STAGE/cloudflare/bin/cloudflared"
}

# ------------------------------------------------------------------ assemble / bundle / clean / package
cmd_assemble() {
  log "assemble"
  cp -a "$REPO/skel/." "$STAGE/"
  mkdir -p "$STAGE"/{lib,data,run,logs,cloudflare/bin,www}
  fetch https://curl.se/ca/cacert.pem "$DL/cacert.pem"; cp "$DL/cacert.pem" "$STAGE/etc/cacert.pem"
  chmod +x "$STAGE/lsrv"
}

bundle_libs() {
  log "bundle shared libs"
  mkdir -p "$STAGE/lib"
  find "$STAGE" -type f -size +0 \( -perm -u+x -o -name '*.so*' \) -print0 |
  while IFS= read -r -d '' f; do
    file -b "$f" | grep -q '^ELF' || continue
    LD_LIBRARY_PATH="$DEPS/luajit/lib" ldd "$f" 2>/dev/null | awk '/=> \//{print $3}'
  done | sort -u |
  while IFS= read -r l; do
    case "$l" in "$STAGE"/*) continue ;; esac
    case "$(basename "$l")" in
      ld-linux*|libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|libresolv.so*|libutil.so*|libnss_*|libanl.so*) continue ;;
    esac
    cp -L "$l" "$STAGE/lib/"
  done
  # ELF ফাইল যা এখনো "not found" দেখায় (mysql/node ইত্যাদি) সেগুলো LD_LIBRARY_PATH দিয়ে ম্যানেজার ঠিক করে
}

fix_rpaths() {
  log "strip + rpath"
  local f rel
  find "$STAGE/nginx" "$STAGE/php" "$STAGE/lib" "$STAGE/openssl" -type f \( -perm -u+x -o -name '*.so*' \) -print0 2>/dev/null |
    while IFS= read -r -d '' f; do file -b "$f" | grep -q '^ELF' && strip --strip-unneeded "$f" 2>/dev/null || true; done
  for f in "$STAGE"/nginx/sbin/nginx "$STAGE"/nginx/modules/*.so "$STAGE"/php/*/bin/php "$STAGE"/php/*/sbin/php-fpm "$STAGE"/php/*/ext/*.so; do
    [ -f "$f" ] || continue
    rel="$(realpath --relative-to="$(dirname "$f")" "$STAGE/lib")"
    patchelf --set-rpath "\$ORIGIN/$rel" "$f"
  done
  for f in "$STAGE"/lib/*.so*; do [ -L "$f" ] || patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true; done
}

cmd_finish() {
  bundle_libs; fix_rpaths
  find "$STAGE" \( -name '*.a' -o -name '*.la' \) -delete
  rm -rf "$STAGE"/run/* "$STAGE"/logs/* "$STAGE"/data/mysql 2>/dev/null || true
  "$STAGE/lsrv" relink
  {
    echo "build_date=$(date -u +%FT%TZ)"; echo "arch=$ARCH"
    echo "nginx=$NGINX_VERSION"; echo "mysql=$MYSQL_VERSION"; echo "node_major=$NODE_MAJOR"
    echo "php=$(ls "$STAGE/php" | tr '\n' ' ')"
  } > "$STAGE/BUILDINFO"
}

cmd_package() {
  local ver="${LSRV_VERSION:-$(date -u +%Y%m%d)}" name
  name="lsrv-$ver-linux-$ARCH"
  log "package $name"
  tar --owner=0 --group=0 --numeric-owner -C "$DIST" -cf - lsrv | xz -T0 -6 > "$DIST/$name.tar.xz"
  ( cd "$DIST" && sha256sum "$name.tar.xz" > "$name.tar.xz.sha256" )
  ls -lh "$DIST"/*.tar.xz
}

cmd_all() {
  cmd_deps
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  cmd_nginx; cmd_php; cmd_mysql; cmd_node; cmd_cloudflared
  cmd_assemble; cmd_finish; cmd_package
}

"cmd_${1:-all}"
