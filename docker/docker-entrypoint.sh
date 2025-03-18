#!/bin/bash

set -e

################################################################################
# Get variable using a prefix
# Globals:
# 	PREFIX_ENV: Prefix used on variables
# Arguments:
# 	$1: Variable name to get the content, in format "${PREFIX_ENV}_$1"
# 	$2: Default value, if variable is empty or not exist
# Outputs:
# 	Output is the content of prefixed variable
# Returns:
# 	Nothing.
################################################################################
function get_env() {
	local env_name="${PREFIX_ENV}_${1}"
	if [ "${!env_name}" != "" ] ; then
		echo -n "${!env_name}"
	else
		echo -n "${2}"
	fi
}

################################################################################
# Set variable using a prefix.  The variable is set in global context.
# Globals:
# 	PREFIX_ENV: Prefix used on variables
# Arguments:
# 	$1: Variable name to set the content, in format "${PREFIX_ENV}_$1"
# Outputs:
# 	Nothing
# Returns:
# 	Nothing.
################################################################################
function set_env() {
	export "${PREFIX_ENV}_${1}=${2}"
}

export PREFIX_ENV=${PREFIX_ENV:-'APP'}
set_env FLASK_APP=$( get_env FLASK_APP "psyflask.bootstrap" )
set_env CELERY_INIT=$( get_env CELERY_INIT "$( get_env FLASK_APP )" )
set_env FORWARDED_ALLOW_IPS=$( get_env FORWARDED_ALLOW_IPS '*' )
set_env LOG_LEVEL=$( get_env LOG_LEVEL 'INFO' )
set_env CELERY_MAX_WORKERS=$( get_env CELERY_MAX_WORKERS 4 )
set_env CELERY_BEAT_DATABASE_FILE=$( get_env CELERY_BEAT_DATABASE_FILE '/tmp/celery_beat_database' )
set_env GUNICORN_CONF=$( get_env GUNICORN_CONF 'python:psyflask.gunicorn' )
export GOSU_ID="$( get_env UID ):$( get_env GID )"

################################################################################
# Execute gosu to change user and group uid, but works with exec and more
# friendly to nonroot. This is used to exec the same command when root or a
# normal execute a command on a container.
# If the inicial argument after the ID is exec, this function will try to be
# compatible with exec of bash.
# Globals:
# 	${PREFIX_ENV}_GOSU_ALLOW_ID: Default 0. If id 0 not has some kind of cap drop, set to something not equal to 0 and not empty.
# Arguments:
# 	$@: Same argument as gosu
# Outputs:
# 	Output the same stdout and stderr of executed program of command line arguments
# Returns:
# 	Return the same return code of executed program of command line arguments
################################################################################
function do_gosu() {
	user="$1"
	shift 1

	is_exec="false"
	if [ "$1" = "exec" ]; then
		is_exec="true"
		shift 1
	fi

	# If user is 0, he can change uid and gid
	if [ "$(id -u)" = "$( get_env GOSU_ALLOW_ID '0' )" ] ; then
		if [ "${is_exec}" = "true" ]; then
			exec gosu "${user}" "$@"
		else
			gosu "${user}" "$@"
			return "$?"
		fi
	else
		if [ "${is_exec}" = "true" ]; then
			exec "$@"
		else
			eval '"$@"'
			return "$?"
		fi
	fi
}

################################################################################
# Read and set variables from a readable file.
# Arguments:
# 	$1: A file with python format of env vars
# Outputs:
# 	Nothing
# Returns:
# 	Nothing
################################################################################
function parse_env() {
	if [ -r "$1" ]; then
		eval "$( /app/docker/shdotenv -d python -e "$1" )"
	fi
}

function bootstrap_conf() {
	if [ "${TZ}" ]; then
		ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && echo "${TZ}" > /etc/timezone
	fi
	if [ "$( get_env DO_CHOWN )" = "true" ] ; then
		find "$( get_env PATH )" -not -user "$( get_env UID )" -exec chown "$( get_env UID ):$( get_env GID )" {} \+ || true
	fi
}

for env_file in $( get_env ENV_FILES "/env.sh /run/secrets/env.sh" ) ; do
	parse_env "${env_file}"
done

bootstrap_conf

if [[ "start" == "$1" ]]; then
	for wait_for in "$( get_env WAIT_FOR )" ; do
		# shellcheck disable=SC2153
		echo "Wait for open port(${wait_for})...."
		/wait-for "${wait_for}" -- echo "${wait_for}" started
	done

	if [ "$( get_env DATABASE_UPGRADE "false" )" = "true" ]; then
		do_gosu "${GOSU_ID}" python manage.py migrate
	fi

	do_gosu "${GOSU_ID}" exec gunicorn -c "$( get_env GUNICORN_CONF )" --bind "0.0.0.0:$( get_env APP_PORT )" "$( get_env FLASK_APP )"
elif [[ "celery-worker" == "$1" ]]; then
	celery_queue="celery"
	if [ "${2}" ]; then
		celery_queue="${2}"
	fi
	do_gosu "${GOSU_ID}" exec celery -A "$(get_env CELERY_INIT)" worker --loglevel="$(get_env LOG_LEVEL)" \
		--pool=eventlet -E -Q "${celery_queue}" -O fair --autoscale="$(get_env CELERY_MAX_WORKERS),1"
elif [[ "celery-beat" == "$1" ]]; then
	do_gosu "${GOSU_ID}" exec celery -A "$( get_env CELERY_INIT)" beat \
		--loglevel="$(get_env LOG_LEVEL)" -s "$(get_env CELERY_BEAT_DATABASE_FILE)"
elif [[ "celery-flower" == "$1" ]]; then
	do_gosu "${GOSU_ID}" exec celery -A "$(get_env CELERY_INIT)" flower \
		--basic_auth="$( get_env CELERY_FLOWER_USER):$(get_env CELERY_FLOWER_PASSWORD)" \
		--address=0.0.0.0 --url_prefix="$(get_env CELERY_FLOWER_PREFIX)" \
		--port="$(get_env CELERY_FLOWER_PORT)"
elif [[ "healthcheck-celery-worker" == "$1" ]]; then
	HEALTHCHECK_OUT=$(
		do_gosu "${GOSU_ID}" celery -A "$(get_env CELERY_INIT)" inspect ping -d "celery@${HOSTNAME}" 2>&1
	)
	echo "${HEALTHCHECK_OUT}"
	grep -F -qs "celery@${HOSTNAME}: OK" <<< "${HEALTHCHECK_OUT}" || exit 1
	exit 0
elif [[ "healthcheck-celery-beat" == "$1" ]]; then
	cp "$(get_env CELERY_BEAT_DATABASE_FILE)" /tmp/celerybeat-schedule
	do_gosu "${GOSU_ID}" exec /beat_healthcheck.py
elif [[ "healthcheck-http-get" == "$1" ]]; then
	do_gosu "${GOSU_ID}" curl -SsLf "${2}" -o /tmp/null --connect-timeout 3 --max-time 20 -w "%{http_code} %{http_version} %{response_code} %{time_total}\n" || exit 1
	exit 0
elif [[ "healthcheck" == "$1" ]]; then
	do_gosu "${GOSU_ID}" curl -SsLf "http://127.0.0.1:$(get_env PORT)/healthcheck" -o /tmp/null --connect-timeout 3 --max-time 20 -w "%{http_code} %{http_version} %{response_code} %{time_total}\n" || exit 1
	exit 0
fi

exec "$@"

# vim: nu ts=4 noet ft=bash:
