#!/bin/bash
set -euo pipefail

ROLE="${1:-bash}"

mkdir -p /etc/munge /var/log/slurm /run/slurm /var/spool/slurmd /var/spool/slurmctld

if [[ ! -s /etc/munge/munge.key ]]; then
    dd if=/dev/urandom of=/etc/munge/munge.key bs=1 count=1024 status=none
fi
chown -R munge:munge /etc/munge
chmod 0700 /etc/munge
chmod 0400 /etc/munge/munge.key

sudo -u munge /usr/sbin/munged --force
for _ in {1..10}; do
    munge -n >/dev/null 2>&1 && break
    sleep 0.2
done

wait_for_host() {
    local host="$1" port="$2"
    for _ in {1..60}; do
        if (echo >/dev/tcp/${host}/${port}) >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    echo "Timeout waiting for ${host}:${port}" >&2
    return 1
}

case "$ROLE" in
    slurmctld)
        wait_for_host slurmdbd 6819 || true
        exec /usr/local/sbin/slurmctld -D -vv
        ;;

    slurmdbd)
        wait_for_host mysql 3306
        exec /usr/local/sbin/slurmdbd -D -vv
        ;;

    slurmd)
        EXTRA=()
        if [[ -n "${NODE_FEATURES:-}" ]]; then
            EXTRA+=("Feature=${NODE_FEATURES}")
        fi
        if [[ -n "${NODE_GRES:-}" ]]; then
            EXTRA+=("Gres=${NODE_GRES}")
        fi
        wait_for_host slurmctld 6817
        if [[ ${#EXTRA[@]} -gt 0 ]]; then
            exec /usr/local/sbin/slurmd -D -Z --conf "${EXTRA[*]}" -vv
        else
            exec /usr/local/sbin/slurmd -D -Z -vv
        fi
        ;;

    bash|shell)
        exec /bin/bash -l
        ;;

    *)
        exec "$@"
        ;;
esac
