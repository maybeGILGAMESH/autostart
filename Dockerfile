FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    coreutils \
    findutils \
    git \
    iproute2 \
    procps \
    python3 \
    python3-venv \
    sed \
    util-linux \
  && rm -rf /var/lib/apt/lists/*

COPY . /app
RUN chmod +x /app/docker/entrypoint.sh \
  && chmod +x /app/*.sh \
  && chmod +x /app/*.py

ENTRYPOINT ["/app/docker/entrypoint.sh"]
CMD ["help"]
