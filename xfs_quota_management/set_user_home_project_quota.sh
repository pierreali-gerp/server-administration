#!/bin/bash
set -e

# This script sets the project quota for the home folder of a specific user on an XFS filesystem.
# We assume that the XFS filesystem is already mounted with project quota support enabled.
# The user must've already been created, and their home directory is assumed to be /home/<username>.
# If the home directory does not exist (i.e., the user has never logged in after its creation),
# the script will create it and assign the appropriate ownership and permissions, as expected for a
# typical home directory.

# Parse input arguments
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <username> <soft_limit> <hard_limit>"
    exit 1
fi

UNAME=$1
SOFT_LIMIT=$2
HARD_LIMIT=$3

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

# If the home directory does not exist, create it, assign proper ownership and permissions,
# copy the contents of /etc/skel into it, and add the custom line added by E4 to .bashrc
HOME_DIR="/home/$UNAME"
if [ ! -d "$HOME_DIR" ]; then
    echo "INFO: The specified user's ($UNAME) home directory $HOME_DIR does not exist. Creating it..."
    mkdir "$HOME_DIR"
    echo "INFO: Adding the content of /etc/skel to the $HOME_DIR and E4's custom line to .bashrc..."
    cp -r /etc/skel/. "$HOME_DIR"
    chown "$UNAME":"$UNAME" -R "$HOME_DIR"
    chmod 700 -R "$HOME_DIR"
    echo -e "\nmodule load amd/slurm" >> "$HOME_DIR/.bashrc"
fi

# Configure projects for xfs. If the configuration files /etc/projects and /etc/projid still do
# not exist, they will be created: in the first, we add the project ID and path; in the second,
# we associate a "project name" to the project with the specified ID. For simplicity, I use the
# user IDs as the IDs to be assigned to home directory projects.
PROJID=$(id -u $UNAME)
PROJNAME=home$UNAME
# If projects and projid files do not exist, create them (touch does not overwrite existing
# files)
touch /etc/projects
touch /etc/projid
#Verify if a project with the same ID already exists in /etc/projects or if a project with the
#same name already exists in /etc/projid, and raise an error if so
if grep -q "^$PROJID:" /etc/projects 2>/dev/null; then
    echo "ERROR: A project with ID $PROJID already exists in /etc/projects."
    exit 1
elif grep -q "^$PROJNAME:" /etc/projid 2>/dev/null; then
    echo "ERROR: A project with name $PROJNAME already exists in /etc/projid."
    exit 1
fi
# Append the user's home project configuration
echo "$PROJID:/home/$UNAME" >> /etc/projects
echo "$PROJNAME:$PROJID" >> /etc/projid

# Initialize the project quota on the filesystem where /home is located
xfs_quota -x -c "project -s $PROJNAME" /home

# Set the soft and hard limits for the user's home project
xfs_quota -x -c "limit -p bsoft=$SOFT_LIMIT bhard=$HARD_LIMIT $PROJNAME" /home

# Print the current user's home project quota for verification
echo "INFO: The following project quota has been successfully set for project $PROJNAME:"
sudo xfs_quota -x -c "report -ph" /home | grep "$PROJNAME"

