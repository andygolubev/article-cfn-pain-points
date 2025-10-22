#!/bin/bash

set -e

DEV_AWS_ACCOUNT_NUMBER="12345678912"
STAGE_AWS_ACCOUNT_NUMBER="12345678912"
PROD_AWS_ACCOUNT_NUMBER="12345678912"


# Function to update the value of a parameter in a JSON file with stack parameters
update_json_parameter() {
  # Usage:
  # update_json_parameter <filename> <key> <value>

  local filename=$1
  local key=$2
  local value=$3

  # Escape special characters in key and value
  local escaped_key=$(printf '%s\n' "$key" | sed 's/[\/&]/\\&/g')
  local escaped_value=$(printf '%s\n' "$value" | sed 's/[\/&]/\\&/g')

  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "/\"$escaped_key\"/{n;s/\"ParameterValue\": \".*\"/\"ParameterValue\": \"$escaped_value\"/;}" "$filename"
  else
    # Linux
    sed -i "/\"$escaped_key\"/{n;s/\"ParameterValue\": \".*\"/\"ParameterValue\": \"$escaped_value\"/;}" "$filename"
  fi
}

check_empty_json_parameter() {
  # Usage:
  # check_empty_json_parameter <filename> <key>

  local filename=$1
  local key=$2

  if jq -e --arg key "$key" '.[] | select(.ParameterKey == $key) | .ParameterValue == ""' "$filename" > /dev/null;
  then
    echo "Error: Parameter '$key' should NOT be empty during a deployment. File: $filename"
    exit 1
  fi

}

# Function to create a JSON file with ParameterKey/ParameterValue objects from stack outputs
create_json_params_file() {
  # Usage:
  # create_json_params_file <stack-name> <region> <output-file>

  # Example usage:
  # create_json_params_file "global-resources-stack" "us-east-1" "my-params.json"

  local stack_name="$1"
  local region="$2"
  local output_file="$3"

  # Check if all inputs are provided
  if [[ -z "$stack_name" || -z "$region" || -z "$output_file" ]]; then
    echo "Usage: create_json_params_file <stack-name> <region> <output-file>"
    return 1
  fi

  # Retrieve stack outputs and transform them into the desired JSON structure
  aws cloudformation describe-stacks \
    --stack-name "$stack_name" \
    --region "$region" \
    --query "Stacks[0].Outputs" \
    --output json | \
    jq '[.[] | {ParameterKey: .OutputKey, ParameterValue: .OutputValue}]' \
    > "$output_file"

  if [[ $? -eq 0 ]]; then
    echo "Created '$output_file' with parameters derived from '$stack_name' outputs in region '$region'."
  else
    echo "Error: Failed to create JSON file from stack outputs."
    return 1
  fi
}

# Check if AWS CLI is installed
command -v aws &> /dev/null || { echo "AWS CLI is not installed. Exiting..."; exit 1; }

# Check if JQ is installed
command -v jq &> /dev/null || { echo "JQ is not installed. Exiting..."; exit 1; }

# Check if the REGION parameter was provided
if [ -z "$1" ] || [ "$1" != "--region" ]; then
    echo "Error: The --region parameter is required and must be the first argument."
    echo "Usage: $0 --region <il-central-1|eu-west-2|...> --env <dev|stage|prod> [--disable-rollback]"
    exit 1
  # then check that environment was provided
elif [ -z "$3" ] || [ "$3" != "--env" ]; then
    echo "Error: The --env parameter is required and must be the second argument."
    echo "Usage: $0 --region <il-central-1|eu-west-2|...> --env <dev|stage|prod> [--disable-rollback]"
    exit 1
  # then check that provided environment is valid
elif [[ "$4" != "dev" && "$4" != "stage" && "$4" != "prod" ]]; then
    echo "Error: Invalid environment. Please use 'dev', 'stage', or 'prod'."
    exit 1
  # then check that provided region is supported
elif ! aws ec2 describe-regions --query "Regions[].RegionName" --output text | grep -qw "$2"; then
    echo "Error: Invalid region. Please use one of these..."
    aws ec2 describe-regions --query "Regions[].RegionName" --output text --no-cli-pager
    exit 1
fi

set -u

################### CHECK THE AWS ACCOUNT NUMBER ###############################
# Modify Account number here if needed

