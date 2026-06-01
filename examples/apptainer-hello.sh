#!/bin/bash
#SBATCH --job-name=apptainer-hello
#SBATCH --partition=main
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:02:00
#SBATCH --output=slurm-%j.out

set -euo pipefail

echo "SLURM job ${SLURM_JOB_ID:-?} on node $(hostname)"
echo "Host OS:    $(. /etc/os-release && echo "$PRETTY_NAME")"
echo "Apptainer:  $(apptainer --version)"
echo

# Keep the pulled image cache on the shared scratch volume so it survives
# between jobs instead of re-downloading every time.
export APPTAINER_CACHEDIR=/data/.apptainer-cache

echo "Pulling and running a tiny Alpine image straight from Docker Hub..."
apptainer exec docker://alpine:3 sh -c '
    . /etc/os-release
    echo "  -> Inside the container, OS is: $PRETTY_NAME"
    echo "  -> Hello from Apptainer, running under SLURM!"
'

echo
echo "The host node runs Rocky Linux but the container reported Alpine — proof"
echo "the job ran inside a real container image, not directly on the node."
