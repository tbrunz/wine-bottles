# #! /usr/bin/env bash
#
# Launch or edit the environment of a Myst game. 
# 
# This script version supports using disk images for wine bottles.
# If the corresponding wine bottle is not mounted, it will be mounted. 
# A mounted wine bottle can be unmounted by including the '-u' switch. 
#
# usage: myst [ o | m | r | e | 1 | 2 | 3 | 4 | 5 ] [ -d | -u | -m ] [ <wine command> ] 
#
SCRIPT_NAME=$( basename ${0} )

SetupErr() {
    echo "${SCRIPT_NAME}: ${1} ! "
    exit 1
}

Mount_Image() {
    # 
    # If it's already mounted, note that and move on:
    #
    if [[ -x "${WINE_MOUNT}" ]]; then
        echo "${SCRIPT_NAME}: '${BOTTLE_NAME}' is already mounted. "
        return
    fi
    
    # See if we can find the IMG file to mount:
    #
    [[ -r "${IMG_FILE}" ]] || \
        SetupErr "Wine Bottle not mounted; cannot find IMG file '${IMG_FILE}'"

    # IMG file is present -- attempt to loop-mount it:
    #
    LOOP_DEV=$( udisksctl loop-setup -o 1048576 -f "${IMG_FILE}" )
    
    # If loop-mounting fails, we can't continue:
    #    
    (( $? == 0 )) && return
    
    SetupErr "Cannot set up IMG file '${IMG_FILE}' for mounting"
}

Unmount_Image() {
    #
    # It's gotta be mounted in order to umount it...
    #
    [[ -x "${WINE_MOUNT}" ]] || SetupErr "'${BOTTLE_NAME}' is not mounted"
    
    # It's mounted, but we need to know what loop device it's using:
    #
    LOOP_DEV=$( /sbin/losetup -j "${IMG_FILE}" | grep -o '/dev/loop.' )
    
    (( $? == 0 )) || SetupErr "Cannot resolve IMG file loop device"
    
    # This unmount also discards the loop device for us -- no 'sudo' required:
    #
    udisksctl unmount -b ${LOOP_DEV} 
    return $?
}

#
# First argument should be the game to play...
# 
INPUT=${1}
shift

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
# Translate user's INPUT to a game index, if possible:
#
GAME=${INPUT,,}

case ${GAME:0:2} in 
"re" )
    case ${GAME:0:3} in 
    "rev" )
        GAME=4
        ;;
    "rea" )
        GAME=1
        ;;
    esac
    ;;
"my" )
    GAME=1
    ;;
"ri" )
    GAME=2
    ;;
"ex" )
    GAME=3
    ;;
"en" )
    GAME=5
    ;;
"ur" )
    GAME=6
    ;;
esac

#
# Set the game-specific parameters:
# 
COMMON_PATH='C:\users\Public\Start Menu\Programs\'

case ${GAME:0:1} in 
'o')
    BOTTLE=myst
    BOTTLE_NAME=MYST_ME
    LAUNCH_ENV="taskset -c 1 env"
    APP_PATH=${COMMON_PATH}'Ubi Soft\Myst Masterpiece Edition\'
    MENU_PATH=${APP_PATH}'Myst Masterpiece Edition.lnk'
    ;;
'0')
    BOTTLE=realmyst
    BOTTLE_NAME=REAL_MYST
    LAUNCH_ENV="taskset -c 1 env"
    APP_PATH=${COMMON_PATH}'realMYST\'
    MENU_PATH=${APP_PATH}'realMYST Interactive 3D Edition.lnk'
    ;;
'1' | 'm' )
    BOTTLE=realmyst-me
    BOTTLE_NAME=MYST_REALMYST
    LAUNCH_ENV="env"
    APP_PATH=${COMMON_PATH}'GOG.com\realMYST Masterpiece Edition\'
    MENU_PATH=${APP_PATH}'realMYST Masterpiece Edition.lnk'
    ;;
'2' )
    BOTTLE=riven
    BOTTLE_NAME=MYST_RIVEN
    LAUNCH_ENV="taskset -c 1 env"
    APP_PATH=${COMMON_PATH}'GOG.com/Riven - The Sequel to Myst\'
    MENU_PATH=${APP_PATH}'Riven - The Sequel to Myst.lnk'
    ;;
'3' )
    BOTTLE=exile
    BOTTLE_NAME=MYST_EXILE
    LAUNCH_ENV="env"
    APP_PATH=${COMMON_PATH}'Ubi Soft\Myst III Exile\'
    MENU_PATH=${APP_PATH}'Myst III Exile.lnk'
    ;;
'4' )
    BOTTLE=revelation
    BOTTLE_NAME=MYST_REVELATION
    LAUNCH_ENV="env"
    APP_PATH=${COMMON_PATH}'UBISOFT\Myst IV - Revelation\'
    MENU_PATH=${APP_PATH}'Myst IV - Revelation.lnk'
    ;;
'5' )
    BOTTLE=endofages
    BOTTLE_NAME=MYST_ENDOFAGES
    LAUNCH_ENV="env"
    APP_PATH=${COMMON_PATH}'GOG.com\Myst V End Of Ages\'
    MENU_PATH=${APP_PATH}'Myst V End Of Ages.lnk'
    ;;
'6' | 'u' )
    BOTTLE=uru-cc
    BOTTLE_NAME=MYST_URU_CC
    LAUNCH_ENV="env"
    APP_PATH=${COMMON_PATH}'GOG.com\Myst Uru Complete Chronicles\'
    MENU_PATH=${APP_PATH}'Myst Uru Complete Chronicles.lnk'
    ;;
*)
    SetupErr "Unknown Myst version, '${INPUT}'"
    ;;
esac;


#
# Determine the IMG file mount point & check to see if it's mounted:
#
WINE_MOUNT=/media/$( whoami )/${BOTTLE_NAME}

#
# Determine the name of the IMG file to mount/unmount:
#
IMG_FILE="wine-myst-${BOTTLE}-maint.img"

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
if [[ ! -x "${WINE_MOUNT}" ]]; then 
    #
    # Mount, then wait for the mount to complete before accessing:
    #
    Mount_Image
    sleep 1
fi

# 
# Assemble the Wine Prefix:
#
WINE_PREFIX=${WINE_MOUNT}/"wine-"${BOTTLE}

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


