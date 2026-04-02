#!/bin/bash
# startup.sh — cloud-init user-data script, runs on every boot
# Keeps the instance up-to-date regardless of snapshot age
apt-get update -q && apt-get upgrade -y -q && apt-get autoremove -y -q
