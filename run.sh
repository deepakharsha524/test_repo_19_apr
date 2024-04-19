#!/bin/bash
set -eu -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" ; pwd -P)"

. "${SCRIPT_DIR}/lib.sh"

. "${SCRIPT_DIR}/config.sh"

usage() {
  cat <<EOF
Usage: Before running the script, Assume the AWS-ADM role of corresponding account.
Export aws access key and secret eval $(saml2aws -a <saml_profile_name> script --shell=bash)
commands:
  deploy [folder] [env] [plan|apply]              runs terraform
  create_image                                    Build docker image
  upload_image                                    Push docker image  to ECR
  assume_role [account] [role_name] [accountid]
  check                                           Check for security vulnerabilities
  test                                            Runs linting and unit tests
  terraform_format                                format terraform code
  check_format                                    Currently checks the format of terraform files
EOF
  exit 1
}

CMD=${1:-}
case ${CMD} in
  deploy) _deploy "$@";;
  create_image) _create_image ;;
  upload_image) _upload_image "$@";;
  assume_role) _assume_role "$@";;
  check) _check "$@";;
  test) _test "$@";;
  terraform_format) _format_terraform;;
  check_format) _check_format;;
  s3_backup_sync) _s3_backup_sync "$@";;
  *) usage ;;
esac
