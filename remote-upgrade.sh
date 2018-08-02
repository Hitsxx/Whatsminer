#!/bin/bash
#
# Remote upgrade script.
# MicroBT.
#

if [ $# -lt 2 ] ;then
    echo "Usage: $0 <upgrade-package-file> <ip-list-file>"
    echo "Example:$0 upgrade.tgz IP.txt"
    exit 0;
fi

firmware=$1
ipfile=$2

if [ ! -f "$firmware" ]; then
    echo "Can not find firmware file: $firmware"
    exit 0;
fi
if [ ! -f "$ipfile" ]; then
    echo "Can not find IP file: $ipfile"
    exit 0;
fi

echo -n "Confirm to continue? [Y/n] "
read act
if [ "$act" = "" ]; then
    act="Y"
fi
if [ "$act" != "Y" -a "$act" != "y" ]; then
    exit 1
fi

# Usage: sendfile $ip $localfile $remotefile
sendfile() {
    expect -c "
        set timeout 90;
        spawn scp $2 root@$1:$3
        expect {
        \"*yes/no*\" {send \"yes\r\"; exp_continue}
        \"*password*\" {send \"root\r\";}
        }
        expect eof;"
}

# Usage: execcmd $ip $cmd
execcmd() {
    expect -c "
        set timeout 90;
        spawn ssh root@$1 $2
        expect {
        \"*yes/no*\" {send \"yes\r\"; exp_continue}
        \"*password*\" {send \"root\r\";}
        }
        expect eof;"
}

rm -f result-ip-ok.txt
rm -f result-ip-skipped.txt
touch result-ip-ok.txt
touch result-ip-skipped.txt

for ip in `cat $ipfile`
do
    # trim
    ip=`echo "$ip" | grep -o "[^ ]\+\( \+[^ ]\+\)*"`

    ping -c 1 -W 2 $ip &> /dev/null
    if [ $? -eq 0 ]; then
        echo "*******************************************************************************"
        echo "Upgrading $ip"
        echo "*******************************************************************************"

        sendfile $ip $firmware "/tmp/"
        execcmd $ip "tar xzf /tmp/$firmware -C /tmp"
        execcmd $ip "/tmp/upgrade.sh"
        echo "$ip upgraded" >> result-ip-ok.txt
    else
        echo "*******************************************************************************"
        echo "Skipped $ip"
        echo "*******************************************************************************"
        echo "$ip skipped" >> result-ip-skipped.txt
    fi
done
