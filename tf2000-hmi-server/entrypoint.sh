#!/bin/sh
# SPDX-License-Identifier: Zero-Clause BSD

# Starts the ADS router (TcSystemServiceUm), initializes the HMI server instance on
# first start and runs the TF2000 HMI server.
# The HMI server command is taken from the TcHmiSrv.service unit shipped with the
# package, unless HMI_SERVER_CMD is set.

set -e

router_pid=""
hmi_pid=""

stop() {
    [ -n "$hmi_pid" ] && kill "$hmi_pid" 2>/dev/null || true
    [ -n "$router_pid" ] && kill "$router_pid" 2>/dev/null || true
    wait
    exit 0
}
trap stop TERM INT

echo "Starting TcSystemServiceUm (AMS Net ID ${AMS_NETID})..."
/usr/bin/TcSystemServiceUm -f 0x7 -i "${AMS_NETID}" -p /var/run/TcSystemServiceUm.pid &
router_pid=$!

# Wait until the local ADS router answers
i=0
until tcadstool 127.0.0.1.1.1 state >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge 30 ]; then
        echo "ADS router not ready after 30s, continuing anyway"
        break
    fi
    sleep 1
done

data_dir=/var/lib/tchmisrv/service
if [ -z "$(ls -A "$data_dir" 2>/dev/null)" ]; then
    if [ -z "${HMI_PASSWORD}" ]; then
        echo "HMI_PASSWORD is not set; it is required for TcHmiSrv --initialize" >&2
        exit 1
    fi
    echo "Initializing HMI server: TcHmiSrv --initialize ${HMI_INIT_ARGS} --password=****"
    # shellcheck disable=SC2086
    TcHmiSrv --initialize ${HMI_INIT_ARGS} "--password=${HMI_PASSWORD}"
fi

if [ -z "${HMI_SERVER_CMD}" ]; then
    unit=""
    for dir in /lib/systemd/system /usr/lib/systemd/system /etc/systemd/system; do
        if [ -f "$dir/TcHmiSrv.service" ]; then
            unit="$dir/TcHmiSrv.service"
            break
        fi
    done
    if [ -z "$unit" ]; then
        echo "TcHmiSrv.service not found; set HMI_SERVER_CMD" >&2
        exit 1
    fi
    HMI_SERVER_CMD=$(sed -n 's/^ExecStart=//p' "$unit" | head -n 1 | sed 's/^[-@+!:]*//')
    workdir=$(sed -n 's/^WorkingDirectory=//p' "$unit" | head -n 1)
    [ -n "$workdir" ] && cd "$workdir"
    # Honor simple Environment=NAME=value lines of the unit
    for assignment in $(sed -n 's/^Environment=//p' "$unit" | tr -d '"'); do
        export "$assignment"
    done
fi

echo "Starting HMI server: ${HMI_SERVER_CMD}"
${HMI_SERVER_CMD} &
hmi_pid=$!

# Exit when the HMI server exits so the container restart policy applies
wait "$hmi_pid"
status=$?
kill "$router_pid" 2>/dev/null || true
exit "$status"
