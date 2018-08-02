#!/bin/sh

cpuinfo_zynq=`cat /proc/cpuinfo | grep "Xilinx Zynq"`
cpuinfo_allwinner=`cat /proc/cpuinfo | grep -i sun`
is_allwinner_h8=`echo $cpuinfo_allwinner | grep sun8iw6`
is_allwinner_h6=`echo $cpuinfo_allwinner | grep sun50iw6`

if [ "$cpuinfo_allwinner" != "" ]; then
	if [ "$is_allwinner_h8" != "" ]; then
		export CONTROL_BOARD_PLATFORM="ALLWINNER_H8"
	elif [ "$is_allwinner_h6" != "" ]; then
		export CONTROL_BOARD_PLATFORM="ALLWINNER_H6"
	else
		export CONTROL_BOARD_PLATFORM="ALLWINNER_H3"
	fi
elif [ "$cpuinfo_zynq" != "" ]; then
	export CONTROL_BOARD_PLATFORM="ZYNQ"
else
	export CONTROL_BOARD_PLATFORM="unknown"
fi

if [ "$CONTROL_BOARD_PLATFORM" = "ALLWINNER_H3" ]; then
	export RED_LED_PIN=102
	export GREEN_LED_PIN=103
	export GET_IP_KEY_PIN=10
	export RESET_KEY_PIN=9
	export WATCHDOG_FEED_PIN=363
	# Hash board SM0
	export HASH_PLUG_PIN0=15
	export HASH_ENABLE_PIN0=96
	export HASH_RESET_PIN0=99
	# Hash board SM1
	export HASH_PLUG_PIN1=7
	export HASH_ENABLE_PIN1=97
	export HASH_RESET_PIN1=100
	# Hash board SM2
	export HASH_PLUG_PIN2=8
	export HASH_ENABLE_PIN2=98
	export HASH_RESET_PIN2=101

elif [ "$CONTROL_BOARD_PLATFORM" = "ALLWINNER_H8" ]; then
	export RED_LED_PIN=193
	export GREEN_LED_PIN=194
	export GET_IP_KEY_PIN=192
	export RESET_KEY_PIN=361
	export WATCHDOG_FEED_PIN=359
	# Hash board SM0
	export HASH_PLUG_PIN0=234
	export HASH_ENABLE_PIN0=233
	export HASH_RESET_PIN0=235
	# Hash board SM1
	export HASH_PLUG_PIN1=35
	export HASH_ENABLE_PIN1=34
	export HASH_RESET_PIN1=36
	# Hash board SM2
	export HASH_PLUG_PIN2=231
	export HASH_ENABLE_PIN2=230
	export HASH_RESET_PIN2=232

elif [ "$CONTROL_BOARD_PLATFORM" = "ALLWINNER_H6" ]; then
	export RED_LED_PIN=233
	export GREEN_LED_PIN=234
	export GET_IP_KEY_PIN=232
	export RESET_KEY_PIN=358
	# Hash board SM0
	export HASH_PLUG_PIN0=196
	export HASH_ENABLE_PIN0=195
	export HASH_RESET_PIN0=197
	# Hash board SM1
	export HASH_PLUG_PIN1=201
	export HASH_ENABLE_PIN1=200
	export HASH_RESET_PIN1=202
	# Hash board SM2
	export HASH_PLUG_PIN2=193
	export HASH_ENABLE_PIN2=192
	export HASH_RESET_PIN2=194

elif [ "$CONTROL_BOARD_PLATFORM" = "ZYNQ" ]; then
	export RED_LED_PIN=943
	export GREEN_LED_PIN=944
	export GET_IP_KEY_PIN=957
	export RESET_KEY_PIN=953
	# Hash board SM0
	export HASH_PLUG_PIN0=961
	export HASH_ENABLE_PIN0=934
	export HASH_RESET_PIN0=960
	# Hash board SM1
	export HASH_PLUG_PIN1=963
	export HASH_ENABLE_PIN1=939
	export HASH_RESET_PIN1=962
	# Hash board SM2
	export HASH_PLUG_PIN2=965
	export HASH_ENABLE_PIN2=937
	export HASH_RESET_PIN2=964
fi
