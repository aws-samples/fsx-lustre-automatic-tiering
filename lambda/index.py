import boto3
import botocore
import os

# Declare client
fsxClient = boto3.client('fsx')

# Initialize variables
dsla = int(os.getenv('days_since_last_access'))
draFileSystemPath = os.getenv('dra_file_system_path')


# Lambda function handler
def lambda_handler(event, context):

    # Get file system id
    fileSystemId = getFileSystemId(event)

    # Create report settings
    reportSettings = createReportSettings(fileSystemId)
            
    # create release task
    createReleaseTask(fileSystemId, reportSettings)



def getFileSystemId(event): 
    try: 
        alarmConfiguration = event.get('alarmData').get('configuration')
        metricData = alarmConfiguration['metrics'][0]['metricStat']['metric']
        fileSystemId = metricData['dimensions']['FileSystemId']
        print('Low storage alarm has been triggered for this FSxL: {}'.format(fileSystemId))
        return fileSystemId
    
    except Exception as e: 
        print('Error while extracting fileSystemId from cloudwatch alarm event payload...')
        raise(e)
    


def createReportSettings(fileSystemId): 
    try: 
        # Retrieve S3 repository path from DRA
        response = fsxClient.describe_data_repository_associations(Filters=[{'Name': 'file-system-id', 'Values': [fileSystemId]}])
        draPath = response.get('Associations')[0].get('DataRepositoryPath')
        print('Data repository path associated with this file system is: {}'.format(draPath))

        # Create report settings
        return {
            'Enabled': True,
            'Path': draPath + 'release-task-reports-lambda',
            'Format': 'REPORT_CSV_20191124',
            'Scope': 'FAILED_FILES_ONLY'
        }    

    except botocore.exceptions.ClientError as error:
        print('Failed to retrieve data repository path associated with this file system!')
        raise(error)        


def createReleaseTask(fileSystemId, reportSettings):

    # Define release config for release task
    releaseConfigSettings = {
        'DurationSinceLastAccess': {
            'Unit': 'DAYS',
            'Value': dsla
        }
    }

    # Create release task
    try:
        print('Initiating a data repository release task on target FSxL file system...')
        response = fsxClient.create_data_repository_task(
            FileSystemId=fileSystemId,
            Type='RELEASE_DATA_FROM_FILESYSTEM',
            Paths=[draFileSystemPath],
            ReleaseConfiguration=releaseConfigSettings,
            Report=reportSettings
        )

        # Extract status code
        statusCode = response['ResponseMetadata']['HTTPStatusCode']
        print('Release task was successfully started on {}'.format(fileSystemId))
        return statusCode

    except botocore.exceptions.ClientError as error:
        print('Failed to create a DRA release task!')
        raise(error)
