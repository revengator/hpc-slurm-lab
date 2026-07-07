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

# SSH login node (used by `make ssh-setup` / `make ssh`)
SSH_PORT      ?= 2222
SSH_HOST      ?= localhost
SSH_USER      ?= admin
SSH_KEY       ?= ./ssh/id_hpclab
SSH_PASSWORD  ?= admin

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

.PHONY: ssh-prep
ssh-prep: ## Ensure ssh/authorized_keys exists so the bind-mount is a file, not a dir.
	@mkdir -p ssh && touch ssh/authorized_keys

.PHONY: up
up: ssh-prep ## Start the cluster (CPU nodes only).
	$(COMPOSE) up -d

.PHONY: up-gpu
up-gpu: ssh-prep ## Start the cluster including the NVIDIA GPU node g1.
	$(COMPOSE) --profile gpu up -d

.PHONY: down
down: ## Stop the cluster (keeps volumes).
	$(COMPOSE) --profile gpu down

.PHONY: clean
clean: ## Stop and delete EVERYTHING (containers, volumes, images, network). Software/ is preserved.
	$(COMPOSE) --profile gpu down --rmi all --volumes --remove-orphans

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

# --- SSH login node (for remote submit / agentic tools) ----------------------

.PHONY: ssh-setup
ssh-setup: ## Generate the lab SSH key + authorized_keys and print connection info.
	@mkdir -p ssh
	@if [[ ! -f "$(SSH_KEY)" ]]; then \
		ssh-keygen -t ed25519 -N '' -C 'hpc-slurm-lab' -f "$(SSH_KEY)" >/dev/null; \
		echo "Generated new keypair: $(SSH_KEY)[.pub]"; \
	else \
		echo "Reusing existing keypair: $(SSH_KEY)"; \
	fi
	@cp "$(SSH_KEY).pub" ssh/authorized_keys
	@chmod 600 "$(SSH_KEY)" ssh/authorized_keys
	@echo
	@echo "SSH login node provisioned. If the cluster is already up, run:"
	@echo "    make up        # (re)create the login container to pick up the key"
	@echo
	@$(MAKE) --no-print-directory ssh-config

.PHONY: ssh-config
ssh-config: ## Print the connection block for SSH / remote-agent setup.
	@echo "──────────────────────────────────────────────────────────────"
	@echo " Connect to this cluster over SSH"
	@echo "──────────────────────────────────────────────────────────────"
	@echo "  Host             : $(SSH_HOST)   (use this machine's LAN IP from another box)"
	@echo "  Port             : $(SSH_PORT)"
	@echo "  User             : $(SSH_USER)"
	@echo "  Scheduler        : SLURM (sbatch / squeue / sacct)"
	@if [[ -n "$(SSH_PASSWORD)" ]]; then \
		echo "  Password         : $(SSH_PASSWORD)   (dev/home-LAN only)"; \
	fi
	@if [[ -f "$(SSH_KEY)" ]]; then \
		echo "  Private key      : $(abspath $(SSH_KEY))"; \
		echo; \
		echo "  Test from a shell:"; \
		echo "    ssh -i $(abspath $(SSH_KEY)) -p $(SSH_PORT) $(SSH_USER)@$(SSH_HOST) sinfo"; \
	else \
		echo; \
		echo "  No key yet. Either 'make ssh-setup' to generate one, or log in"; \
		echo "  with the password and 'ssh-copy-id -p $(SSH_PORT) $(SSH_USER)@$(SSH_HOST)'."; \
		echo "  Test from a shell:"; \
		echo "    ssh -p $(SSH_PORT) $(SSH_USER)@$(SSH_HOST) sinfo"; \
	fi
	@echo
	@echo "  For non-interactive / agentic SSH clients, register the Host/Port/User"
	@echo "  above with the private key (recommended) — key auth is required when"
	@echo "  the client cannot answer an interactive password prompt."
	@echo
	@echo "  Non-interactive clients cannot accept an unknown host key at a prompt."
	@echo "  Add this block to ~/.ssh/config so the first connection is trusted"
	@echo "  automatically:"
	@echo
	@echo "    Host hpc-slurm-lab"
	@echo "        HostName $(SSH_HOST)"
	@echo "        Port $(SSH_PORT)"
	@echo "        User $(SSH_USER)"
	@if [[ -f "$(SSH_KEY)" ]]; then echo "        IdentityFile $(abspath $(SSH_KEY))"; fi
	@echo "        StrictHostKeyChecking accept-new"
	@echo
	@echo "  Then just: ssh hpc-slurm-lab sinfo"
	@echo "  If you rebuilt the cluster and now get 'host key verification failed',"
	@echo "  run 'make ssh-fix-hostkey' once to forget the stale key."
	@echo "──────────────────────────────────────────────────────────────"

.PHONY: ssh-copy-id
ssh-copy-id: ## Install your SSH key on the login node (uses the admin password once).
	@if [[ ! -f "$(SSH_KEY)" ]]; then \
		echo "No key at $(SSH_KEY) — run 'make ssh-setup' first."; exit 1; \
	fi
	ssh-copy-id -i "$(SSH_KEY).pub" -p $(SSH_PORT) \
		-o StrictHostKeyChecking=accept-new \
		-o UserKnownHostsFile=./ssh/known_hosts \
		$(SSH_USER)@$(SSH_HOST)

.PHONY: ssh
ssh: ## Open an interactive SSH session on the login node as admin.
	ssh -i $(SSH_KEY) -p $(SSH_PORT) \
		-o StrictHostKeyChecking=accept-new \
		-o UserKnownHostsFile=./ssh/known_hosts \
		$(SSH_USER)@$(SSH_HOST)

.PHONY: ssh-fix-hostkey
ssh-fix-hostkey: ## Forget a stale host key (fixes "host key verification failed" after a rebuild).
	@ssh-keygen -R "[$(SSH_HOST)]:$(SSH_PORT)" >/dev/null 2>&1 || true
	@rm -f ssh/known_hosts
	@echo "Cleared stale host key for [$(SSH_HOST)]:$(SSH_PORT) from ~/.ssh/known_hosts"
	@echo "and the repo-local ssh/known_hosts. The next connection will re-learn it."
	@echo "Host keys now persist in the 'ssh_hostkeys' volume, so this should be a"
	@echo "one-time fix (they survive 'make down && make up'; only 'make clean' resets them)."

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
