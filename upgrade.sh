#!/bin/sh
#
# Upgrade script.
#

detect_platform_script=`find /tmp -name detect-platform.sh | head -n 1`
if [ "$detect_platform_script" = "" ]; then
    detect_platform_script="/usr/bin/detect-platform.sh"
fi
source $detect_platform_script

# Detect control board type
if [ "${CONTROL_BOARD_PLATFORM:0:9}" = "ALLWINNER" ]; then 
    is_allwinner_platform=true
    mount -o remount,rw /dev/root /
else
    is_allwinner_platform=false
fi

control_board=$CONTROL_BOARD_PLATFORM

echo "Detected machine type: control_board=$control_board"

if [ "$control_board" = "unknown" ]; then
    echo "*********************************************************************"
    echo "Unknown control board type, quit the upgrade process."
    echo "*********************************************************************"
    exit 0
fi

get_theoretical_ghash() {
    local freq=$1
    local bitmicro_options=`uci get cgminer.default.bitmicro_options`
    local board_num=`echo $bitmicro_options|cut -d ":" -f2`
    local chip_num=`echo $bitmicro_options|cut -d ":" -f3`
    local core_num=`echo $bitmicro_options|cut -d ":" -f4`
    local ghash=`expr $freq \* $core_num \* $chip_num \* $board_num / 1000`
    echo $ghash
}

is_advanced_power() {
    if [ -d /sys/bus/i2c/drivers/p6-power/2-002c ]; then
        echo 1
    else
        echo 0
    fi
}

# ADJUST_TYPE
ADJUST_BOTH_VOL_AND_FREQ=1
ADJUST_FREQ_ONLY=2
ADJUST_FREQ_AND_THEN_VOL=3

get_auto_adjust_power_params() {
    local max_vol
    local vol_step
    local max_steps
    local highest_vol_ghash

    local STABLE_SECONDS=600
    local FREQ_STEP=6
    local init_vol=$1
    local freq=$2
    local adjust_type=$3
    local GOOD_RATIO_PERCENT=95
    local theoretical_ghash=$(get_theoretical_ghash $freq)
    local good_ghash=`expr $theoretical_ghash \* 97 / 100`
    local sell_ghash=`expr $good_ghash \* 94 / 100`

    if [ "$(is_advanced_power)" = "1" ]; then
        vol_step=7
        max_vol=`expr $init_vol + 70`
        max_steps=10
    else
        vol_step=1
        max_vol=`expr $init_vol - 10`
        if [ "$max_vol" -lt 0 ];then
            max_vol=0
        fi
        max_steps=`expr $init_vol - $max_vol`
    fi
    highest_vol_ghash=`expr $good_ghash \* \( 100 - $max_steps \) / 100`

    if [ "$adjust_type" -eq "$ADJUST_BOTH_VOL_AND_FREQ" ]; then
        echo $good_ghash:$sell_ghash:$highest_vol_ghash:$STABLE_SECONDS:$max_vol:$vol_step:$FREQ_STEP
    elif [ "$adjust_type" -eq "$ADJUST_FREQ_ONLY" ]; then
        local MAX_FREQ_ADJUST_TIMES=4
        echo $GOOD_RATIO_PERCENT:$MAX_FREQ_ADJUST_TIMES:0:$STABLE_SECONDS:0:0:$FREQ_STEP
    elif [ "$adjust_type" -eq "$ADJUST_FREQ_AND_THEN_VOL" ]; then
        local GOOD_HASH_PERCENT=90
        local MAX_TOTAL_ADJUST_TIMES=99
        local MAX_VOL_ADJUST_TIMES=2
        echo $GOOD_RATIO_PERCENT:$MAX_TOTAL_ADJUST_TIMES:$GOOD_HASH_PERCENT:$STABLE_SECONDS:$MAX_VOL_ADJUST_TIMES:$vol_step:$FREQ_STEP
    fi
}

