ARG BASE_IMAGE=tc31-xar-base:latest
FROM ${BASE_IMAGE}

# The base image already contains the Beckhoff apt sources and signing key, but not the credentials.
# Use login information in the bhf.conf file (secret "apt") to authenticate against deb*.beckhoff.com
RUN --mount=type=secret,id=apt \
    apt-get -o "Dir::Etc::netrc=/run/secrets/apt" update \
    && apt-get -o "Dir::Etc::netrc=/run/secrets/apt" install --yes \
    tf5000-nc-ptp-xar \
    twincat-xar-nci-classic \
    twincat-xar-nci-gst \
    && rm -rf /var/lib/apt/lists/*
