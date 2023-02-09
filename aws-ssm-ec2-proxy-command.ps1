#!/usr/bin/env pwsh
######## Source ################################################################
#
# https://github.com/qoomon/aws-ssm-ec2-proxy-command
#
######## Usage #################################################################
# https://github.com/qoomon/aws-ssm-ec2-proxy-command/blob/master/README.md
#
# Install Proxy Command
#   - Move this script to ~/.ssh/aws-ssm-ec2-proxy-command.ps1
#   - Ensure you are allowed to execute powershell scripts (see Set-ExecutionPolicy command)
#
# Add following SSH Config Entry to ~/.ssh/config
#   host i-* mi-*
#     IdentityFile ~/.ssh/id_rsa
#     ProxyCommand powershell.exe ~/.ssh/aws-ssm-ec2-proxy-command.ps1 %h %r %p ~/.ssh/id_rsa.pub
#     StrictHostKeyChecking no
#
# Ensure SSM Permissions for Target Instance Profile
#   https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-instance-profile.html
#
# Open SSH Connection
#   ssh <INSTANCE_USER>@<INSTANCE_ID>
#
#   Ensure AWS CLI environment variables are set properly
#   e.g. AWS_PROFILE='default' ssh ec2-user@i-xxxxxxxxxxxxxxxx
#
#   If default region does not match instance region you need to provide it like this
#   ssh <INSTANCE_USER>@<INSTANCE_ID>--<INSTANCE_REGION>
#
################################################################################
$ErrorActionPreference = "Stop"

$REGION_SEPARATOR = "--"

$ec2_instance_id = $args[0]
$ssh_user = $args[1]
$ssh_port = $args[2]
$ssh_public_key_path = $args[3]
$aws_sso = $args[4]
$aws_profile = $args[5]
$ssh_public_key = (Get-Content $ssh_public_key_path | Select-Object -first 1)
$ssh_public_key_timeout = 60


#1- Login to create token
aws sso login --sso-session $aws_sso


$splitted_instance = $ec2_instance_id -split $REGION_SEPARATOR

if ($splitted_instance.Length -gt 1)
{
  $ec2_instance_id = $splitted_instance[0]
  $env:AWS_DEFAULT_REGION = $splitted_instance[1]
}

Write-Output "Add public key $ssh_public_key_path for $ssh_user at instance $ec2_instance_id for $ssh_public_key_timeout seconds"

$addPublicKeyCommands = @"
  \"
  mkdir -p ~$ssh_user/.ssh && cd ~$ssh_user/.ssh || exit 1

  authorized_key='$ssh_public_key ssm-session'
  echo \\\"`${authorized_key}\\\" >> authorized_keys

  sleep $ssh_public_key_timeout

  grep -v -F \\\"`${authorized_key}\\\" authorized_keys > .authorized_keys
  mv .authorized_keys authorized_keys
  \"
"@


#2- Send public key to Instance
aws ssm send-command  --profile $aws_profile --instance-ids "$ec2_instance_id"  --document-name AWS-RunShellScript  --comment "Add an SSH public key to authorized_keys for $ssh_public_key_timeout seconds" --parameters commands="$addPublicKeyCommands"
  
if($LASTEXITCODE -ne 0) { Write-Error "Failed to add public key with error $output" }

Write-Output "aws ssm start-session  --target $ec2_instance_id --profile $aws_profile --document-name AWS-StartSSHSession"


#3- Start Session with Document Name: AWS-StartSSHSession
aws ssm start-session  --target $ec2_instance_id --profile $aws_profile --document-name AWS-StartSSHSession 


if($LASTEXITCODE -ne 0) { Write-Error "Failed to start ssm session to instance $output" }