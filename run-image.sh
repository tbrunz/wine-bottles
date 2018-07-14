# #! /usr/bin/env bash
#
# Mount, unmount, or launch a script in an image file
# 
# This script file contains a disk partition image, which can be
# mounted, unmounted, or mounted with a 'launch' script executed.
#

###############################################################################
#
# Image file environment variables
#
# The script name is also the image file name, since the script is 
# embedded in the first 1MiB of the disk image file.
#
SCRIPT_NAME=$( basename "${0}" )

IMAGE_SCRIPT="app-launch.sh"

MOUNT_OFFSET=1048576

#
# Assume there's an argument and that it's a switch..
#
SWITCH=${1}

#
# If the switch is 'help', then show the usage prompt:
# 
if [[ "${SWITCH}" == "-h" ]]; then

    echo >&2 "usage: ${SCRIPT_NAME} [ -m | -u | <command> ] "
    exit 2
fi 


###############################################################################
#
# Print an error message and abort with a non-zero return code
#
SetupErr() {
    echo >&2 "${SCRIPT_NAME}: ${1} ! "
    exit 1
}


###############################################################################
#
# Check the argument to determine if it's a mount/unmount switch 
#
# $1 = The argument passed to this script
#
Check_Mount_Switch() {
    #
    # Set a global variable to communicate the mounting action. 
    # It's possible that no mount/unmount switch is specified,  
    # leading to three states: unset, 'mount', or 'umount'.
    #    
    local SWITCH_ARG

    if [[ -n "${1}" ]]; then
        # 
        # Reduce the switch argument to lower case & get the first two chars.
        #
        SWITCH_ARG=${1,,}
        
        case ${SWITCH_ARG:0:2} in
        
        '-m' )
            MOUNT_ACTION="mount"
            ;;
        '-u' )
            MOUNT_ACTION="unmount"
            ;;
        * )
            unset MOUNT_ACTION
        esac
    fi
}


###############################################################################
#
# Create a 'here-doc' script to exec to that will unmount this image file.
# 
# This is needed to prevent a syserr that would occur if we tried to do this 
# directly from this script -- because this file is the mounted file, and 
# while this script is executing, the file is 'busy', hence the mount is, too.
#
Exec_Unmount_Script() {
    
    local TMP_FILE
    
    # Ask the operating system to make us a temporary file (will be u+rw):
    #
    TMP_FILE=$( mktemp )
    
    (( $? == 0 )) || SetupErr \
            "Cannot create a temp file to serve as a helper script"
    
    # Fill the temp file with script code that will pause as this script 
    # completes and is no longer 'busy', then performs the unmounting. 
    # 
    cat > "${TMP_FILE}" << EOF
    
        #! /usr/bin/env bash
        #
        sleep 1
        
        # Use 'udisksctl' to tear down, as it does not require 'sudo'.
        #
        udisksctl loop-delete -b "${LOOP_DEV}"
        
EOF

    # Verify that the here-document copied correctly to the temp file:
    #
    (( $? == 0 )) || SetupErr \
            "Cannot create a helper script to unmount '${SCRIPT_NAME}'"

    # Now set the mode of the script to make it executable, then xfer to it:
    #
    chmod 750 "${TMP_FILE}" && "${TMP_FILE}" &
    exit
}


###############################################################################
#
# Determine the mount point, if it exists, of the image file 
#
# Return 
#   0 = Bound, mounted, and resolved as MOUNT_PATH & VOLUME_LABEL
#   1 = Bound to a loop device, but not mounted
#   2 = Not bound to a loop device (and obviously not mounted)
#   3 = Error
#
Find_Mount_Point() {
    # 
    # If our script/image file shows up in the loop devices list, then 
    # extract the loop device path from the matching output of 'losetup'.
    # 
    #   'losetup -a' output (multi-line): 
    # 
    # /dev/loopX: []: (<file path>), offset <offset in bytes>
    #
    LOOP_DEV=$( losetup -a | grep "${SCRIPT_NAME}" | egrep -o '^[^:]+' )
    
    # Unfortunately, the above does not include mount information. 
    #
    # If no loop device is bound to our script/image file, return 'fail':
    #
    [[ -n "${LOOP_DEV}" ]] || return 2
    
    # The loop device exists, so use 'df' to see if it's mounted. 
    # 
    #   'df' output (multi-line):
    #
    # /dev/loopX  <size>  <used>  <avail>  <nn>%  <mount point>
    #
    VOLUME_LABEL=
    MOUNT_PATH=$( df | grep "${LOOP_DEV}" | awk '{ print $6 }' )
    
    # If the mount path fails to resolve, return an error code; 
    # If this occurs, both MOUNT_PATH and VOLUME_LABEL will be blank. 
    #    
    [[ -n "${MOUNT_PATH}" ]] || return 1
    
    # Everything after the (lone) '%' char is the mount path; 
    # The base name of this path is the volume label:
    #
    VOLUME_LABEL=$( basename "${MOUNT_PATH}" )
    
    [[ -n "${VOLUME_LABEL}" ]] || return 3
}


