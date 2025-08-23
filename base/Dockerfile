FROM debian:bookworm-slim AS util_build
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libx11-dev libc-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
ADD utils /tmp/utils
WORKDIR /tmp/utils
RUN gcc show_text.c -O2 -lX11 -o show_text

FROM debian:bookworm-slim
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl sudo ed xvfb x11vnc x11-utils xdotool socat python3-websockify python3-venv procps xfonts-scalable tzdata oathtool && \
    python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir ib-insync && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN useradd -ms /bin/bash -u 2000 ibg && \
    adduser ibg sudo && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
WORKDIR /opt
RUN curl -Lk "https://github.com/novnc/noVNC/archive/refs/tags/v1.3.0.tar.gz" -o novnc.tar.gz && \
    tar xfz novnc.tar.gz && \
    rm novnc.tar.gz
USER ibg
WORKDIR /home/ibg
COPY --from=util_build /tmp/utils/show_text /bin

ENV JAUTO_VER=1.0.0
RUN curl -Lk https://github.com/huieric/jauto/releases/download/v$JAUTO_VER/jauto-v$JAUTO_VER-linux-x86_64.tar.gz -o /tmp/jauto.tar.gz && \
    tar xfz /tmp/jauto.tar.gz -C /opt

ADD scripts /opt/ibga/
RUN sudo chmod a+rx /bin/show_text && \
    sudo chmod a+rx /opt/jauto.so && \
    sudo chmod a+rx /opt/ibga/*
EXPOSE 8888/tcp
EXPOSE 6080/tcp

COPY healthcheck.py /opt/healthcheck.py
HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD /opt/venv/bin/python3 /opt/healthcheck.py

ENTRYPOINT /opt/ibga/manager.sh
