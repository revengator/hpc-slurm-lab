#!/bin/bash
#SBATCH --job-name=hello
#SBATCH --partition=main
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:01:00
#SBATCH --output=slurm-%j.out

echo "Hello from $(hostname) — SLURM job ${SLURM_JOB_ID:-?}"
echo "Date: $(date -u +%FT%TZ)"
echo "CPUs visible: $(nproc)"
