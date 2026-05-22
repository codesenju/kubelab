#!/bin/bash
set -euo pipefail

limactl list | grep cp1 || \
limactl start control-plane.yaml --name cp1 -y

limactl list | grep worker-1 || \
limactl start worker1.yaml --name worker-1 -y

limactl list | grep worker-2 || \
limactl start worker2.yaml --name worker-2 -y
