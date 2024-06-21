#!/bin/bash

# Set some default values:

export LIVEROOTPASS=changeme

export ROOTPASS=changeme

export USER=ansible

export USERPASS=changeme

export WORKDIR="/live-build"

export RELEASE=bookworm

export TEMPMOUNT="$WORKDIR/chroot"

export SCRIPTDIR="/root/debian-custom-iso"

export DEBIAN_FRONTEND=noninteractive

export ENCRYPTIONPASS=changeme

export LC_ALL=C

while getopts 'l:e:r:u:p:d:v:s:w:h:i' OPTION; do
  case "$OPTION" in
    l)
      export LIVEROOTPASS="$OPTARG"
      ;;
    e)
      export ENCRYPTIONPASS="$OPTARG"
      ;;
    r)
      export ROOTPASS="$OPTARG"
      ;;
    u)
      export USER="$OPTARG"
      ;;
    p)
      export USERPASS="$OPTARG"
      ;;
    d)
      export WORKDIR="$OPTARG"
      ;;
    v)
      export RELEASE="$OPTARG"
      ;;
    s)
      export WIFISSID="$OPTARG"
      ;;
    w)
      export WIFIPASS="$OPTARG"
      ;;
    i)
      export HIDDENSSID=True
      ;;
    h)
cat << EOF >&2
script usage: $(basename \$0) [options] <output directory for finished iso>
[-l <live root password>] (default: changeme)
[-r <root password for installed system>] (default: changeme)
[-u <user account for installed system>] (default: ansible)
[-p <user password for installed system>] (default: changeme)
[-v <live system release>] (default: bullseye)
[-s <wifi ssid>]
[-w <wifi password>]
[-i] connect to hidden ssid
[-h] print these usage instructions
EOF
      exit 1
      ;;
    ?)
cat << EOF >&2
script usage: $(basename \$0) [options] <output directory for finished iso>
[-l <live root password>] (default: changeme)
[-r <root password for installed system>] (default: changeme)
[-u <user account for installed system>] (default: ansible)
[-p <user password for installed system>] (default: changeme)
[-v <live system release>] (default: bullseye)
[-s <wifi ssid>]
[-w <wifi password>]
[-i] connect to hidden ssid
[-h] print these usage instructions
EOF
      exit 1
      ;;
  esac
done
shift "$(("$OPTIND" -1))"

export TARGET=$1

if [ -d "$WORKDIR" ]; then
  rm -r "$WORKDIR"
fi

mkdir -p "$WORKDIR"/{staging/{EFI/boot,boot/grub/x86_64-efi,isolinux,live},tmp}

mkdir -p $TEMPMOUNT

debootstrap "$RELEASE" $TEMPMOUNT


if [[ "$RELEASE" = 'bullseye' ]]; then 

cat << EOF > $TEMPMOUNT/etc/apt/sources.list
deb http://deb.debian.org/debian $RELEASE main contrib non-free
EOF

else

cat << EOF > $TEMPMOUNT/etc/apt/sources.list
deb http://deb.debian.org/debian $RELEASE main contrib non-free non-free-firmware
EOF

fi


echo "debian-live" > $TEMPMOUNT/etc/hostname

echo "127.0.1.1 debian-live" >> $TEMPMOUNT/etc/hosts

mkdir -p $TEMPMOUNT/dev/pts

mkdir -p $TEMPMOUNT/proc

mkdir -p $TEMPMOUNT/sys

chroot $TEMPMOUNT /bin/bash -c "mount none -t proc /proc"
chroot $TEMPMOUNT /bin/bash -c "mount none -t sysfs /sys"
chroot $TEMPMOUNT /bin/bash -c "mount none -t devpts /dev/pts"

cp /etc/resolv.conf $TEMPMOUNT/etc/resolv.conf

chroot $TEMPMOUNT /bin/bash -c "apt -y update"

chroot $TEMPMOUNT /bin/bash -c "apt install -y dpkg-dev linux-headers-amd64 linux-image-amd64 systemd-sysv firmware-linux dosfstools debootstrap gdisk dkms dpkg-dev sed git vim efibootmgr live-boot openssh-server tmux systemd-timesyncd firmware-iwlwifi network-manager qemu-guest-agent firmware-libertas"

