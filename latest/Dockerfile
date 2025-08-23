FROM ibkr:base

ENV JAUTO_INPUT="/tmp/ibg-jauto.in"

ARG INSTALL_FILENAME="ibgateway-10.39.1h-standalone-linux-x64.sh"
ARG JAUTO_PATCH="-agentpath:/opt/jauto.so=$JAUTO_INPUT"
ARG OPTIONS_FILE="Jts/ibgateway/ibgateway.vmoptions"

USER root
RUN apt-get update && \
    apt-get install --no-install-recommends -y wget2

USER ibg
WORKDIR /home/ibg
# Fetch hashes
RUN wget2 "https://github.com/extrange/ibkr-docker/releases/download/10.39.1h-latest/ibgateway-10.39.1h-standalone-linux-x64.sh.sha256" \
    -O hash

# Download IB Gateway (which contains TWS) and check hashes
RUN wget2 "https://github.com/extrange/ibkr-docker/releases/download/10.39.1h-latest/ibgateway-10.39.1h-standalone-linux-x64.sh" \
    -O "$INSTALL_FILENAME" \
    && sha256sum -c hash \
    && chmod +x "$INSTALL_FILENAME" \
    && yes '' | "./$INSTALL_FILENAME"  \
    && grep -qxF -- "$JAUTO_PATCH" $OPTIONS_FILE || echo "$JAUTO_PATCH" >> $OPTIONS_FILE \
    && rm "$INSTALL_FILENAME"
