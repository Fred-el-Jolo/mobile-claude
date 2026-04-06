#!/usr/bin/env bash
# List all OpenStack instances with their status and IP
set -euo pipefail

openstack server list --format table -c ID -c Name -c Status -c Networks -c Flavor
