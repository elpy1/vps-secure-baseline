#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

ansible-playbook site.yml "$@"
