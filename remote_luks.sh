#!/bin/bash
##################################################################################################################119:#
# remote_luks.sh - copy(l)eft 2020 http://harald.ist.org/
##################################################################################################################119:#
# WHAT DOES IT DO?
# Backup your data in an encrypted container on a cloud server you don't trust
# A directory from the server will be mounted using SSHFS
# A LUKS container from that mount will contain an encrypted virtual file system
# Your data will be backed up into this file system
# This way, the administrators of the server can not access your data
##################################################################################################################119:#
# HOW TO USE
# Read all the options in the section "Preferences" below and adjust them to your needs.
# Make sure, you have access to the server via ssh
# To connect without entering a password all the time, set up an ssh key:
#	$ ssh-keygen
#	$ ssh-copy-id <server-address>
# Create a folder that will contain your image(s)
#	$ ssh user@server
#	$ mkdir remote_luks
#	$ logout
# Create an image file on the remote server and format it:
#	$ remote_luks.sh create
# Back up your data:
#	$ remote_luks.sh backup
##################################################################################################################119:#
# TODO
# [ ] Confirm overwriting key
# [ ] Confirm overwriting image
# [ ] Implement incremental backup
##################################################################################################################119:#


##################################################################################################################119:#
#
#  Preferences - ADJUST THESE SETTINGS BEFORE USING THIS SCRIPT!
#
##################################################################################################################119:#
# To ENABLE a setting, remove the "#" from the beginning of the line

#############################
### MISCELLANEOUS OPTIONS ###
#############################
# DISABLE to get output without colors
use_ansi_colors=true

# DISABLE to get rid of the warning that this script may be inefficient
show_noob_warning=true

# DISABLE status summary
always_show_status=true

# DISABLE to make the script be silent
#confirm_every_command=false

# How I will format command confirmations
cap_indent="\e[28G"
#cap_indent="\n"


###############################
### SSHFS and LUKS SETTINGS ###
###############################
# How large to make the file system when creating a new LUKS image file
# Valid entries are 123K (kilobytes) 123M (megabytes) 123G (gigabytes)
# Sizes are base 10 (1K = 1000 bytes)
image_size="10M"

# Name of the image file (.luks.img will be appended)
image_prefix="my_secure_remote"

# Name to mount the LUKS container as (May show on your Desktop)
volume_name="RemoteLUKS"

# Where I should put my temporary files and mount points
working_dir="/home/$USER/remote_luks"

# How I will connect to the server with sshfs
# Example: Login using alternate port number:
#	remote_directory="-p 12345 user@server:/home/username/remote_luks_images/"
remote_directory="user@server:/home/username/remote_luks/"

# Which file to use to lock/unlock the LUKS container
# ENABLE, if you want to use your own existing key file
# DISABLE, if you want to have a new key file generated, when creating a new LUKS image
#user_key_file="/path/to/my_keyfile.dat"


####################
### RSYNC BACKUP ###
####################
# Select directory to sync to the encrypted file system (Your data to be backed up)
# Add a "/" to the end, if you want to backup only the contents of the folder
rsync_this="/this/directory/"

# Select mode of operation for rsync
# Example: rsync_options="-avxHAWX --info=progress2 --delete"
rsync_options="-avxHAWX --info=progress2 --delete"

# Select files to be excluded using --exclude
#
# Names are matched against the root of the source directory.
# Assuming we backup /data/test and want to exclude:
#	Any file starting with "dir"	rsync_exclude=dir
#	Specifically /data/test/dir 	rsync_exclude=/dir
#	Files in dir, but copy dir	rsync_exclude=/dir/*
#	Files containing white space	rsync_exclude="'dir with space'"
# Multiple filters can be set like so:
# 	rsync_exclude={filter1,"filter2 with white space"}
rsync_exclude="lost+found"


#########################
### I AM UNCONFIGURED ###
#########################
# ENABLE to make the protection go away
#i_am_configured=true


##################################################################################################################119:#
# Internal Variables
##################################################################################################################119:#

sshfs_mount_point="${working_dir}/mnt/sshfs"
image_mount_point="${working_dir}/mnt/image"
image_file_name="${image_prefix}.luks.img"
image_file="${sshfs_mount_point}/${image_file_name}"
loop_device_file="${working_dir}/loop_device_name"
rsync_source="$rsync_this"
rsync_target="$image_mount_point"

if [ "$rsync_exclude" != "" ] ; then
	rsync_exclude=" --exclude ${rsync_exclude}"
