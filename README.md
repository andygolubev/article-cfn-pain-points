## Article Demo: CloudFormation Stacks

### What this is
End‑to‑end AWS infrastructure for a demo application. It provisions core networking, security, data stores, compute (ECS + Lambda), API Gateway, WAF, S3 static hosting with CloudFront, and all necessary shared resources via nested CloudFormation stacks and two helper deployment scripts.

### High‑level architecture
- **Technical stack (`00-technical-stack.yaml`)**: S3 artifacts bucket, ECR repositories, KMS keys, CFN event logger.
- **Elastic IPs (`01-elastic-ip-stack.yaml`)**: Allocations for NAT gateways (used by network stack).
- **S3 (`02-s3-stack.yaml`)**: Private S3 bucket for frontend hosting with OAI policy.
- **Hosted zone (`05-hosted-zone-stack.yaml`)**: Public Route 53 zone for `HostedZoneDomainNameParam`.
- **Network (`06-network-stack.yaml`)**: VPC, 3× public + 3× private subnets, IGW, route tables, S3 gateway endpoint, Lambda SG, RDS subnet group + SG, NATs (1 in non‑prod, 3 in prod).
- **RDS (`14-rds-nested-stack.yaml`)**: Aurora Serverless v2 for Postgres.
- **Redis (`15-redis-nested-stack.yaml`)**: ElastiCache Redis cluster.
- **ECS (`16-ecs-nested-stack.yaml`)**: Fargate cluster + internal NLB + service discovery + autoscaling.
- **API Gateway (`17-api-gateway-nested-stack.yaml`)**: Public API mapped to internal NLB, DNS integrated with hosted zone.
- **EventBridge (`18-event-bridge-nested-stack.yaml`)**: Event bus/rules (demo wiring).
- **WAF (`19-waf-nested-stack.yaml`)**: WebACL attached to API (regional) or CloudFront (global).
- **Lambda (`20-lambda-stack.yaml`)**: Lambda layer, a Python Lambda from source, and an antivirus scanner Lambda from ECR image.
- **Global (`50-global-resources-stack.yaml`)**: CloudFront cert (us‑east‑1), WAF for CloudFront, distribution, and Route 53 A‑alias to the distribution.
- **Main (`10-main-stack.yaml`)**: Orchestrates nested stacks and parameter wiring.

### Prerequisites
- AWS CLI v2 and `jq` installed and in PATH.
- Valid AWS credentials for the target account. The deploy scripts verify account numbers; update them in `scripts/01-deploy-cfn.sh` and `scripts/02-deploy-cfn-global.sh` if needed.
- Populate parameters in `cfn-stacks/parameters-<env>.json` (`dev`, `stage`, `prod`).
- A prepared Lambda layer zip at `lambda-layer/lambda_layer.zip` (the script uploads it for you). Use `--skip-lambda-layer` to reuse the last uploaded object version.

### Key parameters (edit in `parameters-<env>.json`)
- **EnvironmentParam**: One of `dev|stage|prod`.
- **CidrBlockParam**: VPC CIDR, e.g. `10.90.0.0/16`.
- **HostedZoneDomainNameParam**: Public DNS zone to create, e.g. `dev.example.com`.
- **DemoApiGatewaySubDomainNameParam**: Label for API subdomain, e.g. `api` → `api.dev.example.com`.
- **DemoCloudFrontCertificateDomainNameParam**: Label for frontend, e.g. `front` → `front.dev.example.com`.
- **RDS/Redis backup params**: `RDSBackupEnabledParam`, `RDSBackupRetentionPeriodParam`, `RDSBackupScheduleExpressionParam`, `RedisBackupEnabledParam`, `RedisBackupVaultNameInDRRegionParam`.
- **RDS params**: `DemoDBEngineVersionParam` (e.g. `17`), `DemoDBMinAcuParam`, `DemoDBMaxAcuParam`, `DemoDBNameParam`, `DemoDBMasterUsernameParam`, `DemoDBDeletionProtectionParam`.
- **Redis params**: `RedisEngineVersionParam`, `RedisInstanceTypeParam`, `RedisNumberOfReplicasParam`, `RedisAutomaticFailoverEnabledParam`, `RedisMultiAZEnabledParam`.
- **WafScopeParam**: `REGIONAL` (API) or `CLOUDFRONT`.
- **LambdaLayerS3ObjectVersionParam**: Managed by the deploy script; leave empty locally.

