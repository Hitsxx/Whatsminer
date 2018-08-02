#!/bin/sh

if [ $# -lt 2 ] ;then
    echo "Usage: $0 <upgrade_dir> <orig_dir> <target_dir> <rootfs_type>"
    echo "Example:$0 $UPGRADE_WHATSMINER_PATH $STAGING_DIR/../build_dir/target-arm_cortex-a8+vfpv3_musl-1.1.15_eabi/root-sunxi /tmp/root-sunxi"
    exit 0;
fi

# Target dir to be upgraded is openwrt/build_dir/target-arm_cortex-a8+vfpv3_musl-1.1.15_eabi/root-sunxi
upgrade_dir=$1
orig_dir=$2
target_dir=$3
rootfs_type=$4

tmp_src_dir=$upgrade_dir/upgrade-files/tmp-rootfs

#
# upgrade target_dir with patch_dir
#
echo -e "\nGenerating $target_dir by $orig_dir + $upgrade_dir/upgrade-files/rootfs"

if [ -d $tmp_src_dir ]; then
	echo "rm -rf $tmp_src_dir"
	rm -rf $tmp_src_dir
fi

cp -af $upgrade_dir/upgrade-files/rootfs $tmp_src_dir
cp $upgrade_dir/upgrade.sh $tmp_src_dir/usr/bin/

find $tmp_src_dir/ -name "*.allwinner" | xargs rename -f 's/\.allwinner$//'

cp -afr $orig_dir/. $target_dir

# Remove unused files under $target_dir
rm -f $target_dir/etc/config/firewall
rm -f $target_dir/etc/init.d/om-watchdog
rm -f $target_dir/etc/rc.d/S11om-watchdog
rm -f $target_dir/etc/rc.d/K11om-watchdog
rm -f $target_dir/usr/lib/lua/luci/controller/firewall.lua

cp -af $tmp_src_dir/* $target_dir/

md5sum $LICHEE_PATH/tools/pack/out/kernel.fex | awk '{print $1}' > $target_dir/etc/kernel.md5
# for recovering kernel partition if corrupted
cp $LICHEE_PATH/tools/pack/out/kernel.fex $target_dir/root/

md5sum $LICHEE_PATH/tools/pack/out/boot_package.fex | awk '{print $1}' > $target_dir/etc/uboot.md5

if [ "$rootfs_type" = "factory-test" ]; then
    # Update for factory test
    rm -f $target_dir/etc/rc.d/*
    cp -af $upgrade_dir/factory-test/rootfs/etc/rc.d/* $target_dir/etc/rc.d/
    cp -f  $upgrade_dir/factory-test/rootfs/etc/init.d/* $target_dir/etc/init.d/
    cp -f  $upgrade_dir/factory-test/rootfs/etc/config/* $target_dir/etc/config/
    cp -f  $upgrade_dir/factory-test/rootfs/usr/bin/* $target_dir/usr/bin/
fi

# Removed $tmp_src_dir
rm -rf $tmp_src_dir

echo ""
echo "Done"
sync
