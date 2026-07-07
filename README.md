# hpc-slurm-lab

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20368838.svg)](https://doi.org/10.5281/zenodo.20368838)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A minimal, modern SLURM HPC cluster you can run on your laptop with Docker
Compose, for testing pipelines and learning. Works on **Apple Silicon (arm64)**
and **Linux x86_64 with optional NVIDIA GPU**.

- SLURM 25.05 (built from source on Rocky Linux 9)
- Accounting enabled (`slurmdbd` + MariaDB → `sacct` works)
- Dynamic node registration (`slurmd -Z`) — scale workers without rebuilding
- `Lmod` + `EasyBuild` baked in, with a shared `/software` volume for HPC-style
  modules (`module load samtools/1.21-...`)
- Optional NVIDIA GPU node via Docker profile (`make up-gpu`)
- **Apptainer** (Singularity) preinstalled — run Docker/OCI images from SLURM
  jobs, the way real HPC clusters do
- **SSH login node** — submit jobs remotely, or wire the cluster into any
  SSH-capable client or agent as a compute target (`make ssh-setup`)

## Requirements

- Docker 24+ with Compose v2 — the daemon must be **running** (start Docker
  Desktop, or `systemctl start docker` on Linux) before any `make` target that
  builds or starts containers
- ~3 GB free disk for the built image
- For GPU: Linux host with NVIDIA driver + `nvidia-container-toolkit`

## Quickstart

```bash
cp .env.example .env          # optional, edit values
make build                    # first time, ~10 min (compiles SLURM from source)
make up                       # CPU-only cluster (slurmctld + 2 nodes + db)
make status                   # sinfo / squeue
make test                     # submit examples/hello.sh
make shell                    # interactive shell on the controller as `admin`
```

Inside the `admin` shell:

```bash
sinfo
sbatch --wrap='hostname; sleep 5'
squeue
sacct
```

## Use over SSH

This lab ships an **SSH login node** — a submit host that runs `sshd`, shares
the cluster's `munge` key and `slurm.conf`, and talks to `slurmctld` — so you
can drive it over SSH exactly like a real HPC cluster.

The login node is a standard OpenSSH server that accepts key-based auth and
exposes the SLURM CLI (`sbatch` / `squeue` / `sacct`). Anything that can open an
SSH connection with a private key connects the same way — an AI agent or
assistant, a CI runner, a plain `ssh` command, or a script. If your client
supports registering an SSH "compute target" or "remote host", point it at the
Host / Port / User / key that `make ssh-setup` prints.

```bash
make ssh-setup   # generate the lab keypair + print the connection block
make up          # start the cluster (now includes the `login` node)
make ssh         # optional: open an interactive session to sanity-check
```

`make ssh-setup` creates an ed25519 keypair under `./ssh/` (gitignored) and
prints everything you need:

```
  Host             : localhost   (use this machine's LAN IP from another box)
  Port             : 2222
  User             : admin
  Private key      : /path/to/hpc-slurm-lab/ssh/id_hpclab
  Scheduler        : SLURM (sbatch / squeue / sacct)
```

Register that Host / Port / User and the private key with your client — most
SSH-based agents and tools have an "add SSH host" or "add remote compute" form
where you paste them. Reprint the block any time with `make ssh-config`.

### First connection — step by step

The cluster side is fully scriptable; **registering the host with a client is a
one-time manual step** (pasting a private key and opening an outbound SSH
connection is a decision the human makes, not the agent). Start to finish:

1. **Docker running** — start Docker Desktop (or `systemctl start docker`).
2. **`make ssh-setup`** — creates `./ssh/id_hpclab` and prints the connection
   block (Host / Port / User / key path).
3. **`make up`** — starts the cluster, including the `login` node on port 2222.
4. **Register the host** with your client:
   - *Agents / tools with an SSH-host form*: paste Host / Port / User and the
     contents of `./ssh/id_hpclab` (the private key) into their "add SSH host"
     or "add remote compute" dialog.
   - *A plain SSH client*: add a block to `~/.ssh/config` (the one printed by
     `make ssh-setup`) and connect with `ssh hpc-slurm-lab`.
5. **First connect may hit a host-key prompt.** A non-interactive client
   (like an agent) cannot accept an unknown host key at a prompt, so either use
   `StrictHostKeyChecking accept-new` in your `~/.ssh/config` (the printed block
   already does), or — if you rebuilt the cluster and a *stale* key is cached —
   run `make ssh-fix-hostkey` once. See the host-key note under
   [Notes & caveats](#notes--caveats).

Once registered, just ask the agent (or run the client) to submit work:
`sbatch`, `squeue`, `sacct` all run over that one SSH connection.

**On this laptop**, use `localhost:2222`. **On another machine at home**, run
the same three commands there and connect to that machine's LAN IP on the same
port (the login node listens on all interfaces). Change the port with
`SSH_PORT=... make up` or by setting `SSH_PORT` in `.env`.

Verify the path end-to-end from any shell:

```bash
ssh -i ./ssh/id_hpclab -p 2222 admin@localhost sinfo
ssh -i ./ssh/id_hpclab -p 2222 admin@localhost \
    "sbatch --wrap='hostname; sleep 3' && squeue"
```

### Authentication: password and/or key

For a zero-config local/home lab, the login node ships with a **default
password** (`admin` / `admin`) so you can log in immediately:

```bash
ssh -p 2222 admin@localhost          # password: admin
```

The simplest way to add a key from any machine — no file juggling — is to log
in once with the password and let `ssh-copy-id` install your key:

```bash
make ssh-setup                       # once, to create a local keypair
make ssh-copy-id                     # asks for the password once, installs the key
# or, from a machine that already has its own key:
ssh-copy-id -p 2222 admin@<host>
```

`ssh-copy-id` **appends** to the login node's `authorized_keys`, so repeat it
from each machine you want to connect from — no need to disable the password
afterward. Change or disable the password by setting `SSH_PASSWORD` in `.env`
(`SSH_PASSWORD=` empty → strict key-only auth).

> **Agents need a key.** A non-interactive client (an agent, a CI runner, any
> automated SSH connection) can't answer a password prompt, so register the
> cluster with the private key (`make ssh-setup` → paste `./ssh/id_hpclab`), not
> the password. The password is for your own interactive logins and for
> bootstrapping keys with `ssh-copy-id`.

> ⚠️ **Dev/home-LAN only.** The default `admin`/`admin` password and the
> published port are meant for a laptop or a trusted home network. Do **not**
> expose this to the public internet. For a hardened setup, set `SSH_PASSWORD=`
> (empty) for key-only auth; root login is always disabled.

## With NVIDIA GPU (Linux only)

```bash
make up-gpu                   # adds compute node g1 with NVIDIA passthrough
sbatch --gres=gpu:1 --wrap='nvidia-smi'
```

Adjust `GPU_GRES` in `.env` to match your card (e.g. `gpu:rtx4090:1`).

## Architecture

| Service     | Role                                              |
|-------------|---------------------------------------------------|
| `mysql`     | MariaDB 11 — accounting backend                   |
| `slurmdbd`  | Accounting daemon (`sacct`, `sreport`)            |
| `slurmctld` | SLURM controller                                  |
| `login`     | SSH submit host — entry point for users and SSH agents |
| `c1`, `c2`  | CPU compute nodes (dynamically registered)        |
| `g1`        | GPU compute node (profile `gpu`)                  |

All SLURM containers share:

- `munge` volume → shared authentication key
- `./software` (bind mount) → EasyBuild installs persist on host
- `jobs` volume → `/data` shared scratch

## Adding software with EasyBuild

EasyBuild + Lmod are preinstalled. Builds live in `./software/easybuild` and
generate modulefiles under `./software/modules/all`, all visible from every
node.

```bash
make shell
eb --search SAMtools           # find a recipe
eb SAMtools-1.21-GCC-13.2.0.eb --robot --install-latest-eb-release
module avail
module load SAMtools/1.21-GCC-13.2.0
samtools --version
```

## Running containers with Apptainer

Real HPC clusters don't let users run Docker on the compute nodes — the Docker
daemon runs as root, which is a non-starter on a shared system. Instead they use
**[Apptainer](https://apptainer.org/)** (formerly Singularity), which runs
containers rootless, as your own user, and plugs into the batch scheduler. This
lab ships Apptainer so you can practice that exact workflow:

```bash
make test-apptainer        # submits examples/apptainer-hello.sh
```

The job pulls a tiny Alpine image straight from Docker Hub and runs it inside a
SLURM allocation. The host node is Rocky Linux but the container reports Alpine,
which proves it really ran inside the image:

```bash
sbatch examples/apptainer-hello.sh
```

Apptainer consumes OCI/Docker images directly, so anything on a registry works —
including images you publish yourself:

```bash
apptainer exec docker://alpine:3 cat /etc/os-release
apptainer pull tool.sif docker://ghcr.io/<owner>/<image>:<tag>
apptainer run  tool.sif --help
```

(The first pull needs outbound internet on the compute node.)

> ⚠️ **Development / education only.** This lab runs the SLURM compute nodes as
> `privileged` Docker containers so Apptainer can mount and run images from
> inside them — handy on a laptop, but not how a real cluster is built (there the
> compute nodes are real hosts). To make image mounts work on Docker Desktop's
> kernel it also sets `allow setuid-mount squashfs = yes` instead of relying on
> signed images + ECL. It's a learning sandbox: don't use this configuration as a
> template for a production cluster.

## Common commands

```bash
make build      # build image
make up         # start CPU cluster
make up-gpu     # start CPU + GPU
make down       # stop, keep volumes
make clean      # stop + delete EVERYTHING (containers, volumes, images, network)
make rebuild    # rebuild image no-cache and recreate
make shell      # shell on controller as admin
make ssh-setup  # generate SSH key + print connection block
make ssh-copy-id# install your key on the login node (password login once)
make ssh        # SSH into the login node as admin
make ssh-config # reprint the SSH connection block
make ssh-fix-hostkey # forget a stale host key after a rebuild
make logs       # follow all logs
make status     # sinfo + squeue
make nodes      # scontrol show nodes
make test       # submit examples/hello.sh and print output
make test-apptainer # run a container via Apptainer under SLURM
```

## Layout

```
hpc-slurm-lab/
├── docker-compose.yml
├── Makefile
├── .env.example
├── images/slurm/
│   ├── Dockerfile          # Rocky 9 + SLURM 25.05 from source + EasyBuild + Lmod
│   ├── entrypoint.sh       # role switcher (slurmctld | slurmdbd | slurmd | login)
│   ├── slurm.conf
│   └── slurmdbd.conf
├── examples/
│   └── hello.sh
└── software/               # bind mount; EasyBuild installs land here
```

## Notes & caveats

- **No cgroup constraints.** Container friendly: jobs use
  `proctrack/linuxproc` and `task/affinity`. Add cgroup constraints later if
  you need to enforce memory/CPU isolation.
- **No MPI configured by default.** Add `MpiDefault=pmix` and the matching
  packages when you actually need inter-node MPI.
- **slurm.conf changes** require `make reconfigure` (live) or `make rebuild`
  (full rebuild) — it's baked into the image, not a host file.
- **SSH login node** (`make ssh-setup`) for remote submit from any SSH client
  or agent; `make shell` still drops you onto the controller directly for quick
  checks.
- **SSH host keys persist** in the `ssh_hostkeys` volume, so the login node
  keeps the same identity across `make down && make up`. A `make clean` wipes
  that volume, so the next `make up` generates fresh host keys — if a client
  that connected before now reports `host key verification failed`, run
  `make ssh-fix-hostkey` once to forget the stale key.
- **GPU on macOS** is not supported (no NVIDIA on Apple Silicon).

## Contributions

This is a personal project published for transparency and reference.
Pull requests are not actively reviewed — feel free to fork instead.

## License

MIT — see [LICENSE](LICENSE).
