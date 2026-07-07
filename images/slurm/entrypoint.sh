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

    login)
        # SSH submit host: reachable over SSH, talks to slurmctld, runs no
        # slurmd. This is the entry point remote/agentic tools (or a plain
        # `ssh`) connect to in order to run sbatch/squeue/sacct against the
        # cluster.
        #
        # Persist the host keys in a named volume mounted at
        # /etc/ssh-hostkeys so the server identity stays stable across
        # `make down && make up`. Regenerating them on every recreate is what
        # triggers "Host key verification failed" in non-interactive SSH
        # clients (they cannot accept a changed/unknown key at a prompt).
        HOSTKEY_DIR=/etc/ssh-hostkeys
        install -d -m 0755 "$HOSTKEY_DIR"
        for t in rsa ecdsa ed25519; do
            kf="$HOSTKEY_DIR/ssh_host_${t}_key"
            [[ -f "$kf" ]] || ssh-keygen -q -t "$t" -f "$kf" -N ''
        done

        # Install the lab's public key for the admin user. The key is
        # bind-mounted read-only at /etc/ssh-lab/authorized_keys by
        # docker-compose (generated on the host by `make ssh-setup`).
        install -d -m 0700 -o admin -g admin /home/admin/.ssh
        if [[ -s /etc/ssh-lab/authorized_keys ]]; then
            install -m 0600 -o admin -g admin \
                /etc/ssh-lab/authorized_keys /home/admin/.ssh/authorized_keys
        fi

        # Optional password login (opt-in via SSH_PASSWORD). Handy for a
        # local/home lab: set a password so `ssh-copy-id` can install a key on
        # the first login. Leave SSH_PASSWORD empty for strict key-only auth
        # (the default when unset). The 05- drop-in sorts before 10-hpclab.conf
        # so its PasswordAuthentication value wins.
        if [[ -n "${SSH_PASSWORD:-}" ]]; then
            echo "admin:${SSH_PASSWORD}" | chpasswd
            cat > /etc/ssh/sshd_config.d/05-hpclab-password.conf <<'EOF'
# Enabled because SSH_PASSWORD is set (dev/home-LAN convenience).
PasswordAuthentication yes
EOF
            echo "INFO: password login enabled for user 'admin'." >&2
        elif [[ ! -s /home/admin/.ssh/authorized_keys ]]; then
            echo "WARNING: no authorized_keys and no SSH_PASSWORD set — you" >&2
            echo "         cannot log in. Run 'make ssh-setup' or set" >&2
            echo "         SSH_PASSWORD in .env, then 'make up'." >&2
        fi

        # munged is already running (started above, before this case).
        wait_for_host slurmctld 6817 || true
        exec /usr/sbin/sshd -D -e
        ;;

    bash|shell)
        exec /bin/bash -l
        ;;

    *)
        exec "$@"
        ;;
esac
