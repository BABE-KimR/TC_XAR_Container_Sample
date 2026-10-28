FROM debian:trixie-slim

# curl and ca-certificates: load bhf.asc signing file from beckhoff.com during build, used by the health check
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
    curl \
    ca-certificates

# Use login information in the bhf.conf file to authenticate against deb*.beckhoff.com
# See https://manpages.debian.org/testing/apt/apt_auth.conf.5.en.html for more information
RUN --mount=type=secret,id=apt \
    curl --fail --netrc-file "/run/secrets/apt" \
    -o /usr/share/keyrings/bhf.asc \
    https://deb.beckhoff.com/repo.pub

# Replace default debian.org package sources.
# From here on, all packages will be loaded from deb*.beckhoff.com
RUN rm /etc/apt/sources.list.d/debian.sources
# "apt-config" is a named build context pointing to ./apt-config.private (see README)
COPY --from=apt-config bhf.list debian.sources.list /etc/apt/sources.list.d/

# TF2000 HMI Server plus the TwinCAT user-mode system service, which provides the ADS router
RUN --mount=type=secret,id=apt \
    apt-get -o "Dir::Etc::netrc=/run/secrets/apt" update \
    && apt-get -o "Dir::Etc::netrc=/run/secrets/apt" install --yes \
    tf2000-hmi-server \
    tc31-xar-um \
    adstool \
    && rm -rf /var/lib/apt/lists/*

# ADS route to the MQTT broker, so the HMI server reaches the other TwinCAT containers
ARG TC3_DIR=/etc/TwinCAT/3.1
COPY TwinCAT/StaticRoutes.xml $TC3_DIR/Target/

# Local HTTP endpoint (2010, loopback only) and HTTPS endpoint (2020) of the HMI server
EXPOSE 2020/tcp

WORKDIR /app
COPY entrypoint.sh /app/
# Guard against CRLF line endings when building from a Windows working copy
RUN sed -i 's/\r$//' /app/entrypoint.sh

CMD [ "/bin/sh", "/app/entrypoint.sh"]
