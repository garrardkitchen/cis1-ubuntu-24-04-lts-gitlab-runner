#!/usr/bin/env bash
# Non-destructive: test validation against temporary fixtures; never install packages.
set -euo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib/common.sh
source scripts/lib/common.sh
for file in scripts/*.sh scripts/lib/*.sh tests/*.sh; do bash -n "$file"; done
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
passed=0
accept() { "$@" >/dev/null 2>&1 || { fail "Expected acceptance: $*"; exit 1; }; ((passed+=1)); }
reject() { if "$@" >/dev/null 2>&1; then fail "Expected rejection: $*"; exit 1; fi; ((passed+=1)); }
accept ubuntu_codename 24.04
accept ubuntu_codename 22.04
reject ubuntu_codename 20.04
printf '{}\n' > "$scratch/pins.json"
accept validate_pins "$scratch/pins.json"
printf '{"docker-ce":"5:29.0.0-1~ubuntu.24.04~noble"}\n' > "$scratch/pins.json"
accept validate_pins "$scratch/pins.json"
printf '{"docker-ce":"1; touch /tmp/unwanted"}\n' > "$scratch/pins.json"
reject validate_pins "$scratch/pins.json"
printf '{"unknown":"1"}\n' > "$scratch/pins.json"
reject validate_pins "$scratch/pins.json"
printf '{"gitlab-runner":"18.0.0-1"}\n' > "$scratch/pins.json"
reject validate_pins "$scratch/pins.json"
printf '{"gitlab-runner":"18.0.0-1","gitlab-runner-helper-images":"18.0.1-1"}\n' > "$scratch/pins.json"
reject validate_pins "$scratch/pins.json"
printf '{"gitlab-runner":"18.0.0-1","gitlab-runner-helper-images":"18.0.0-1"}\n' > "$scratch/pins.json"
accept validate_pins "$scratch/pins.json"
printf '{"docker-ce":42}\n' > "$scratch/pins.json"
reject validate_pins "$scratch/pins.json"
chmod 0600 "$scratch/pins.json"
accept require_private_file "$scratch/pins.json"
chmod 0644 "$scratch/pins.json"
reject require_private_file "$scratch/pins.json"
chmod 0600 "$scratch/pins.json"
ln -s "$scratch/pins.json" "$scratch/link"
reject require_private_file "$scratch/link"
reject require_private_file "$scratch"
printf '{"ApiKey":"0123456789abcdef0123456789abcdef","Site":"datadoghq.eu"}\n' > "$scratch/dd.json"
accept validate_datadog "$scratch/dd.json"
jq '.Site="invalid.example"' "$scratch/dd.json" > "$scratch/bad.json"
reject validate_datadog "$scratch/bad.json"
jq '.ApiKey="secret\\nsite: injected"' "$scratch/dd.json" > "$scratch/bad.json"
reject validate_datadog "$scratch/bad.json"
printf '{"Url":"https://gitlab.example.com","AuthenticationToken":"glrt-test","DockerImage":"ubuntu@sha256:%064d","Name":"runner-1"}\n' 0 > "$scratch/runner.json"
accept validate_runner "$scratch/runner.json"
for mutation in '.Url="http://gitlab.example.com"' '.Url="https://user:password@gitlab.example.com"' '.DockerImage="ubuntu:latest"' '.AuthenticationToken="legacy-token"'; do
  jq "$mutation" "$scratch/runner.json" > "$scratch/bad.json"
  reject validate_runner "$scratch/bad.json"
done
printf '# fixture only\n' > "$scratch/MicrosoftDefenderATPOnboardingLinuxServer.py"
(cd "$scratch" && zip -q good.zip MicrosoftDefenderATPOnboardingLinuxServer.py)
accept select_onboarding_entry "$scratch/good.zip"
printf 'fixture\n' > "$scratch/windows.cmd"
(cd "$scratch" && zip -q windows.zip windows.cmd)
reject select_onboarding_entry "$scratch/windows.zip"
mkdir "$scratch/nested"
cp "$scratch/MicrosoftDefenderATPOnboardingLinuxServer.py" "$scratch/nested/"
(cd "$scratch" && zip -q nested.zip nested/MicrosoftDefenderATPOnboardingLinuxServer.py)
reject select_onboarding_entry "$scratch/nested.zip"
(cd "$scratch" && zip -q duplicate.zip MicrosoftDefenderATPOnboardingLinuxServer.py nested/MicrosoftDefenderATPOnboardingLinuxServer.py)
reject select_onboarding_entry "$scratch/duplicate.zip"
echo "$passed security/input assertions passed; Bash syntax checks passed."
