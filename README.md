# pestpp-aws-example

This repository contains a containerized Pest++ application intended for deployment on AWS using Linux. It runs the `sagehen_mf6 model` and is provided for demonstration and testing purposes only; it is not intended for production use.

## 📋 Initial Requirements

Ensure you have the following installed:

1. [Python](https://www.python.org/downloads/)
2. [Docker](https://docs.docker.com/get-docker/) (if using WSL install Docker Desktop for Windows)
3. [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)

## 🛠️ Installing and Configuring AWS CLI

1. **Install AWS CLI**: 
    ```bash
      curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
      unzip awscliv2.zip
      sudo ./aws/install
    ```
2. **Configure AWS CLI**:
    ```bash
      aws configure
    ```

   Fill out your credential information. The AWS Access Key ID and Secret Access Key are generated in IAM. Contact your AWS administrator.
    ```bash  
      AWS Access Key ID [None]: 
      AWS Secret Access Key [None]:
      Default region name [None]: us-east-2
      Default output format [None]: json
    ```

## 🏗️ Installing and Configuring Terraform

1. **Update and/or install dependencies**:
   ```bash
      sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
   ```
2. **Install the HashiCorp GPG key**:
   ```bash
      wget -O- https://apt.releases.hashicorp.com/gpg | \
      gpg --dearmor | \
      sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
   ```

3. **Add HashiCorp repository to your system**:
   ```bash
      echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
      https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
      sudo tee /etc/apt/sources.list.d/hashicorp.list
   ```
4. **Update HashiCorp repository**:
   ```bash
      sudo apt update
   ```

5. **Install Terraform from Hashicorp repository**:
   ```bash
      sudo apt-get install terraform
   ```

## 🚀 Deploying to AWS

Follow these steps to deploy Pest++ to AWS:

1. **Alter variables if needed**
   - Alter the `terraform/variables.tf`
      - You may need to adjust the `aws_region`, `availability_zones`, and `model_count` variables.

2. **Deploy AWS Architecture Using Terraform**
   - Enter into the terraform directory `cd terraform`
   - Run `terraform init`
   - Run `terraform apply`  

3. **Submit Pest++ to AWS Batch**
   - Once the architecture is deployed, return to the main directory and submit Pest++ to AWS Batch by running:
     ```bash
     bash run_pestpp.sh
     ```
   - Monitor the logs via AWS CloudWatch.

4. **Tear Down AWS Architecture**
   - After Pest++ completes and you grabbed the model output from s3, teardown the architecture.
        ```bash
     terraform destroy
     ```
