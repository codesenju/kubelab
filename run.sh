#!/bin/sh
set -e

cd opentofu
tofu init
tofu apply --auto-approve

cd ../ansible
ansible-playbook main.yaml --tags baseline