#!/bin/sh
#

POWERS_FILES=`ls upgrade-files/rootfs/etc/config/powers.default.*`

if [ "$1" = "restore" ]; then
    git checkout -- upgrade-files/rootfs/etc/microbt_release
    git checkout -- upgrade-rootfs/allwinner-rootfs/etc/microbt_release
    git checkout -- upgrade-rootfs/zynq-rootfs/etc/microbt_release

    for file in $POWERS_FILES
    do
        git checkout -- $file
        filename=`echo $file | sed 's/upgrade-files\/rootfs\///g'`
        git checkout -- upgrade-rootfs/allwinner-rootfs/$filename
        git checkout -- upgrade-rootfs/zynq-rootfs/$filename
    done
else
    for file in $POWERS_FILES
    do
        sed -i "s/:1:/:0:/" $file
    done

    sed -i "s/.1'/.2'/g" upgrade-files/rootfs/etc/microbt_release
fi
