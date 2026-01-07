#!/bin/bash

clear
set -e

AWS_REGION=$(aws configure get region)

# Colors for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner function
print_banner() {
    local title="$1"
    local length=${#title}
    local line=$(printf '=%.0s' $(seq 1 $((length + 10))))
    
    echo -e "${BLUE}$line${NC}"
    echo -e "${BLUE}====${NC} ${YELLOW}$title${NC} ${BLUE}====${NC}"
    echo -e "${BLUE}$line${NC}"
}

# Function to push Docker image to ECR
push_image_to_ecr() {
    print_banner "PUSHING IMAGE TO ECR"
    
    #local region="$AWS_REGION"
    local repository_name="pestpp"
    local image_tag="latest"

    # Authenticate Docker to the AWS ECR repository
    local account_id=$(aws sts get-caller-identity --query "Account" --output text)
    local ecr_login_password=$(aws ecr get-login-password --region "$AWS_REGION")
    local ecr_repository="${account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com"

    echo "Authenticating with ECR..."
    echo $ecr_login_password | docker login --username AWS --password-stdin $ecr_repository

    echo "Building Docker image..."
    docker build -t $repository_name ./docker

    echo "Tagging Docker image..."
    docker tag $repository_name:latest $ecr_repository/$repository_name:$image_tag

    echo "Pushing image to ECR..."
    docker push $ecr_repository/$repository_name:$image_tag

    echo -e "${GREEN}Successfully pushed image to ECR!${NC}"
}

# Submit manager job and get its IP
submit_manager_job() {
    print_banner "SUBMITTING MANAGER JOB"
    
    echo "Submitting PESTPP manager job to AWS Batch..."
    
    MANAGER_JOB_ID=$(aws batch submit-job \
        --job-name "$MANAGER_JOB_NAME" \
        --job-queue "$MANAGER_JOB_QUEUE" \
        --job-definition "$MANAGER_JOB_DEFINITION" \
        --region "$AWS_REGION" \
        --query 'jobId' \
        --output text)
    
    echo -e "Manager job submitted with ID: ${YELLOW}$MANAGER_JOB_ID${NC}"
    echo "Waiting for manager job to start running..."
    
    while true; do
        STATUS=$(aws batch describe-jobs --jobs "$MANAGER_JOB_ID" --region "$AWS_REGION" --query 'jobs[0].status' --output text)
        if [ "$STATUS" = "RUNNING" ]; then
            echo -e "${GREEN}Manager job is now running!${NC}"
            break
        elif [ "$STATUS" = "FAILED" ]; then
            echo "ERROR: Manager job failed to start. Check AWS Batch console for details."
            exit 1
        fi
        echo "Job status: $STATUS - waiting..."
        sleep 10
    done

}

# Submit worker jobs pointing to the manager (array job)
submit_worker_jobs() {
    print_banner "SUBMITTING WORKER JOBS"
    
    echo -e "Submitting ${YELLOW}$NUM_WORKERS${NC} PESTPP worker jobs as an array..."
    
    if [ "$NUM_WORKERS" -gt 1 ]; then
        # Submit array job
        WORKER_JOB_ID=$(aws batch submit-job \
        --job-name "$WORKER_JOB_NAME_PREFIX" \
        --job-queue "$WORKER_JOB_QUEUE" \
        --job-definition "$WORKER_JOB_DEFINITION" \
        --region "$AWS_REGION" \
        --array-properties size=$NUM_WORKERS \
        --query 'jobId' \
        --output text)
    else
        # Submit a single job
        WORKER_JOB_ID=$(aws batch submit-job \
        --job-name "$WORKER_JOB_NAME_PREFIX" \
        --job-queue "$WORKER_JOB_QUEUE" \
        --job-definition "$WORKER_JOB_DEFINITION" \
        --region "$AWS_REGION" \
        --query 'jobId' \
        --output text)
    fi

    echo -e "Worker jobs submitted with parent ID: ${YELLOW}$WORKER_JOB_ID${NC}"
}

# Main function
main() {
    local subfolder="./terraform"
    
    print_banner "PESTPP AWS BATCH SUBMISSION"
    
    echo "Retrieving configuration from Terraform outputs..."
    
    AWS_REGION=$(terraform -chdir="$subfolder" output -raw aws_region 2>/dev/null) || AWS_REGION="us-east-2"
    MANAGER_JOB_QUEUE=$(terraform -chdir="$subfolder" output -raw batch_manager_job_queue_name 2>/dev/null) || MANAGER_JOB_QUEUE="pestpp-manager-queue"
    WORKER_JOB_QUEUE=$(terraform -chdir="$subfolder" output -raw batch_worker_job_queue_name 2>/dev/null) || WORKER_JOB_QUEUE="pestpp-worker-queue"
    MANAGER_JOB_DEFINITION=$(terraform -chdir="$subfolder" output -raw batch_manager_job_definition_name 2>/dev/null) || MANAGER_JOB_DEFINITION="pestpp-manager"
    WORKER_JOB_DEFINITION=$(terraform -chdir="$subfolder" output -raw batch_worker_job_definition_name 2>/dev/null) || WORKER_JOB_DEFINITION="pestpp-worker"
    S3_BUCKET_NAME=$(terraform -chdir="$subfolder" output -raw s3_bucket_name 2>/dev/null) || S3_BUCKET_NAME="model-output-geomega-1337"
    
    NUM_WORKERS=$(terraform -chdir="$subfolder" output -raw model_count 2>/dev/null) || NUM_WORKERS=${1:-1}
    
    if [[ ! $NUM_WORKERS =~ ^[0-9]+$ ]]; then
        echo "Error: Failed to get a valid model count from Terraform. Using default of 1."
        NUM_WORKERS=1
    fi
    
    MANAGER_JOB_NAME="pestpp-manager-job"
    WORKER_JOB_NAME_PREFIX="pestpp-worker-job"
    
    echo -e "Configuration:"
    echo -e "  AWS Region: ${YELLOW}$AWS_REGION${NC}"
    echo -e "  Manager Job Queue: ${YELLOW}$MANAGER_JOB_QUEUE${NC}"
    echo -e "  Worker Job Queue: ${YELLOW}$WORKER_JOB_QUEUE${NC}"
    echo -e "  Manager Job Definition: ${YELLOW}$MANAGER_JOB_DEFINITION${NC}"
    echo -e "  Worker Job Definition: ${YELLOW}$WORKER_JOB_DEFINITION${NC}"
    echo -e "  S3 Bucket Name: ${YELLOW}$S3_BUCKET_NAME${NC}"
    echo -e "  Number of Worker Jobs: ${YELLOW}$NUM_WORKERS${NC}"
    
    push_image_to_ecr
    submit_manager_job
    submit_worker_jobs
    
    print_banner "JOB SUBMISSION COMPLETE"
    echo -e "${GREEN}All jobs submitted successfully!${NC}"
    echo -e "You can monitor job status in the AWS Batch console:"
    echo -e "${BLUE}https://console.aws.amazon.com/batch/home?region=$AWS_REGION#jobs${NC}"
}

main "$@"