if [[ "$4" == "dev" && "$(aws sts get-caller-identity --query Account --output text --no-cli-pager)" != "${DEV_AWS_ACCOUNT_NUMBER}" ]]; then echo "Error: Used AWS Secret Key is not for DEV environment for ACCOUNT number ${DEV_AWS_ACCOUNT_NUMBER}. \nYour current Role: $(aws sts get-caller-identity --query Arn --output text) \nExiting..."; exit 1; fi
if [[ "$4" == "stage" && "$(aws sts get-caller-identity --query Account --output text --no-cli-pager)" != "${STAGE_AWS_ACCOUNT_NUMBER}" ]]; then echo -e "Error: Used AWS Secret Key is not for STAGE environment for ACCOUNT number ${STAGE_AWS_ACCOUNT_NUMBER}. \nYour current Role: $(aws sts get-caller-identity --query Arn --output text) \nExiting..."; exit 1; fi
if [[ "$4" == "prod" && "$(aws sts get-caller-identity --query Account --output text --no-cli-pager)" != "${PROD_AWS_ACCOUNT_NUMBER}" ]]; then echo "Error: Used AWS Secret Key is not for PRODUCTION environment for ACCOUNT number ${PROD_AWS_ACCOUNT_NUMBER}. \nYour current Role: $(aws sts get-caller-identity --query Arn --output text) \nExiting..."; exit 1; fi


# Set the AWS region for the script
export REGION=$2

# Print info about the deployment
echo "########################## DEPLOY USER INFO ##########################"
echo "#"
echo "#   Role: $(aws sts get-caller-identity --query Arn --output text)"
echo "#   Region: $REGION"
echo "#   Environment: $4"
echo "#"
echo "######################################################################"
echo ""


# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd $SCRIPT_DIR/../cfn-stacks
echo "Current working directory: $(pwd)"


################### CREATE GLOBAL RESOURCES STACK ###############################

DEMO_HOSTED_ZONE_ID=$(aws cloudformation list-exports --region $REGION | jq -r ".Exports[] | select(.Name == \"demo-hosted-zone-id\") | .Value")
DEMO_HOSTED_ZONE_DOMAIN=$(aws cloudformation list-exports --region $REGION | jq -r ".Exports[] | select(.Name == \"demo-hosted-zone-domain-name\") | .Value")
DEMO_CLOUDFRONT_CERTIFICATE_DOMAIN_NAME=$(jq -r '.[] | select(.ParameterKey == "DemoCloudFrontCertificateDomainNameParam") | .ParameterValue' "parameters-$4.json")
S3_DEMO_BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name demo-s3-stack --region $REGION --query "Stacks[0].Outputs[?OutputKey=='DemoFrontendBucketName'].OutputValue" --output text)
S3_DEMO_BUCKET_OAI=$(aws cloudformation describe-stacks --stack-name demo-s3-stack  --region $REGION --query "Stacks[0].Outputs[?OutputKey=='DemoFrontendCloudFrontOAI'].OutputValue" --output text)
S3_BUCKET_REGION=$REGION

# Deploy Global Resources stack in us-east-1 region
echo "####################### Global stack ###############################"
echo "Deploying Global Resources stack..."
deploy_global_resources_command="aws cloudformation deploy --stack-name global-resources-stack \
  --template-file 50-global-resources-stack.yaml \
  --parameter-override \
    HostedZoneIdParam=$DEMO_HOSTED_ZONE_ID \
    HostedZoneDomainNameParam=$DEMO_HOSTED_ZONE_DOMAIN \
    DemoCloudFrontCertificateDomainNameParam=$DEMO_CLOUDFRONT_CERTIFICATE_DOMAIN_NAME \
    S3DemoBucketName=$S3_DEMO_BUCKET_NAME \
    S3DemoBucketOAI=$S3_DEMO_BUCKET_OAI \
    S3DemoBucketRegion=$S3_BUCKET_REGION \
  --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND CAPABILITY_IAM"

echo "Executing deploy Global Resources stack..."
eval "$deploy_global_resources_command"
if [ $? -ne 0 ]; then
  echo "Error executing deploy Global Resources stack. Exiting..."
  exit 1
fi

echo "####################### End Global stack ###############################"

