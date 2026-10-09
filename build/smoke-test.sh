#!/usr/bin/env bash
# প্যাকেজ অন্য distro-তে (debian) খুলে, দুটো আলাদা পাথে চালিয়ে দেখে — পোর্টেবিলিটি প্রমাণ।
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker run --rm -v "$REPO/dist":/dist:ro debian:12-slim bash -euc '
  apt-get update -qq && apt-get install -y -qq curl xz-utils procps >/dev/null
  mkdir -p /mnt/a/very/deep/dir && tar -xJf /dist/lsrv-*.tar.xz -C /mnt/a/very/deep/dir
  cd /mnt/a/very/deep/dir/lsrv
  ./lsrv config set RUN_USER root
  check() {
    ./lsrv start all
    curl -fsS  http://127.0.0.1:8080/  | grep -q "LSRV OK"
    curl -fskS https://127.0.0.1:8443/ | grep -q "LSRV OK"
    for v in $(./lsrv php list | awk "{print \$1}"); do
      ./lsrv site add "t${v/./}" --php "$v" >/dev/null
      echo "<?php echo \"PHP-\".PHP_VERSION;" > "www/t${v/./}/index.php"
    done
    ./lsrv reload; ./lsrv restart php
    for v in $(./lsrv php list | awk "{print \$1}"); do
      curl -fsS -H "Host: t${v/./}.localhost" http://127.0.0.1:8080/ | grep -q "PHP-$v"
    done
    ./lsrv mysql shell -e "select version()"
    ./bin/node -v
    ./lsrv stop all
  }
  check
  mkdir -p /opt && mv /mnt/a/very/deep/dir/lsrv /opt/moved-lsrv   # পাথ বদলালেও চলতে হবে
  cd /opt/moved-lsrv && check
  echo SMOKE-TEST-PASSED
'
