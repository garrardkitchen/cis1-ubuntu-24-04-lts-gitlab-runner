#!/usr/bin/env bash
set -euo pipefail
set +x
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$script_dir/lib/common.sh"
require_root
[[ $# == 1 ]] || { fail 'Usage: install.sh PACKAGE_PINS_JSON'; exit 1; }
# shellcheck source=/dev/null
source /etc/os-release
[[ $ID == ubuntu && $(dpkg --print-architecture) == amd64 ]] || { fail 'Ubuntu amd64 required.'; exit 1; }
codename=$(ubuntu_codename "$VERSION_ID")
assert_unenrolled
[[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]] || { fail 'Existing policy-rc.d requires review.'; exit 1; }
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
apt() { apt-get -o DPkg::Lock::Timeout=300 -o Acquire::Retries=3 "$@"; }
# Prevent package post-install scripts from starting tenant-specific services.
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod 0755 /usr/sbin/policy-rc.d
trap 'rm -f /usr/sbin/policy-rc.d' EXIT
apt update
apt install -y --no-install-recommends ca-certificates gnupg curl apt-transport-https jq unzip python3 libplist-utils git
validate_pins "$1"
apt -o Dpkg::Options::=--force-confold upgrade -y
install -d -m 0755 /etc/apt/keyrings
repository() {
  local name=$1 key_url=$2 repo=$3
  curl --fail --silent --show-error --location --retry 3 --max-time 120 --proto '=https' --proto-redir '=https' "$key_url" -o "/etc/apt/keyrings/$name.asc"
  gpg --batch --show-keys "/etc/apt/keyrings/$name.asc" >/dev/null
  chmod 0644 "/etc/apt/keyrings/$name.asc"
  printf 'deb [arch=amd64 signed-by=/etc/apt/keyrings/%s.asc] %s\n' "$name" "$repo" > "/etc/apt/sources.list.d/image-factory-$name.list"
}
repository docker https://download.docker.com/linux/ubuntu/gpg "https://download.docker.com/linux/ubuntu $codename stable"
repository gitlab-runner https://packages.gitlab.com/runner/gitlab-runner/gpgkey "https://packages.gitlab.com/runner/gitlab-runner/ubuntu/ $codename main"
repository datadog https://keys.datadoghq.com/DATADOG_APT_KEY_CURRENT.public 'https://apt.datadoghq.com/ stable 7'
repository microsoft https://packages.microsoft.com/keys/microsoft.asc "https://packages.microsoft.com/ubuntu/$VERSION_ID/prod $codename main"
apt update
specs=()
for package in "${packages[@]}"; do
  pin=$(jq -r --arg p "$package" '.[$p] // empty' "$1")
  specs+=("$package${pin:+=$pin}")
done
apt install -y --no-install-recommends "${specs[@]}"
systemctl disable --now datadog-agent gitlab-runner mdatp
systemctl enable docker containerd
systemctl start docker
bash "$script_dir/verify.sh"
dpkg-query -W -f='${Package}\t${Version}\n' > "$script_dir/packages.tsv"
resolved='{}'
for package in "${packages[@]}"; do
  pin=$(dpkg-query -W -f='${Version}' "$package")
  resolved=$(jq --arg p "$package" --arg v "$pin" '. + {($p): $v}' <<< "$resolved")
done
printf '%s\n' "$resolved" > "$script_dir/resolved-package-pins.json"
chmod 0644 "$script_dir/packages.tsv" "$script_dir/resolved-package-pins.json"
