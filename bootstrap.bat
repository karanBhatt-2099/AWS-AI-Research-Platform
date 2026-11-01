@echo off
setlocal

set REGION=ap-south-1
set BUCKET=research-agent-tfstate-836986223851-ai-security
set TABLE=research-agent-tf-locks

echo Checking AWS credentials...
aws sts get-caller-identity
if errorlevel 1 (
    echo ERROR: AWS credentials are invalid or inaccessible.
    exit /b 1
)

echo.
echo Checking S3 bucket: %BUCKET%

aws s3api head-bucket --bucket %BUCKET% >nul 2>&1

if not errorlevel 1 (
    echo Bucket exists and is accessible.
) else (
    echo Attempting to create bucket...

    aws s3api create-bucket --bucket %BUCKET% --region %REGION% --create-bucket-configuration LocationConstraint=%REGION%

    if errorlevel 1 (
        echo ERROR: Could not create the bucket.
        echo Check IAM permissions and bucket-name availability.
        exit /b 1
    )

    echo Bucket created successfully.
)

echo.
echo Enabling S3 versioning...

aws s3api put-bucket-versioning --bucket %BUCKET% --versioning-configuration Status=Enabled
if errorlevel 1 (
    echo ERROR: Failed to enable versioning.
    exit /b 1
)

echo Blocking public access...

aws s3api put-public-access-block --bucket %BUCKET% --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
if errorlevel 1 (
    echo ERROR: Failed to block public access.
    exit /b 1
)

echo Enabling server-side encryption...

set ENCFILE=%TEMP%\s3-encryption-config.json
echo {"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]} > "%ENCFILE%"

aws s3api put-bucket-encryption --bucket %BUCKET% --server-side-encryption-configuration file://%ENCFILE%

if errorlevel 1 (
    echo ERROR: Failed to configure encryption.
    del "%ENCFILE%" >nul 2>&1
    exit /b 1
)

del "%ENCFILE%" >nul 2>&1

echo.
echo Checking DynamoDB table: %TABLE%

aws dynamodb describe-table --table-name %TABLE% --region %REGION% >nul 2>&1

if not errorlevel 1 (
    echo DynamoDB table already exists.
) else (
    echo Creating DynamoDB table...

    aws dynamodb create-table --table-name %TABLE% --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region %REGION%

    if errorlevel 1 (
        echo ERROR: Could not create DynamoDB table.
        echo Check IAM permissions and existing table status.
        exit /b 1
    )

    echo Waiting for DynamoDB table to become active...

    aws dynamodb wait table-exists --table-name %TABLE% --region %REGION%

    if errorlevel 1 (
        echo ERROR: DynamoDB table did not become available.
        exit /b 1
    )
)

echo.
echo Verifying S3 configuration...

aws s3api get-bucket-versioning --bucket %BUCKET%
if errorlevel 1 exit /b 1

aws s3api get-bucket-encryption --bucket %BUCKET%
if errorlevel 1 exit /b 1

aws s3api get-public-access-block --bucket %BUCKET%
if errorlevel 1 exit /b 1

echo.
echo Bootstrap completed successfully.
echo S3 bucket: %BUCKET%
echo DynamoDB table: %TABLE%
echo.
echo Next: cd terraform
echo Then: terraform init

endlocal