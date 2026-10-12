#!/bin/bash
set -e

# Configure Go proxy for China network
export GOPROXY="https://goproxy.cn,direct"
echo "GOPROXY=https://goproxy.cn,direct" >> /etc/environment

USER="root"

# Configure Docker registry mirrors for the inner dockerd
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'DAEMONJSON'
{
    "registry-mirrors": [
        "https://hub-mirror.c.163.com",
        "https://mirror.baidubce.com",
        "https://docker.1ms.run",
        "https://dockerproxy.net",
        "https://mirror.aliyuncs.com",
        "https://docker.m.daocloud.io",
        "https://docker.nju.edu.cn",
        "https://docker.mirrors.ustc.edu.cn"
    ]
}
DAEMONJSON

# Run dockerd
dockerd -s vfs &> /dev/null &


# Setup local group, if not existing
if [ "${BUILDER_GID:-0}" -ne 0 ] && ! getent group "${BUILDER_GID:-0}"; then
  groupadd -g "${BUILDER_GID}" builder
fi

# Setup local user
if [ "${BUILDER_UID:-0}" -ne 0 ]; then
  useradd -m -u "${BUILDER_UID}" -g "${BUILDER_GID}" -G docker,sudo builder
  echo "builder ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
  # Make sure cache is accessible by builder
  chown "${BUILDER_UID}:${BUILDER_GID}" /cache
  # Make sure output is accessible by builder (if anonymous volume is used)
  chown "${BUILDER_UID}:${BUILDER_GID}" /build/output || true
  USER="builder"
fi

if CMD="$(command -v "$1")"; then
  shift
  sudo -H -u ${USER} "$CMD" "$@"
else
  echo "Command not found: $1"
  exit 1
fi
