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

## Requirements

- Docker 24+ with Compose v2
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
| `slurmctld` | SLURM controller — entry point for users          |
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
make clean      # stop + delete volumes (DB, munge, jobs)
make rebuild    # rebuild image no-cache and recreate
make shell      # shell on controller as admin
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
│   ├── entrypoint.sh       # role switcher (slurmctld | slurmdbd | slurmd)
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
- **No SSH login node.** Use `make shell` to enter the controller as `admin`.
- **GPU on macOS** is not supported (no NVIDIA on Apple Silicon).

## Contributions

This is a personal project published for transparency and reference.
Pull requests are not actively reviewed — feel free to fork instead.

## License

MIT — see [LICENSE](LICENSE).
