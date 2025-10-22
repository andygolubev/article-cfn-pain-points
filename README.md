## wegoremit.com Cloud Formation templates

### ☑️ Prerequisites
Before the stack is deployed there are couple of things that should be done manually:

#### ⚙️ **uploadqr**
- The DNS zone should be created beforehand. If the new zone is a child (e.g. test.example.com), the necessary records should be added manually to the parent one (example.com) as well.
- The Cloud Front certificate for `uploadqr` should be created and validated manually in `us-east-1` region.
- After the deploy is finished, the code should be uploaded in the `uploadqr` S3 bucket manually. This could be done by using `aws s3 sync {{ LOCAL_DIR}}/. s3://{{ S3_BUCKET }}`.


#### Deploy Stage with 'aws cli' to a new region for test (NOT WORKING NOW)

### ☑️ Prerequisites
- Create a S3 bucket for lambda code (example: vala-lambda-code-ireland)
- Create a S3 bucket for nested stacks (example: vala-nested-stack-ireland)
- Open Cloud Shell and sync S3 content for code ``` aws s3 sync s3://vala-lambda-code s3://vala-lambda-code-ireland ```
- Open Cloud Shell and sync S3 content for stacks ``` aws s3 sync s3://vala-nested-stacks s3://vala-nested-stack-ireland ```
- Create a KeyPair with name "xxxxx" (Default name in stack)


### Deploy stack

Run a command with an REGION and ENV  as parameters to deploy a new stack:

``` bash  ./scripts/deploy-cfn.sh --region eu-west-2 --env staging ```


### Deploy Stage with 'aws cli' to a current London region

#### Copy old stack to stack bucket

``` aws s3 cp ./vala-stack-stging.yml s3://vala-nested-stack ```

#### Deploy stack

``` aws cloudformation update-stack --stack-name vala-staging --template-url https://vala-nested-stacks.s3.amazonaws.com/vala-stack-stging.yml --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND ```