chroot $TEMPMOUNT /bin/bash -c "apt install -y --no-install-recommends zfs-dkms zfsutils-linux"

mkdir $TEMPMOUNT/root/zbm

wget https://get.zfsbootmenu.org/efi -O $TEMPMOUNT/root/zbm/vmlinuz.EFI

if [[ -n "$HIDDENSSID" ]]; then 

cat << EOF > "$TEMPMOUNT/usr/bin/wifi-autoconnect.sh"
#!/bin/bash

/usr/bin/nmcli dev wifi connect '$WIFISSID' password '$WIFIPASS' hidden yes

sleep 3

/usr/bin/nmcli dev wifi connect '$WIFISSID' password '$WIFIPASS' hidden yes

sleep 3

/usr/bin/nmcli dev wifi connect '$WIFISSID' password '$WIFIPASS' hidden yes

sleep 3
EOF

elif [[ -z "$HIDDENSSID" ]]; then 

cat << EOF > "$TEMPMOUNT/usr/bin/wifi-autoconnect.sh"
#!/bin/bash

/usr/bin/nmcli dev wifi connect '$WIFISSID' password '$WIFIPASS'

sleep 3

/usr/bin/nmcli dev wifi connect '$WIFISSID' password '$WIFIPASS'

sleep 3

/usr/bin/nmcli dev wifi connect '$WIFISSID' password '$WIFIPASS'

sleep 3
EOF

else 

  echo "It shouldn't be possible for a wifi SSID to be hidden and not hidden"
  echo "How did you get here?"
  sleep 2400
  exit 1

fi

chmod +x "$TEMPMOUNT/usr/bin/wifi-autoconnect.sh"

sed -i '/PermitRootLogin/c\PermitRootLogin\ yes' $TEMPMOUNT/etc/ssh/sshd_config

chroot $TEMPMOUNT /bin/bash -c "echo root:$LIVEROOTPASS | chpasswd"

chroot $TEMPMOUNT /bin/bash -c "git clone https://github.com/loosebinding/debian-custom-iso.git /root/debian-custom-iso"
chroot $TEMPMOUNT /bin/bash -c "apt clean"
chroot $TEMPMOUNT /bin/bash -c "rm -rf /tmp/*"
chroot $TEMPMOUNT /bin/bash -c "rm /etc/resolv.conf"
chroot $TEMPMOUNT /bin/bash -c "umount -lf /dev/pts"
chroot $TEMPMOUNT /bin/bash -c "umount -lf /sys"
chroot $TEMPMOUNT /bin/bash -c "umount -lf /proc"

mkdir $TEMPMOUNT/etc/systemd/system/getty@tty1.service.d

cat << EOF > $TEMPMOUNT/etc/systemd/system/getty@tty1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root %I $TERM
EOF

cat << EOF > $TEMPMOUNT/root/.bash_profile
[ -z "\$SSH_TTY" ] && tmux new-session -s auto_install "$SCRIPTDIR/debian-auto-install.sh"
[ -n "\$SSH_TTY" ] && tmux attach-session
EOF

mksquashfs $TEMPMOUNT "$WORKDIR"/staging/live/filesystem.squashfs -e boot

cp $TEMPMOUNT/boot/vmlinuz-* "$WORKDIR/staging/live/vmlinuz"

cp $TEMPMOUNT/boot/initrd.img-* "$WORKDIR/staging/live/initrd"

cat << EOF > "$WORKDIR/staging/isolinux/isolinux.cfg"
UI vesamenu.c32

MENU TITLE Boot Menu
DEFAULT linux
TIMEOUT 300
MENU RESOLUTION 640 480
MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #9033ccff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std
MENU COLOR help         37;40   #c0ffffff #a0000000 std
MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07        37;40   #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40   #30ffffff #00000000 std

