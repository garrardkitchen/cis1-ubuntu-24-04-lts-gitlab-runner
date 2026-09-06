#!/usr/bin/env bash
set -euo pipefail
set +x
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "$script_dir/lib/common.sh"
cd "$script_dir/.."
usage() { fail 'Usage: factory.sh resolve RELEASE REGION | {check|build} AZURE_VARS SOURCE_JSON'; exit 1; }
[[ $# == 3 ]] || usage
mkdir -p artifacts
case "$1" in
  resolve)
    ubuntu_codename "$2" >/dev/null
    case "$2" in 24.04) sku=cis-ubuntulinux2404-l1-gen2 ;; 22.04) sku=cis-ubuntulinux2204-l1-gen2 ;; esac
    metadata=$(az vm image show --location "$3" --urn "center-for-internet-security-inc:cis-ubuntu:$sku:latest" --output json)
    jq -e '.hyperVGeneration == "V2" and (.architecture == null or .architecture == "x64") and
      (.name | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and (.plan | type == "object") and
      all(.plan.name, .plan.product, .plan.publisher; type == "string" and length > 0)' <<< "$metadata" >/dev/null || { fail 'Expected explicit Gen2 x64 CIS image and purchase plan.'; exit 1; }
    jq --arg sku "$sku" '{source_image_sku: $sku, source_image_version: .name, plan_name: .plan.name, plan_product: .plan.product, plan_publisher: .plan.publisher}' <<< "$metadata" > "artifacts/source-$2.pkrvars.json"
    printf '%s\n' "$metadata" > "artifacts/marketplace-$2.json"
    echo "Resolved artifacts/source-$2.pkrvars.json; review the source and terms before building."
    ;;
  check|build)
    [[ -f $2 && -f $3 ]] || { fail 'Variable files are missing.'; exit 1; }
    jq -e '(.source_image_sku | IN("cis-ubuntulinux2404-l1-gen2", "cis-ubuntulinux2204-l1-gen2")) and
      (.source_image_version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$3" >/dev/null
    urn=$(jq -r '"center-for-internet-security-inc:cis-ubuntu:\(.source_image_sku):\(.source_image_version)"' "$3")
    terms=$(az vm image terms show --urn "$urn" --output json)
    jq -e '.accepted == true' <<< "$terms" >/dev/null || { fail 'Review and accept Marketplace terms in the active subscription before building.'; exit 1; }
    packer init packer
    packer validate "-var-file=$2" "-var-file=$3" packer
    if [[ $1 == build ]]; then packer build "-var-file=$2" "-var-file=$3" packer; fi
    ;;
  *) usage ;;
esac