get_power_file() {
    local power_file=`readlink /etc/config/powers`

    if [ "${power_file:0:12}" = "powers.m3.v1" ]; then
        power_file="powers.m3.v10"
    elif [ "${power_file:0:12}" = "powers.m3.v2" ]; then
        power_file="powers.m3.v20"
    fi

    if [ -f /tmp/eeprom_data_out ]; then
        source /tmp/eeprom_data_out
        miner_type_lowcase=`echo $miner_type | tr 'A-Z' 'a-z'`
        if [ "$miner_type_lowcase" = "m3" ] && [ "${pcb_version:0:1}" = "2" ]; then
            power_file="powers.m3.v20"
        fi
    fi

    source /usr/bin/miner-detect-common
    if [ "$miner_type" = "M1" ]; then
        if [ "$hash_board_version" = "HB10" ]; then
            power_file="powers.m1.v10"
        elif [ "$hash_board_version" = "HB12" ]; then
            power_file="powers.m1.v12"
        fi
    fi

    echo "$power_file"
}

get_best_vol_freq() {
    local power_file=$1

    if [ ! -d /tmp/config ]; then
        # set default power config for main miners
        mkdir /tmp/config
        echo "000106,28,510" > /tmp/config/powers.m3.v10
        echo "000107,29,540" > /tmp/config/powers.m3.v20
        echo "000107,29,552" > /tmp/config/powers.m1.v20
        echo "000106,14,504" > /tmp/config/powers.m1.v12
        echo "000106,14,504" > /tmp/config/powers.m1.v10
    fi
    echo "/tmp/config/$power_file"
}

first_string_line_num() {
    local string=$1
    local file=$2
    local line=`sed -n "/$string/=" $file | head -1`
    echo $line
}

modify_specified_power_config() {
    local default_power_file="/etc/config/$1"
    local power_version=$2
    local new_value=$3
    local match_lines=`grep ":$power_version:" $default_power_file | wc -l`
    local line

    if [ "$match_lines" -eq 1 ]; then
        line=$(first_string_line_num $power_version $default_power_file)
        local line_copy=`sed -n "${line}p" $default_power_file`
        sed -i "${line}i $line_copy" $default_power_file
    fi

    line=$(first_string_line_num $power_version $default_power_file)
    sed -i "${line}s/:$power_version:.*/:$power_version:$new_value'/" $default_power_file
}

modify_powers_config_with_new_value() {
    local default_power_file=$1
    local power_version=$2
    local new_value=$3

    modify_specified_power_config $default_power_file $power_version $new_value

    if [ "$power_version" = "000106" ]; then
        if [ "$default_power_file" = "powers.default.m3.v10" ]; then
            similar_power="000107"
            modify_specified_power_config $default_power_file $similar_power $new_value
        elif [ "$default_power_file" = "powers.default.m1.v12" ] || [ "$default_power_file" = "powers.default.m1.v10" ]; then
            similar_power="000105"
            modify_specified_power_config $default_power_file $similar_power $new_value
            similar_power="000004"
            modify_specified_power_config $default_power_file $similar_power $new_value
            similar_power="000107"
            modify_specified_power_config $default_power_file $similar_power $new_value
        fi
    fi
}

modify_release_version_by_type() {
    local adjust_type=$1
    if [ "$adjust_type" -eq "$ADJUST_FREQ_AND_THEN_VOL" ]; then 
        sed -i "s/.1'/.A'/" /tmp/upgrade-files/rootfs/etc/microbt_release
    elif [ "$adjust_type" -eq "$ADJUST_FREQ_ONLY" ]; then 
        sed -i "s/.1'/.F'/" /tmp/upgrade-files/rootfs/etc/microbt_release
    fi
}

