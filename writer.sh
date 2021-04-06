#!/bin/bash


SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"


LOG_FILE=$DIR/write_dd.log

function write_log() {
	sudo -u $SUDO_USER echo "$(date) $1" >> "${LOG_FILE}"
}

function write_stdout() {
	write_log "$1"
	echo "$1"
}

function write_stdout_nnl() {
	write_log "$1"
	echo -n "$1"
}

get_usbs() {
	USBS=""
	for BLKDEV in /sys/block/sd*; do
		READLINKDEV=$(readlink -f ${BLKDEV}/device)
		if [[ $READLINKDEV == *"usb"* ]]; then
			USB_DEVNAME=$(basename ${BLKDEV})
			USB_DEVNAME="/dev/"${USB_DEVNAME}
			if grep -qs "${USB_DEVNAME}" /proc/mounts; then
				umount ${USB_DEVNAME}?
				write_stdout "Unmounting mountpoints from ${USB_DEVNAME}"
			fi
			USBS="${USBS} ${USB_DEVNAME}"
		fi
	done
	USBS_COUNT=$(echo "${USBS}" | wc -w)
}

DISK_IMAGE=$1

[[ "$EUID" -ne 0 ]] && { echo "This script must be run with root privileges!"; exit 1; }
[[ -z "$DISK_IMAGE" ]] && { echo "usage: $0 *path to disk image*"; exit 1; }
[[ ! -f "$DISK_IMAGE" ]] && { echo "Disk image not found!"; exit 1; }

IMAGE_SIZE=$(stat -c%s "${DISK_IMAGE}")
IMAGE_CHECKSUM=$(sha256sum ${DISK_IMAGE} | cut --delimiter=' ' -f 1)

get_usbs

[[ "${USBS_COUNT}" == "0" ]] && { echo "No USBs found!"; exit 1; }

echo "${USBS_COUNT} USBs found!"

wipe_usb() {
  wipefs -af $1 >/dev/null 2>&1
  partprobe
}

verify_usb() {
	local USB_CHECKSUM=$(dd if=${1} bs=4M 2>/dev/null | head -c ${IMAGE_SIZE} | sha256sum | cut --delimiter=' ' -f 1)
	echo "Local: ${USB_CHECKSUM}"
	echo "Image: ${IMAGE_CHECKSUM}"
	if [ "${USB_CHECKSUM}" != "${IMAGE_CHECKSUM}" ]; then
		echo "${1}" >> failed.tmp
		echo "FAILED!"
	fi
}

write_stdout "WIPING USBs"
for CURR_USB in ${USBS}; do
	write_stdout_nnl "  ${CURR_USB}: "
	if [ -b ${CURR_USB} ]; then
		write_stdout "Formatting ..."
		wipe_usb $CURR_USB
	else
		write_stdout "Error: The device is not a block device!"
	fi
done

# we need to unmount everything again
get_usbs

#delete temp file and create new one
rm failed.tmp >/dev/null 2>&1
touch failed.tmp

write_stdout "Writing to USBs"
for CURR_USB in ${USBS}; do
	write_stdout_nnl "  ${CURR_USB}: "
	if [ -b ${CURR_USB} ]; then
		write_stdout "Started writing ..."
		( dd if=${DISK_IMAGE} of=${CURR_USB} bs=4M >/dev/null 2>&1 ) &
	else
		write_stdout "  Error: device ${CURR_USB} is not a block device!"
	fi
done

write_stdout "Waiting for writes to complete ..."
wait
write_stdout "All writes completed ..."
sleep 3

sync

write_stdout "Verifying USBs"
for CURR_USB in ${USBS}; do
	write_stdout_nnl "  ${CURR_USB}: "
	if [ -b ${CURR_USB} ]; then
		write_stdout "Started verifying ..."
		verify_usb ${CURR_USB} &
	else
		write_stdout "  Error: device ${CURR_USB} is not a block device!"
	fi
done

write_stdout "Waiting for verifies to complete ..."
wait
write_stdout "Verifying completed, Remove devices one by one and follow instructions."
sleep 3

readarray -t FAIL_USBS < failed.tmp

while [ "${USBS}" != "" ]
do
	NEWUSBS=""
	for CURR_USB in ${USBS}; do
		ls ${CURR_USB} > /dev/null 2>&1 # hacky and ugly
		if [ $? -ne 0 ]; then
			FLAG_FAILED=0
			for CHECK_USB in "${FAIL_USBS[@]}"; do
				[[ "${CURR_USB}" == "${CHECK_USB}" ]] && FLAG_FAILED=1
			done
			if [[ $FLAG_FAILED -eq 0 ]]; then
				write_stdout "Removed drive ${CURR_USB}. It was written SUCCESSFULLY"
			else
				write_stdout "Removed drive ${CURR_USB}. Writing it FAILED"
			fi
		else
			NEWUSBS="${NEWUSBS} ${CURR_USB}"
		fi
	done
	USBS=${NEWUSBS}
	sleep 1
done

rm failed.tmp >/dev/null 2>&1

write_stdout "All drives written and removed. Bye."