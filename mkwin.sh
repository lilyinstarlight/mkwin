#!/bin/sh
if [ "$UID" -ne "0" ]; then
	echo "error: script must be run as root"
	exit 1
fi

# get distro configuration
iso="$1"
if [ -z "$iso" ]; then
	echo "error: you must specify an iso"
	exit 1
fi

# get device
dev="$2"
if [ -z "$dev" ]; then
	echo "getting device..."
	devs="$(find /dev/disk/by-path | grep -- '-usb-' | grep -v -- '-part[0-9]*$')"

	if [ -z "$devs" ]; then
		echo "error: no usb device found"
		exit 2
	fi

	devs="$(readlink -f $devs)"

	dialogdevs=""

	dialogmodel=""
	for dialogdev in $devs; do
		dialogmodel="$(lsblk -ndo model "$dialogdev")"
		dialogdevs="$dialogdevs $dialogdev '$dialogmodel' off"
	done
	unset dialogdev
	unset dialogmodel

	while [ -z "$dev" ]; do
		dev="$(eval "dialog --stdout --radiolist 'select usb device' 12 40 5 $dialogdevs")"
		if [ "$?" -ne "0" ]; then
			exit
		fi
	done

	unset dialogdevs

	unset devs
fi

# get label
label="$3"
if [ -z "$label" ]; then
	label="WindowsInstaller"
fi

# partition device
echo "partitioning..."
fdisk "$dev" >/dev/null <<EOF
o
n



+$(expr $(blockdev --getsize64 "$dev") / 1024 - 524288)K
t
7
a
n




t

ef
w
EOF

winpart="$dev"1
efipart="$dev"2

# format device
echo "formatting..."
mkfs.ntfs -f -L "$label" "$winpart" >/dev/null
mkfs.fat -F 32 -n ESP "$efipart" >/dev/null

# mount devie
echo "mounting..."
winmnt="$(mktemp -d)"
efimnt="$(mktemp -d)"
isomnt="$(mktemp -d)"
mount "$winpart" "$winmnt"
mount "$efipart" "$efimnt"
mount -o ro "$iso" "$isomnt"

unset efipart
unset winpart

# install bootloaders
echo "installing bootloaders..."
grub-install --target=x86_64-efi --boot-directory="$efimnt" --efi-directory="$efimnt" --removable >/dev/null
ms-sys -7 "$dev" >/dev/null

unset dev

# configuring grub
echo "configuring grub..."
cat >"$efimnt"/grub/grub.cfg <<EOF
if loadfont /grub/fonts/unicode.pf2; then
	set gfxmode=auto

	insmod efi_gop
	insmod efi_uga

	insmod gfxterm
	terminal_output gfxterm
fi

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

set gfxpayload=keep

set timeout=0

search --no-floppy --label --set=root $label

menuentry "$label" {
	chainloader /efi/boot/bootx64.efi
}
EOF

unset label

# copy files
echo "copying files..."
cp -r "$isomnt"/* "$winmnt"/

# sync
echo "syncing..."
sync

# unmount
echo "unmounting..."
umount "$isomnt"
umount "$efimnt"
umount "$winmnt"
rmdir "$isomnt"
rmdir "$efimnt"
rmdir "$winmnt"

unset isomnt
unset efimnt
unset winmnt

echo "done"