set_best_power_config_if_needed() {
    local power_file=$(get_power_file)
    local default_power_file=`echo $power_file | sed 's/powers./powers.default./'`
    local best_vol_freq=$(get_best_vol_freq $power_file)
    local ADJUST_TYPE=$ADJUST_FREQ_ONLY

    if [ -f $best_vol_freq ]; then
        local power_version=`cat $best_vol_freq | cut -d ',' -f 1`
        local voltage=`cat $best_vol_freq | cut -d ',' -f 2`
        local freq=`cat $best_vol_freq | cut -d ',' -f 3`
        local new_value="$voltage:$freq:$freq:$freq"

        new_value=$new_value:$ADJUST_TYPE:$(get_auto_adjust_power_params $voltage $freq $ADJUST_TYPE)
        modify_powers_config_with_new_value $default_power_file $power_version $new_value
        restore_to_default_config $default_power_file
        modify_release_version_by_type $ADJUST_TYPE
    fi
}

# Compare two files.
# Return 'no' if these two files are the same,
# else return 'yes'.
diff_files() {
    if [ ! -f $1 -o ! -f $2 ]; then
        echo "yes"
    else
        cmp $1 $2 > /tmp/upgrade-file.diff 2>&1
        DIFF=`cat /tmp/upgrade-file.diff`
        if [ "$DIFF" = "" ]; then
            echo "no"
        else
            echo "yes"
        fi
    fi
}

is_any_file_to_be_modified_or_added() {
    local files=$(find /tmp/upgrade-files/rootfs -type f)
    for srcfile in $files; do
        filename=`echo $srcfile | sed 's/\/tmp\/upgrade-files\/rootfs\///g'`
        dstfile="/$filename"
        DIFF=`diff_files $srcfile $dstfile`
        if [ "$DIFF" = "yes" ]; then
            return 1
        fi
    done

    # voltage may be changed
    if [ -d /tmp/config ]; then
        return 1
    fi

    return 0
}

reset_board0() {
    echo out > /sys/class/gpio/gpio$HASH_RESET_PIN0/direction
    echo 0 > /sys/class/gpio/gpio$HASH_RESET_PIN0/value
}

reset_board1() {
    echo out > /sys/class/gpio/gpio$HASH_RESET_PIN1/direction
    echo 0 > /sys/class/gpio/gpio$HASH_RESET_PIN1/value
}

reset_board2() {
    echo out > /sys/class/gpio/gpio$HASH_RESET_PIN2/direction
    echo 0 > /sys/class/gpio/gpio$HASH_RESET_PIN2/value
}

# /etc/config/system
upgrade_file() {
    local file=$1
    local mode0=$2
    local mode1=$3
    if [ -f /tmp/upgrade-files/rootfs/$file ]; then
        DIFF=`diff_files /tmp/upgrade-files/rootfs/$file $file`
        if [ "$DIFF" = "yes" ]; then
            echo "Upgrading $file"
            chmod $mode0 $file >/dev/null 2>&1
            cp -f /tmp/upgrade-files/rootfs/$file $file
            chmod $mode1 $file # readonly
        fi
    fi
}

upgrade_config_files() {
    local files=$1
    local mode0=$2
    local mode1=$3
    for srcfile in $(find /tmp/upgrade-files/rootfs/etc/config -name "$files")
    do
        filename=`echo $srcfile | sed 's/\/tmp\/upgrade-files\/rootfs\/etc\/config\///g'`
        dstfile="/etc/config/$filename"

        DIFF=`diff_files $srcfile $dstfile`
        if [ "$DIFF" = "yes" ]; then
            echo "Upgrading $dstfile"
            chmod $mode0 $dstfile >/dev/null 2>&1
            cp -f $srcfile $dstfile
            chmod $mode1 $dstfile # readonly
        fi
    done
}

restore_to_default_config() {
    for default_file in $(find /etc/config -name "$1")
    do
        file=`echo $default_file | sed 's/default.//g'`
        DIFF=`diff_files $default_file $file`
        if [ -f $file ] && [ "$DIFF" = "yes" ]; then
            chmod 644 $file >/dev/null 2>&1
            echo "Copy $default_file to $file"
            cp -f $default_file $file
            chmod 444 $file
        fi
    done
}

