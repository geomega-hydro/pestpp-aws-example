import os
import datetime
import shutil
import subprocess
from time import sleep
import boto3
from botocore.exceptions import NoCredentialsError, PartialCredentialsError, ClientError

def current_date_time() -> str:
    now = datetime.datetime.now().strftime("%Y%m%d_%H%M")
    return now

def get_instance_private_ip(region, tag_key, tag_value):
    try:
        # Initialize a session using your preferred AWS region
        session = boto3.Session(region_name=region)

        # Create an EC2 client
        ec2_client = session.client('ec2')

        # Describe instances with the specified tag name
        response = ec2_client.describe_instances(
            Filters=[
                {
                    'Name': f'tag:{tag_key}',
                    'Values': [tag_value]
                }
            ]
        )
        
        if not response['Reservations']:
            print(f"No instances found with tag {tag_key}={tag_value}")
            return None

        # Extract the private IP from the instance
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                # First try to get the IP from the PrivateIpAddress field directly
                if 'PrivateIpAddress' in instance:
                    return instance['PrivateIpAddress']
                
                # If not available directly, check the network interfaces
                if 'NetworkInterfaces' in instance:
                    # First try DeviceIndex 0 (primary interface)
                    for eni in instance['NetworkInterfaces']:
                        if eni['Attachment']['DeviceIndex'] == 0:
                            return eni['PrivateIpAddress']
                    
                    # If no primary interface found, use any available interface
                    if instance['NetworkInterfaces']:
                        return instance['NetworkInterfaces'][0]['PrivateIpAddress']
        
        print('No suitable IP address found')
        return None

    except NoCredentialsError:
        print("No credentials provided.")
        return None
    except PartialCredentialsError:
        print("Incomplete credentials provided.")
        return None
    except ClientError as e:
        print(f"Client error occurred: {e}")
        return None
    except Exception as e:
        print(f"An error occurred: {e}")
        return None

def zip_model_folder(pestpp_binary, model_directory: str) -> None:
    """
    Zips the specified model directory.

    Parameters:
    - model_directory (str): The name of the model directory to zip.
    """
    if os.getcwd() != "/pestpp":
        os.chdir("/pestpp")
    else:
        pass

    base_dir = os.getcwd()
    model_dir = os.path.join(base_dir, model_directory)

    zip_filename = f"{pestpp_binary}-outputs"
    zip_filepath = base_dir  

    print("Zipping model directory...")
    shutil.make_archive(os.path.join(zip_filepath, zip_filename), 'zip', model_dir)
    print(f"Zipping complete! Model output saved as {zip_filename}.zip")
    return None

def upload_manager_folder_to_s3(region_name: str) -> bool:
    """
    Uploads the contents of the /pestpp/model/manager folder to an Amazon S3 bucket.
    The S3 bucket name is retrieved from the environment variable 'S3_BUCKET'.
    If the environment variable is not set, it prints an error.

    Parameters:
    - region_name (str): The AWS region where the S3 bucket is located.

    Returns:
    - bool: True if the contents were uploaded successfully, False otherwise.
    """
    # Retrieve the bucket name from the environment variable
    bucket_name = os.environ.get("S3_BUCKET_NAME")
    if not bucket_name:
        print("Error: 'S3_BUCKET_NAME' environment variable is not set.")

    s3_client = boto3.client('s3', region_name=region_name)
    manager_folder = '/pestpp/model/'
    folder_key = 'model_results/'  # Define the folder in S3 where files should go (optional)

    try:
        # Upload the contents of the manager folder
        for root, dirs, files in os.walk(manager_folder):
            for file in files:
                file_path = os.path.join(root, file)
                key = os.path.join(folder_key, os.path.relpath(file_path, manager_folder))
                
                # Upload each file to the S3 bucket in the specified folder
                s3_client.upload_file(file_path, bucket_name, key)
                print(f"File {file_path} uploaded successfully to s3://{bucket_name}/{key}")

    except ClientError as e:
        print(f"Client error occurred: {e}")
    except Exception as e:
        print(f"An error occurred: {e}")
 

def start_manager_agent(pestpp_binary: str, control_file: str) -> None:
    """
    Starts the manager agent for a PEST++ model run using the specified binary and control file.

    Parameters:
    - pestpp_binary (str): The path to the PEST++ binary executable.
    - control_file (str): The name of the PEST++ control file.
    """
    command = [pestpp_binary, control_file, "/h", ":4004"]

    subprocess.run(command)


def start_worker_agent(pestpp_binary: str, control_file: str, manager_ip: str) -> None:
    """
    Starts a worker agent for a PEST++ model run using the specified binary, control file, and manager IP address.

    Parameters:
    - pestpp_binary (str): The path to the PEST++ binary executable.
    - control_file (str): The name of the PEST++ control file.
    - manager_ip (str): The IP address of the manager agent.
    """
    command = [pestpp_binary, control_file, "/h", f"{manager_ip}:4004"]

    subprocess.run(command)

def main():
    """
    Main function to start either a manager or worker agent for a PEST++ model run based on environment variables.

    This function reads environment variables to determine the role (manager or worker), the control file,
    the manager IP address (for workers), and the path to the PEST++ binary executable. It then changes the
    current working directory to the 'model' directory and starts the appropriate agent based on the role.

    Environment Variables:
    - ROLE: Specifies the role of the current instance ('manager' or 'worker').
    - CONTROL_FILE: The name of the PEST++ control file.
    - MANAGER_IP: The IP address of the manager (required for workers).
    - PESTPP_BINARY: The path to the PEST++ binary executable.
    - MODEL_DIR: The name of the model directory.
    - S3_BUCKET_NAME: The name of the S3 bucket to which the output zip file will be uploaded.
    - AWS_REGION: The region AWS will launch resources
    """
    role = os.getenv("ROLE")
    control_file = os.getenv("CONTROL_FILE")
    manager_ip = os.getenv("MANAGER_IP")
    pestpp_binary = os.getenv("PESTPP_BINARY")
    model_dir = os.getenv("MODEL_DIR")
    s3_bucket_name = os.getenv("S3_BUCKET_NAME")
    region = os.getenv("AWS_REGION")

    os.chdir(model_dir)
    
    if role == "manager":
        start_manager_agent(pestpp_binary, control_file)
        if s3_bucket_name != "local":
            print("Uploading model output to S3 bucket...")
            upload_manager_folder_to_s3(region)
        else:
            print(f"Go on and grab the model files...")
            sleep(3*60*60)
    elif role == "worker":
        # tags are located in the EC2 instance metadata aka ec2.tf
        tag_key = 'Name'
        tag_value = 'PESTPP-Manager-Ondemand'
        manager_ip = get_instance_private_ip(region, tag_key, tag_value)
        if manager_ip == None:
            print("Starting manager on localhost.")
            manager_ip = 'manager'
            start_worker_agent(pestpp_binary, control_file, manager_ip)
        else:
            start_worker_agent(pestpp_binary, control_file, manager_ip)


if __name__ == "__main__":
    main()
