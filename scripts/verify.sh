#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$script_dir/lib/common.sh"
require_root
for package in "${packages[@]}"; do
  [[ $(dpkg-query -W -f='${Status}' "$package") == 'install ok installed' ]] || { fail "Not installed: $package"; exit 1; }
done
[[ $(dpkg-query -W -f='${Version}' gitlab-runner) == "$(dpkg-query -W -f='${Version}' gitlab-runner-helper-images)" ]] || { fail 'Runner/helper version mismatch.'; exit 1; }
docker version
docker compose version
docker buildx version
gitlab-runner --version
datadog-agent version
mdatp --help
assert_unenrolled
printf '%s\n' 'Package and CLI checks passed; a CIS assessment is still required.'
