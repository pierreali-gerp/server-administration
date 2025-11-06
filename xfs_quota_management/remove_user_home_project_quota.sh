#!/bin/bash
set -e

# This script removes the project quota for the home folder of a specific user on an XFS filesystem.
# It assumes that the user's home project quota was previously set using the corresponding
# "set_user_home_project_quota.sh" script.
# This script does not delete the user or their home directory. It only removes the project
# quota assigned to the home directory.
# NB: It must be run BEFORE the user and their home directory is deleted !!!

# Parse input arguments
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

UNAME=$1

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

# Check if the specified user exists
if ! id "$UNAME" &>/dev/null; then
    echo "ERROR: User $UNAME does not exist."
    exit 1
fi

# Check if the user's home directory still exists
HOME_DIR="/home/$UNAME"
if [ ! -d "$HOME_DIR" ]; then
    echo "ERROR: The specified user's ($UNAME) home directory $HOME_DIR does not exist."
    exit 1
fi

# Getting project ID and name based on the choices made in the script used for setting
# home project quotas ("set_user_home_project_quota.sh")
PROJID=$(id -u $UNAME)
PROJNAME=home$UNAME

# Check that the project quota for the user's home project actually exists
if ! xfs_quota -x -c "quota -ph $PROJNAME" /home; then
    echo "ERROR: No project quota found for project $PROJNAME. No changes have been made."
    exit 1
fi

# Remove from project quota management (-C stands for "clear") all files and directories (i.e.,
# the project's "inodes") currently present in the user's home directory
xfs_quota -x -c "project -C $PROJNAME" /home

# Remove the project quota limits for the user's home project (to be done before removing the
# project from /etc/projects and /etc/projid, so that we can still refer to the project with
# its "project name")
xfs_quota -x -c "limit -p bsoft=0 bhard=0 $PROJNAME" /home

# Check that the project PROJNAME is actually linked to the PROJID we expect from the script
# "set_user_home_project_quota.sh". If not, raise an error.
if ! grep -q "^$PROJNAME:$PROJID" /etc/projid; then
    echo "ERROR: The project $PROJNAME is associated with an unexpected ID:"
    grep "^$PROJNAME:" /etc/projid
    echo "No changes have been made to /etc/projects and /etc/projid"
    exit 1
fi

# Remove the user's home project from /etc/projects and /etc/projid
sed -i "/^$PROJNAME:/d" /etc/projid
sed -i "/^$PROJID:/d" /etc/projects

# Verify that any reference to the project quota has actually been removed
if !(xfs_quota -x -c "report -ph" /home | grep -q "$PROJNAME"); then
    echo "INFO: Project quota for project $PROJNAME successfully removed."
else
    echo "ERROR: Project quota for project $PROJNAME still present (see below). Something went wrong."
    xfs_quota -x -c "report -ph" /home | grep "$PROJNAME"
    exit 1
fi
