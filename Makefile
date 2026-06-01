.DEFAULT_GOAL := help
SHELL := /bin/bash

ifneq (,$(wildcard .env))
include .env
export
endif

COMPOSE       := docker compose
SLURM_VERSION ?= 25.05.3
BASE_IMAGE    ?= rockylinux:9
IMAGE_TAG     ?= hpc-slurm-lab:latest

# --- Help ---------------------------------------------------------------------

.PHONY: help
## Show this help.
help:
	@awk 'BEGIN{FS=":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} \
	     /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# --- Lifecycle ----------------------------------------------------------------

.PHONY: build
build: ## Build the slurm image (slow first time, ~10 min).
	docker build \
		--build-arg SLURM_VERSION=$(SLURM_VERSION) \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		-t $(IMAGE_TAG) \
		./images/slurm

.PHONY: up
up: ## Start the cluster (CPU nodes only).
	$(COMPOSE) up -d

.PHONY: up-gpu
up-gpu: ## Start the cluster including the NVIDIA GPU node g1.
	$(COMPOSE) --profile gpu up -d

.PHONY: down
down: ## Stop the cluster (keeps volumes).
	$(COMPOSE) --profile gpu down

.PHONY: clean
clean: ## Stop and delete EVERYTHING (containers, volumes, network). Software/ is preserved.
	$(COMPOSE) --profile gpu down --volumes --remove-orphans

.PHONY: rebuild
rebuild: ## Rebuild image from scratch and restart.
	docker build --no-cache \
		--build-arg SLURM_VERSION=$(SLURM_VERSION) \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		-t $(IMAGE_TAG) \
		./images/slurm
	$(COMPOSE) up -d --force-recreate

# --- Access -------------------------------------------------------------------

.PHONY: shell
shell: ## Interactive shell on slurmctld as admin user.
	$(COMPOSE) exec --user admin slurmctld bash -l

.PHONY: root
root: ## Interactive shell on slurmctld as root.
	$(COMPOSE) exec slurmctld bash -l

.PHONY: logs
logs: ## Follow logs (Ctrl+C to stop).
	$(COMPOSE) logs -f

# --- Cluster info -------------------------------------------------------------

.PHONY: status
status: ## Show sinfo + squeue snapshot.
	$(COMPOSE) exec --user admin slurmctld bash -lc 'sinfo; echo; squeue'

.PHONY: nodes
nodes: ## Show registered nodes (scontrol).
	$(COMPOSE) exec --user admin slurmctld bash -lc 'scontrol show nodes'

.PHONY: reconfigure
reconfigure: ## Reload slurm.conf on running cluster.
	$(COMPOSE) exec slurmctld scontrol reconfigure

# --- Quick test ---------------------------------------------------------------

.PHONY: test
test: ## Submit examples/hello.sh and tail its output.
	$(COMPOSE) cp examples/hello.sh slurmctld:/tmp/hello.sh
	$(COMPOSE) exec --user admin slurmctld bash -lc \
		'sbatch -W /tmp/hello.sh && cat slurm-*.out && rm -f slurm-*.out'

.PHONY: test-apptainer
test-apptainer: ## Submit examples/apptainer-hello.sh (runs a container via Apptainer).
	$(COMPOSE) cp examples/apptainer-hello.sh slurmctld:/tmp/apptainer-hello.sh
	$(COMPOSE) exec --user admin slurmctld bash -lc \
		'sbatch -W /tmp/apptainer-hello.sh && cat slurm-*.out && rm -f slurm-*.out'
