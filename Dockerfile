ARG DOCKER_VERSION=20.10.13

FROM docker:${DOCKER_VERSION} AS docker-cli

FROM ghcr.io/linuxserver/baseimage-alpine:3.15 AS build

ARG COMPOSE_VERSION

RUN \
  apk -U --update --no-cache add \
    bash \
    build-base \
    ca-certificates \
    curl \
    gcc \
    git \
    jq \
    libc-dev \
    libffi-dev \
    libgcc \
    make \
    musl-dev \
    openssl \
    openssl-dev \
    python3-dev \
    py3-pip \
    zlib-dev

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker

RUN \
  mkdir -p /compose && \
  if [ -z ${COMPOSE_VERSION+x} ]; then \
    COMPOSE_VERSION=$(curl -sX GET "https://api.github.com/repos/docker/compose/releases" \
    | jq -r 'first(.[] | select(.tag_name | startswith("1."))) | .tag_name'); \
  fi && \
  git clone https://github.com/docker/compose.git && \
  cd /compose && \
  git checkout "${COMPOSE_VERSION}" && \
  pip3 install -U pip && \
  pip install -U --ignore-installed \
      virtualenv \
      tox && \
  PY_ARG=$(printf "$(python3 -V)" | awk '{print $2}' | awk 'BEGIN{FS=OFS="."} NF--' | sed 's|\.||g' | sed 's|^|py|g') && \
  sed -i "s|envlist = .*|envlist = ${PY_ARG},pre-commit|g" tox.ini && \
  tox --notest && \
  mkdir -p dist && \
  chmod 777 dist && \
  /compose/.tox/${PY_ARG}/bin/pip3 install -q -r requirements-build.txt && \
  echo "$(script/build/write-git-sha)" > compose/GITSHA && \
  PYINSTVER=$(cat requirements-build.txt | grep pyinstaller | sed 's|pyinstaller==|v|') && \
  git clone --single-branch --branch develop https://github.com/pyinstaller/pyinstaller.git /tmp/pyinstaller && \
  cd /tmp/pyinstaller/bootloader && \
  git checkout ${PYINSTVER} && \
  /compose/.tox/${PY_ARG}/bin/python3 ./waf configure --no-lsb all && \
  /compose/.tox/${PY_ARG}/bin/pip3 install .. && \
  cd /compose && \
  export PATH="/compose/pyinstaller:${PATH}" && \
  /compose/.tox/${PY_ARG}/bin/pyinstaller --exclude-module pycrypto --exclude-module PyInstaller docker-compose.spec && \
  ls -la dist/ && \
  ldd dist/docker-compose && \
  mv dist/docker-compose /usr/local/bin && \
  docker-compose version

############## runtime stage ##############
FROM ghcr.io/linuxserver/baseimage-alpine:3.15

ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="aptalca"

COPY --from=build /compose/docker-compose-entrypoint.sh /usr/local/bin/docker-compose-entrypoint.sh
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=build /usr/local/bin/docker-compose /usr/local/bin/docker-compose
ENTRYPOINT ["sh", "/usr/local/bin/docker-compose-entrypoint.sh"]
