#!/usr/bin/env bash
# Ubuntu 20.04 (glibc 2.31) কন্টেইনারে বিল্ড — যাতে প্যাকেজ নতুন-পুরনো সব distro-তে চলে।
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${BUILD_IMAGE:-ubuntu:20.04}"
docker run --rm -v "$REPO":/src -w /src \
  -e JOBS="${JOBS:-$(nproc)}" -e LSRV_VERSION="${LSRV_VERSION:-}" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  "$IMAGE" bash -c 'bash ./build/build.sh all; rc=$?; chown -R "$HOST_UID:$HOST_GID" /src/dist /src/.work 2>/dev/null; exit $rc'