upgrade_bootloader() {
    local md5
    echo "Upgrading bootloader"
    cd /tmp/upgrade-bin
    ./boot_updater
    if [ -f env.fex ]; then
        cat env.fex > /dev/nandb
    fi

    md5=`md5sum /tmp/upgrade-bin/boot_package.fex | awk '{print $1}'`
    echo $md5 > /etc/uboot.md5
    been_upgraded=1
    cd -
}

rename_files_by_removing_extension() {
    local path=$1
    local extension=$2
    for file in $(find $path -name "*.$extension")
    do
        newfile=`echo $file | sed "s/\.$extension$//"`
        mv $file $newfile
    done
}

remove_files_by_extension() {
    local path=$1
    local extension=$2
    if [ -d $path ]; then
        find $path -name "*.$extension" | xargs rm -f
    fi
}

log_upgrading() {
    local old_version=`cat /etc/microbt_release | grep FIRMWARE_VERSION | awk -F '=' '{print $2}'`
    local new_version=`cat /tmp/upgrade-files/rootfs/etc/microbt_release | grep FIRMWARE_VERSION | awk -F '=' '{print $2}'`
    local tmp_log="/tmp/miner-state.log"
    if [ -f $tmp_log ]; then
        echo "Upgrade firmware from $old_version to $new_version" >> $tmp_log
    fi
}

