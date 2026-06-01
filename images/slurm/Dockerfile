ARG BASE_IMAGE=rockylinux:9
FROM ${BASE_IMAGE}

ARG SLURM_VERSION=25.05.3
ENV SLURM_VERSION=${SLURM_VERSION}

SHELL ["/bin/bash", "-c"]

RUN dnf -y install epel-release dnf-plugins-core \
 && dnf config-manager --set-enabled crb \
 && dnf -y update \
 && dnf -y install \
        wget bzip2 tar gzip xz which sudo procps-ng iproute hostname findutils \
        gcc gcc-c++ make autoconf automake libtool pkgconf-pkg-config \
        munge munge-devel \
        mariadb mariadb-devel mariadb-server \
        pam-devel readline-devel libyaml-devel \
        hwloc hwloc-devel numactl-devel \
        libbpf libbpf-devel bpftool dbus dbus-devel \
        json-c-devel http-parser-devel libjwt-devel openssl-devel \
        python3 python3-pip python3-devel \
        perl perl-ExtUtils-MakeMaker perl-Switch \
        lua lua-devel lua-posix lua-filesystem tcl tcl-devel \
        Lmod \
        openssh-server openssh-clients \
        vim-enhanced less git \
 && dnf clean all && rm -rf /var/cache/dnf

RUN cd /tmp \
 && wget -q https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2 \
 && tar -xjf slurm-${SLURM_VERSION}.tar.bz2 \
 && cd slurm-${SLURM_VERSION} \
 && ./configure \
        --prefix=/usr/local \
        --sysconfdir=/etc/slurm \
        --with-mysql_config=/usr/bin \
        --with-munge \
        --with-hwloc \
        --enable-pam \
        --with-pam_dir=/usr/lib64/security \
 && make -j"$(nproc)" \
 && make install \
 && cd / && rm -rf /tmp/slurm-${SLURM_VERSION}*

RUN groupadd -r slurm --gid=995 \
 && useradd  -r -g slurm --uid=995 --shell=/bin/bash --home-dir=/var/lib/slurm slurm \
 && mkdir -p /var/spool/slurmd /var/spool/slurmctld /var/log/slurm \
             /var/lib/slurm /etc/slurm /run/slurm \
 && chown -R slurm:slurm /var/spool/slurmd /var/spool/slurmctld \
                         /var/log/slurm /var/lib/slurm /run/slurm

RUN pip3 install --no-cache-dir easybuild

# Apptainer (formerly Singularity) — the HPC-native container runtime, so SLURM
# jobs can run OCI/Docker images on the compute nodes.
# DEV/EDUCATION ONLY: this installs the *setuid* flavour and relies on the
# compute containers running privileged (see docker-compose.yml). A real
# multi-tenant cluster runs Apptainer fully unprivileged instead.
RUN dnf -y install apptainer apptainer-suid squashfs-tools fuse-overlayfs \
 && dnf clean all && rm -rf /var/cache/dnf \
 && conf=/etc/apptainer/apptainer.conf \
 && sed -i '/^[# ]*allow setuid-mount squashfs/d' "$conf" \
 && printf '\n# DEV LAB: mount squashfs via the kernel in setuid mode. The default\n# (iflimited) falls back to squashfuse/FUSE, and exec from a FUSE mount\n# fails with EINVAL on the Docker Desktop (linuxkit) kernel. A real\n# cluster would rely on signed images + ECL instead.\nallow setuid-mount squashfs = yes\n' >> "$conf"

RUN useradd -m -s /bin/bash -u 1000 admin \
 && echo 'admin ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/admin \
 && chmod 440 /etc/sudoers.d/admin

RUN mkdir -p /software /data \
 && chown admin:admin /software /data

RUN cat > /etc/profile.d/zz_hpc_lab.sh <<'EOF'
export EASYBUILD_PREFIX=/software/easybuild
export EASYBUILD_INSTALLPATH=/software
export MODULEPATH=/software/modules/all:${MODULEPATH:-}
EOF

COPY slurm.conf      /etc/slurm/slurm.conf
COPY slurmdbd.conf   /etc/slurm/slurmdbd.conf
COPY cgroup.conf     /etc/slurm/cgroup.conf
COPY entrypoint.sh   /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
 && chown slurm:slurm /etc/slurm/slurmdbd.conf \
 && chmod 0600 /etc/slurm/slurmdbd.conf

WORKDIR /home/admin

EXPOSE 6817 6818 6819

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