###############################################################################
#
# Determine if the image file is mounted, and mount it if it's not
#
# $1 = If '-q', and the image file is mounted, then return quietly; 
#      else output an 'already mounted' message & exit the script. 
#
Mount_Image() {
    # 
    # Attempt to resolve a mount point:
    #
    Find_Mount_Point
    
    # Then handle the possible results:
    #
    case $? in
    
    1 ) # Bound to a loop device, but not mounted. 
        # Use 'udisksctl' to mount, as it does not require 'sudo' 
        # elevation, and it will auto-create a mount directory:  
        #
        udisksctl mount -b "${LOOP_DEV}"

        # If the mount fails, we can't continue:
        #    
        (( $? == 0 )) || exit 1
        
        # But if successful, we still need the mount point:
        #
        Find_Mount_Point

        # If we still can't resolve a mount point, we can't continue:
        # 
        (( $? == 0 )) || SetupErr \
                "${SCRIPT_NAME} is bound to '${LOOP_DEV}', but won't mount"
        ;;
        
    2 ) # Not bound to a loop device; Attempt to loop-mount the image file.
        # Use 'udisksctl' so that we don't have to have 'sudo' privileges.
        #
        RESULT=$( udisksctl loop-setup -o ${MOUNT_OFFSET} -f "${SCRIPT_NAME}" )
        
        # If loop-mounting fails, then we cannot continue:
        #    
        (( $? == 0 )) || SetupErr \
                "Cannot bind '${SCRIPT_NAME}' to a loop device for mounting"
        
        # If it succeeds, it should be bound & mounted; get the loop device:
        #
        LOOP_DEV=$( printf "%s" "${RESULT}" | grep -o '/dev/loop.' )
        
        [[ -n "${LOOP_DEV}" ]] || SetupErr \
                "Cannot determine the loop device bound to '${SCRIPT_NAME}'"
        
        # Now that we have a valid loop device, get the mount point:
        #
        sleep 2
        Find_Mount_Point

        # If we can't resolve the mount point, we can't continue:
        #    
        (( $? == 0 )) || SetupErr \
                "Cannot determine the mount point for '${LOOP_DEV}'"
        ;;
        
    3 ) # Unknown system call error occurred...
        #
        SetupErr "Cannot determine a mount point for '${SCRIPT_NAME}'"
        ;;
    esac   
    
    # At this point, we have a resolved mount point for the image file; 
    # If the 'quiet' switch was given, then quietly return:
    # 
    [[ "${1}" == "-q" ]] && return
    
    # Otherwise, echo an 'already mounted' message & exit successfully:
    #
    echo >&2 "${SCRIPT_NAME}: Mounted as '${MOUNT_PATH}'. "
    exit
}


###############################################################################
#
# Determine if the image file is mounted, and unmount it if it is
#
Unmount_Image() {
    #
    # Check to see if the script/image file is already mounted:
    #
    Find_Mount_Point
    
    # Then handle the possible results:
    #
    case $? in
        
    0 ) # We're bound to a loop device and mounted.
        # We need to exec to another script to unmount, 
        # otherwise our own execution will block umounting. 
        #
        Exec_Unmount_Script
        ;;
    
    1 ) # We're bound to a loop device, but not mounted. 
        # Use 'udisksctl' to tear down, as it does not require 'sudo'.
        #
        udisksctl loop-delete -b "${LOOP_DEV}"
        ;;
        
    2 ) # Echo an 'already unmounted' message & exit successfully:
        #
        echo >&2 "${SCRIPT_NAME}: Not mounted "
        ;;
        
    3 ) # Unknown system call error occurred...
        #
        SetupErr "Cannot determine a mount point for '${SCRIPT_NAME}'"
        ;;
    
    esac
    
    exit $?
}


###############################################################################
#
# Check for an argument instructing us to mount/umount the image file:
#
Check_Mount_Switch "${1}"

#
# Are we to mount the IMG file?  If explicitly commanded to, 
# then do only that (echoing results to the console), and exit:
#
[[ "${MOUNT_ACTION}" == "mount" ]] && Mount_Image

#
# Are we to unmount the IMG file?  If so, umount & exit:
#
[[ "${MOUNT_ACTION}" == "unmount" ]] && Unmount_Image

#
# Check to see if the IMG file is mounted; mount it if not (quietly):
#
Mount_Image -q

# If the 'quiet' version of the above returns, it succeeded...
# Wait a second for the OS to complete the mounting process:
# 
sleep 3

#
# Pass all the arguments to the script in the partition image:
#
if [[ ! -r "${MOUNT_PATH}"/"${IMAGE_SCRIPT}" ]]; then 
    
    echo >&2 -n "${SCRIPT_NAME}: "
    echo >&2    "Cannot find a script '${IMAGE_SCRIPT}' in ${MOUNT_PATH} "
    exit
fi

#
# We've detected the expected launch script in the mounted image -- run it:
#
exec "${MOUNT_PATH}"/"${IMAGE_SCRIPT}" "$@"

#
# We MUST end the script explicitly, as the partition image follows!!
#
exit $?

###############################################################################


