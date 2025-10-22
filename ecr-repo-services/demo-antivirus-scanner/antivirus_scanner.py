import boto3
import subprocess
import os

s3 = boto3.client('s3')

def lambda_handler(event, context):
    print(event)
    try:
        bucket_name = event['BucketName']
        object_key = event['ObjectKey']
        
        print('Starting virus scan...')
        print(f'BucketName: {bucket_name}, ObjectKey: {object_key}')
        
        # Define the local path to save the file
        local_file_path = f'/tmp/{os.path.basename(object_key)}'
        print(f'Local file path: {local_file_path}')

        # Download the file from S3 to the /tmp directory
        print('Downloading file from S3...')
        s3.download_file(bucket_name, object_key, local_file_path)
        print(f'Files in /tmp directory: {os.listdir("/tmp")}')

        print(f'Running virus scan for {local_file_path} ...')
        # Run the virus scan on the downloaded file
        subprocess.run(['clamscan', local_file_path], check=True)
        print(f'The file {object_key} is free of viruses')
        
        s3.put_object_tagging(
            Bucket=bucket_name,
            Key=object_key,
            Tagging={
                'TagSet': [
                    {
                        'Key': 'VirusScanResult',
                        'Value': 'Scanned'
                    },
                ]
            }
        )
        return {
            'statusCode': 200,
            'body': 'Virus scan completed successfully'
        }    
    except subprocess.CalledProcessError as err:
        if err.returncode == 1:
            print(f'The file {object_key} is infected')
            
            s3.put_object_tagging(
                Bucket=bucket_name,
                Key=object_key,
                Tagging={
                    'TagSet': [
                        {
                            'Key': 'VirusScanResult',
                            'Value': 'Infected'
                        },
                    ]
                }
            )
            return {
                'statusCode': 423,
                'body': 'Provided file is infected'
            }
        else:
            print(f'An error occurred: {err}')
            return {
                'statusCode': 500,
                'body': 'Virus scan failed'
            }
    except Exception as e:
        print(f'A general error occurred: {e}')
        return {
            'statusCode': 500,
            'body': 'An unexpected error occurred'
        }
    finally:
        # Clean up the local file
        if os.path.exists(local_file_path):
            os.remove(local_file_path)