fi

color_red="\e[1;31m"
color_green="\e[1;32m"
color_yellow="\e[1;33m"
color_bright="\e[1;37m"
color_normal="\e[0;37m"

exit_unconfigured=-1
exit_not_connected=2
exit_uncrecognized_option=3

if [ "$use_my_own_key_file" == "true" ] ; then
	key_file=$user_key_file
else
	key_file="${working_dir}/key_file.dont_loose_me"
fi


if [ -f $loop_device_file ] ; then
	loop_device="$(cat ${loop_device_file})"
fi


##################################################################################################################119:#
# Confirm command before executing
##################################################################################################################119:#
function run_cmd () {
	caption=$1
	command=$2
	if [ "$confirm_every_command" != "false" ] ; then
		if [ "$caption" != "" ] ; then
			echo -en "${color_yellow}> ${color_bright}${caption}"
			if [ "$command" == "" ] ; then
				echo
			else
				echo -en "${cap_indent}\e[0;37m\$ ${color_yellow}${command}\e[0;37m ?"
				read
			fi
		fi
	fi
	eval $command
}


##################################################################################################################119:#
# Individual Operations
##################################################################################################################119:#
function create_loop_device () {
	run_cmd "Find free loop device" "loop_device=$(losetup -f)"
	run_cmd "Create loop device" "losetup ${loop_device} ${image_file}"
	run_cmd "Remember loop device" "echo '${loop_device}' > ${loop_device_file}"
}
function mount_remote_directory () {
	if [ ! -d $sshfs_mount_point ] ; then
		run_cmd "Create sshfs mount point" "mkdir -v -p ${sshfs_mount_point}"
	fi
	run_cmd "Mount remote dir" "sshfs -v ${remote_directory} ${sshfs_mount_point}"
}
function open_image () {
	run_cmd "Unlock/open image" "sudo cryptsetup luksOpen ${loop_device} ${volume_name} --key-file ${key_file}"
}
function mount_fs () {
	if [ ! -d $image_mount_point ] ; then
		run_cmd "Create image mount point" "mkdir -p ${image_mount_point}"
	fi
	run_cmd "Mount file system" "sudo mount /dev/mapper/${volume_name} ${image_mount_point}"
}
function backup () {
	run_cmd "Backup data" "rsync ${rsync_options}${rsync_exclude} ${rsync_source} ${rsync_target}"
}
function umount_fs () {
	run_cmd "Unmount file system" "sudo umount ${image_mount_point}"
}
function close_image () {
	run_cmd "Close LUKS container" "sudo cryptsetup luksClose ${volume_name}"
}
function umount_remote_directory () {
	run_cmd "Unmount remote directory" "fusermount -u ${sshfs_mount_point}"
}
function remove_loop_device () {
	run_cmd "Remove loop device" "losetup --detach ${loop_device}"
	run_cmd "Forget loop device" "rm ${loop_device_file}"
	loop_device=""
}
function remove_all_loop_devices () {
	run_cmd "Remove all loop devices" "losetup --detach-all"
	run_cmd "Unlink" "rm ${loop_device_file}"
}
function create_key_file () {
	if [ "$user_key_file" == "" ] ; then
		if [ -f "$key_file" ] ; then
			run_cmd "Key file already existing."
			echo "Remove ${key_file}, if you want me to create a new key"
		else
			echo -e "\e[1;31mWARNING${color_bright}: This may overwrite your existing key file!${color_normal}"
			run_cmd "Create key file" "dd if=/dev/urandom of=$key_file bs=1024 count=1"
		fi
	fi
}
function create_image () {
	result=$(mount | grep $sshfs_mount_point)
	if [ "$result" == "" ] ; then
		echo "Error: Image file $image_file not found."
		echo 'You need to connect first (-c)'
		exit $exit_not_connected
	fi


	create_key_file
	echo -e "\e[1;31mWARNING${color_bright}: This may overwrite your LUKS container!${color_normal}"
	run_cmd "Create container" "dd if=/dev/zero of=${image_file} bs=1 count=0 seek=${image_size}"
	create_loop_device
	run_cmd "Format image" "sudo cryptsetup luksFormat `echo \${loop_device}` ${volume_name} --key-file=${key_file}"
	open_image
	run_cmd "Format FS" "sudo mkfs.ext4 -L ${volume_name} /dev/mapper/${volume_name}"
	mount_fs
	run_cmd "Take ownership" "sudo chown -R ${USER} ${image_mount_point}"
}


