FROM ibkr:base

ARG INSTALL_FILENAME="ibgateway-10.40.1d-standalone-linux-x64.sh"

USER root
RUN apt-get update && \
    apt-get install --no-install-recommends -y wget2

USER ibg
WORKDIR /home/ibg
# Fetch hashes
RUN wget2 "https://github.com/huieric/ibga/releases/download/10.40.1d-latest/ibgateway-10.40.1d-standalone-linux-x64.sh.sha256" \
    -O hash

# Download IB Gateway (which contains TWS) and check hashes
RUN wget2 "https://github.com/huieric/ibga/releases/download/10.40.1d-latest/ibgateway-10.40.1d-standalone-linux-x64.sh" \
    -O "$INSTALL_FILENAME" \
    && sha256sum -c hash \
    && chmod +x "$INSTALL_FILENAME" \
    && yes '' | "./$INSTALL_FILENAME"  \
    && rm "$INSTALL_FILENAME"
