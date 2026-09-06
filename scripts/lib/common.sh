#!/usr/bin/env bash
# Shared validation; sourcing this file performs no machine changes.
fail() { printf '%s\n' "$*" >&2; return 1; }
require_root() { [[ $EUID == 0 ]] || fail 'Run as root on the image VM.'; }
packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin gitlab-runner gitlab-runner-helper-images datadog-agent mdatp)
ubuntu_codename() {
  case "$1" in 24.04) echo noble ;; 22.04) echo jammy ;; *) fail 'Only Ubuntu 24.04 and 22.04 are supported.' ;; esac
}
validate_pins() {
  jq -e --argjson allowed "$(printf '%s\n' "${packages[@]}" | jq -R . | jq -s .)" '
    type == "object" and all(to_entries[];
      .key as $k | ($allowed | index($k)) != null and
      (.value | type == "string" and test("^[0-9][A-Za-z0-9.+:~\\-]*$"))) and
    (."gitlab-runner" == ."gitlab-runner-helper-images")' "$1" >/dev/null || fail 'Invalid package pins; pin Runner and helper together at the same version.'
}
require_private_file() {
  [[ -f $1 && ! -L $1 ]] || { fail 'Expected a regular secret file, not a symlink.'; return 1; }
  local mode owner
  mode=$(stat -c '%a' -- "$1")
  owner=$(stat -c '%u' -- "$1")
  if [[ $owner != "$EUID" ]] || (( (8#$mode & 077) != 0 )); then
    fail 'Secret files must be owned by the invoking user and mode 0600 or stricter.'; return 1
  fi
}
assert_unenrolled() {
  [[ ! -e /etc/opt/microsoft/mdatp/mdatp_onboard.json ]] || { fail 'Defender is already onboarded.'; return 1; }
  if [[ -f /etc/gitlab-runner/config.toml ]] && grep -Eq '^[[:space:]]*\[\[runners\]\]' /etc/gitlab-runner/config.toml; then
    fail 'Runner is already registered.'; return 1
  fi
  if [[ -f /etc/datadog-agent/datadog.yaml ]] && grep -Eq '^[[:space:]]*api_key:[[:space:]]*[^[:space:]#]' /etc/datadog-agent/datadog.yaml; then
    fail 'Datadog configuration found; use an unenrolled source.'; return 1
  fi
}
validate_datadog() {
  jq -e '(.ApiKey | type == "string" and test("^[a-fA-F0-9]{32}$")) and
    (.Site | IN("datadoghq.com", "datadoghq.eu", "us3.datadoghq.com", "us5.datadoghq.com", "ap1.datadoghq.com", "ap2.datadoghq.com", "ddog-gov.com"))' "$1" >/dev/null
}
validate_runner() {
  jq -e '(.Url | type == "string" and test("^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/-]*)?$")) and
    (.AuthenticationToken | type == "string" and test("^glrt-[A-Za-z0-9_-]+$")) and
    (.Name | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")) and
    (.DockerImage | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._:/-]*@sha256:[a-f0-9]{64}$"))' "$1" >/dev/null
}
select_onboarding_entry() {
  local entries entry matches=0 selected=''
  entries=$(unzip -Z1 "$1") || return 1
  while IFS= read -r entry; do
    if [[ ${entry##*/} == MicrosoftDefenderATPOnboardingLinuxServer.py ]]; then
      ((matches+=1)); selected=$entry
    fi
  done <<< "$entries"
  # Require the vendor script at the ZIP root. Never extract archive paths.
  [[ $matches == 1 && $selected == MicrosoftDefenderATPOnboardingLinuxServer.py ]] || {
    fail 'Expected exactly one Linux onboarding script at the ZIP root. Download Linux Server / Local Script.'; return 1;
  }
  printf '%s\n' "$selected"
}
