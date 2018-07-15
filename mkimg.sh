#! /usr/bin/env bash 
#
# Create an image file from a Wine environment
# 
# This script guides the creation of a disk image (.img) file to hold the 
# environment of one or more wine applications.  The resulting image file 
# can be mounted by a user as though it were a disk to '/media', allowing 
# the application(s) in the "wine bottle" to be run.  
#
# A separate script automates mounting and launching the application in 
# the image file.  Another script automates embedding this launcher script 
# within the image file, creating a '.run' file that is self-executing.
#
SCRIPT_VERSION=1.0

ONE_MIB=1048576

METER_THRESH=$(( 500 * ONE_MIB ))

MOUNT_OFFSET=${ONE_MIB}

THIS_SCRIPT=$( basename ${0} )


###############################################################################
#
# Print an error message and abort with a non-zero return code
#
ThrowError() {
    echo >&2 "${THIS_SCRIPT}: ${1} "
    exit 1
}


###############################################################################
#
# Determine how large an image file we need to hold the Wine environment.
#
Determine_Image_Size () {

    [[ -d "${WINE_ENV}" ]] || ThrowError \
            "Cannot read the Wine environment in '${}'; exiting..."
}


###############################################################################
#
# Create the disk image file as an empty (initialized) disk.
#
Make_Image_File () { 

    [[ -e "${IMAGE_FILE}" ]] && ThrowError \
            "Image file '${IMAGE_FILE}' already exists; exiting..."
    
    (( IMAGE_SIZE > 1 )) || ThrowError \
            "Image file size (${IMAGE_SIZE}) is too small; exiting..."

    #
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
# Format the disk image file as a mountable disk.
#
Format_Image_File () { 
    local LABEL_CMD=

    [[ -w "${IMAGE_FILE}" ]] || ThrowError \
            "Cannot modify image file '${IMAGE_FILE}'!"
    
    # 
    # Force the image label variable into an acceptable format, 
    # maximum 11 characters with no white space (subst with '_' instead): 
    #
    if [[ -n "${IMAGE_LABEL}" ]]; then
    
        IMAGE_LABEL=$( printf "%s" "${IMAGE_LABEL}" | tr -s '[:space:]' '_' )
        IMAGE_LABEL=${IMAGE_LABEL:0:11}
        
        LABEL_CMD="-L ${IMAGE_LABEL}"
    fi
    
    mkfs -t ext4 -q -m 1 -b 4096 -E offset=${ONE_MIB} \
            ${LABEL_CMD} "${IMAGE_FILE}"
    
    (( $? == 0 )) || ThrowError \
            "Cannot format image file '${IMAGE_FILE}'!"
}


###############################################################################
#
# Mount the disk image file using a loop device.
#
Mount_Image_File () { 

    [[ -w "${IMAGE_FILE}" ]] || ThrowError \
            "Cannot access image file '${IMAGE_FILE}' for writing!"

    RESULT=$( udisksctl loop-setup -o "${MOUNT_OFFSET}" -f "${IMAGE_FILE}" )
        
    (( $? == 0 )) || ThrowError \
        "Can't bind '${IMAGE_FILE}' to a loop device!"

    #
    # Get the loop device that was created...
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


dotar () { 
    sudo chown maint.maint /media/maint/${1} && \
    tar -C /media/maint/${1} -xf wine-${2}.tar && \
    cp myst install-winapps-in-wine.txt /media/maint/${1} && \
    sync
}

drop () { 
    udisksctl unmount -b /dev/loop1 && \
    udisksctl loop-delete -b /dev/loop1 && \
    ls --color=auto -lF
    sudo losetup
}

###############################################################################

# dotar <partition-LABEL> <tarfile-core-filename>

# drop

# mkrun.sh <run-script> <image-file>

IMAGE_FILE=test_disk.img
IMAGE_SIZE=123
IMAGE_LABEL="TEST"

WINE_ENV=

Determine_Image_Size

Make_Image_File

Format_Image_File

Mount_Image_File



exit

#
# Finish up by renaming and changing the mode of the image file:
#
chmod -x "${IMAGE_FILE}"

echo >&2 "Completed; file '${IMAGE_FILE}' should be mountable. "



###############################################################################

