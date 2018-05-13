# ActiveMQ Artemis

##########################################################
## Build Image                                           #
##########################################################
FROM openjdk:8 as builder
LABEL maintainer="Victor Romero <victor.romero@gmail.com>"

ARG ACTIVEMQ_ARTEMIS_VERSION

# add user and group for artemis
RUN groupadd -r artemis && useradd -r -g artemis artemis

RUN apt-get -qq -o=Dpkg::Use-Pty=0 update && \
  apt-get -qq -o=Dpkg::Use-Pty=0 install -y --no-install-recommends \
    libaio1=0.3.110-3 \
    xmlstarlet=1.6.1-2 \
    jq=1.5+dfsg-1.3 \
    ca-certificates=20161130+nmu1 \
    wget=1.18-5+deb9u2 && \
  rm -rf /var/lib/apt/lists/*

# grab gosu for easy step-down from root
ENV GOSU_VERSION 1.10
RUN set -ex; \
  dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
  wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
  wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
  # verify the signature
  GNUPGHOME="$(mktemp -d)"; \
  export GNUPGHOME; \
  gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 || \
    gpg --keyserver p80.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 || \
    gpg --keyserver pgp.mit.edu --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
  gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
  chmod +x /usr/local/bin/gosu; \
  # verify that the binary works
  gosu nobody true;

# Uncompress and validate
WORKDIR /opt
RUN wget "https://repository.apache.org/content/repositories/releases/org/apache/activemq/apache-artemis/${ACTIVEMQ_ARTEMIS_VERSION}/apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz" && \
  wget "https://repository.apache.org/content/repositories/releases/org/apache/activemq/apache-artemis/${ACTIVEMQ_ARTEMIS_VERSION}/apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz.asc" && \
  wget "http://apache.org/dist/activemq/KEYS" && \
  gpg --import "KEYS" && \
  gpg "apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz.asc" && \
  tar xfz "apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz" && \
  ln -s "/opt/apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}" "/opt/apache-artemis" && \
  rm -f "apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz" "KEYS" "apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}-bin.tar.gz.asc"

# Create broker instance
WORKDIR /var/lib
RUN if test "${ACTIVEMQ_ARTEMIS_VERSION}" = "1.0.0" ; \
    then \
      echo n | "/opt/apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}/bin/artemis" create artemis \
        --home /opt/apache-artemis \
        --user artemis \
        --password simetraehcapa \
        --cluster-user artemisCluster \
        --cluster-password simetraehcaparetsulc; \
    else \
      "/opt/apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}/bin/artemis" create artemis \
        --home /opt/apache-artemis \
        --user artemis \
        --password simetraehcapa \
        --role amq \
        --require-login \
        --cluster-user artemisCluster \
        --cluster-password simetraehcaparetsulc; \
    fi 

# Ports are only exposed with an explicit argument, there is no need to binding
# the web console to localhost
WORKDIR /var/lib/artemis/etc
RUN xmlstarlet ed -L -N amq="http://activemq.org/schema" \
    -u "/amq:broker/amq:web/@bind" \
    -v "http://0.0.0.0:8161" bootstrap.xml

##########################################################
## Run Image                                             #
##########################################################
FROM openjdk:8
LABEL maintainer="Victor Romero <victor.romero@gmail.com>"
ARG ACTIVEMQ_ARTEMIS_VERSION

# add user and group for artemis
RUN groupadd -r artemis && useradd -r -g artemis artemis

RUN apt-get -qq -o=Dpkg::Use-Pty=0 update && \
  apt-get -qq -o=Dpkg::Use-Pty=0 install -y --no-install-recommends \
    libaio1=0.3.110-3 \
    xmlstarlet=1.6.1-2 \
    jq=1.5+dfsg-1.3 && \
  rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/gosu /usr/local/bin/gosu
COPY --from=builder "/opt/apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}" "/opt/apache-artemis-${ACTIVEMQ_ARTEMIS_VERSION}"
COPY --from=builder "/var/lib/artemis" "/var/lib/artemis"

RUN chown -R artemis.artemis /var/lib/artemis

RUN mkdir -p /opt/assets
COPY assets/merge.xslt /opt/assets
COPY assets/enable-jmx.xml /opt/assets

# Web Server
EXPOSE 8161

# Port for CORE,MQTT,AMQP,HORNETQ,STOMP,OPENWIRE
EXPOSE 61616

# Port for HORNETQ,STOMP
EXPOSE 5445

# Port for AMQP
EXPOSE 5672

# Port for MQTT
EXPOSE 1883

#Port for STOMP
EXPOSE 61613

# Expose some outstanding folders
VOLUME ["/var/lib/artemis/data"]
VOLUME ["/var/lib/artemis/tmp"]
VOLUME ["/var/lib/artemis/etc"]
VOLUME ["/var/lib/artemis/etc-override"]

WORKDIR /var/lib/artemis/bin

COPY assets/docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["artemis-server"]