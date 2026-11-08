#!/bin/sh
# DSH Control daemon.
#
# launchd starts this script when the app writes
# /var/mobile/Documents/dsh/.dshcontrol-request, runs it as mobile, and it
# exits again. It is the only part that may run the dsh launcher and signal
# the dsh process — the app itself is sandboxed for WebKit's sake.
#
# Only shell builtins are used: a launchd job's PATH holds none of the
# bootstrap's tools (no sed, no cat, no date).
set -u
DIR=/var/mobile/Documents/dsh
REQ="$DIR/.dshcontrol-request"
RES="$DIR/.dshcontrol-result"

[ -f "$REQ" ] || exit 0

CMD=""
while IFS= read -r LINE || [ -n "$LINE" ]; do
	case "$LINE" in
	*'"command"'*)
		REST=${LINE#*\"command\"}
		REST=${REST#*\"}
		CMD=${REST%%\"*}
		;;
	esac
done <"$REQ"

PID=""
if [ -f "$DIR/dsh-web.pid" ]; then
	read -r PID <"$DIR/dsh-web.pid" || true
fi

OK=false
MSG=unknown-command

case "$CMD" in
start)
	# Always hand it to the launcher: it is idempotent (it reports an already
	# running instance itself) and a stale pid file must not block a restart.
	"$DIR/dsh" >/dev/null 2>&1 &
	OK=true
	MSG=started
	;;
stop)
	if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
		if kill "$PID" 2>/dev/null; then
			OK=true
			MSG=stopped
		else
			OK=false
			MSG=kill-failed
		fi
	else
		OK=false
		MSG=not-running
	fi
	;;
esac

printf '{"ok":%s,"message":"%s","command":"%s"}\n' "$OK" "$MSG" "$CMD" >"$RES"

exit 0
