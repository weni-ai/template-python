FROM python:3-slim-buster AS base

ARG APP_UID=1000
ARG APP_GID=500

ARG NODE_VERSION="14"

ARG BUILD_DEPS="\
  python3-dev default-libmysqlclient-dev build-essential \
  build-essential \
  libmariadbclient-dev \
  git cmake \
  autoconf pkg-config autoconf libtool automake \
  librabbitmq-dev \
  libmariadbclient-dev-compat"
ARG NODE_BUILD_DEPS=""

ARG RUNTIME_DEPS="\
  tzdata \
  libmariadb3 \
  librabbitmq4 \
  netcat \
  curl \
  gosu"
ARG NODE_RUNTIME_DEPS=""

ARG APP_VERSION="0.1"

# set environment variables
ENV APP_VERSION=${APP_VERSION} \
  RUNTIME_DEPS=${RUNTIME_DEPS} \
  BUILD_DEPS=${BUILD_DEPS} \
  NODE_RUNTIME_DEPS=${NODE_RUNTIME_DEPS} \
  NODE_BUILD_DEPS=${NODE_BUILD_DEPS} \
  NODE_VERSION=${NODE_VERSION} \
  APP_UID=${APP_UID} \
  APP_GID=${APP_GID} \
  PYTHONDONTWRITEBYTECODE=1 \
  PYTHONUNBUFFERED=1 \
  PYTHONIOENCODING=UTF-8 \
  PIP_DISABLE_PIP_VERSION_CHECK=1 \
  PATH="/install/bin:${PATH}"

LABEL app=${VERSION} \
  os="debian" \
  os.version="10" \
  name="APP ${APP_VERSION}" \
  description="APP image" \
  maintainer="APP Team"

RUN addgroup --gid "${APP_GID}" app_group \
  && useradd --system -m -d /app -u "${APP_UID}" -g "${APP_GID}" app_user

# set work directory
WORKDIR /app

FROM base AS build

RUN if [ ! "x${NODE_BUILD_DEPS}" = "x" ] ; then apt-get update \
 && apt-get install -y --no-install-recommends curl -y \
 && curl -sL https://deb.nodesource.com/setup_"${NODE_VERSION}".x | bash - \
 && apt-get install -y nodejs \
 && npm install -g ${NODE_BUILD_DEPS} ; fi

RUN if [ ! "x${BUILD_DEPS}" = "x" ] ; then apt-get update \
  && apt-get install -y --no-install-recommends ${BUILD_DEPS} ; fi

# install dependencies
COPY requirements.txt requirements-freeze.tx[t] .
RUN mkdir /install \
  && if test -e requirements-freeze.txt; then pip install --no-cache-dir --prefix=/install -r requirements-freeze.txt ; else pip install --no-cache-dir --prefix=/install -r requirements.txt ; fi

# copy project
COPY . .

FROM base

COPY --from=build /install /usr/local
COPY --from=build --chown=app_user:app_group /app /app

RUN if [ ! "x${NODE_RUNTIME_DEPS}" = "x" ] ; then apt-get update \
 && apt-get install -y --no-install-recommends curl -y \
 && curl -sL https://deb.nodesource.com/setup_"${NODE_VERSION}".x | bash - \
 && apt-get install -y nodejs \
 && npm install -g ${NODE_RUNTIME_DEPS} ; fi

RUN apt-get update \
  && SUDO_FORCE_REMOVE=yes apt-get remove --purge -y ${BUILD_DEPS} \
  && apt-get autoremove -y \
  && apt-get install -y --no-install-recommends ${RUNTIME_DEPS} \
  && rm -rf /usr/share/man \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/app/utils/docker/docker-entrypoint.sh"]

CMD ["start"]
#CMD sleep 6d

HEALTHCHECK --interval=15s --timeout=20s --start-period=60s \
  CMD /app/utils/docker/docker-entrypoint.sh healthcheck