LABEL linux
  MENU LABEL Debian 11 bullseye: Single disk ext4 root
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live bootmode=bios release=bullseye disklayout=ext4_single rootpass=$ROOTPASS user=$USER userpass=$USERPASS

LABEL linux
  MENU LABEL Debian 11 bullseye: Single disk zfs root
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live bootmode=bios release=bullseye disklayout=zfs_single rootpass=$ROOTPASS user=$USER userpass=$USERPASS
  
LABEL linux
  MENU LABEL Debian 11 bullseye: Single disk zfs root (encrypted)
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live bootmode=bios release=bullseye disklayout=zfs_single rootpass=$ROOTPASS user=$USER userpass=$USERPASS encryptionpass=$ENCRYPTIONPASS

LABEL linux
  MENU LABEL Debian 11 bullseye: Two disk zfs mirror root
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live bootmode=bios release=bullseye disklayout=zfs_mirror rootpass=$ROOTPASS user=$USER userpass=$USERPASS

LABEL linux
  MENU LABEL Debian 11 bullseye: Two disk zfs mirror root (encrypted)
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live bootmode=bios release=bullseye disklayout=zfs_mirror rootpass=$ROOTPASS user=$USER userpass=$USERPASS encryptionpass=$ENCRYPTIONPASS

LABEL linux
  MENU LABEL Debian 12 bookworm: Single disk ext4 root
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live bootmode=bios release=bookwrom disklayout=ext4_single rootpass=$ROOTPASS user=$USER userpass=$USERPASS

LABEL linux
  MENU LABEL Debian 12 bookworm: Single disk zfs root
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live bootmode=bios release=bookworm disklayout=zfs_single rootpass=$ROOTPASS user=$USER userpass=$USERPASS

LABEL linux
  MENU LABEL Debian 12 bookworm: Single disk zfs root (encrypted)
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live bootmode=bios release=bookworm disklayout=zfs_single rootpass=$ROOTPASS user=$USER userpass=$USERPASS encryptionpass=$ENCRYPTIONPASS

LABEL linux
  MENU LABEL Debian 12 bookworm: Two disk zfs mirror root
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live bootmode=bios release=bookworm disklayout=zfs_mirror rootpass=$ROOTPASS user=$USER userpass=$USERPASS

LABEL linux
  MENU LABEL Debian 12 bookworm: Two disk zfs mirror root (encrypted)
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live bootmode=bios release=bookworm disklayout=zfs_mirror rootpass=$ROOTPASS user=$USER userpass=$USERPASS encryptionpass=$ENCRYPTIONPASS
EOF

cat << EOF > "$WORKDIR/staging/boot/grub/grub.cfg"
search --set=root --file /DEBIAN_CUSTOM

set default="0"
set timeout=30

insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660

insmod all_video
insmod font

menuentry "Debian 11 bullseye: Single disk ext4 root" {
    linux (\$root)/live/vmlinuz boot=live bootmode=efi release=bullseye disklayout=ext4_single rootpass=$ROOTPASS user=$USER userpass=$USERPASS
    initrd (\$root)/live/initrd
}

menuentry "Debian 11 bullseye: Single disk zfs root" {
    linux (\$root)/live/vmlinuz boot=live bootmode=efi release=bullseye disklayout=zfs_single rootpass=$ROOTPASS user=$USER userpass=$USERPASS
    initrd (\$root)/live/initrd
}

menuentry "Debian 11 bullseye: Single disk zfs root (encrypted)" {
    linux (\$root)/live/vmlinuz boot=live bootmode=efi release=bullseye disklayout=zfs_single rootpass=$ROOTPASS user=$USER userpass=$USERPASS encryptionpass=$ENCRYPTIONPASS
    initrd (\$root)/live/initrd
}

menuentry "Debian 11 bullseye: Two disk zfs mirror root" {
    linux (\$root)/live/vmlinuz boot=live bootmode=efi release=bullseye disklayout=zfs_mirror rootpass=$ROOTPASS user=$USER userpass=$USERPASS
    initrd (\$root)/live/initrd
}

