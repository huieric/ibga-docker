FROM debian:bookworm-slim AS util_build
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libx11-dev libc-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
ADD image-files/show_text.c /tmp
WORKDIR /tmp
RUN gcc show_text.c -O2 -lX11 -o show_text

FROM debian:bookworm-slim
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl sudo ed xdotool socat python3-websockify python3-venv procps xfonts-scalable tzdata oathtool \
    ca-certificates git libxtst6 libgtk-3-0 openbox tigervnc-standalone-server openjdk-17-jdk \
    # https://github.com/extrange/ibkr-docker/issues/74
    libasound2 \
    libnss3 \
    libgbm1 \
    libnspr4 && \
    python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir ib-insync && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN useradd -ms /bin/bash -u 2000 ibg && \
    adduser ibg sudo && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
WORKDIR /opt
RUN git clone --depth 1 https://github.com/novnc/noVNC.git && \
    chmod +x ./noVNC/utils/novnc_proxy && \
    git clone --depth 1 https://github.com/novnc/websockify.git ./noVNC/utils/websockify
COPY image-files/index.html ./noVNC
ENV JAUTO_VER=1.0.0
RUN curl -Lk https://github.com/huieric/jauto/releases/download/v$JAUTO_VER/jauto-v$JAUTO_VER-linux-x86_64.tar.gz -o jauto.tar.gz && \
    tar xfz jauto.tar.gz && \
    rm jauto.tar.gz

USER ibg
WORKDIR /home/ibg
COPY --from=util_build /tmp/show_text /bin
ADD image-files/scripts /opt/ibga/
RUN sudo chmod a+rx /bin/show_text && \
    sudo chmod a+rx /opt/jauto.so && \
    sudo chmod a+rx /opt/ibga/*

COPY image-files/healthcheck.py /opt/healthcheck.py
# HEALTHCHECK --interval=60s --timeout=10s --retries=1 --start-period=30s CMD /opt/venv/bin/python3 /opt/healthcheck.py

ENTRYPOINT /opt/ibga/start.sh
