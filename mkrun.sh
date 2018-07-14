#! /usr/bin/env bash 
#
# Embed a bash script in the first 1 MiB of an image file
# 
# This script merges a "run" script with a disk image file, which can 
# then be mounted, unmounted, or mounted with a 'launch' script executed.
#
# Two arguments are required: A script and an image file.
#
MOUNT_OFFSET=1048576

METER_THRESH=500000000

THIS_SCRIPT=$( basename ${0} )

# Quick check on the arguments..  We have to have exactly two:
#
if (( $# != 2 )); then 

    echo >&2 "usage: ${THIS_SCRIPT} <script file> <image file> "
    exit 2
fi


###############################################################################
#
# Print an error message and abort with a non-zero return code
#
SetupErr() {
    echo >&2 "${THIS_SCRIPT}: ${1} "
    exit 1
}


###############################################################################
# 
# To prevent disaster, we'll need to check both files to be sure 
# they're the file types they're supposed to be...
#
SCRIPT_FILE=${1}
IMAGE_FILE=${2}

TARGET_SIZE=$( stat -c %s "${IMAGE_FILE}" )
TARGET_FILE=$( basename "${IMAGE_FILE}" ".img" )".sh"

unset METERING
(( TARGET_SIZE > METER_THRESH )) && METERING=true


#
# Start with analyzing the script file -- If legit, it will have a header:
#
read -r SCR_COMMENT  SCR_INVOKE  SCR_INTERP < ${SCRIPT_FILE}

[[ "${SCR_COMMENT}" != "#!"           || \
    "${SCR_INVOKE}" != "/usr/bin/env" || \
    "${SCR_INTERP}" != "bash"            ]] || SetupErr \
            "${THIS_SCRIPT}: '${SCRIPT_FILE}' must be a bash script file !"

echo >&2 "Script file '${SCRIPT_FILE}' appears valid... "
sleep 2

###############################################################################
#
# The only way to be sure about the image file is to actually mount it:
#
RESULT=$( udisksctl loop-setup -o ${MOUNT_OFFSET} -f "${IMAGE_FILE}" )
#    
(( $? == 0 )) || SetupErr \
    "${THIS_SCRIPT}: Can't mount '${IMAGE_FILE}' - Is this a disk image file ?"
    
LOOP_DEV=$( printf "%s" "${RESULT}" | grep -o '/dev/loop.' )

#
# If loop-mounting fails, then the file is probably not valid:
#    
[[ -n "${LOOP_DEV}" ]] || SetupErr \
        "${THIS_SCRIPT}: Cannot determine loop device for '${IMAGE_FILE}' !"

#
# If loop-mounting succeeds, then immediately un-mount it & continue:
#
sleep 2
RESULT=$( udisksctl unmount -b "${LOOP_DEV}" )

#
# If unmounting fails, then we cannot continue:
#  
(( $? == 0 )) || echo >&2 \
        "${THIS_SCRIPT}: Error unmounting '${IMAGE_FILE}' ! "

echo >&2 "Image file '${IMAGE_FILE}' appears valid... "
sleep 2


###############################################################################
#
# Make a temporary file to pad out the script file; 
# It need not be any larger than 1 MiB, as that's the max script size.
#
PADDING_FILE=$( mktemp )

(( $? == 0 )) || SetupErr \
        "Cannot create a temp file for padding the script file !"

dd 2>/dev/null if=/dev/zero of="${PADDING_FILE}" \
        bs=${MOUNT_OFFSET} count=1 && sync

(( $? == 0 )) || SetupErr \
        "Failure creating the zero-padding file !"

# 
# Make another temp file to hold the padded script file, which will be > 1 MiB:
#
OVER_PADDED_SCRIPT=$( mktemp )

(( $? == 0 )) || SetupErr \
        "Cannot create a temp file to hold the padded script file !"

cat "${SCRIPT_FILE}" "${PADDING_FILE}" > "${OVER_PADDED_SCRIPT}" && sync

(( $? == 0 )) || SetupErr \
        "Failed to zero-pad the script file !"

#
# Re-use the first temp file to hold the padded script, now 1 MiB in size:
#
PADDED_SCRIPT=${PADDING_FILE}

dd 2>/dev/null if="${OVER_PADDED_SCRIPT}" of="${PADDED_SCRIPT}" \
        bs=${MOUNT_OFFSET} count=1 && sync

(( $? == 0 )) || SetupErr \
        "Failed to create the zero-padded script file !"


#
# Re-use the second temp file to hold the clipped image file:
#
CLIPPED_IMAGE_FILE=${OVER_PADDED_SCRIPT}

if [[ ${METERING} ]]; then
    echo >&2 "Creating target file ... "

    dd if="${IMAGE_FILE}" of="${CLIPPED_IMAGE_FILE}" \
            bs=${MOUNT_OFFSET} skip=1 status=progress && sync
else
    dd &>/dev/null if="${IMAGE_FILE}" of="${CLIPPED_IMAGE_FILE}" \
            bs=${MOUNT_OFFSET} skip=1 && sync
fi

(( $? == 0 )) || SetupErr \
        "Failed to clip the leading 1 MiB from the image file !"

#
# Now combine the padded script with the clipped image file:
#
if [[ ${METERING} && $( which pv >/dev/null ) ]]; then

    pv "${PADDED_SCRIPT}" "${CLIPPED_IMAGE_FILE}" \
            > "${TARGET_FILE}" && sync
else
    cat "${PADDED_SCRIPT}" "${CLIPPED_IMAGE_FILE}" \
            > "${TARGET_FILE}" && sync
fi

(( $? == 0 )) || SetupErr \
        "Failed to write out the combined script-image file !"


###############################################################################
#
# Remove the temp files that are no longer needed:
#
rm "${PADDED_SCRIPT}"

(( $? == 0 )) || echo >&2 "Failed to delete temp file '${PADDED_SCRIPT}' !"

rm "${CLIPPED_IMAGE_FILE}"

(( $? == 0 )) || echo >&2 "Failed to delete temp file '${CLIPPED_IMAGE_FILE}' !"

#
# Finish up by renaming and changing the mode of the image file:
#
chmod +x "${TARGET_FILE}"

echo >&2 "Completed; file '${TARGET_FILE}' should be executable. "


###############################################################################