menuentry "Debian 11 bullseye: Two disk zfs mirror root (encrypted)" {
    linux (\$root)/live/vmlinuz boot=live bootmode=efi release=bullseye disklayout=zfs_mirror rootpass=$ROOTPASS user=$USER userpass=$USERPASS encryptionpass=$ENCRYPTIONPASS
    initrd (\$root)/live/initrd
}

menuentry "Debian 12 bookworm: Single disk ext4 root" {
    linux (\$root)/live/vmlinuz boot=live bootmode=efi release=bookworm disklayout=ext4_single rootpass=$ROOTPASS user=$USER userpass=$USERPASS
    initrd (\$root)/live/initrd
}

menuentry "Debian 12 bookworm: Single disk zfs root" {
    linux (\$root)/live/vmlinuz boot=live bootmode=efi release=bookworm disklayout=zfs_single rootpass=$ROOTPASS user=$USER userpass=$USERPASS
    initrd (\$root)/live/initrd
}

menuentry "Debian 12 bookworm: Single disk zfs root (encrypted)" {
    linux (\$root)/live/vmlinuz boot=live bootmode=efi release=bookworm disklayout=zfs_single rootpass=$ROOTPASS user=$USER userpass=$USERPASS encryptionpass=$ENCRYPTIONPASS
    initrd (\$root)/live/initrd
}

menuentry "Debian 12 bookworm: Two disk zfs mirror root" {
    linux (\$root)/live/vmlinuz boot=live bootmode=efi release=bookworm disklayout=zfs_mirror rootpass=$ROOTPASS user=$USER userpass=$USERPASS
    initrd (\$root)/live/initrd
}

menuentry "Debian 12 bookworm: Two disk zfs mirror root (encrypted)" {
    linux (\$root)/live/vmlinuz boot=live bootmode=efi release=bookworm disklayout=zfs_mirror rootpass=$ROOTPASS user=$USER userpass=$USERPASS encryptionpass=$ENCRYPTIONPASS
    initrd (\$root)/live/initrd
}
EOF

cat << 'EOF' > "$WORKDIR"/tmp/grub-standalone.cfg
search --set=root --file /DEBIAN_CUSTOM
set prefix=($root)/boot/grub/
configfile /boot/grub/grub.cfg
EOF

touch "$WORKDIR"/staging/DEBIAN_CUSTOM

cp /usr/lib/ISOLINUX/isolinux.bin "$WORKDIR/staging/isolinux/" 

cp /usr/lib/syslinux/modules/bios/* "$WORKDIR/staging/isolinux/"

cp -r /usr/lib/grub/x86_64-efi/* "$WORKDIR/staging/boot/grub/x86_64-efi/"

grub-mkstandalone --locales="" --themes="" --fonts="" --format=x86_64-efi --modules="part_gpt part_msdos fat iso9660" --output="$WORKDIR/tmp/bootx64.efi" "boot/grub/grub.cfg=$WORKDIR/tmp/grub-standalone.cfg"

dd if=/dev/zero of="$WORKDIR"/staging/EFI/boot/efiboot.img bs=1M count=20 

mkfs.vfat "$WORKDIR"/staging/EFI/boot/efiboot.img 

mmd -i "$WORKDIR"/staging/EFI/boot/efiboot.img efi efi/boot

mcopy -vi "$WORKDIR/staging/EFI/boot/efiboot.img" "$WORKDIR/tmp/bootx64.efi" "$WORKDIR/staging/boot/grub/grub.cfg" ::efi/boot/

xorriso -as mkisofs -iso-level 3 -o "$WORKDIR/debian-custom.iso" -full-iso9660-filenames -volid "DEBIAN_CUSTOM" -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin -eltorito-boot isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table --eltorito-catalog isolinux/isolinux.cat -eltorito-alt-boot -e /EFI/boot/efiboot.img -no-emul-boot -isohybrid-gpt-basdat -append_partition 2 0xef "$WORKDIR"/staging/EFI/boot/efiboot.img "$WORKDIR/staging"

chmod a+r "$WORKDIR"/debian-custom.iso

cp "$WORKDIR"/debian-custom.iso "$TARGET"