function show_usage () {
	cat << EOF
Usage: $(basename $0) [-v | --verbose] [create | open | close | backup]
EOF
}

##################################################################################################################119:#
# Program Entry Point
##################################################################################################################119:#
if [ "$i_am_configured" != "true" ] ; then
	echo "I AM UNCONFIGURED - See section 'Preferences' in $0"
	exit $exit_unconfigured
fi

# Make sure, we can use LUKS
modprobe dm-crypt
if [ "$?" != "0" ] ; then exit ; fi
modprobe dm-mod
if [ "$?" != "0" ] ; then exit ; fi


if [ "$1" == "-v" ] || [ "$1" == "--verbose" ] ; then
	confirm_every_command=true
	shift
fi

case "$1" in
	open)
		mount_remote_directory
		create_loop_device
		open_image
		mount_fs
		;;
	close)
		umount_fs
		close_image
		remove_loop_device
		umount_remote_directory
		;;
	create)
		mount_remote_directory

		create_image

		umount_fs
		close_image
		remove_loop_device
		umount_remote_directory
		;;
	backup)
		mount_remote_directory
		create_loop_device
		open_image
		mount_fs

		backup

		umount_fs
		close_image
		remove_loop_device
		umount_remote_directory
		;;
	\-l | \-\-create\-loop)
		create_loop_device
		;;
	\-s | \-\-connect)
		mount_remote_directory
		;;
	\-o | \-\-open)
		create_loop_device
		open_image
		;;
	\-m | \-\-mount)
		mount_fs
		;;
	\-b | \-\-rsync)
		backup
		;;
	\-u | \-\-umount)
		umount_fs
		;;
	\-c | \-\-close)
		close_image
		;;
	\-d | \-\-disconnect)
		umount_remote_directory
		;;
	\-r | \-\-remove\-loop)
		remove_loop_device
		;;
	\-D)
		remove_all_loop_devices
		;;
	\-x | \-\-create-image)
		create_image
		;;
	\-k | \-\-create-key)
		create_key_file
		;;
	'')
		show_usage
		;;
	\-h | \-\-help)
		echo -en "${color_green}$(basename $0)${color_normal} - "
		echo -e "${color_bright}Manage remote LUKS file system containers via sshfs${color_yellow}"
		if [ "$show_noob_warning" == "true" ] ; then
		cat << EOF

> WARNING: This whole script may be inefficient.
> I also have no idea, what I am doing.
> Use this script at your own risk.

EOF
		fi
		echo -en $color_normal
		show_usage
		cat << EOF

Options (only for fine control/debugging):
-l, --create-loop	Create a new loop device
-s, --connect		Mount remote directory via sshfs
-o, --open              Open LUKS container
-b, --rsync             Copy data to mounted LUKS file system
-m, --mount      	Mount LUKS file system
-u, --umount     	Unmount LUKS file system
-c, --close             Close LUKS container
-d, --disconnect	Unmount remote sshfs directory
-r, --remove-loop       Remove the loop device
-D                      Remove all unused loop devices (system wide)
-k, --create-key	Create a key file
-x, --create-image	Create remote LUKS container
-v, --verbose           Show and confirm every command before execution

Current configuration:
sshfs options		${remote_directory}
sshfs mount point	${sshfs_mount_point}/
Image file		${image_file}
LUKS FS mount point	${image_mount_point}/
Use key file            ${key_file}
EOF
		;;
	*)
		echo "Unrecognized option $1"
		exit $exit_uncrecognized_option
		;;
esac


if [ "$confirm_every_command" != "true" ] && [ "$always_show_status" != "true" ] ; then
	exit
fi
##################################################################################################################119:#
# Show Status
##################################################################################################################119:#
echo -e "\n${color_normal}Status:"

if [ "$loop_device" != "" ] ; then
	echo "Current loop device: ${loop_device}"
fi

result=$(mount | grep  $sshfs_mount_point 2>&1)
if [ "$result" == "" ] ; then
	echo "Remote directory not mounted"
	exit
else
	echo "Remote directory mounted"
fi


if [ -f $image_file ] ; then
	echo "Image file found"
fi

#result=$(lsof -w $image_file | grep -v COMMAND)
result=$(mount | grep "$remove_directory")
if [ "$result" != "" ] ; then
	echo "LUKS container mounted"
fi


#EOF
