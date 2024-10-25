
# Optimizing FSx for Lustre storage costs using automatic data tiering with Amazon S3

Managing high-performance file storage can be a significant operational and cost challenge for many organizations, especially those running compute-intensive workloads like high-performance computing (HPC) or data analytics. This project demonstrates how you can leverage Amazon FSx for Lustre (FSxL) as a high-performance caching layer in front of Amazon S3, enabling cost optimization through automated file release.

## Solution Overview
The proposed solution leverages the following key components:
1. FSxL File System
2. Data Repository Association (DRA)
3. DRA Release Task
4. EventBridge Scheduler
5. Capacity Monitoring and Alerting
6. DRA Emergency Release Task

The architecture allows you to use FSxL as a high-performance cache for your Amazon S3 data, with an automated file release mechanism to optimize file system capacity.

## Prerequisites
Before starting, you will need the following prerequisites:
1. Terraform: The Terraform CLI installed on your local machine or remote development environment such as AWS Cloud9.
2. AWS Credentials: Terraform needs access to your AWS credentials to create and manage resources. Configure your AWS credentials as environment variables or use the AWS credentials file (`~/.aws/credentials`).

## Solution Deployment
To deploy the solution using the provided Terraform configuration, follow these steps:

1. Clone the Github repository to your local machine.
2. Navigate to the `terraform` directory within the repository.
3. Review the `variables.tf` file and adjust the variable values according to your requirements.Following are a few important variables
    * sns_topic_email - Email to use for SNS notification, update to your email address.
    * alarm_storage_pct_threshold_for_sns_notifications - The file system’s available storage threshold below which email notifications are sent (default: 0.15).
    * alarm_storage_pct_threshold_for_dra_emergency_release - The file system’s available storage threshold below which an emergency release is triggered (default: 0.25). 
    * duration_since_last_access_value: The variable sets the file contents eviction threshold in days, to release file contents from file system (default: 2).
4. Initialize the Terraform working directory by running `terraform init`.
5. Review the execution plan by running `terraform plan`.
6. If the execution plan looks correct, apply the changes by running `terraform apply -auto-approve`.

Once the deployment is complete, you can start using the file system by launching an EC2 instance and mounting the created FSxL file system.

## Cleanup
When you are done with your testing, run `terraform destroy` to clean up the deployed resources and avoid incurring charges on your AWS account.

## Additional Resources
- [Amazon FSx for Lustre Documentation](https://aws.amazon.com/fsx/lustre/)
- [Amazon FSx for Lustre Using Data Repository Association](https://docs.aws.amazon.com/fsx/latest/LustreGuide/overview-dra-data-repo.html)

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.

