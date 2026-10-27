#!/bin/sh
# Fetches the collection, serves the web page, and refreshes the collection
# every BGG_REFRESH_HOURS. With arguments, runs bgg-list with them instead.
set -eu

# Adjust user IDs to match host (e.g. PUID/PGID in .env or docker-compose).
# Matches the linuxserver pattern; when unset the app user keeps its build-time ID.
PUID="${PUID:-}"
PGID="${PGID:-}"
if [ -n "$PUID" ] && [ "$PUID" != "10001" ]; then
    usermod --uid "$PUID" app 2>/dev/null || true
fi
if [ -n "$PGID" ] && [ "$PGID" != "10001" ]; then
    # Try to modify the existing group; fall back to creating one.
    if getent group "$PGID" >/dev/null 2>&1; then
        usermod -g "$PGID" app 2>/dev/null || true
    else
        groupadd -g "$PGID" appgroup 2>/dev/null || true
        usermod -g "$PGID" app 2>/dev/null || true
    fi
fi

if [ "$#" -gt 0 ]; then
    exec bgg-list "$@"
fi

REFRESH_HOURS="${BGG_REFRESH_HOURS:-24}"
DATA=/app/site/collection.json

case "$REFRESH_HOURS" in
    ''|*[!0-9]*|0)
        echo "BGG_REFRESH_HOURS must be a whole number of hours, 1 or more" >&2
        exit 2
        ;;
esac

refresh() {
    # Write a new file and swap it in, so visitors never get a half-written one.
    # BGG_OPTIONS is split into words on purpose, for options such as -x.
    # shellcheck disable=SC2086
    if bgg-list -u "$BGG_USERS" --no-csv --no-table --json "$DATA.new" ${BGG_OPTIONS:-} && [ -s "$DATA.new" ]; then
        mv "$DATA.new" "$DATA"
    else
        rm -f "$DATA.new"
        echo "Refreshing the collection failed; serving the previous data, if any." >&2
    fi
}

# Without them the page is still served, so the container stays healthy (as
# when docker-image-refresh tests the image), but with no collection
refresher=
if [ -z "${BGG_API_KEY:-}" ] || [ -z "${BGG_USERS:-}" ]; then
    echo "Set BGG_API_KEY to your BoardGameGeek API key and BGG_USERS to comma-separated BoardGameGeek usernames;" \
        "serving the page without refreshing the collection until then." >&2
else
    refresh

    (
        while sleep "$((REFRESH_HOURS * 3600))"; do
            refresh
        done
    ) &
    refresher=$!
fi

python -m http.server "$PORT" --directory /app/site &
server=$!

# The shell runs as PID 1, so pass docker stop's signal on to both processes
trap 'kill "$server" ${refresher:+"$refresher"} 2>/dev/null; exit 0' TERM INT
wait "$server"
