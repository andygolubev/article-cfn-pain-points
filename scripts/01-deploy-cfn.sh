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
    echo "Usage: $0 --region <eu-west-2|us-east-1|...> --env <dev|stage|prod> [--disable-rollback]"
    exit 1
  # then check that environment was provided
elif [ -z "$3" ] || [ "$3" != "--env" ]; then
    echo "Error: The --env parameter is required and must be the second argument."
    echo "Usage: $0 --region <eu-west-2|us-east-1|...> --env <dev|stage|prod> [--disable-rollback]"
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
if [[ "$4" == "prod" && "$(aws sts get-caller-identity --query Account --output text --no-cli-pager)" != "${PROD_AWS_ACCOUNT_NUMBER}" ]]; then echo "Error: Used AWS Secret Key is not for PROD environment for ACCOUNT number ${PROD_AWS_ACCOUNT_NUMBER}. \nYour current Role: $(aws sts get-caller-identity --query Arn --output text) \nExiting..."; exit 1; fi


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


################### CREATE TECHNICAL STACK ###############################

echo "Deploying demo technical stack (S3 bucket and ECR repositories)..."
deploy_cfn_command="aws cloudformation deploy --stack-name demo-technical-stack --template-file 00-technical-stack.yaml --parameter-overrides file://parameters-$4.json --region $REGION --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND CAPABILITY_IAM"

echo "Executing deploy demo technical stack..."
eval "$deploy_cfn_command"
if [ $? -ne 0 ]; then
  echo "Error executing deploy demo technical stack. Exiting..."
  exit 1
fi

################### CREATE ELASTIC IP STACK ###############################

echo "Deploying demo Elastic IP stack..."
deploy_elasticip_command="aws cloudformation deploy --stack-name demo-elastic-ip-stack --template-file 01-elastic-ip-stack.yaml --parameter-overrides file://parameters-$4.json --region $REGION"

echo "Executing deploy demo Elastic IP stack..."
eval "$deploy_elasticip_command"
if [ $? -ne 0 ]; then
  echo "Error executing deploy demo Elastic IP stack. Exiting..."
  exit 1
fi


################### CREATE S3 STACK ###############################

echo "Deploying demo S3 stack..."
deploy_s3_command="aws cloudformation deploy --stack-name demo-s3-stack --template-file 02-s3-stack.yaml --parameter-overrides file://parameters-$4.json --region $REGION --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND CAPABILITY_IAM"

echo "Executing deploy demo S3 stack..."
eval "$deploy_s3_command"
if [ $? -ne 0 ]; then
  echo "Error executing deploy demo S3 stack. Exiting..."
  exit 1
fi

################### CREATE NETWORK STACK ###############################

echo "Deploying demo Network stack..."
deploy_network_command="aws cloudformation deploy --stack-name demo-network-stack --template-file 06-network-stack.yaml --parameter-overrides file://parameters-$4.json --region $REGION --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND CAPABILITY_IAM"

echo "Executing deploy demo Network stack..."

eval "$deploy_network_command"
if [ $? -ne 0 ]; then
  echo "Error executing deploy demo Network stack. Exiting..."
  exit 1
fi

################### UPLOAD LAMBDA LAYER TO S3 ###############################

# you need your own aotomation to build the lambda layer

# Get the cfn bucket name from stack outputs (to be exported in Lambda Layer resource)
CFN_BUCKET=$(aws cloudformation describe-stacks --stack-name demo-technical-stack --region $REGION --query "Stacks[0].Outputs" --output json | jq -r '.[] | select(.OutputKey=="DemoDeploymentArtifactsBucket") | .OutputValue')


echo "Uploading lambda layer to $CFN_BUCKET..."

# Check if we run in --skip-lambda-layer mode for debug purposes
if [[ "${5:-}" == "--skip-lambda-layer" ]]; then echo "======= Skip new lambda layer upload. Using --dryrun option ======="; DRY_RUN_OPTION='--dryrun'; fi

aws s3 cp ../lambda-layer/lambda_layer.zip s3://$CFN_BUCKET --region $REGION --output json ${DRY_RUN_OPTION:-}
if [ $? -ne 0 ]; then
  echo "Error copying the new layer. Exiting."
  exit 1
fi

LAMBDA_LAYER_FILE_S3_OBJECT_VERSION=$(aws s3api list-object-versions --bucket $CFN_BUCKET --prefix lambda_layer.zip --region $REGION | jq -r '.Versions | sort_by(.LastModified) | last | .VersionId')

# Put S3 object version into parameter
update_json_parameter "parameters-$4.json" "LambdaLayerS3ObjectVersionParam" "$LAMBDA_LAYER_FILE_S3_OBJECT_VERSION"



echo "Lambda layer version: $LAMBDA_LAYER_FILE_S3_OBJECT_VERSION"


################### CREATE HOSTED ZONE STACK ###############################

# Check if the export demo-hosted-zone-id exists
DEMO_HOSTED_ZONE_ID=$(aws cloudformation list-exports --region $REGION | jq -r ".Exports[] | select(.Name == \"demo-hosted-zone-id\") | .Value")

if [ -n "$DEMO_HOSTED_ZONE_ID" ]; then
  DEMO_HOSTED_ZONE_DOMAIN=$(aws cloudformation describe-stacks --region $REGION --stack-name demo-hosted-zone-stack --query "Stacks[0].Outputs[?OutputKey=='DemoHostedZoneName'].OutputValue" --output text)
  echo "Export 'demo-hosted-zone-id' exists for $DEMO_HOSTED_ZONE_DOMAIN with value: $DEMO_HOSTED_ZONE_ID"
