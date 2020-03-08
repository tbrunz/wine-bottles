#! /usr/bin/env bash 
#
# Embed a bash script in the first 1 MiB of an image file
# 
# This script merges a "run" script with a disk image file, which can 
# then be mounted, unmounted, or mounted with a 'launch' script executed.
#
# Two arguments are required: A script and an image file.
#
SCRIPT_VERSION=2.0

ONE_MIB=1048576

METER_THRESH=$(( 500 * ONE_MIB ))

IMAGE_SCRATCH_SPACE=$(( 10 * ONE_MIB ))

MOUNT_OFFSET=${ONE_MIB}

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
ThrowError() {
    echo >&2 "${THIS_SCRIPT}: ${1} exiting... "
    exit 1
}


###############################################################################
#
# Determine how large an image file we'll need to hold the Wine environment.
#
# Dependencies: ${WINE_ENV}   = path to an existing directory; 
# Output:       ${IMAGE_SIZE} = sizeof ${IMAGE_FILE} in round MiB; 
#
Determine_Image_Size () {

    [[ -d "${WINE_ENV}" ]] || ThrowError \
            "Cannot read a Wine environment in '${WINE_ENV}';"
    
    # Get size, in 1K blocks, of the target Wine environment:
    #
    DU_SIZE=$( du -s "${WINE_ENV}" | cut -f 1 )
    
    # Increase this to allow for adding files to the disk image in 
    # the future, then round down to an integral number of MiB:
    #
    IMAGE_SIZE=$(( DU_SIZE * 1024 + IMAGE_SCRATCH_SPACE ))
    IMAGE_SIZE=$(( IMAGE_SIZE / ONE_MIB ))
    
    (( $? == 0 )) || ThrowError \
            "Could not determine the size of '${WINE_ENV}'!"
}


###############################################################################
#
# Create the disk image file as an empty (initialized) disk.
#
# Dependencies: ${IMAGE_FILE} = path to (non-existent) image file; 
#               ${IMAGE_SIZE} = sizeof ${IMAGE_FILE} in round MiB;
#
Make_Image_File () { 

    [[ -e "${IMAGE_FILE}" ]] && ThrowError \
            "Image file '${IMAGE_FILE}' already exists;"
    
    (( IMAGE_SIZE > 1 )) || ThrowError \
            "Image file size (${IMAGE_SIZE}) is too small;"

    # Create a zeroed-out file with size in an integral number of 1MB blocks:
    # 
    RESULT=$( dd if=/dev/zero of="${IMAGE_FILE}" iflag=fullblock bs=1M \
            count="${IMAGE_SIZE}" 2>&1 ) 
    
    (( $? == 0 )) || ThrowError \
            "Cannot create image file '${IMAGE_FILE}'!"
    sync
}


###############################################################################
#
# Format the disk image label (11 char max, no whitespace).
#
# Dependencies: ${IMAGE_LABEL} = name string; can be blank; 
#
Format_Image_Label () { 

    if [[ -n "${IMAGE_LABEL}" ]]; then
        
        # Replace all whitespace characters with (one) underscore:
        #
        IMAGE_LABEL=$( printf "%s" "${IMAGE_LABEL}" | tr -s '[:space:]' '_' )
        
        # Maximum 11 characters, truncate as necessary:
        #
        IMAGE_LABEL=${IMAGE_LABEL:0:11}
    fi
}


###############################################################################
#
# Format the disk image file as a mountable disk.
#
# Dependencies: ${IMAGE_FILE}  = path to (existing) image file; 
#               ${IMAGE_LABEL} = name string for the virtual disk; 
#               
#
Format_Image_File () { 

    [[ -w "${IMAGE_FILE}" ]] || ThrowError \
            "Cannot modify image file '${IMAGE_FILE}'!"
    
    # Create a 'mkfs' label option if the name string is not blank:
    #
    Format_Image_Label

    local LABEL_CMD=
    [[ -n "${IMAGE_LABEL}" ]] && LABEL_CMD="-L ${IMAGE_LABEL}"
    
    # Format the virtual disk image; 'mkfs' *will* format a file:
    #
    mkfs -t ext4 -q -m 1 -b 4096 -E offset=${ONE_MIB} \
            ${LABEL_CMD} "${IMAGE_FILE}"
    
    (( $? == 0 )) || ThrowError \
            "Cannot format image file '${IMAGE_FILE}'!"
}


