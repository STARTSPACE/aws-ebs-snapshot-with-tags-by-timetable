#!/bin/bash
# Safety feature: exit script if error is returned, or if variables not set.
# Exit if a pipeline results in an error.
set -ue
set -o pipefail

#######################################################################
#
## Automatic EBS Volume Snapshot Creation & Clean-Up Script
#
# Originally written by Star Dot Hosting (http://www.stardothosting.com)
# http://www.stardothosting.com/blog/2012/05/automated-amazon-ebs-snapshot-backup-script-with-7-day-retention/
#
# Heavily updated by Casey Labs Inc. (http://www.caseylabs.com)
# Casey Labs - Contact us for all your Amazon Web Services Consulting needs!
# 
# Modified by STARTSPACE Cloud - snapshots executes by tag selections and can be started by any user in sudo group
# https://www.startspace.ru/
#
# PURPOSE: This Bash script can be used to take automatic snapshots of your Linux EC2 instance. Script process:
# - Gather a list of all volume IDs where tag attached
# - Take a snapshot of each attached volume
# - The script will then delete all associated snapshots taken by the script that are older than 7 days
#
#
# DISCLAMER: The software and service is provided by the copyright holders and contributors "as is" and any express or implied warranties, 
# including, but not limited to, the implied warranties of merchantability and fitness for a particular purpose are disclaimed. In no event shall
# the copyright owner or contributors be liable for any direct, indirect, incidental, special, exemplary, or consequential damages (including, but
# not limited to, procurement of substitute goods or services; loss of use, data, or profits; or business interruption) however caused and on any
# theory of liability, whether in contract, strict liability, or tort (including negligence or otherwise) arising in any way out of the use of this
# software or service, even if advised of the possibility of such damage.
#
# NON-LEGAL MUMBO-JUMBO DISCLAIMER: Hey, this script deletes snapshots (though only the ones that it creates)!
# Make sure that you understand how the script works. No responsibility accepted in event of accidental data loss.
# 
#######################################################################

export PATH=$PATH:/usr/local/bin/:/usr/bin

## START SCRIPT

# Set Variables
today=`date +"%d-%m-%Y"+"%T"`
logfile="/awslog/ebs-snapshot.log"

# How many days do you wish to retain backups for?
retention_days="7"
retention_date_in_seconds=`date +%s --date "$retention_days days ago"`

# Start log file: today's date
echo Backup started $today >> $logfile

# Grab all volume IDs attached to this instance, and export the IDs to a text file
sudo aws ec2 describe-volumes  --filters Name=tag:snap-07-time,Values=23-00 Name=tag:bash-profile,Values=wd --query Volumes[*].[VolumeId] --output text | tr '\t' '\n' > ~/tmp/volume-info-days-07.txt 2>&1

# Take a snapshot of all volumes attached to this instance
for volume_id in $(cat ~/tmp/volume-info-days-07.txt)
do
    description="$(hostname)-backup-$(date +%Y-%m-%d)"
	echo "Volume ID is $volume_id" >> $logfile
    
	# Next, we're going to take a snapshot of the current volume, and capture the resulting snapshot ID
	snapresult=$(sudo aws ec2 create-snapshot --output=text --description $description --volume-id $volume_id --query SnapshotId)
	
    echo "New snapshot is $snapresult" >> $logfile
         
    # And then we're going to add a "CreatedBy:AutomatedBackup" tag to the resulting snapshot.
    # Why? Because we only want to purge snapshots taken by the script later, and not delete snapshots manually taken.
    sudo aws ec2 create-tags --resource $snapresult --tags Key=Created-By,Value=STS-Automated-Backup
done

# Get all snapshot IDs associated with each volume attached to this instance
rm ~/tmp/snapshot-info-days-07.txt --force

for vol_id in $(cat ~/tmp/volume-info-days-07.txt)

do
    sudo aws ec2 describe-snapshots --output=text --filters "Name=volume-id,Values=$vol_id" "Name=tag:Created-By,Values=STS-Automated-Backup" --query Snapshots[*].[SnapshotId] | tr '\t' '\n' | sort | uniq >> ~/tmp/snapshot-info-days-07.txt 2>&1
done

# Purge all instance volume snapshots created by this script that are older than X days
for snapshot_id in $(cat ~/tmp/snapshot-info-days-07.txt)
do
    echo "Checking $snapshot_id..."
	snapshot_date=$(sudo aws ec2 describe-snapshots --output=text --snapshot-ids $snapshot_id --query Snapshots[*].[StartTime] | awk -F "T" '{printf "%s\n", $1}')
    snapshot_date_in_seconds=`date "--date=$snapshot_date" +%s`

    if (( $snapshot_date_in_seconds <= $retention_date_in_seconds )); then
        echo "Deleting snapshot $snapshot_id ..." >> $logfile
        sudo aws ec2 delete-snapshot --snapshot-id $snapshot_id
    else
        echo "Not deleting snapshot $snapshot_id ..." >> $logfile
    fi
done

# One last carriage-return in the logfile...
echo "" >> $logfile

echo "Results logged to $logfile"