Tip: defaults for `dev` are provided in `parameters-dev.json`.

### Deployment flow
1) Deploy regional stacks (artifacts, ECR, S3, networking, main, etc.)

```bash
./scripts/01-deploy-cfn.sh --region <aws-region> --env <dev|stage|prod> [--disable-rollback] [--skip-lambda-layer]
```

What the script does:
- Deploys `00-technical`, `01-elastic-ip`, `02-s3`, `06-network` stacks.
- Uploads `lambda_layer.zip` to the artifacts bucket and injects `LambdaLayerS3ObjectVersionParam` into your params file.
- Ensures the hosted zone exists via `05-hosted-zone-stack.yaml`. If newly created, it prints the NS records so you can delegate from the parent zone; then re‑run the script.
- Packages `10-main-stack.yaml` and deploys `demo-main-stack` with capabilities.
- In `stage`/`prod`, applies a restrictive stack policy (see `main-stack-policy.json`).

2) Deploy global (us‑east‑1) CloudFront + cert + WAF

```bash
./scripts/02-deploy-cfn-global.sh --region <same-regional-region> --env <dev|stage|prod>
```

Notes:
- The script reads exports and S3 outputs from regional stacks and deploys `50-global-resources-stack.yaml` in `us-east-1` (as required by ACM for CloudFront).
- CloudFront alias becomes `<DemoCloudFrontCertificateDomainNameParam>.<HostedZoneDomainNameParam>`.

3) Upload the frontend app to S3

```bash
aws s3 sync cloudfront-frontend-code/ s3://<demo-frontend-bucket> --region <aws-region>
```

Find the bucket name from outputs/export `demo-s3-bucket-for-frontend`.

### Container images and Lambda images
- Backend ECS image: push to ECR repo export `demo-backend-service` (defaults to `:latest` if no tag provided in task definition). Example:

```bash
aws ecr get-login-password --region <aws-region> | docker login --username AWS --password-stdin <account>.dkr.ecr.<aws-region>.amazonaws.com
docker build -t demo-backend-service ecr-repo-services/demo-backend-service
docker tag demo-backend-service:latest <repo-uri>:latest
docker push <repo-uri>:latest
```

- Antivirus scanner Lambda image: push to repo export `demo-antivirus-scanner`. Tag defaults to `latest` or set via `DemoAntivirusScannerECRRepositoryTag`.

### Useful outputs/exports
- `demo-s3-bucket-for-main-stack`: Artifacts bucket for packaging templates and the Lambda layer.
- `demo-s3-bucket-for-frontend`: Frontend hosting bucket.
- `demo-hosted-zone-id` and `demo-hosted-zone-domain-name`: Used by API/CloudFront Route 53 records.
- `demo-backend-nlb-dns-<env>`: Internal NLB DNS, wired into API Gateway.
- `demo-ecs-cluster-name-<env>`: ECS cluster name.

### Troubleshooting
- If `10-main-stack` validation fails, check that `parameters-<env>.json` matches required parameter types and that the artifacts bucket exists in the region.
- If certificate validation is pending, ensure the DNS validation CNAMEs were created automatically (they are when cert and zone are in the same account/zone).
- If the hosted zone was just created, delegate NS records from the parent zone and re‑run the regional deploy.

### Cleanup
Delete in reverse order and empty S3 buckets before deletion:
1) Global stack (`global-resources-stack`) in `us-east-1`.
2) Main and nested regional stacks (NATs/elastic IPs last).
3) ECR images (optional) and S3 artifact/frontend buckets.


