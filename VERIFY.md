# Verification checklist — SSH login node (v0.3.0)

Run these on the host where Docker is installed. They validate the new SSH
submit path end-to-end. Expected result is noted after each step.

## 1. Build the image (picks up sshd config + login role)

```bash
make build          # or: make rebuild   (~10 min first time)
```

Expect: image `hpc-slurm-lab:latest` built with no errors.

## 2. Provision the SSH key

```bash
make ssh-setup
```

Expect: a keypair at `./ssh/id_hpclab[.pub]`, `./ssh/authorized_keys`, and a
printed connection block (Host / Port / User / private key path). Re-running is
idempotent (reuses the existing key).

## 3. Start the cluster (now includes the `login` node)

```bash
make up
docker compose ps        # or: make status
```

Expect: `hpc-login` container running and healthy alongside
`slurmctld`, `slurmdbd`, `mysql`, `c1`, `c2`. Port 2222 published on the host.

## 4. Verify SSH + SLURM from the host shell

```bash
ssh -i ./ssh/id_hpclab -p 2222 admin@localhost sinfo
```

Expect: partition `main` listed with nodes `c1`,`c2` in `idle`/`mixed` state.

```bash
ssh -i ./ssh/id_hpclab -p 2222 admin@localhost \
    "sbatch --wrap='hostname; sleep 3' && sleep 5 && squeue && sacct -n"
```

Expect: `Submitted batch job <N>`, the job visible in `squeue`, and an
accounting row from `sacct` (proves the login node reaches slurmdbd too).

Password login (default `admin`/`admin`, dev/home-LAN only):

```bash
ssh -p 2222 admin@localhost sinfo        # password: admin
```

Expect: logs in with the password and prints `sinfo`.

One-time key install with `ssh-copy-id` (the simplest multi-machine flow):

```bash
make ssh-copy-id                          # asks for the password once
ssh -i ./ssh/id_hpclab -p 2222 admin@localhost sinfo   # now key-only, no prompt
```

Expect: the second command succeeds without a password. Repeat `ssh-copy-id`
from each machine you connect from — it appends, never overwrites.

Optional hardening — strict key-only auth:

```bash
echo 'SSH_PASSWORD=' >> .env && make up    # recreate login with password off
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -p 2222 admin@localhost true
```

Expect: `Permission denied (publickey)` (password refused).

## 5. Register with a remote-agent / SSH client

`make ssh-config` reprints the block. In your agentic tool's SSH/compute
host settings, enter Host/Port/User and paste the private key
(`./ssh/id_hpclab`). Then ask it to run a test `sbatch`.

## 6. From another machine on your home network

On the second machine (clone the repo, `make build`, `make ssh-setup`,
`make up`), connect from elsewhere using that machine's LAN IP:

```bash
ssh -i ./ssh/id_hpclab -p 2222 admin@<LAN-IP> sinfo
```

Expect: same `sinfo` output. If it hangs, check the host firewall allows
inbound on `SSH_PORT` (2222).

---

### Teardown

```bash
make down     # stop, keep volumes
make clean    # stop + delete volumes (DB, munge, jobs)
```

The `./ssh/` keys are local and gitignored; delete the folder to rotate them,
then re-run `make ssh-setup && make up`.