#
# Prepare rootfs
#
if [ "$is_allwinner_platform" = true ]; then
    # remove useless files;
    rm -f /tmp/upgrade-bin/devicetree.dtb
    rm -f /tmp/upgrade-files/packages/*
    rm -f /tmp/upgrade-files/rootfs/usr/bin/aging_test.allwinner
    rm -f /tmp/upgrade-files/rootfs/etc/init.d/agingtest.allwinner
    rm -f /tmp/upgrade-files/rootfs/usr/bin/phonixtest.allwinner
    rm -f /tmp/upgrade-files/rootfs/etc/init.d/phonixtest.allwinner

    rename_files_by_removing_extension /tmp/upgrade-files/rootfs "allwinner"

    if [ "$CONTROL_BOARD_PLATFORM" = "ALLWINNER_H3" ]; then
        rename_files_by_removing_extension /tmp/upgrade-bin "h3"
        remove_files_by_extension /tmp/upgrade-bin "h8"
    else
        rename_files_by_removing_extension /tmp/upgrade-bin "h8"
        remove_files_by_extension /tmp/upgrade-bin "h3"
    fi

    # for recovering kernel partition if corrupted
    mkdir -p /tmp/upgrade-files/rootfs/root/
    cp /tmp/upgrade-bin/kernel.fex /tmp/upgrade-files/rootfs/root/

else
    # ZYNQ: 1) remove useless files for allwinner
    rm -f `ls /tmp/upgrade-bin/* | grep -v devicetree.dtb`
    remove_files_by_extension /tmp/upgrade-files/rootfs "allwinner"
fi

#
# 1. Verify and upgrade /tmp/upgrade-bin/*
#


been_upgraded=0

# kernel (mtd4 for ZYNQ)
if [ -f /tmp/upgrade-bin/uImage ]; then
    # verify with mtd data
    mtd verify /tmp/upgrade-bin/uImage /dev/mtd4 2>/tmp/.mtd-verify-stderr.txt
    result_success=`cat /tmp/.mtd-verify-stderr.txt | grep Success`
    if [ "$result_success" != "Success" ]; then
        # upgrade to mtd
        echo "Upgrading kernel.bin to /dev/mtd4"
        mtd erase /dev/mtd4
        mtd write /tmp/upgrade-bin/uImage /dev/mtd4
        been_upgraded=1
    fi
fi

# kernel (for allwinner)
osrelease=`cat /proc/sys/kernel/osrelease`
if [ -f /tmp/upgrade-bin/kernel.fex ]; then
    if [ -e /dev/nandc ]; then
        kernel_dev=/dev/nandc
        kernel_dev_bak=/dev/nande
    else
        kernel_dev=/dev/mmcblk0p6
        kernel_dev_bak=/dev/mmcblk0p8
    fi
    new_md5=`md5sum /tmp/upgrade-bin/kernel.fex | awk '{print $1}'`
    if [ "`cat /etc/kernel.md5`" != "$new_md5" ]; then
        echo "Upgrading kernel.fex to $kernel_dev and $kernel_dev_bak"
        cat /tmp/upgrade-bin/kernel.fex > $kernel_dev
        cat /tmp/upgrade-bin/kernel.fex > $kernel_dev_bak
        echo $new_md5 > /etc/kernel.md5
        been_upgraded=1

        # Save mac to file for the old board which mac hasn't been written into secure storage,
        # and it will be write to secure storage under linux4.4 when sst hasn't mac, and then will
        # be removed.
        mac=`ifconfig eth0 | grep HWaddr | cut -b 39-55`
        if [ "$osrelease" = "3.4.39" ] && [ "${mac:0:2}" = "C0" ]; then
            echo "Save $mac to /etc/mac"
            echo $mac > /etc/mac
        fi
    fi
fi

# devicetree (mtd5)
if [ -f /tmp/upgrade-bin/devicetree.dtb ]; then
    # verify with mtd data
    mtd verify /tmp/upgrade-bin/devicetree.dtb /dev/mtd5 2>/tmp/.mtd-verify-stderr.txt
    result_success=`cat /tmp/.mtd-verify-stderr.txt | grep Success`
    if [ "$result_success" != "Success" ]; then
        # upgrade to mtd
        echo "Upgrading devicetree.bin to /dev/mtd5"
        mtd erase /dev/mtd5
        mtd write /tmp/upgrade-bin/devicetree.dtb /dev/mtd5
        been_upgraded=1
    fi
fi

#update bootloader
if [ "$osrelease" = "3.4.39" ]; then
    # upgrade for linux4.4
    upgrade_bootloader
fi

if [ -f /tmp/upgrade-bin/boot_package.fex ]; then
    md5=`md5sum /tmp/upgrade-bin/boot_package.fex | awk '{print $1}'`
    if [ "`cat /etc/uboot.md5`" != "$md5" ]; then
        upgrade_bootloader
    fi
fi

#
# 2. Upgrade /tmp/upgrade-rootfs/
#
if [ -d /tmp/upgrade-rootfs ]; then
    echo "Upgrading rootfs ..."

    rm -fr /usr/lib/lua

    if [ "$is_allwinner_platform" = true ]; then
        # /etc is a link
        cp -afr /tmp/upgrade-rootfs/allwinner-rootfs/etc/* /etc/
        rm -rf /tmp/upgrade-rootfs/allwinner-rootfs/etc/
        cp -afr /tmp/upgrade-rootfs/allwinner-rootfs/* /
    else
        cp -afr /tmp/upgrade-rootfs/zynq-rootfs/* /
    fi

    restore_to_default_config "cgminer.default.*"
    restore_to_default_config "powers.default.*"

    # Change owner
    chown root:root / -R >/dev/null 2>&1

    # Confirm file attributes again
    chmod 555 /usr/bin/cgminer
    chmod 555 /usr/bin/cgminer-api
    chmod 555 /usr/bin/cgminer-monitor
    chmod 555 /usr/bin/miner-detect-common
    chmod 555 /usr/bin/detect-miner-info
    chmod 555 /usr/bin/detect-voltage-info
    chmod 555 /usr/bin/lua-detect-version
    chmod 555 /usr/bin/keyd
    chmod 555 /usr/bin/readpower
    chmod 555 /usr/bin/setpower
    chmod 555 /usr/bin/system-monitor
    chmod 555 /usr/bin/remote-daemon
    chmod 555 /etc/init.d/boot
    chmod 555 /etc/init.d/cgminer
    chmod 555 /etc/init.d/detect-cgminer-config
    chmod 555 /etc/init.d/remote-daemon
    chmod 555 /etc/init.d/system-monitor
    chmod 555 /etc/init.d/sdcard-upgrade
    chmod 555 /bin/bitmicro-test
    chmod 444 /etc/microbt_release

    echo "Done, reboot control board ..."

    # reboot or sync may be blocked under some conditions
    # so we call 'reboot -n -f' background to force rebooting
    # after sleep timeout
    sleep 20 && reboot -n -f &

    sync
    mount /dev/root -o remount,ro >/dev/null 2>&1
    reboot
    exit 1
fi

is_any_file_to_be_modified_or_added
if [ $? -eq 0 ] && [ "$been_upgraded" -ne 1 ]; then
    echo "No file has been updated, do nothing."
    mount /dev/root -o remount,ro >/dev/null 2>&1
    exit 0
fi

#
# 3. Upgrade /tmp/upgrade-files/
#

echo "Upgrading files ..."

upgrade_file /etc/config/system 644 444
upgrade_file /etc/config/uhttpd 644 444
upgrade_file /etc/config/luci 644 444
upgrade_file /usr/bin/detect-platform.sh 755 555
upgrade_file /usr/bin/miner-detect-common 755 555
upgrade_file /usr/bin/miner-detect-by-legacy 755 555
upgrade_file /usr/bin/detect-eeprom-data 755 555
upgrade_file /usr/bin/detect-miner-info 755 555

upgrade_config_files "powers.*" 644 444
restore_to_default_config "powers.default.*"

if [ ! -f /tmp/upgrade-files/factory_mode ]; then
    set_best_power_config_if_needed
fi

upgrade_config_files "fans.*" 644 444

upgrade_file /etc/config/temp_overheat_limit 644 444
upgrade_file /etc/config/network.default 644 444
upgrade_file /etc/config/pools.default 644 444

# /etc/config/pools
if [ ! -f /etc/config/pools ]; then
    echo "Upgrading /etc/config/pools"

    # Special handling. Reserve user pools configuration
    # /etc/config/cgminer -> /etc/config/pools
    fromfile="/etc/config/cgminer"
    tofile="/etc/config/pools"
    echo "" > $tofile
    echo "config pools 'default'" >> $tofile

    line=`cat $fromfile | grep "ntp_enable"`
    echo "$line" >> $tofile
    line=`cat $fromfile | grep "ntp_pools"`
    echo "$line" >> $tofile

    line=`cat $fromfile | grep "pool1url"`
    echo "$line" >> $tofile
    line=`cat $fromfile | grep "pool1user"`
    echo "$line" >> $tofile
    line=`cat $fromfile | grep "pool1pw"`
    echo "$line" >> $tofile

    line=`cat $fromfile | grep "pool2url"`
    echo "$line" >> $tofile
    line=`cat $fromfile | grep "pool2user"`
    echo "$line" >> $tofile
    line=`cat $fromfile | grep "pool2pw"`
    echo "$line" >> $tofile

    line=`cat $fromfile | grep "pool3url"`
    echo "$line" >> $tofile
    line=`cat $fromfile | grep "pool3user"`
    echo "$line" >> $tofile
    line=`cat $fromfile | grep "pool3pw"`
    echo "$line" >> $tofile

    chmod 644 /etc/config/pools
fi

# Upgrade /etc/config/cgminer after updating pools
upgrade_config_files "cgminer.*" 644 444
restore_to_default_config "cgminer.default.*"

upgrade_file /etc/init.d/boot 755 555
upgrade_file /etc/init.d/detect-cgminer-config 755 555
upgrade_file /etc/crontabs/root 644 444
upgrade_file /etc/init.d/cgminer 755 555
upgrade_file /etc/init.d/system-monitor 755 555
upgrade_file /etc/init.d/sdcard-upgrade 755 555
upgrade_file /etc/init.d/remote-daemon 755 555
upgrade_file /usr/bin/cgminer 755 555
upgrade_file /usr/bin/cgminer-api 755 555
upgrade_file /usr/bin/cgminer-monitor 755 555
upgrade_file /usr/bin/system-monitor 755 555
upgrade_file /usr/bin/setpower 755 555
upgrade_file /usr/bin/readpower 755 555
upgrade_file /usr/bin/keyd 755 555
upgrade_file /usr/bin/watchdog 755 555
upgrade_file /usr/bin/securezone 755 555
upgrade_file /usr/bin/remote-daemon 755 555
upgrade_file /usr/bin/detect-voltage-info 755 555
upgrade_file /usr/bin/lua-detect-version 755 555

# /usr/lib/lua
if [ -d /tmp/upgrade-files/rootfs/usr/lib/lua ]; then
    if [ -d /usr/lib/lua ]; then
        cd /tmp/upgrade-files/rootfs/usr/lib/lua
        find ./ -type f -print0 | xargs -0 md5sum | sort > /tmp/lua-md5sum-new.txt
        cd /usr/lib/lua
        find ./ -type f -print0 | xargs -0 md5sum | sort > /tmp/lua-md5sum-cur.txt
        DIFF=`cmp /tmp/lua-md5sum-new.txt /tmp/lua-md5sum-cur.txt`
        if [ "$DIFF" != "" ]; then
            echo "Upgrading /usr/lib/lua"
            rm -fr /usr/lib/lua
            cp -afr /tmp/upgrade-files/rootfs/usr/lib/lua /usr/lib/
        fi
    else
        echo "Upgrading /usr/lib/lua"
        rm -fr /usr/lib/lua
        cp -afr /tmp/upgrade-files/rootfs/usr/lib/lua /usr/lib/
    fi
fi

upgrade_file /bin/detect-chip-num 755 555
upgrade_file /bin/detect-dev-tty 755 555
upgrade_file /bin/get-chip-num 755 555
upgrade_file /bin/set-chip-num 755 555
upgrade_file /bin/bitmicro-test 755 555
upgrade_file /bin/test-readchipid 755 555
upgrade_file /bin/test-sendgoldenwork 755 555
upgrade_file /bin/test-hashboard 755 555
upgrade_file /bin/test-core-one-by-one 755 555
upgrade_file /usr/bin/pre-reboot 755 555
upgrade_file /usr/bin/restore-factory-settings 755 555
upgrade_file /etc/shadow 755 555
upgrade_file /etc/shadow.default 755 555
upgrade_file /etc/rc.common 644 444
upgrade_file /etc/profile 644 444
upgrade_file /usr/bin/log-cpu-overheat 755 555
upgrade_file /usr/bin/write-eeprom-data 755 555
upgrade_file /root/kernel.fex 644 444

# Remove unused files
if [ -f /etc/cpuinfo_sun8i ]; then
    rm -f /etc/cpuinfo_sun8i
fi
if [ -f /etc/config/firewall ]; then
    rm -f /etc/config/firewall
fi
if [ -f /etc/init.d/om-watchdog ]; then
    rm -f /etc/init.d/om-watchdog
fi
if [ -f /etc/rc.d/S11om-watchdog ]; then
    rm -f /etc/rc.d/S11om-watchdog
fi
if [ -f /etc/rc.d/K11om-watchdog ]; then
    rm -f /etc/rc.d/K11om-watchdog
fi

if [ -f /etc/rc.d/S90temp-monitor ]; then
    rm -f /etc/rc.d/S90temp-monitor
fi
if [ -f /etc/init.d/temp-monitor ]; then
    rm -f /etc/init.d/temp-monitor
fi
if [ -f /usr/bin/temp-monitor ]; then
    rm -f /usr/bin/temp-monitor
fi

if [ -f /usr/bin/phonixtest ]; then
    rm -f /usr/bin/phonixtest
fi

if [ -f /usr/bin/remote-update-cgminer ]; then
    rm -f /usr/bin/remote-update-cgminer
fi

if [ -f /etc/init.d/boot.bak ]; then
    rm -f /etc/init.d/boot.bak
fi

if [ -f /etc/config/powers.hash10 ]; then
    rm -f /etc/config/powers.hash10
fi
if [ -f /etc/config/powers.hash12 ]; then
    rm -f /etc/config/powers.hash12
fi
if [ -f /etc/config/powers.hash20 ]; then
    rm -f /etc/config/powers.hash20
fi
if [ -f /etc/config/powers.alb10 ]; then
    rm -f /etc/config/powers.alb10
fi
if [ -f /etc/config/powers.alb20 ]; then
    rm -f /etc/config/powers.alb20
fi

if [ -f /etc/config/cgminer.hash10 ]; then
    rm -f /etc/config/cgminer.hash10
fi
if [ -f /etc/config/cgminer.hash12 ]; then
    rm -f /etc/config/cgminer.hash12
fi
if [ -f /etc/config/cgminer.hash20 ]; then
    rm -f /etc/config/cgminer.hash20
fi
if [ -f /etc/config/cgminer.alb10 ]; then
    rm -f /etc/config/cgminer.alb10
fi
if [ -f /etc/config/cgminer.alb20 ]; then
    rm -f /etc/config/cgminer.alb20
fi

if [ -f /etc/config/cgminer.default.hash10 ]; then
    rm -f /etc/config/cgminer.default.hash10
fi
if [ -f /etc/config/cgminer.default.hash12 ]; then
    rm -f /etc/config/cgminer.default.hash12
fi
if [ -f /etc/config/cgminer.default.hash20 ]; then
    rm -f /etc/config/cgminer.default.hash20
fi
if [ -f /etc/config/cgminer.default.alb10 ]; then
    rm -f /etc/config/cgminer.default.alb10
fi
if [ -f /etc/config/cgminer.default.alb20 ]; then
    rm -f /etc/config/cgminer.default.alb20
fi

if [ -f /etc/config/powers.m3 ]; then
    rm -f /etc/config/powers.m3
fi
if [ -f /etc/config/powers.default.m3 ]; then
    rm -f /etc/config/powers.default.m3
fi
if [ -f /etc/config/powers.m3f ]; then
    rm -f /etc/config/powers.m3f
fi
if [ -f /etc/config/powers.default.m3f ]; then
    rm -f /etc/config/powers.default.m3f
fi
if [ -f /etc/config/cgminer.m3 ]; then
    rm -f /etc/config/cgminer.m3
fi
if [ -f /etc/config/cgminer.default.m3 ]; then
    rm -f /etc/config/cgminer.default.m3
fi
if [ -f /etc/config/cgminer.m3f ]; then
    rm -f /etc/config/cgminer.m3f
fi
if [ -f /etc/config/cgminer.default.m3f ]; then
    rm -f /etc/config/cgminer.default.m3f
fi

if [ -f /etc/config/firewall.unused ]; then
    rm -f /etc/config/firewall.unused
fi

if [ -f /bin/test-core-send-work-one-by-one ]; then
    rm -f /bin/test-core-send-work-one-by-one
fi

find /etc/config/ -name "*m3.v11*" | xargs rm -f
find /etc/config/ -name "*m3.v14*" | xargs rm -f

if [ -f /etc/rc.d/S98sysntpd ]; then
    rm -f /etc/rc.d/S98sysntpd
fi

# Don't remount /dev/root rw for allwinner
upgrade_file /lib/preinit/80_mount_root 755 555

# Make allwinner start up faster
upgrade_file /lib/preinit/01_preinit_sunxi.sh 755 555
upgrade_file /lib/preinit/30_failsafe_wait 755 555

upgrade_file /usr/bin/upgrade.sh 755 555
upgrade_file /etc/microbt_release 644 444

log_upgrading

#
# Kill services
#
killall -9 crond >/dev/null 2>&1
killall -9 system-monitor >/dev/null 2>&1
killall -9 temp-monitor >/dev/null 2>&1
killall -9 keyd >/dev/null 2>&1
killall -9 cgminer >/dev/null 2>&1
killall -9 uhttpd >/dev/null 2>&1
killall -9 ntpd >/dev/null 2>&1
killall -9 udevd >/dev/null 2>&1

# Make power consumption lower, so reboot operation may be more stable
reset_board0
sleep 1
reset_board1
sleep 1
reset_board2
sleep 1

echo "Done, reboot control board ..."
source /usr/bin/pre-reboot
reboot
