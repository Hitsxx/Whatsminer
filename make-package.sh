#!/bin/bash

rm -f upgrade-whatsminer*.tgz

VERSION_NUMBER=`cat upgrade-files/rootfs/etc/microbt_release | grep FIRMWARE_VERSION | cut -d"=" -f2 | sed "s/'\|.1'//g"`
UPGRADE_FULL_PACKAGENAME=upgrade-whatsminer-full-$VERSION_NUMBER.tgz
UPGRADE_FILES_COMMON_PACKAGENAME=upgrade-whatsminer-common-$VERSION_NUMBER
UPGRADE_SCRIPT_PATH=upgrade-files/rootfs/usr/bin/

cp upgrade.sh $UPGRADE_SCRIPT_PATH # copy for whatsminerTool

# For user
echo "Generating full package $UPGRADE_FULL_PACKAGENAME for user"
./update-upgrade-rootfs.sh
tar zcf $UPGRADE_FULL_PACKAGENAME upgrade.sh upgrade-bin upgrade-rootfs

user_auto_vol_package=$UPGRADE_FILES_COMMON_PACKAGENAME.AutoVol.tgz
echo "Generating incremental package(adjust freq and then vol) $user_auto_vol_package for user"
tar zcf $user_auto_vol_package upgrade.sh upgrade-bin upgrade-files

user_fix_vol_package=$UPGRADE_FILES_COMMON_PACKAGENAME.FixVol.tgz
echo "Generating incremental package(adjust freq only) $user_fix_vol_package for user"
sed -i "s/ADJUST_TYPE=\$ADJUST_FREQ_AND_THEN_VOL/ADJUST_TYPE=\$ADJUST_FREQ_ONLY/" upgrade.sh
tar zcf $user_fix_vol_package upgrade.sh upgrade-bin upgrade-files
git checkout upgrade.sh

# For factory

fixed_vol_package=$UPGRADE_FILES_COMMON_PACKAGENAME.2.tgz
touch upgrade-files/factory_mode

echo "Generating fixed-voltage version $fixed_vol_package for factory mode"
# Update /etc/microbt_release & /etc/config/powers.*
./update-fixed-voltage-version.sh
tar zcf $fixed_vol_package upgrade.sh upgrade-bin upgrade-files

auto_vol_package=$UPGRADE_FILES_COMMON_PACKAGENAME.1.tgz
echo "Generating auto-voltage version $auto_vol_package for factory mode"

./update-fixed-voltage-version.sh restore
tar zcf $auto_vol_package upgrade.sh upgrade-bin upgrade-files

rm upgrade-files/factory_mode
rm $UPGRADE_SCRIPT_PATH/upgrade.sh

echo "OK"
