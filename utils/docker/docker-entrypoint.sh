#!/bin/bash

set -e

APP_CELERY_INIT="app.celery_client.bootstrap"

parse_env(){
	if [ -r "$1" ] ; then
		while IFS="=" read key value  ; do
			export "${key}=${value}"
		done<<<"$( egrep '^[^#]+=.*' "$1" )"
	fi
}

bootstrap_conf(){
	if [ "${TZ}" ] ; then
		ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && echo "${TZ}" > /etc/timezone
	fi
	find /app -not -user "${APP_UID}" -exec chown "${APP_UID}:${APP_GID}" {} \+
}

parse_env '/env.sh'
parse_env '/run/secrets/env.sh'

bootstrap_conf

if [[ "start" == "$1" ]]; then
	echo "Checking DB(${DB_HOST}:${DB_PORT}) UP...."
	/app/utils/docker/wait-for "${DB_HOST}:${DB_PORT}" -- echo DB "${DB_HOST}:${DB_PORT}" started
	echo "Checking Rabbit(${MESSAGE_BROKER_HOST}:${MESSAGE_BROKER_PORT}) server UP...."
	/app/utils/docker/wait-for "${MESSAGE_BROKER_HOST}:${MESSAGE_BROKER_PORT}" -- echo Message Broker Server: "${MESSAGE_BROKER_HOST}:${MESSAGE_BROKER_PORT}" started

	if [ "${APP_DONT_INIT_DATABASE}" != "true" ] ; then
		gosu "${APP_UID}:${APP_GID}" python ./manage.py migrate
	fi

	exec gosu "${APP_UID}:${APP_GID}" gunicorn --bind "0.0.0.0:${APP_PORT}" --capture-output --error-logfile - --worker-class eventlet -w 1 "app:create_app()"
elif [[ "celery-worker" == "$1" ]]; then
	exec gosu "${APP_UID}:${APP_GID}" celery -A "${APP_CELERY_INIT}" worker --loglevel=INFO --pool=eventlet -E
elif [[ "celery-beat" == "$1" ]]; then
	exec gosu "${APP_UID}:${APP_GID}" celery -A "${APP_CELERY_INIT}" beat --loglevel=INFO
elif [[ "celery-flower" == "$1" ]]; then
	exec gosu "${APP_UID}:${APP_GID}" celery -A "${APP_CELERY_INIT}" flower --basic_auth="${CELERY_FLOWER_USER}:${CELERY_FLOWER_PASSWORD}" --address=0.0.0.0 --url_prefix="${CELERY_FLOWER_PREFIX}" --port="${CELERY_FLOWER_PORT}"
elif [[ "healthcheck-celery-worker" == "$1" ]]; then
	HEALTHCHECK_OUT=$( gosu "${APP_UID}:${APP_GID}" celery -A "${APP_CELERY_INIT}" inspect ping -d "celery@${HOSTNAME}"  2>&1 )
	echo "${HEALTHCHECK_OUT}"
	fgrep -qs "celery@${HOSTNAME}: OK" <<<"${HEALTHCHECK_OUT}" || exit 1
	exit 0
elif [[ "healthcheck-celery-beat" == "$1" ]]; then
	cp celerybeat-schedule /tmp/celerybeat-schedule
	exec gosu "${APP_UID}:${APP_GID}" utils/docker/beat_healthcheck.py
elif [[ "healthcheck-http-get" == "$1" ]]; then
	gosu "${APP_UID}:${APP_GID}" curl -SsLf "${2}" -o /tmp/null --connect-timeout 3 --max-time 20 -w "%{http_code} %{http_version} %{response_code} %{time_total}\n" || exit 1
	exit 0
elif [[ "healthcheck" == "$1" ]]; then
	gosu "${APP_UID}:${APP_GID}" curl -SsLf "http://127.0.0.1:${APP_PORT}/login" -o /tmp/null --connect-timeout 3 --max-time 20 -w "%{http_code} %{http_version} %{response_code} %{time_total}\n" || exit 1
	exit 0
fi

exec "$@"

