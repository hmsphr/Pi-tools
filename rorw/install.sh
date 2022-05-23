#!/bin/bash
BASEPATH="$(dirname "$(readlink -f "$0")")"
DISTRO=''

echo "$BASEPATH"
cd "$BASEPATH"

ln -sf "$BASEPATH/ro" /usr/local/bin/
ln -sf "$BASEPATH/rw" /usr/local/bin/


### randomness
###

## xBIAN (DEBIAN / RASPBIAN / UBUNTU)
if [[ $(command -v apt) ]]; then
    apt -y install haveged 
## ARCH Linux
elif [[ $(command -v pacman) ]]; then
    pacman -S haveged --noconfirm --needed
fi
systemctl disable systemd-random-seed
systemctl enable haveged
systemctl start haveged

#
# read only
#

RAMSIZE=$(grep MemTotal /proc/meminfo | awk -F ' ' '{print $2}')
if [ -z "$RAMSIZE" ]
then
      RAMSIZE=1024000
fi
TMPSIZE=$(($RAMSIZE/8000))
if [ "$TMPSIZE" -eq "0" ]; then
   TMPSIZE=128
fi

# ARCH Raspberry Pi
if (lsblk -o uuid /dev/mmcblk0p3 > /dev/null 2>&1); then

    UUID_boot=`lsblk -o uuid /dev/mmcblk0p1 | tail -1`
    UUID_root=`lsblk -o uuid /dev/mmcblk0p2 | tail -1`
    UUID_data=`lsblk -o uuid /dev/mmcblk0p3 | tail -1`

    mkdir -p /data
    mount -U "$UUID_data" /data
    mkdir -p /data/media
    mkdir -p /data/var/lib/NetworkManager
    mkdir -p /data/var/lib/dnsmasq
    mkdir -p /var/lib/dnsmasq

    echo "
    UUID=$UUID_boot                                 /boot       vfat    defaults,ro,errors=remount-ro,umask=177        0       0
    UUID=$UUID_root                                 /           ext4    defaults,ro,errors=remount-ro        0       0         # also RO in /boot/cmdline.txt
    UUID=$UUID_data                                 /data       ext4    defaults        0       0

    tmpfs                                           /tmp        tmpfs   defaults,size=${TMPSIZE}M 0 0
    /data/var/lib/dnsmasq                           /var/lib/dnsmasq none defaults,bind 0 0
    /data/var/lib/NetworkManager                    /var/lib/NetworkManager none defaults,bind 0 0
    /run                                            /var/run     none    defaults,bind 0 0
    /tmp                                            /var/lock   none    defaults,bind 0 0    
    /tmp                                            /var/spool  none    defaults,bind 0 0
    /tmp                                            /var/log    none    defaults,bind 0 0
    /tmp                                            /var/tmp    none    defaults,bind 0 0
    " > /etc/fstab

    sed -i 's/rw/fastboot noswap ro/g' /boot/cmdline.txt
    sed -i "s/root=[^ ]*/root=UUID=$UUID_root rootfstype=ext4/g" /boot/cmdline.txt

    echo "source $BASEPATH/rorw.bashrc" >> /etc/bash.bashrc

#XBIAN ayufan RockPro64 eMMc
elif (lsblk -o uuid /dev/mmcblk1p8 > /dev/null 2>&1); then

    UUID_boot=`lsblk -o uuid /dev/mmcblk1p6 | tail -1`
    UUID_root=`lsblk -o uuid /dev/mmcblk1p7 | tail -1`
    UUID_data=`lsblk -o uuid /dev/mmcblk1p8 | tail -1`

    mkdir -p /data
    mount -U "$UUID_data" /data
    #mkdir -p /data/media
    mkdir -p /data/var/lib/NetworkManager
    mkdir -p /data/var/lib/dnsmasq
    mkdir -p /var/lib/dnsmasq

    echo "
    UUID=$UUID_boot                                 /boot/efi   vfat    defaults,ro,errors=remount-ro,umask=177        0       0
    #UUID=$UUID_root                                 /           ext4    defaults,ro,errors=remount-ro        0       0         # already done in /boot/extlinux/extlinux.conf
    UUID=$UUID_data                                 /data       ext4    defaults        0       0

    tmpfs                                           /tmp        tmpfs   defaults,size=${TMPSIZE}M 0 0
    /data/var/lib/dnsmasq                           /var/lib/dnsmasq none defaults,bind 0 0
    /data/var/lib/NetworkManager                    /var/lib/NetworkManager none defaults,bind 0 0
    /run                                            /var/run     none    defaults,bind 0 0
    /tmp                                            /var/lock   none    defaults,bind 0 0    
    /tmp                                            /var/spool  none    defaults,bind 0 0
    /tmp                                            /var/log    none    defaults,bind 0 0
    /tmp                                            /var/tmp    none    defaults,bind 0 0
    " > /etc/fstab

    sed -i 's/rw/fastboot noswap ro/g' /boot/extlinux/extlinux.conf
    sed -i "s/root=LABEL=linux-root/root=UUID=$UUID_root/g" /boot/extlinux/extlinux.conf
    
    echo "source $BASEPATH/rorw.bashrc" >> /root/.bashrc

else
    echo ""
    echo "Can't find third partition or detect partition system..."
    echo "RORW install FAILED"
    echo ""
    exit 1
fi


#
# fake-hwclock
#

systemctl disable systemd-timesyncd
systemctl disable ntp

ln -sf "$BASEPATH/fake-clock" /usr/local/bin/
ln -sf "$BASEPATH/fake-clock.service" /etc/systemd/system/
ln -sf "$BASEPATH/fake-clock-autosave.service" /etc/systemd/system/
ln -sf "$BASEPATH/fake-clock-autosave.timer" /etc/systemd/system/

systemctl daemon-reload
systemctl enable fake-clock 
systemctl enable fake-clock-autosave.timer

fake-clock save

echo "rw
history -a
ro
fake-clock save
" >> /etc/bash.bash_logout
