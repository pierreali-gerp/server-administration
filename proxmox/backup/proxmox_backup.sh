#!/bin/bash

# In this script "tee" is used in pipe (look for this operator close to the end: | ) with a subprocess. Thus,
# the following is important to set as "pipefail" returns the exit status of the rightmost failing command. Without it,
# if "tee" runs correctly and the log is written at the end of the script, a 0 status would be reported by the whole program.
set -o pipefail

#--------------------------------------------------------------------------------
# DEFINITIONS

# IMPORTANT NOTES BEFORE RUNNING:
#  - Remember to make this script executable with "chmod +x" before running;
#  - This script can be run as a NON-ROOT user on non-heavily-customized Proxmox
#    configurations, and you should always do so!!!

# TARGET_STORAGE definitions:
TS_IP="xxx.xxx.xxx.xxx"
TS_BASE_PATH="shared_folder_name/path" #On Synology NASs, this takes the form: "<shared_folder_name>/<path>".
                                       #The target path specified here must be entirely dedicated to the outputs
                                       #from this backup script and must be empty (subfolders will be automatically
                                       #created on the first run).
TS_USER="uname" #Replace with a user with write permissions on TS_BASE_PATH
TS_PASS="$HOME/proxmox_backup.secret" #Replace with absolute path to a file containing user's password.
                                      #NOTE: This file must be stored with "600" permissions for it to be read by
                                      #      sshpass (use "chmod 600 ..." after copying it to the final destination)

# PVE definitions:
PVE_VM_BACKUP_PATH="/datapool/archive/VMdataProxmox/dump/" #Default one: /var/lib/vz/dump/
PVE_BACKUP_STORAGE_NAME="datapool-VMdata" #Default one: local
BACKUP_INTERFACES=1 #1: yes, 0: no
BACKUP_DNSMASQ=1 #1: yes, 0: no

# RSYNC OPTIONS
A_MOD_FLAGS="-rltD" #The -a flag includes -rlptgoD, but one might not want to preserve all of those when transferring to a
                    #network storage (e.g., disabling -p, -g, and -o is useful to let Synology NASs keep default shared folder
                    #permissions)
PERM_FLAGS="--no-p --no-g" #As suggested in rsync manual, this should stress mantaining the destination
                           #permissions and group ownership (changing the -a flag as made above didn't bring correct
                           #inheritance of Synology's ACLs). However, it still doesn't seem to guarantee Synology's ACL
                           #are kept in the destination folder...
FUNC_FLAGS="-z --progress" #Add --dry-run here for testing

#--------------------(do not change anything below this line)--------------------


#--------------------------------------------------------------------------------
# LOGGING SETUP AND START

# Redirect standard error (2) to standard output (1) to capture both with "tee"
LOG_FNAME=log_$(date +"%Y_%m_%d-%H_%M_%S").txt
LOG_PATH="$HOME/BackupLogs"
exec 2>&1

# # DECOMMENT FOR DEBUGGING:
# echo "Press Enter to create log folder in $LOG_PATH..."
# read -p ""

# Create backup logs local folder
if [[ ! -d "$LOG_PATH" ]]; then
    mkdir -p $LOG_PATH
fi

