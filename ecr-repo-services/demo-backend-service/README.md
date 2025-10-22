# variables
REGION=eu-west-2
ACCOUNT_ID=12345678912
REPO=demo-backend-service
ECR_URL=${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# authenticate Docker to ECR
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin $ECR_URL

# create repo if not exists
aws ecr describe-repositories --repository-names $REPO --region $REGION >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name $REPO --region $REGION


# build and push AMD64 image
docker buildx build \
  --platform linux/amd64 \
  -t ${ECR_URL}/${REPO}:latest \
  --push .