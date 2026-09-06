#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$script_dir/lib/common.sh"
require_root
[[ $# == 2 ]] || { fail 'Usage: enrol.sh {datadog|runner|defender} PRIVATE_INPUT_FILE'; exit 1; }
input=$(realpath -s -- "$2")
require_private_file "$input"
case "$1" in
  datadog)
    validate_datadog "$input" || { fail 'Invalid Datadog settings.'; exit 1; }
    temporary=$(mktemp /etc/datadog-agent/.image-factory.XXXXXXXX)
    trap 'rm -f -- "$temporary"' EXIT
    jq -r '"api_key: \(.ApiKey | tojson)\nsite: \(.Site | tojson)"' "$input" > "$temporary"
    chown root:dd-agent "$temporary"
    chmod 0640 "$temporary"
    mv -f -- "$temporary" /etc/datadog-agent/datadog.yaml
    systemctl enable datadog-agent
    systemctl restart datadog-agent
    echo 'Datadog configured. Confirm agent status and host arrival in the correct site.'
    ;;
  runner)
    validate_runner "$input" || { fail 'Invalid Runner settings; require HTTPS, glrt- token and digest-pinned Docker image.'; exit 1; }
    if [[ -f /etc/gitlab-runner/config.toml ]] && grep -Eq '^[[:space:]]*\[\[runners\]\]' /etc/gitlab-runner/config.toml; then
      fail 'Runner already registered; refusing duplicate registration.'; exit 1
    fi
    # Shell assignments put secrets in the child environment, never argv or logs.
    if ! CI_SERVER_URL=$(jq -r .Url "$input") RUNNER_TOKEN=$(jq -r .AuthenticationToken "$input") \
      RUNNER_NAME=$(jq -r .Name "$input") DOCKER_IMAGE=$(jq -r .DockerImage "$input") \
      RUNNER_EXECUTOR=docker DOCKER_PRIVILEGED=false gitlab-runner register --non-interactive >/dev/null 2>&1; then
      fail 'Runner registration failed; details suppressed to avoid exposing credentials.'; exit 1
    fi
    chmod 0600 /etc/gitlab-runner/config.toml
    systemctl enable gitlab-runner
    systemctl restart gitlab-runner
    gitlab-runner verify >/dev/null 2>&1 || { fail 'Runner verification failed.'; exit 1; }
    echo 'Runner registered. Run a real smoke-test job before admitting workloads.'
    ;;
  defender)
    entry=$(select_onboarding_entry "$input")
    temporary=$(mktemp -d /run/image-factory-mde.XXXXXXXX)
    trap 'rm -rf -- "$temporary"' EXIT
    # Stream only the selected entry; never extract archive-controlled paths.
    # Limit output to 1 MiB to reject oversized/decompression-bomb scripts.
    (ulimit -f 1024; unzip -p "$input" "$entry" > "$temporary/onboard.py")
    [[ -s $temporary/onboard.py && $(stat -c %s "$temporary/onboard.py") -le 1048576 ]] || { fail 'Invalid onboarding script size.'; exit 1; }
    systemctl enable --now mdatp
    python3 "$temporary/onboard.py" >/dev/null 2>&1 || { fail 'Microsoft onboarding script failed; output suppressed.'; exit 1; }
    systemctl restart mdatp
    org=$(mdatp health --field org_id)
    [[ $org =~ ^\"?[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}\"?$ ]] || { fail 'Defender returned no valid organisation ID.'; exit 1; }
    echo 'Defender onboarded. Check health, definitions, protection and portal arrival.'
    ;;
  *) fail 'Unknown enrolment command.'; exit 1 ;;
esac