# Mark the beginning of the script portion to be logged
{

#--------------------------------------------------------------------------------
# FIRST CHECKS
# Check for password file existence to ensure rsync commands can run
if [[ ! -r "$TS_PASS" ]]; then
    echo "ERROR: Rsync password file is missing or unreadable."
    exit 1
fi

#--------------------------------------------------------------------------------
# NETWORK FILES BACKUP
# Copy network files to local temporary path
NETWORK_FILES_TEMP_PATH="$HOME/Network_backup" #DO NOT append "/" at the end
if [[ ! -d "$NETWORK_FILES_TEMP_PATH" ]]; then
    mkdir -p "$NETWORK_FILES_TEMP_PATH"
fi

# # DECOMMENT FOR DEBUGGING:
# echo "Press Enter to copy network backup to $NETWORK_FILES_TEMP_PATH..."
# read -p ""

if (( BACKUP_INTERFACES == 1 )); then
    echo "Copying interfaces file and interfaces.d..."

    if [[ -f /etc/network/interfaces ]]; then
        cp /etc/network/interfaces "$NETWORK_FILES_TEMP_PATH" ||
            echo "WARNING: Failed to copy interfaces file. Excluded from backup."
    else
        echo "WARNING: interfaces file not found. Excluded from backup."
    fi

    if [[ -d /etc/network/interfaces.d ]]; then
        cp -R /etc/network/interfaces.d "$NETWORK_FILES_TEMP_PATH" ||
            echo "WARNING: Failed to copy interfaces.d. Excluded from backup."
    else
        echo "WARNING: interfaces.d not found. Excluded from backup."
    fi
    
fi

if (( BACKUP_DNSMASQ == 1 )); then
    echo "Copying dnsmasq configuration..."

    if [[ -f /etc/dnsmasq.conf ]]; then
        cp /etc/dnsmasq.conf "$NETWORK_FILES_TEMP_PATH/" ||
            echo "WARNING: Failed to copy dnsmasq.conf. Excluded from backup."
    else
        echo "WARNING: dnsmasq.conf not found. Excluded from backup."
    fi

    if [[ -d /etc/dnsmasq.d ]]; then
        cp -R /etc/dnsmasq.d "$NETWORK_FILES_TEMP_PATH/" ||
            echo "WARNING: Failed to copy dnsmasq.d. Excluded from backup."
    else
        echo "WARNING: dnsmasq.d not found. Excluded from backup."
    fi

fi


# Send temporary folder with network files to target storage
# Note: The :: syntax identifies an rsync daemon module, not an ordinary filesystem path or SSH destination.
#       While "::" is compatible with Synology NASs (when "rsync" transfers are enabled in settings), the simpler ":" is
#       the one to use for SSH/SFTP storage targets.
echo "--------------------------------------------------------------------------"
echo "INFO: Starting network files backup with rsync..."

rsync $A_MOD_FLAGS $PERM_FLAGS $FUNC_FLAGS \
      -e "sshpass -f $TS_PASS ssh" \
      "$NETWORK_FILES_TEMP_PATH/" \
      $TS_USER@$TS_IP::"$TS_BASE_PATH/Network_backup/"
RSYNC_EXIT_CODE=$?

if (( RSYNC_EXIT_CODE == 5 )); then
    echo "ERROR: rsync failed to start the client-server protocol."
    echo "       Possible causes include SSH authentication, host key"
    echo "       verification, or remote rsync daemon configuration."
    echo "       To verify SSH connectivity, run:"
    echo "          ssh $TS_USER@$TS_IP"
    echo "       Verify the remote host key before accepting it."
    echo "       If you are prompted with host key verification, re-run"
    echo "       this script even if SSH authentication fails (your user might"
    echo "       be authorized to use rsync and SFTP but not SSH directly)."
    exit "$RSYNC_EXIT_CODE"
elif (( RSYNC_EXIT_CODE > 0 )); then
    echo "ERROR: rsync failed with exit code $RSYNC_EXIT_CODE."
    echo "       Check the rsync output above for details."
    exit "$RSYNC_EXIT_CODE"
fi

echo "INFO: Network files backup with rsync ended (check above for any issues)."
echo "--------------------------------------------------------------------------"

# # DECOMMENT FOR DEBUGGING:
# echo "Press Enter to remove $NETWORK_FILES_TEMP_PATH..."
# read -p ""

# Remove network local temporary path
rm -R "$NETWORK_FILES_TEMP_PATH"


#--------------------------------------------------------------------------------
# VMs BACKUP

# Create VM backups
# Note: We don't need the following if we manage backup scheduling directly
#       from Proxmox WebUI (Datacenter -> Backup -> Add). Nonetheless, the
#       command below looks legit (IT HAS NEVER BEEN TESTED!) to achieve what we
#       generally want:
#         - all VMs get backed up
#         - "snapshot" mode is used (VMs that are on get backed up without interruptions)
#         - retention policy is set to keep only the last backup; by doing so, we count
#           on the snapshots taken directly on the target storage (to spare storage space
#           on the Proxmox host)
# vzdump --node $(hostname) --compress zstd --notes-template 'Automated backup of {{node}} VM {{vmid}}-{{guestname}}' \
#        --all 1 --mode snapshot --storage $PVE_BACKUP_STORAGE_NAME --fleecing 0 --notification-mode notification-system \
#        --prune-backups 'keep-last=1'

# FUTURE DEVELOPMENT: Note that managing backup creation directly from this script would:
#   a) ensure that PVE backups are completed before running the following rsync command;
#   b) make possible to perform custom checks before executing the backup task for each VM.
# Regarding b), for example, we could list all the existing VMs with "qm list" and, for each VM:
#   - if it's running, run vzdump;
#   - if it isn't running, run vzdump only if the last time it was stopped or shut down comes after
#     the last available backup for that VM.
# A possible implementation of those (Pierluigi's workspace): https://chatgpt.com/s/t_6b04875e47dc81a48b6c52e0325629cd

# Check PVE backup path existence
if [[ ! -d "$PVE_VM_BACKUP_PATH" ]]; then
    echo "ERROR: PVE VM backup directory does not exist."
    exit 1
fi

# Copy VM backups to target storage
# Notes: * --delete-delay deletes VM backups from the destination that do not exist in source directory to avoid wasting storage.
#          Again, we are counting on target storage snapshots with a sensible retention policy. Using --delete-delay instead of the
#          simpler --delete, the evaluation of which files should be removed is done at the beginning, but we ensure that the
#          actual deletion is performed after the data transfer is completed (i.e., if the rsync process crashes for any reason,
#          and the data transfer halts, older backups are preserved).
#        * --itemize-changes is added to make transfers and deletions transparent on the produced log.
#        * Before using rsync with --delete-delay, we check that at least one backup file is present in PVE backup folder; if
#          there isn't any, a wrong PVE_VM_BACKUP_PATH might have been defined by the user, and we need to protect all files in the
#          backup destination path from being removed! To perform the check we can use "compgen":
#          compgen -G returns success if at least one matching file exists, and failure otherwise. The > /dev/null discards its
#          output because we only need the exit status.
if ! compgen -G "$PVE_VM_BACKUP_PATH/*.vma.*" > /dev/null; then
    echo "WARNING: No VM backup archives found. Skipping backup with rsync to prevent remote deletions."
else
    echo "-------------------------------------------------------------------------------------------"
    echo "INFO: Starting VMs backup with rsync..."
    rsync $A_MOD_FLAGS $PERM_FLAGS $FUNC_FLAGS \
        --itemize-changes --delete-delay \
        -e "sshpass -f $TS_PASS ssh" \
        "$PVE_VM_BACKUP_PATH/" \
        $TS_USER@$TS_IP::"$TS_BASE_PATH/dump/"
    echo "INFO: VMs backup with rsync ended (check above for synced/deleted files and any issues)."
    echo "-------------------------------------------------------------------------------------------"
fi

#--------------------------------------------------------------------------------
# LOG EVERYTHING TO FILE - Mark the end of the script portion to be logged and write the log to file with "tee"
# Added 2>&1 to redirect standard error to standard output and make tee logging it too. So, if
# the Python script encounters errors while executing, these will be reported in the log file!

} 2>&1 | tee "${LOG_PATH}/${LOG_FNAME}"

# The following stores the proper exit code, thanks to the "pipefail" set at the beginning
BACKUP_EXIT_CODE=$?

# Append the backup result to the log
if (( BACKUP_EXIT_CODE == 0 )); then
    echo "INFO: Backup operations completed with no ERRORS." \
        | tee -a "${LOG_PATH}/${LOG_FNAME}"
else
    echo "ERROR: Backup operations failed (last failure exit code: $BACKUP_EXIT_CODE)." \
        | tee -a "${LOG_PATH}/${LOG_FNAME}"
fi

# Copy log file to target storage
rsync $A_MOD_FLAGS $PERM_FLAGS $FUNC_FLAGS \
      -e "sshpass -f $TS_PASS ssh" \
      "${LOG_PATH}/${LOG_FNAME}" \
      $TS_USER@$TS_IP::"$TS_BASE_PATH/BackupLogs/"

# Ensure that the backup exit code is reported at the end 
exit "$BACKUP_EXIT_CODE"

# # DECOMMENT FOR DEBUGGING:
# echo "Press Enter to close..."
# read -p ""

