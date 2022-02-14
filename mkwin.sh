#!/bin/sh -e
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
	cat >&2 <<EOF
$0 <iso> [device] [label]

  See mkwin(1) manual page for more info
EOF
	exit
fi

if [ "$(id -u)" -ne 0 ]; then
	echo "error: script must be run as root"
	exit 1
fi

# get system configuration
if [ -n "$MKWIN_GRUB" ]; then
	sysgrub="$MKWIN_GRUB"
elif which grub2-install >/dev/null 2>/dev/null; then
	sysgrub=grub2
else
	sysgrub=grub
fi

if [ -n "$MKWIN_GRUB_EFI" ]; then
	sysgrubefi="$MKWIN_GRUB_EFI"
else
	sysgrubefi="$sysgrub"-install
fi

if [ -n "$MKWIN_GRUB_PC" ]; then
	sysgrubpc="$MKWIN_GRUB_PC"
else
	sysgrubpc="$sysgrub"-install
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
	devs="$(find /dev/disk/by-path | grep -- '-usb-' | grep -v -- '-part[0-9]*$' || true)"

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

# sector sizes
secstart=2048
secefi=1048576

# partition device
echo "partitioning..."
dd if=/dev/zero of="$dev" count=$secstart >/dev/null 2>/dev/null
sfdisk "$dev" >/dev/null <<EOF
label: dos
device: $dev
unit: sectors

${dev}1 : start=$secstart, size=$(expr "$(blockdev --getsz "$dev")" - $secstart - $secefi), type=7
${dev}2 : size=$secefi, type=ef
EOF
blockdev --rereadpt "$dev"

if [ -b "$dev"p1 ]; then
	winpart="$dev"p1
	efipart="$dev"p2
else
	winpart="$dev"1
	efipart="$dev"2
fi

unset secstart
unset secefi

# format device
echo "formatting..."
mkfs.ntfs -f -L "$label" "$winpart" >/dev/null
mkfs.fat -F 32 -n ESP "$efipart" >/dev/null

# mount device
echo "mounting..."
winmnt="$(mktemp -d)"
efimnt="$(mktemp -d)"
isomnt="$(mktemp -d)"
ntfs-3g "$winpart" "$winmnt"
mount "$efipart" "$efimnt"
mount -o ro "$iso" "$isomnt"

trap "(set +e; umount '$winmnt'; rmdir '$winmnt'; umount '$efimnt'; rmdir '$efimnt'; umount '$isomnt'; rmdir '$isomnt'; true) >/dev/null 2>/dev/null" EXIT

unset iso
unset efipart
unset winpart

# install bootloaders
echo "installing bootloaders..."
"$sysgrubefi" --target=x86_64-efi --boot-directory="$efimnt" --efi-directory="$efimnt" --removable >/dev/null
"$sysgrubpc" --target=i386-pc --boot-directory="$efimnt" "$dev" >/dev/null

# fix Windows 7 not coming with EFI boot by default
if [ ! -e "$isomnt"/efi/boot/bootx64.efi ]; then
	mkdir -p "$winmnt"/efi/boot
	7z e -so "$isomnt"/sources/install.wim 1/Windows/Boot/EFI/bootmgfw.efi >"$winmnt"/efi/boot/bootx64.efi
fi

unset dev

# configuring grub
echo "configuring grub..."
cat >"$efimnt"/grub/grub.cfg <<EOF
if loadfont /grub/fonts/unicode.pf2; then
	set gfxmode=auto

	if [ \${grub_platform} == "efi" ]; then
		insmod efi_gop
		insmod efi_uga
	else
		insmod all_video
	fi

	insmod gfxterm
	terminal_output gfxterm
fi

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

set gfxpayload=keep

set timeout=0

search --no-floppy --label --set=root $label

menuentry "$label" {
	if [ \${grub_platform} == "efi" ]; then
		chainloader /efi/boot/bootx64.efi
	else
		ntldr /bootmgr
	fi
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
