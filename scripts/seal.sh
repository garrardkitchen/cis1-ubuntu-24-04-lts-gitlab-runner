#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$script_dir/lib/common.sh"
require_root
assert_unenrolled
systemctl stop docker.socket docker containerd
systemctl disable --now datadog-agent gitlab-runner mdatp
apt-get clean
rm -f /var/lib/docker/engine-id /etc/docker/key.json /etc/gitlab-runner/.runner_system_id
cloud-init clean --logs --machine-id --seed
# Last customization: do not boot again before capture.
waagent -deprovision+user -force
