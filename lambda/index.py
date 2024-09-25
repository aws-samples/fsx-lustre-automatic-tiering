# Import libraries
import boto3
import botocore
import os

# Declare clients and initialize variables
fsx = boto3.client('fsx')
days_since_last_access = int(os.getenv('days_since_last_access'))
dra_file_system_path = os.getenv('dra_file_system_path')

# Handler
def lambda_handler(event, context):
    
    # Log event
    # print(event)
    
    # Extact file system id from CW alarm payload
    try: 
        alarmConfiguration = event.get('alarmData').get('configuration')
        metricData = alarmConfiguration['metrics'][0]['metricStat']['metric']
        fileSystemId = metricData['dimensions']['FileSystemId']
        print('Low storage alarm has been triggered for this FSxL: {}'.format(fileSystemId))
    
    except Exception as e: 
        print('Error while extracting fileSystemId from cloudwatch alarm event payload...')
        raise(e)
    
    # Define release config for release task
    releaseConfigSettings = {
        'DurationSinceLastAccess': {
            'Unit': 'DAYS',
            'Value': days_since_last_access
        }
    }
    
    # Define report settings for release task
    try: 
        # Retrieve S3 repository path from DRA
        response = fsx.describe_data_repository_associations(Filters=[{'Name': 'file-system-id', 'Values': [fileSystemId]}])
        draPath = response.get('Associations')[0].get('DataRepositoryPath')
        print('Data repository path associated with this file system is: {}'.format(draPath))

        # Create report settings
        reportSettings = {
            'Enabled': True,
            'Path': draPath + 'release-task-reports-lambda',
            'Format': 'REPORT_CSV_20191124',
            'Scope': 'FAILED_FILES_ONLY'
        }        

    except botocore.exceptions.ClientError as error:
        print('Failed to retrieve data repository path associated with this file system!')
        raise(error)    

    
    # create release task
    try: 
        print('Initiating a data repository release task on target FSxL file system...')
        response = fsx.create_data_repository_task(
            FileSystemId=fileSystemId, 
            Type='RELEASE_DATA_FROM_FILESYSTEM', 
            Paths=[dra_file_system_path], 
            ReleaseConfiguration=releaseConfigSettings,
            Report=reportSettings
        )    
    
        # Extract status code
        statusCode = response['ResponseMetadata']['HTTPStatusCode'] 
        print('Release task was successfully started on {}'.format(fileSystemId))
    
    except botocore.exceptions.ClientError as error:
        print('Failed to create a DRA release task!')
        raise(error)
