#! /usr/bin/env bash
#
# Launch or edit the environment of a Myst game. 
# 
# This script version supports using disk images for wine bottles.
# If the corresponding wine bottle is not mounted, it will be mounted. 
# A mounted wine bottle can be unmounted by including the '-u' switch. 
#
# usage: myst-<game-name> [ -d | -u | -m ] [ <wine command> ] 
#

###############################################################################
#
# Wine Bottle-specific environment variable values.
#
# The MOUNT_NAME is the partition label, which Linux will use to name 
# the directory it creates when it mounts the image file.   
# This name is set when the bottle's disk image is created.
#
MOUNT_NAME="MYST_URU_CC"

MOUNT_DIR_PATH=/media/$(whoami)/${MOUNT_NAME}

PREFIX_DIR_NAME="wine-uru-cc"

WINE_PREFIX=${MOUNT_DIR_PATH}/${PREFIX_DIR_NAME}

LAUNCH_ENV="env"

START_MENU_PATH='C:\users\Public\Start Menu\Programs'
APP_MENU_PATH=${START_MENU_PATH}'\GOG.com\Myst Uru Complete Chronicles'
MENU_PATH=${APP_MENU_PATH}'\Myst Uru Complete Chronicles.lnk'

#
# The script name is also the wine-bottle file name, since the script is 
# embedded in the first 1MiB of the bottle disk image file.
#
SCRIPT_NAME=$( basename "${0}" )


###############################################################################
#
# Print an error message and abort with a non-zero return code.
#
SetupErr() {
    echo >&2 "${SCRIPT_NAME}: ${1} ! "
    exit 1
}

#
# No (non-switch) arguments -> Nothing to do
# 
if [[ -z "${INPUT}" || "${INPUT:0:1}" == '-' ]]; then

    echo "usage: ${FUNCNAME} <game name | # > [ -d | -u ] [ <wine command> ] "
    exit 2
fi 

#
# Start with the assumption that there are no other arguments, 
# and that all Wine debug output will be suppressed: 
#
DEBUG_CMD="WINEDEBUG=-all"
IMAGE_MOUNTING=

#
# Any additional arguments imply '-d'; 
# This includes '-d' itself, which, if present, needs to be removed: 
#
if [[ -n "${1}" ]]; then
    # 
    # Reduce the next argument to lower case & get the first two chars.
    # Note that since we're to erase DEBUG_CMD, it's a free variable here:
    #
    DEBUG_CMD=${1,,}
    DEBUG_CMD=${DEBUG_CMD:0:2}
    
    # Check for an explicit 'debug' switch:
    #
    [[ "${DEBUG_CMD}" == '-d' ]] && shift
    
    # An 'mount' switch takes precedence over 'debug':
    #
    [[ "${DEBUG_CMD}" == '-m' ]] && IMAGE_MOUNTING="mount"
    
    # An 'unmount' switch takes precedence over all:
    #
    [[ "${DEBUG_CMD}" == '-u' ]] && IMAGE_MOUNTING="unmount"
    
    # Since '-d' was implied or expressed, do NOT turn off Wine debug:
    #
    DEBUG_CMD=""
fi

#
# Are we to unmount the IMG file?
#
if [[ "${IMAGE_MOUNTING}" == "unmount" ]]; then  
    # 
    # If instructed explicitly to 'unmount', then it's do & die:
    #    
    Unmount_Image
    exit $?
fi

#
# Are we to mount the IMG file (and do nothing else)?
#
if [[ "${IMAGE_MOUNTING}" == "mount" ]]; then 
    # 
    # If instructed explicitly to 'mount', then it's do & die:
    #    
    Mount_Image
    exit $?
fi

#
# Check to see if the IMG file is mounted; mount it if not:
#
if [[ ! -x "${MOUNT_DIR_PATH}" ]]; then 
    #
    # Mount, then wait for the mount to complete before accessing:
    #
    Mount_Image
    sleep 1
fi

#
# Is everything in place?
#
[[ -x "${WINE_PREFIX}/drive_c" ]] || \
        SetupErr "Cannot find Wine Bottle '${WINE_PREFIX}'"

#
# Determine what to do: Run the game or run a wine command on its bottle:
#
if [[ -n "${1}" ]]; then

    ${LAUNCH_ENV} WINEARCH=win32 WINEPREFIX=${WINE_PREFIX} "$@"
else

    ${LAUNCH_ENV} ${DEBUG_CMD} WINEPREFIX=${WINE_PREFIX} wine start "${MENU_PATH}"
fi


