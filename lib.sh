SCRIPT_DIR="$(cd "$(dirname "$0")" ; pwd -P)"
. "${SCRIPT_DIR}/config.sh"

_ensure_tfenv() {
  if ! type tfenv &> /dev/null ; then
    echo "Please install tfenv!" 1>&2
    exit 1
  fi
  if ! tfenv exec --version &> /dev/null; then
    echo "Please install required terraform version via tfenv!"
    exit 1
  fi
}


_s3_backup_sync() {
  source_bucket=${2}
  dest_bucket=${3}
  source_bucket_region=${4}
  dest_bucket_region=${5}
  _assume_role "${6}" "backup_pipeline_role" ${7}
  echo "trying to copy"
  aws s3 sync s3://${source_bucket} s3://${dest_bucket} --source-region ${source_bucket_region} --region ${dest_bucket_region}
  echo "aws s3 sync s3://${source_bucket} s3://${dest_bucket} --source-region ${source_bucket_region} --region ${dest_bucket_region}"

  }

_deploy() {
  _ensure_tfenv

  export SCRIPT_DIR="$(cd "$(dirname "$0")" ; pwd -P)"

  local deployment="${2}"
  local environment="${3}"

  pushd "${SCRIPT_DIR}/${deployment}" > /dev/null
    tfenv list
    tfenv exec init
    tfenv exec workspace select "${environment}" || tfenv exec workspace new "${environment}"
    if [ "${4}" == "apply" ]; then
      tfenv exec "${4}" -var-file="${environment}.tfvars" -input=false --auto-approve
    elif [ "${4}" == "destroy" ]; then
      tfenv exec "${4}" -var-file="${environment}.tfvars" -input=false --auto-approve
    else
      tfenv exec "${4}" -var-file="${environment}.tfvars" -input=false
    fi

  popd > /dev/null
}


_get_role(){
  local account=${1}
  local role_name=${2}
  local account_id=$(env | grep -i "^${account}_ACCOUNT_ID" | cut -d= -f2)
  local AWS_ROLE="arn:aws:iam::${account_id}:role/generic_pipeline_role"
  local ECR_ROLE="arn:aws:iam::${account_id}:role/${role_name}"
  local account_id=$(env | grep -i "^${account}_ACCOUNT_ID" | cut -d= -f2)
  CREDENTIALS=`aws sts assume-role --role-arn "$AWS_ROLE" --role-session-name genericSession --duration-seconds 3600 --output=json`
  export AWS_ACCESS_KEY_ID=`echo ${CREDENTIALS} | jq -r '.Credentials.AccessKeyId'`
  export AWS_SECRET_ACCESS_KEY=`echo ${CREDENTIALS} | jq -r '.Credentials.SecretAccessKey'`
  export AWS_SESSION_TOKEN=`echo ${CREDENTIALS} | jq -r '.Credentials.SessionToken'`
  export AWS_EXPIRATION=`echo ${CREDENTIALS} | jq -r '.Credentials.Expiration'`
  CREDENTIALS=`aws sts assume-role --role-arn "$ECR_ROLE" --role-session-name ecrSession --duration-seconds 3600 --output=json`
  export AWS_ACCESS_KEY_ID=`echo ${CREDENTIALS} | jq -r '.Credentials.AccessKeyId'`
  export AWS_SECRET_ACCESS_KEY=`echo ${CREDENTIALS} | jq -r '.Credentials.SecretAccessKey'`
  export AWS_SESSION_TOKEN=`echo ${CREDENTIALS} | jq -r '.Credentials.SessionToken'`
  export AWS_EXPIRATION=`echo ${CREDENTIALS} | jq -r '.Credentials.Expiration'`

}

_assume_role(){
  local account=${1}
  local role_name=${2}
  local account_id=${3}
  local role_arn="arn:aws:iam::${account_id}:role/${role_name}"
  echo "Calling Assume role function"
  echo $role_arn
  local credentials
  local access_key_id
  local secret_access_key
  local session_token

    credentials=$( aws sts assume-role \
      --role-arn "${role_arn}" \
      --role-session-name "assumed_role_session_${role_name}" \
      --region ${AWS_DEFAULT_REGION})
  export AWS_ACCESS_KEY_ID=$(echo "${credentials}" | jq -r .Credentials.AccessKeyId)
  export AWS_SECRET_ACCESS_KEY=$(echo "${credentials}" | jq -r .Credentials.SecretAccessKey)
  export AWS_SESSION_TOKEN=$(echo "${credentials}" | jq -r .Credentials.SessionToken)
  echo "Assumed role"
}

_create_image() {
    docker build -f Dockerfile -t "${SERVICE_NAME}:${REVISION}" .
}

_upload_image() {
     local REVISION="${2}"
    _assume_role "infra" "partner_portal_pipeline_role" ${INFRA_ACCOUNT_ID}
    _create_image
    echo login to ecr
    #aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin 622399446748.dkr.ecr.eu-central-1.amazonaws.com
    aws ecr get-login-password   --region eu-central-1 | docker login --username AWS --password-stdin ${INFRA_ACCOUNT_ID}.dkr.ecr.eu-central-1.amazonaws.com
    local repositoryUri="$(aws ecr describe-repositories --output=text --region=${AWS_DEFAULT_REGION} --query="repositories[?repositoryName=='${SERVICE_NAME}'].repositoryUri")"
    echo repository uri  $repositoryUri
    docker tag "${SERVICE_NAME}:${REVISION}" "${repositoryUri}:${REVISION}"
    docker tag "${SERVICE_NAME}:${REVISION}" "${repositoryUri}:latest"
    docker push "${repositoryUri}:latest"
    docker push "${repositoryUri}:${REVISION}"
}

_format_terraform() {
  _ensure_tfenv
  tfenv exec fmt -recursive
}

function _check_format() {
  _ensure_tfenv
  tfenv exec fmt -check=true -recursive
}

_check() {
  dirname=${2}
  export SCRIPT_DIR="$(cd "$(dirname "$0")" ; pwd -P)"
  pushd "${SCRIPT_DIR}/${dirname}" > /dev/null
  yarn install
  yarn audit
  popd > /dev/null
}

_test() {
  dirname=${2}
  export SCRIPT_DIR="$(cd "$(dirname "$0")" ; pwd -P)"
  pushd "${SCRIPT_DIR}/${dirname}" > /dev/null
  yarn  install
  yarn lint
  yarn test
  popd > /dev/null
}
