# lsrv — portable web stack (nginx + PHP + MySQL + Node + cloudflared)

## বিল্ড
    ./build/docker-build.sh            # Docker লাগবে; ফলাফল: dist/lsrv-<ver>-linux-<arch>.tar.xz
    ./build/smoke-test.sh              # Debian কন্টেইনারে পরীক্ষা
GitHub-এ push করলেই `.github/workflows/build.yml` বিল্ড+টেস্ট করে artifact দেয়; `v1.0.0` tag দিলে Release-ও তৈরি হয়।
ভার্সন বদলাতে `build/versions.env` দেখুন।

## ব্যবহার (যেকোনো পিসিতে, যেকোনো পাথে)
    tar -xJf lsrv-*.tar.xz && cd lsrv
    ./lsrv start        # http://localhost:8080  https://localhost:8443 (h2/h3)
    ./lsrv site add blog --php 8.2     # www/blog + https://blog.localhost:8443
    ./lsrv help

## লেআউট
    lsrv/  lsrv(ম্যানেজার) bin/ lib/ conf/ nginx/ php/<ver>/ mysql/ node/ cloudflare/ www/ data/ run/ logs/

## সীমাবদ্ধতা
- Host glibc >= 2.31 (Ubuntu 20.04+, Debian 11+, Fedora, RHEL 9...). RHEL 8 / Alpine(musl) চলবে না।
- ড্রাইভ ext4/xfs/btrfs হতে হবে এবং noexec নয়। exFAT/NTFS-এ MySQL data চলবে না (DATA_DIR অন্যত্র দিন)।
- 80/443 পোর্টে root লাগে (বা `sysctl net.ipv4.ip_unprivileged_port_start=80`)।
