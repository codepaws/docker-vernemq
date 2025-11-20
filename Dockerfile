# ==============================================================================
# STAGE 1: BUILDER
# ==============================================================================
FROM erlang:27-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential libsnappy-dev libssl-dev libncurses-dev ca-certificates cmake \
 && rm -rf /var/lib/apt/lists/*

ARG VERNEMQ_VERSION=2.1.2
WORKDIR /vernemq-src
RUN git clone https://github.com/vernemq/vernemq.git . \
 && git checkout "${VERNEMQ_VERSION}" \
 && git submodule update --init --recursive
RUN make rel

# ==============================================================================
# STAGE 2: RUNTIME (Keep this identical to Upstream where possible)
# ==============================================================================
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get -y install bash procps openssl iproute2 curl jq libsnappy-dev net-tools nano && \
    rm -rf /var/lib/apt/lists/* && \
    addgroup --gid 10000 vernemq && \
    adduser --uid 10000 --system --ingroup vernemq --home /vernemq --disabled-password vernemq

WORKDIR /vernemq

# Defaults
ENV DOCKER_VERNEMQ_KUBERNETES_LABEL_SELECTOR="app=vernemq" \
    DOCKER_VERNEMQ_LOG__CONSOLE=console \
    PATH="/vernemq/bin:$PATH" \
    VERNEMQ_VERSION="2.1.1"
COPY --chown=10000:10000 bin/vernemq.sh /usr/sbin/start_vernemq
COPY --chown=10000:10000 bin/join_cluster.sh /usr/sbin/join_cluster
COPY --chown=10000:10000 files/vm.args /vernemq/etc/vm.args

# Copy VerneMQ build from previous stage
COPY --from=build --chown=10000:10000 /vernemq-src/_build/default/rel/vernemq /vernemq

# 5. Setup Symlinks (Required for Helm paths)
RUN ln -s /vernemq/etc /etc/vernemq && \
    ln -s /vernemq/data /var/lib/vernemq && \
    ln -s /vernemq/log /var/log/vernemq && \
    chmod +x /usr/sbin/start_vernemq /usr/sbin/join_cluster

# Ports
# 1883  MQTT
# 8883  MQTT/SSL
# 8080  MQTT WebSockets
# 44053 VerneMQ Message Distribution
# 4369  EPMD - Erlang Port Mapper Daemon
# 8888  Health, API, Prometheus Metrics
# 9100 9101 9102 9103 9104 9105 9106 9107 9108 9109  Specific Distributed Erlang Port Range

EXPOSE 1883 8883 8080 44053 4369 8888 \
       9100 9101 9102 9103 9104 9105 9106 9107 9108 9109

VOLUME ["/vernemq/log", "/vernemq/data", "/vernemq/etc"]

HEALTHCHECK CMD vernemq ping | grep -q pong

USER vernemq

CMD ["start_vernemq"]
