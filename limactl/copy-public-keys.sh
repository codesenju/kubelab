#!/bin/bash
set -euo pipefail
HOST_USER=changeme # change me
limactl shell cp1 sudo mkdir -p /home/k8s/.ssh/
limactl shell cp1 sudo bash -c 'cat /Users/$HOST_USER/.ssh/id_ed25519.pub | tee /home/k8s/.ssh/authorized_keys'

limactl shell worker-1 sudo mkdir -p /home/k8s/.ssh/
limactl shell worker-1 sudo bash -c 'cat /Users/$HOST_USER/.ssh/id_ed25519.pub | tee /home/k8s/.ssh/authorized_keys'

limactl shell worker-2 sudo mkdir -p /home/k8s/.ssh/
limactl shell worker-2 sudo bash -c 'cat /Users/$HOST_USER/.ssh/id_ed25519.pub | tee /home/k8s/.ssh/authorized_keys'