else
  echo "CFN Export for 'demo-hosted-zone-id' does not exist. Deploying..."
  deploy_hostedzone_command="aws cloudformation deploy --stack-name demo-hosted-zone-stack --parameter-overrides file://parameters-$4.json --template-file 05-hosted-zone-stack.yaml --region $REGION"

  echo "Executing deploy demo Hosted Zone stack..."
  eval "$deploy_hostedzone_command"
  if [ $? -ne 0 ]; then
    echo "Error executing deploy demo Hosted Zone stack. Exiting..."
    exit 1
  fi  
  DEMO_HOSTED_ZONE_ID=$(aws cloudformation describe-stacks --region $REGION --stack-name demo-hosted-zone-stack --query "Stacks[0].Outputs[?OutputKey=='DemoHostedZoneID'].OutputValue" --output text)
  DEMO_HOSTED_ZONE_DNS=$(aws cloudformation describe-stacks --region $REGION --stack-name demo-hosted-zone-stack --query "Stacks[0].Outputs[?OutputKey=='DemoHostedZoneNameServers'].OutputValue" --output text)
  DEMO_HOSTED_ZONE_DOMAIN=$(aws cloudformation describe-stacks --region $REGION --stack-name demo-hosted-zone-stack --query "Stacks[0].Outputs[?OutputKey=='DemoHostedZoneName'].OutputValue" --output text)
  
  echo "Export 'demo-hosted-zone-id' created with value: $DEMO_HOSTED_ZONE_ID" 
  echo "##############################################################################################################"
  echo "   Please create a new NS record for subdomain $DEMO_HOSTED_ZONE_DOMAIN"
  echo "   in your parent Hosted Zone, then run this script again."
  echo ""
        # Print each DNS server on a new line with a trailing dot if not present for easy copy
  echo "   Copy these DNS servers for $DEMO_HOSTED_ZONE_DOMAIN:" 
  echo $DEMO_HOSTED_ZONE_DNS | tr ' ' '\n' | sed 's/\.$//; s/$/./'
  echo "##############################################################################################################"
  exit 0
fi


################### CREATE MAIN STACK ###############################

echo "Using this bucket for package.yaml $CFN_BUCKET" 

# Create a package.yaml with main stack
echo "Creating package.yaml file..."
package_command="aws cloudformation package --template-file ./10-main-stack.yaml --s3-bucket $CFN_BUCKET --output-template-file /tmp/packaged.yaml  --region $REGION"

echo "Executing package command..."
eval "$package_command"
if [ $? -ne 0 ]; then
  echo "Error executing package command. Exiting."
  exit 1
fi

# Validate the CloudFormation template
validate_command="aws cloudformation validate-template --template-body file:///tmp/packaged.yaml --no-cli-pager 2>&1 | jq -c 'del(.Parameters)'"
echo "Validating template..."
eval "$validate_command"


# Construct the deploy command
# 
echo "Deploy demo main stack"

# Check if we run in --disable-rollback mode for debug purposes
if [[ "${5:-}" == "--disable-rollback" ]]; then echo "======= Using --disable-rollback option ======="; ROLLBACK_OPTION='--disable-rollback'; fi

# deploy stack
deploy_command="aws cloudformation deploy --region $REGION --template-file /tmp/packaged.yaml --stack-name demo-main-stack --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND CAPABILITY_IAM --parameter-overrides file://parameters-$4.json ${ROLLBACK_OPTION:-} "
echo "Executing deploy command..."
echo "$deploy_command"
eval "$deploy_command"
if [ $? -ne 0 ]; then
  echo "Error executing deploy command. Exiting."
  exit 1
fi

################### PROTECTING STACKS ###############################

if [[ "$4" == "stage" || "$4" == "prod" ]]; then

  NESTED_STACK_ARNS=$(aws cloudformation describe-stack-resources --stack-name demo-main-stack  --region $REGION --query "StackResources[?ResourceType=='AWS::CloudFormation::Stack'].PhysicalResourceId" --output text)

  echo "Setting stack policy for demo main stack: demo-main-stack"
  aws cloudformation set-stack-policy --stack-name demo-main-stack --stack-policy-body file://main-stack-policy.json --region $REGION
  if [ $? -ne 0 ]; then
    echo "Error setting stack policy to demo main stack. Exiting..."
    exit 1
  fi

  # Apply stack policy to each nested stack
  for STACK in $NESTED_STACK_ARNS; do
      echo "Setting stack policy for nested stack: $STACK"
      aws cloudformation set-stack-policy --stack-name $STACK --stack-policy-body file://./main-stack-policy.json --region $REGION
      if [ $? -ne 0 ]; then
        echo "Error setting stack policy to nested stack: $STACK. Exiting..."
        exit 1
      fi
  done

  for STACK in $NESTED_STACK_ARNS; do
      echo "Get stack policy for nested stack: $STACK"
      aws cloudformation get-stack-policy --stack-name $STACK --region $REGION --output json --no-cli-pager | jq '.StackPolicyBody | fromjson'
      if [ $? -ne 0 ]; then
        echo "Error getting stack policy from nested stack: $STACK. Exiting..."
        exit 1
      fi
  done

else
    echo "======= Skip setting Stack Policy for $4 ======="
fi


echo "******************** End Deploying Demo Main Stack ********************"

################### END MAIN STACK ###############################

update_json_parameter "parameters-$4.json" "LambdaLayerS3ObjectVersionParam" ""

echo "******************** End Deploying CloudFormation Stacks ********************"
