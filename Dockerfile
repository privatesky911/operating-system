FROM debian:trixie

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Replace apt sources with Aliyun mirror
RUN sed -i 's|http://deb.debian.org|http://mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources; \
    sed -i 's|https://deb.debian.org|https://mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources

# Docker
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && . /etc/os-release \
    && printf '%s\n' \
        'Types: deb' \
        'URIs: https://mirrors.aliyun.com/docker-ce/linux/debian' \
        "Suites: $VERSION_CODENAME" \
        'Components: stable' \
        "Architectures: $(dpkg --print-architecture)" \
        'Signed-By: /etc/apt/keyrings/docker.asc' \
        > /etc/apt/sources.list.d/docker.sources \
    && apt-get update && apt-get install -y --no-install-recommends \
        docker-ce \
    && rm -rf /var/lib/apt/lists/*

# Build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
        automake \
        bash \
        bc \
        binutils \
        build-essential \
        bzip2 \
        cpio \
        e2fsprogs \
        file \
        git \
        graphviz \
        help2man \
        jq \
        make \
        ncurses-dev \
        openssh-client \
        patch \
        perl \
        pigz \
        python3 \
        python3-matplotlib \
        python-is-python3 \
        qemu-utils \
        rsync \
        skopeo \
        sudo \
        texinfo \
        unzip \
        vim \
        wget \
        zip \
    && rm -rf /var/lib/apt/lists/*

# Docker daemon registry mirrors
RUN mkdir -p /etc/docker && \
    printf '%s\n' \
        '{' \
        '    "registry-mirrors": [' \
        '        "https://hub-mirror.c.163.com",' \
        '        "https://mirror.baidubce.com",' \
        '        "https://docker.1ms.run",' \
        '        "https://dockerproxy.net",' \
        '        "https://proxy.vvvv.ee",' \
        '        "https://dockerproxy.link",' \
        '        "https://hub.rat.dev",' \
        '        "https://mirror.aliyuncs.com",' \
        '        "https://swr.cn-north-4.myhuaweicloud.com",' \
        '        "https://do.nark.eu.org",' \
        '        "https://dc.j8.work",' \
        '        "https://docker.m.daocloud.io",' \
        '        "https://dockerproxy.com",' \
        '        "https://docker.nju.edu.cn",' \
        '        "https://docker.mirrors.ustc.edu.cn",' \
        '        "https://docker.xuanyuan.me",' \
        '        "https://docker.mszx.com",' \
        '        "https://ghcr.nju.edu.cn"' \
        '    ]' \
        '}' \
        > /etc/docker/daemon.json

# Init entry
COPY scripts/entry.sh /usr/sbin/
ENTRYPOINT ["/usr/sbin/entry.sh"]

# Get buildroot
WORKDIR /build