###############################################################################
#
# Mount the disk image file using a loop device.
#
# Dependencies: ${IMAGE_FILE}  = path to a formatted virtual disk image file; 
# Output:       ${LOOP_DEV}    = "/dev/loopN", N=0..7; 
#               ${LOOP_NUMBER} = 0..7;
#
Mount_Image_File () { 

    [[ -w "${IMAGE_FILE}" ]] || ThrowError \
            "Cannot access image file '${IMAGE_FILE}' for writing!"
    
    # Mount the virtual disk image using a loop device; 'udisksctl' can 
    # conveniently do this for us without requiring the use of 'sudo':
    #
    RESULT=$( udisksctl loop-setup -o "${MOUNT_OFFSET}" -f "${IMAGE_FILE}" )
        
    (( $? == 0 )) || ThrowError \
        "Can't bind '${IMAGE_FILE}' to a loop device!"

    # Get the loop device that was created; 
    # This will be one of '/dev/loop0'..'/dev/loop7'.
    #     
    LOOP_DEV=$( printf "%s" "${RESULT}" | grep -o '/dev/loop.' )
        
    [[ -n "${LOOP_DEV}" ]] || ThrowError \
            "Cannot determine the loop device bound to '${IMAGE_FILE}' !"
    
    LOOP_NUMBER=${LOOP_DEV##*loop}
}


###############################################################################
#
# Transfer the wine environment to the disk image file. 
#
Copy_Image_File () { 

#
# If the image file is larger than the threshold, then enable metering 
# to display a progress bar for the user, since transcribing the image 
# file will take a long time for a large file.  A Windows game distributed 
# on a DVD and installed in a Wine enviroment could be nearly 5 GB in size. 
#
unset METERING
(( TARGET_SIZE > METER_THRESH )) && METERING=true

    echo "Copying '${WINE_ENV}' to '${IMAGE_FILE}' "
    
    

#
# If the image file is large enough to meter, tell 'dd' to show 
# a progress-style status as it's working; otherwise silence it. 
#
DD_SILENCE=
DD_STATUS=

if [[ ${METERING} ]]; then
    echo >&2 "Creating target file ... "

    DD_STATUS="status=progress"
else
    DD_SILENCE="&>/dev/null"
fi

dd ${DD_SILENCE} if="${IMAGE_FILE}" of="${CLIPPED_IMAGE_FILE}" \
        bs=${MOUNT_OFFSET} skip=1 ${DD_STATUS}

(( $? == 0 )) || ThrowError \
        "Failed to clip the leading (big) block from the image file !"
sync



}


###############################################################################
#
# Mount the disk image file using a loop device.
#
# Dependencies: ${SCRIPT_FILE}  = path to a valid script file (preferably bash); 
#
Validate_Script_File () { 

    [[ -e "${SCRIPT_FILE}" ]] || ThrowError \
            "File '${SCRIPT_FILE}' does not exist!"

    [[ -r "${SCRIPT_FILE}" ]] || ThrowError \
            "Cannot read file '${SCRIPT_FILE}'!"

    # Script file should be "Bourne-Again shell script, ASCII text executable":
    #
    file ${SCRIPT_FILE} | grep -i "script" &>/dev/null

    (( $? == 0 )) || ThrowError "'${SCRIPT_FILE}' must be a script;"
}


###############################################################################




###############################################################################
# 
# 



Validate_Script_File  
echo >&2 "Script file '${SCRIPT_FILE}' appears valid... "
sleep 2


#
# Image file is accepted if it has an extension ".img":
#
EXTENSION=${IMAGE_FILE##*.}

[[ "${EXTENSION}" == "img" ]] || ThrowError \
    "'${IMAGE_FILE}' must be a disk image file ('.img').  Exiting... "




#
# Get the size of the image file and make a target file name from its name:
#
TARGET_SIZE=$( stat -c %s "${IMAGE_FILE}" )
TARGET_FILE=$( basename "${IMAGE_FILE}" ".img" )".run"

#
# If the image file is larger than the threshold, then enable metering 
# to display a progress bar for the user, since transcribing the image 
# file will take a long time for a large file.  A Windows game distributed 
# on a DVD and installed in a Wine enviroment could be nearly 5 GB in size. 
#
unset METERING
(( TARGET_SIZE > METER_THRESH )) && METERING=true


###############################################################################
#
# Finish up by renaming and changing the mode of the run file:
#
chmod +x "${TARGET_FILE}"

echo >&2 "Completed; file '${TARGET_FILE}' should be executable. "

exit



###############################################################################
#
############### NO LONGER NEEDED ##################
#
Concatenate_Image_File_with_Script_File () {

    # Make a temporary file to pad out the script file; 
    # It need not be any larger than 1 MiB, as that's the max script size.
    #
    PADDING_FILE=$( mktemp )

    (( $? == 0 )) || ThrowError \
            "Cannot create a temp file for padding the script file !"

    dd 2>/dev/null if=/dev/zero of="${PADDING_FILE}" \
            bs=${MOUNT_OFFSET} count=1 && sync

    (( $? == 0 )) || ThrowError \
            "Failure creating the zero-padding file !"

    # 
    # Make another temp file to hold the padded script file, 
    # which will be > 1 MiB:
    #
    OVER_PADDED_SCRIPT=$( mktemp )

    (( $? == 0 )) || ThrowError \
            "Cannot create a temp file to hold the padded script file !"

    cat "${SCRIPT_FILE}" "${PADDING_FILE}" > "${OVER_PADDED_SCRIPT}" && sync

    (( $? == 0 )) || ThrowError \
            "Failed to zero-pad the script file !"

    #
    # Re-use the first temp file to hold the padded script, now 1 MiB in size:
    #
    PADDED_SCRIPT=${PADDING_FILE}

    dd 2>/dev/null if="${OVER_PADDED_SCRIPT}" of="${PADDED_SCRIPT}" \
            bs=${MOUNT_OFFSET} count=1 && sync

    (( $? == 0 )) || ThrowError \
            "Failed to create the zero-padded script file !"

    #
    # Re-use the second temp file to hold the clipped image file:
    #
    CLIPPED_IMAGE_FILE=${OVER_PADDED_SCRIPT}

    #
    # If the image file is large enough to meter, tell 'dd' to show 
    # a progress-style status as it's working; otherwise silence it. 
    #
    DD_SILENCE=
    DD_STATUS=

    if [[ ${METERING} ]]; then
        echo >&2 "Creating target file ... "

        DD_STATUS="status=progress"
    else
        DD_SILENCE="&>/dev/null"
    fi

    dd ${DD_SILENCE} if="${IMAGE_FILE}" of="${CLIPPED_IMAGE_FILE}" \
            bs=${MOUNT_OFFSET} skip=1 ${DD_STATUS}

    (( $? == 0 )) || ThrowError \
            "Failed to clip the leading (big) block from the image file !"
    sync

    #
    # Now combine the padded script with the clipped image file:
    #
    CAT_APP=cat
    [[ ${METERING} ]] && $( which pv >/dev/null ) && CAT_APP=pv

        ${CAT_APP} "${PADDED_SCRIPT}" "${CLIPPED_IMAGE_FILE}" \
                > "${TARGET_FILE}" && sync

    (( $? == 0 )) || ThrowError \
            "Failed to write out the combined script-image file !"

    #
    # Remove the temp files that are no longer needed:
    #
    rm "${PADDED_SCRIPT}"

    (( $? == 0 )) || \
            echo >&2 "Failed to delete temp file '${PADDED_SCRIPT}' !"

    rm "${CLIPPED_IMAGE_FILE}"

    (( $? == 0 )) || \
            echo >&2 "Failed to delete temp file '${CLIPPED_IMAGE_FILE}' !"
}


###############################################################################




###############################################################################
#
############# NO LONGER NEEDED ##################
#
# The only way to be sure about the image file is to actually mount it:
#
RESULT=$( udisksctl loop-setup -o ${MOUNT_OFFSET} -f "${IMAGE_FILE}" )
    
(( $? == 0 )) || ThrowError \
    "Can't bind '${IMAGE_FILE}' - Is this a disk image file ?"

#
# If binding to a loop device fails, then the file is probably not valid:
#     
LOOP_DEV=$( printf "%s" "${RESULT}" | grep -o '/dev/loop.' )
    
[[ -n "${LOOP_DEV}" ]] || ThrowError \
        "Cannot determine the loop device bound to '${IMAGE_FILE}' !"

#
# If loop-mounting succeeds, then immediately un-mount it & continue:
#
sleep 2
RESULT=$( udisksctl unmount -b "${LOOP_DEV}" )

#
# But if unmounting fails, we cannot continue:
#  
(( $? == 0 )) || ThrowError \
        "Error unmounting '${IMAGE_FILE}' ! "
      
echo >&2 "Image file '${IMAGE_FILE}' appears valid... "
sleep 2
###############################################################################



