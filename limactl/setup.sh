#!/bin/bash
set -euo pipefail

limactl list | grep control-plane-0 || \
limactl start control-plane.yaml --name control-plane-0 -y
limactl list | grep worker-0 || \
limactl start worker.yaml --name worker-0 -y
limactl list | grep worker-1 || \
limactl start worker_x86_64.yaml --name worker-1 -y

sleep 20

ANSIBLE_CONFIG=ansible/ansible.cfg
ansible-playbook ansible/main.yaml