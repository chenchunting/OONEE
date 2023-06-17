#!/bin/bash

########################################################
#   global
########################################################
declare -r RETURN="OPCi_R"
declare -r SUCC="OPCi_R_Succ"
declare -r FAIL="OPCi_R_Fail"

declare -r GUID=a0999a12-8bbe-4255-ac0b-9534193407e7
declare -r BIOS_GUID=801ba4e1-8970-46c6-ab25-ccdc948ddedb


# PWM range:
# 3SM     PWM min 6%  (937Hz, range:0~20491)
# CC48SM  PWM min 6%  (1KHz, range:0~19200)
# QSMR211 PWM min 4%  (1.8KHz, range:0~1067)
# QSM     PWM min 4%  (1.8KHz, range:0~1067)
# 8Ui     NULL
# 6XT4    PWM min 12%  (3750Hz, range:0~5120)

# PART_LIST:
#   "PartNumber__SensorPositionListAry__BootOrientation__PanelID__MinPWM__MaxNits__MinNits" 
declare -r PART_LIST=(
    "VEN032FSNWM00__0__left__lg_1080p_video__1229__880__780"        #3SM
    "VEN048CSVWM00__0__normal__hdmi_cc48sm?147__1152__605__495"     #CC48SM
    "VEN026QSNWM50__0__right__lg_square_video__43__450__350"        #QSM_R211
    "VEN026QSNWM00__0__right__lg_square_video__43__460__400"        #QSM
    "VEN075ULPWB10__0__sensor__hdmi_pd75?128__NULL__4450__4250"     #8U2i 110V
    "VEN075ULPWB20__0__sensor__hdmi_pd75?128__NULL__4450__4250"     #8U2i 277V
    "O754000TGLUP3__1__sensor__hdmi_pd75?128__NULL__4500__3600"     #TGLUP3 OPCi2
)
   #"xxxxxxxxxxxxxx_0__sensor__hdmi_mstar2?128__NULL__???__???"     # 6XT

declare -r SENSOR_POSITION_LIST=(
    "ACCEL_MOUNT_MATRIX=-1,0,0;0,1,0;0,0,1"  # sensor_position[0]
    "ACCEL_MOUNT_MATRIX=1,0,0;0,-1,0;0,0,1"   # sensor_position[1] for TGLUP3
)

declare -r BUS_TABLE=(
    "0000:00:10.0|1"
    "0000:00:15.0|2"
    "0000:00:15.1|3"
    "0000:00:15.2|4"
    "0000:00:19.0|5"
    "0000:00:19.1|6"
)

declare -r LOGDIR="/var/log"

timestart=$(date +"%s.%N")
REBOOT_LATER=0

########################################################
#   internal 
########################################################
log()
{
    local message=$*
    local timeend=$(date +"%s.%N")
    local runtime=$(echo "${timeend}-${timestart}" | bc -l)
    local logfile="${LOGDIR}/$(basename $0).log"
    echo -n "$(date +'%F %H:%M:%S')| ${runtime} | ${ARG_ALL} | " >> $logfile
    echo $message | tee -a $logfile

    if [[ $message == *"${FAIL}"* ]]; then
        exit -1
    else
        if [ $REBOOT_LATER -eq 0 ]; then
            exit 0
        fi
    fi
}

gcd()
{
    local a=$1
    local b=$2
    if [ $b -eq 0 ]; then
        echo $a
    else
        c=$(($a%$b))
        gcd $b $c
    fi
}

set_efivar()
{
    local name=$1
    local value=$2
    local ret=1

    if [ $# -eq 2 ]; then
        if [ ! -f "/sys/firmware/efi/efivars/${name}-${GUID}" ]; then
            touch /sys/firmware/efi/efivars/${name}-${GUID}
        fi
        chattr -i /sys/firmware/efi/efivars/${name}-${GUID}
        printf "\x07\x00\x00\x00"${value} > /sys/firmware/efi/efivars/${name}-${GUID}
        chattr +i /sys/firmware/efi/efivars/${name}-${GUID}

        if [ "$(tr -d '\0\a' < /sys/firmware/efi/efivars/${name}-${GUID})" = "${value}" ]; then
            ret=0
        fi
    fi
    return $ret
}

get_efivar()
{
    local name=$1
    local ret=""
    if [ $# -eq 1 ]; then
        if [ -f "/sys/firmware/efi/efivars/${name}-${GUID}" ]; then
            ret=$(tr -d '\0\a' < "/sys/firmware/efi/efivars/${name}-${GUID}")
        fi
    fi
    echo "${ret}"
}



########################################################
#   factory command 
########################################################
ECB600_COOLER_STATUS()
{
    if [ -z "$1" ]; then
        echo "Please input Cooler ID"
        rec_return=$FAIL
    else
        ECB600_MCU_test -c $1 0 0
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

ECB600_COOLER_TEST()
{
    local id=$1
    local val=$2
    if [ -z "$id" ]; then
        echo "Please input Cooler ID (0~3)"
        rec_return=$FAIL
    elif [ -z "$val" ]; then
        echo "Please input switch"
        rec_return=$FAIL
    else
        ECB600_MCU_test -c $id 1 $val
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

#usage: sudo OONEE_tool.sh 8U_ECB600_DEBUG [CMD] [P0] [P1] [P2] [P3] [P4]
ECB600_DEBUG()
{
    ECB600_MCU_test -u $1 $2 $3 $4 $5 $6
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

ECB600_DOOR_TEST()
{
    ECB600_MCU_test -d
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

# usage: sudo OONEE_tool.sh 8U_ECB600_ENVTABLE_GET <OFFSET_H> <OFFSET_L>
ECB600_ENVTABLE_GET()
{
    local offset_h=$1
    local offset_l=$2
    if [ -z "$offset_h" ]; then
        echo "Please input offset_H"
        rec_return=$FAIL
    elif [ -z "$offset_l" ]; then
        echo "Please input offset_L"
        rec_return=$FAIL
    else
        ECB600_MCU_test -j $offset_h $offset_l
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
      log $rec_return
}

ECB600_ENV_ERRREPORT_STATUS()
{
    ECB600_MCU_test -l 0 0
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

ECB600_ENV_ERRREPORT_TEST()
{
    if [ -z "$1" ]; then
        echo "Please input switch"
        rec_return=$fFAIL
    else
        ECB600_MCU_test -l 1 $1
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

ECB600_ENV_STATUS()
{
    ECB600_MCU_test -e 0 0
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

ECB600_ENV_TEST()
{
    if [ -z "$1" ]; then
        echo "Please input switch"
        rec_return=$FAIL
    else
        ECB600_MCU_test -e 1 $1
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

# usage:  sudo OONEE_tool.sh 8U_ECB600_FANHUB_STATUS <PORT> <ID> <BOTTOM_RPM> <TOP_RPM>
ECB600_FANHUB_STATUS()
{
    local fan_hub=$1
    local fan_id=$2
    local bottom_rpm=$3
    local top_rpm=$4
    if [ -z "$fan_hub" ]; then
        echo "Please input Fan Hub port (1~4)"
        rec_return=$FAIL
    elif [ -z "$fan_id" ]; then
        echo "Please input Fan ID (1~6)"
        rec_return=$FAIL
    elif [ -z "$bottom_rpm" ]; then
        echo "Please input bottom of RPM"
        rec_return=$FAIL
    elif [ -z "$top_rpm" ]; then
        echo "Please input top of RPM"
        rec_return=$FAIL
    else
        ECB600_MCU_test -r $fan_hub $fan_id $bottom_rpm $top_rpm
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

# usage: sudo OONEE_tool.sh 8U_ECB600_FANHUB_TEST <PORT> <ID> <PWM>
ECB600_FANHUB_TEST()
{
    local fan_hub=$1
    local fan_id=$2
    local rpm=$3
    if [ -z "$fan_hub" ]; then
        echo "Please input Fan Hub port (1~4)"
        rec_return=$FAIL
    elif [ -z "$fan_id" ]; then
        echo "Please input Fan ID (1~6)"
        rec_return=$FAIL
    elif [ -z "$rpm" ]; then
        echo "Please input Fan RPM (0~100)"
        rec_return=$FAIL
    else
        ECB600_MCU_test -f $fan_hub $fan_id $rpm
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

ECB600_FAULT_PIN()
{
    # LED_DRIVER_FAULT#= GPP_B21/GSPI1_MISO
    # 21-0+152 = 173
    local fault_pin=173
    echo $fault_pin > /sys/class/gpio/export
    GPIO_3=$(cat /sys/class/gpio/gpio${fault_pin}/value)
    echo $fault_pin > /sys/class/gpio/unexport
    if [ $GPIO_3 -eq 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

ECB600_HEATER_STATUS()
{
	if [ -z "$1" ]; then
		echo "Please input Heater ID"
		rec_return=$FAIL
	else
		ECB600_MCU_test -h $1 0 0
		if [ $? = 0 ]; then
			rec_return=$SUCC
		else
			rec_return=$FAIL
		fi
	fi
	log $rec_return
}

ECB600_HEATER_TEST()
{
	local id=$1
	local val=$2
	if [ -z "$id" ]; then
		echo "Please input Heater ID (0~2)"
		rec_return=$FAIL
	elif [ -z "$val" ]; then
		echo "Please input switch"
		rec_return=$FAIL
	else
		ECB600_MCU_test -h $id 1 $val
		if [ $? = 0 ]; then
			rec_return=$SUCC
		else
			rec_return=$FAIL
		fi
	fi
	log $rec_return
}

# usage: sudo OONEE_tool.sh 8U_ECB600_I2C_READ  <ADDRESS> <REGISTER>
ECB600_I2C_READ()
{
    if [ -z "$1" ]; then
        echo "Please input i2c addr"
        rec_return=$FAIL
    elif [ -z "$2" ]; then
        echo "Please input Device Register"
        rec_return=$FAIL
    else
        ECB600_MCU_test -s $1 $2
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

# usage: sudo OONEE_tool.sh 8U_ECB600_I2C_WRITE  <ADDRESS> <REGISTER> <DATA>
ECB600_I2C_WRITE()
{
    if [ -z "$1" ]; then
        echo "Please input i2c addr"
        rec_return=$FAIL
    elif [ -z "$2" ]; then
        echo "Please input Device Register"
        rec_return=$FAIL
    elif [ -z "$3" ]; then
        echo "Please input data"
        rec_return=$FAIL
    else
        ECB600_MCU_test -x $1 $2 $3
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

ECB600_I2CEXT_STATUS()
{
    ECB600_MCU_test -i 0 0
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

ECB600_I2CEXT_TEST()
{
    if [ -z "$1" ]; then
        echo "Please input switch"
        rec_return=$FAIL
    else
        ECB600_MCU_test -i 1 $1
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

ECB600_MCU_LDROM_VERSION_GET()
{
	USBPATH=/sys/bus/usb/devices/3-2
	PID=`cat ${USBPATH}/idProduct`
	if [ "${PID}" = "23a3" ]; then
	   pl2303gcgpio -g 0 -o 1
	else
	   pl2303gpio -g 0 -o 1
	fi
	sleep 0.5
    MCU_Update -i > /dev/null 2>&1
    if [ "$?" = "0" ]; then
        MCU_Update -v
        if [ "$?" != "0" ]; then
            rec_return=$FAIL
        fi
        MCU_Update -a > /dev/null 2>&1
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

ECB600_MCU_RESET()
{
    ECB600_MCU_test -m
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

ECB600_MCU_VERSION_GET()
{
    ECB600_MCU_test -v
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

ECB600_MCU_UPDATE_APR()
{
    if [ -z "$1" ]; then
        echo "Please input path of aprom bin file"
        rec_return=$FAIL
    else
        MCU_Update -i
        if [ "$?" = "0" ]; then
            MCU_Update -u $1
            if [ $? = 0 ]; then
                rec_return=$SUCC
            else
                rec_return=$FAIL
            fi
        else
            echo "MCU_Update aprom failed"
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

ECB600_MCU_UPDATE_ENV()
{
    if [ -z "$1" ]; then
        echo "Please input path of ENV bin file"
        rec_return=$FAIL
    else
        MCU_Update -i
        if [ "$?" = "0" ]; then
            MCU_Update -c
            MCU_Update -s $1
            MCU_Update -a
            rec_return=$SUCC
        else
            echo "MCU_Update env-data failed"
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

ECB600_MCU_UPDATE_FAC()
{
    if [ -z "$1" ]; then
        echo "Please input path of aprom-factory bin file"
        rec_return=$FAIL
    else
        MCU_Update -i
        if [ "$?" = "0" ]; then
            MCU_Update -c
            MCU_Update -F $1
            MCU_Update -a
            rec_return=$SUCC
        else
            echo "MCU_Update aprom-factory failed"
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

# = B46U_PRT_AMT_STATUS
ECB600_PCBA_HEATER_STATUS()
{
    ECB600_MCU_test -A 0 0
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

# = B46U_PRT_AMT_TEST
ECB600_PCBA_HEATER_TEST()
{
    if [ -z "$1" ]; then
        echo "Please input 0:off/1:on"
        exit 1
    fi
    ECB600_MCU_test -A 1 $1
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

ECB600_POWER_STATUS()
{
    ECB600_MCU_test -p 0 0
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

ECB600_POWER_TEST()
{
    if [ -z "$1" ]; then
        echo "Please input switch"
        rec_return=$FAIL
    else
        ECB600_MCU_test -p 1 $1
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

ECB600_PL2303_GPIO_STATUS()
{
    if [ ! -e "/dev/ttyUSBecb" ]; then
        echo "PL2303 USB serial device not exist"
        rec_return=$FAIL
    else
        USBPATH=/sys/bus/usb/devices/3-2
        PID=`cat ${USBPATH}/idProduct`
        if [ "${PID}" = "23a3" ]; then
            GP0=$(pl2303gcgpio -r 0)
            GP1=$(pl2303gcgpio -r 1)
        else
            GP0=$(pl2303gpio -r 0)
            GP1=$(pl2303gpio -r 1)
        fi
        rec_return="OPCi_R_GPIO_${GP0}_${GP1}"
    fi
    log $rec_return
}

ECB600_PL2303_GPIO_TEST()
{
    if [ -z "$1" ]; then
        echo "Please input GPIO: (0~1)"
        rec_return=$FAIL
        echo $rec_return
    elif [ -z "$2" ]; then
        echo "Please input switch"
        rec_return=$FAIL
        echo $rec_return
    else
        USBPATH=/sys/bus/usb/devices/3-2
        PID=`cat ${USBPATH}/idProduct`
        gpio=$1
        value=$2
        if [ "${PID}" = "23a3" ]; then
            pl2303gcgpio -g $gpio -o $value
            RET=$(pl2303gcgpio -r $gpio)
        else
            pl2303gpio -g $gpio -o $value
            RET=$(pl2303gpio -r $gpio)
        fi
        echo "GP${gpio} => ${RET}"
        if [ "$value" = "$RET" ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

ECB600_PL2303_USB_ID()
{
    USBPATH=/sys/bus/usb/devices/3-2
    if [ ! -d "${USBPATH}" ]; then
        echo "PL2303 USB serial device not exist"
        rec_return=$FAIL
        echo $rec_return
    else
        PID=`cat ${USBPATH}/idProduct`
        VID=`cat ${USBPATH}/idVendor`
        rec_return="OPCi_R_USBID_${PID}_${VID}"
    fi
    log $rec_return
}

ECB600_PSU_ERROR_STATUS()
{
    ECB600_MCU_test -P
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

ECB600_PWM_STATUS()
{
    ECB600_MCU_test -w 0 0
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

ECB600_PWM_TEST()
{
    if [ -z "$1" ]; then
        echo "Please input switch"
        rec_return=$FAIL
    else
        ECB600_MCU_test -w 1 $1
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

ECB600_THERMAL_TEST()
{
    if [ -z "$1" ]; then
        echo "Please input thermal CH (1~8)"
        rec_return=$FAIL
    else
        ECB600_MCU_test -t $1 1
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

# =ON6U_ECB600_I2CEXT_STATUS
ECB600_UART_TEST() 
{
    ECB600_MCU_test -i 0 0
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

ECB600_WATCHDOG_ENABLE()
{
    if [ -z "$1" ]; then
        echo "Please input switch"
        rec_return=$FAIL
        echo $rec_return
    else
        ECB600_MCU_test -g $1
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

ECB600_WATCHDOG_KICK()
{
    ECB600_MCU_test -k
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

GET_BT_MAC()
{
    tmpVar1=$(hcitool dev |grep hci|awk '{print $2}')

    if [ -n "$tmpVar1" ]; then
        rec_return=$RETURN"_BT_MAC_"$tmpVar1
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

GET_CUSTOM_EFIVAR()
{
    ls /sys/firmware/efi/efivars/*-$GUID > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        for file in /sys/firmware/efi/efivars/*-$GUID; do
            local name=$(basename "$file"|cut -d'-' -f 1)
            local value=$(tr -d '\0\a' < $file)
            echo "$name = $value"
        done
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi 
    log  $rec_return
}

GET_P12V()
{
    local num=174
    if [ -d /sys/class/gpio/gpio${num} ]; then
        local value=$(cat /sys/class/gpio/gpio${num}/value)
        rec_return=$RETURN"_P12V_${value}"
    else
        echo "gpio${num} not export!"
        rec_return=$FAIL
    fi
    log  $rec_return
}

GET_PANEL_SELECT_ID()
{
    local value=$( get_efivar PanelSelectId )
    if [ "${value}" != "" ]; then
        rec_return=$RETURN"_PANEL_SELECT_ID_${value}"
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

GET_SYS_PN()
{
    local value=$( get_efivar PartNumber )
    if [ "${value}" != "" ]; then
        rec_return=$RETURN"_SYS_PN_${value}"
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

GET_SYS_SN()
{
    local value=$( get_efivar SerialNumber )
    if [ "${value}" != "" ]; then
        rec_return=$RETURN"_SYS_SN_${value}"
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

GET_LAN_MAC()
{
    local addr=$(ifconfig eth0 |grep "ether" | awk '{print $2}'|tr '[:lower:]' '[:upper:]')
    if [ -n "$addr" ]; then
        rec_return=$RETURN"_LAN_MAC_"$addr
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

GET_WIFI_MAC()
{
    tmpVar1=$(ifconfig wlan0|grep ether|awk '{print $2}'|tr '[:lower:]' '[:upper:]')

    if [ -n "$tmpVar1" ]; then
        rec_return=$RETURN"_WIFI_MAC_"$tmpVar1
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

PRT160_RTC_TEST()
{
    declare -a REG=(   0x00 0x01 0x02 0x03 0x04 0x05 0x06 0x07 0x08 0x0D 0x14)
    declare -a VALUE=( 0x00 0x00 0x00 0x09 0x01 0x01 0x01 0x80 0x00 0x01 0x01)
    declare -a RESULT=(   0    0    0    0    0    0    0    0    0    0    0)
    BUS=$( I2C_MAP 2 )

    i2cget -y ${BUS} 0x6F 0x00 | grep "0x" 2>&1 > /dev/null
    if [ "$?" = "0" ]; then
        RET=0
        i=0
        for reg in "${REG[@]}"
        do
            i2cset -y ${BUS} 0x6f ${reg} ${VALUE[${i}]}
            if [ $? -ne 0 ]; then
               RESULT[$i]=1;
               RET=1
            fi
            i=$(($i+1))
        done

        if [ $RET = 0 ]; then
            rec_return=$SUCC
        else
            rec_return="iCanvas_R_Fail_${RESULT[0]}_${RESULT[1]}_${RESULT[2]}_${RESULT[3]}_${RESULT[4]}_${RESULT[5]}_${RESULT[6]}_${RESULT[7]}_${RESULT[8]}_${RESULT[9]}_${RESULT[10]}"
        fi
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

PRT_RTC_REBOOT()
{
    I2C_BUS_NO=$( I2C_MAP 2 )
    I2C_BUS_BASE_PATH="/sys/class/i2c-dev/i2c-${I2C_BUS_NO}/device"
    modprobe rtc-ds1307
    echo mcp7941x 0x6f > $I2C_BUS_BASE_PATH/new_device
    sleep 3

    NAME="RTCTest-${BIOS_GUID}"
    if [ ! -f "/sys/firmware/efi/efivars/${NAME}" ]; then
        touch /sys/firmware/efi/efivars/${NAME}
    fi
    chattr -i /sys/firmware/efi/efivars/${NAME}
    printf "\x07\x00\x00\x00\x01" > /sys/firmware/efi/efivars/${NAME}
    chattr +i /sys/firmware/efi/efivars/${NAME}
    if [ "$(hexdump -C /sys/firmware/efi/efivars/${NAME}|head -1|awk '{print $6}')" = "01" ]; then
        REBOOT_LATER=1
        rec_return=$SUCC
        log  $rec_return
        sleep 1
        reboot power_cycle
    else
        rec_return=$FAIL
        log  $rec_return
    fi
}

PRT_RTC_REBOOT_CHECK()
{
    NAME="RTCTest-${BIOS_GUID}"
    if [ ! -f "/sys/firmware/efi/efivars/${NAME}" ]; then
        rec_return=$FAIL
    else
        if [ "$(hexdump -C /sys/firmware/efi/efivars/${NAME}|head -1|awk '{print $6}')" = "01" ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
        chattr -i /sys/firmware/efi/efivars/${NAME}
        rm /sys/firmware/efi/efivars/${NAME}
    fi
    log  $rec_return
}

SET_BOOT_ORIENTATION()
{
    set_efivar BootOrientation "$1"
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

SET_BRIGHTNESS()
{
    BRIGHTNESS=$1

    echo $BRIGHTNESS > /sys/class/backlight/intel_backlight/brightness
    RET=$?
    tmpVar1=$(cat /sys/class/backlight/intel_backlight/brightness)

    if [ "$tmpVar1" = "$BRIGHTNESS" ] && [ $RET = 0 ]; then
        /lib/systemd/systemd-backlight save backlight:intel_backlight
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

SET_CUSTOM_EFIVAR()
{
    rec_return=$SUCC

    # check all efivar
    PART_NUMBER=$( get_efivar PartNumber )
    [ $PART_NUMBER ] || rec_return=${FAIL}_PartNumber_not_be_set
    SERIAL_NUMBER=$( get_efivar SerialNumber )
    [ $SERIAL_NUMBER ] || rec_return=${FAIL}_SerialNumber_not_be_set
    BOOT_ORIENTATION=$( get_efivar BootOrientation )
    [ $BOOT_ORIENTATION ] || rec_return=${FAIL}_BootOrientation_not_be_set
    SENSOR_POSITION=$( get_efivar SensorPosition )
    [ $SENSOR_POSITION ] || rec_return=${FAIL}_SensorPosition_not_be_set
    PANEL_ID=$( get_efivar PanelSelectId )
    [ $PANEL_ID ] || rec_return=${FAIL}_PanelSelectId_not_be_set
    PWMMIN=$( get_efivar Pwm0 )
    PWMMAX=$( get_efivar Pwm5 )
    [ $PWMMAX ] || rec_return=${FAIL}_PWMMAX_not_be_set
    NITSMIN=$( get_efivar Nits0 )
    NITSMAX=$( get_efivar Nits5 )
    [ $NITSMAX ] || rec_return=${FAIL}_NITSMAX_not_be_set

    # match model 
    FIND=0
    FIND_SENSOR=1
    for element in ${PART_LIST[@]}
    do
        dev=(${element//__/ })
        dev_PART=${dev[0]}
        dev_SENSOR=${SENSOR_POSITION_LIST[${dev[1]}]}
        dev_BOOT=${dev[2]}
        dev_PANEL=${dev[3]}
        dev_PWM=${dev[4]}
        dev_NITSMAX=${dev[5]}
        dev_NITSMIN=${dev[6]}
        if [ "$dev_PART" == "$PART_NUMBER" ] ; then
            FIND=1
            if [ "$dev_PANEL" != "" ] && [ "$dev_PANEL" != "$PANEL_ID" ]; then
                rec_return="${FAIL}_Wrong_Panel_Select_Id_${PANEL_ID}"
                break;
            fi

            if [ "$dev_BOOT" != "$BOOT_ORIENTATION" ]; then
                rec_return="${FAIL}_Wrong_BootOrientation_${BOOT_ORIENTATION}"
                break;
            fi

            if [ "$dev_SENSOR" != "$SENSOR_POSITION" ]; then
                rec_return="${FAIL}_Wrong_SensorPosition_${SENSOR_POSITION}"
                break;
            fi

            if [ "$dev_PWM" = "NULL" ]; then
                dev_PWM=0
                PWMMIN=0
                NITSMIN=1
            fi
            [ $NITSMIN ] || rec_return=${FAIL}_NITSMIN_not_be_set
            [ $PWMMIN ] || rec_return=${FAIL}_PWMMIN_not_be_set

                # PWM check
                if [ "$dev_PWM" != "$PWMMIN" ]; then
                    rec_return="${FAIL}_Wrong_PWMMIN_${PWMMIN}_SHOULD_BE_${dev_PWM}"
                    break;
                elif [ $PWMMAX -le $PWMMIN ]; then
                    rec_return="${FAIL}_Wrong_PWMMAX${PWMMAX}_LESS_THEN_PWMMIN_${PWMMIN}"
                    break;
                fi
                
                # NITS check
                if [ "$NITSMAX" = "" ] || [ "$NITSMIN" = "" ]; then
                    rec_return="${FAIL}_Wrong_NITSMAX/NITSMIN_IS_EMPTY"
                    break;
                elif [ $NITSMAX -eq 0 ] || [ $NITSMIN -eq 0 ]; then
                    rec_return="${FAIL}_Wrong_NITSMAX(${NITSMAX})_NITSMIN(${NITSMIN})"
                    break;
                elif [ $NITSMAX -le $NITSMIN ]; then
                    rec_return="${FAIL}_Wrong_NITSMAX(${NITSMAX})_LESS_THEN_NITSMIN(${NITSMIN})"
                    break;
                elif [ $NITSMAX -gt $dev_NITSMAX ] || [ $NITSMAX -lt $dev_NITSMIN ]; then
                    rec_return="${FAIL}_Wrong_NITSMAX(${NITSMAX})_(${dev_NITSMIN}-${dev_NITSMAX})"
                    break;
                fi
        fi
    done

    if [ "$FIND" = "0" ]; then
        rec_return="$FAIL_${PART_NUMBER}_not_be_found"
    fi


    log  $rec_return
}

SET_LAN_MAC()
{
    MAC=$1
    tmpVar1=$(echo $MAC | sed 's/:*//g')
    tmpVar2=`echo $tmpVar1 | cut -c 1-2`\ `echo $tmpVar1 | cut -c 3-4`\ `echo $tmpVar1 | cut -c 5-6`\ `echo $tmpVar1 | cut -c 7-8`\ `echo $tmpVar1 | cut -c 9-10`\ `echo $tmpVar1 | cut -c 11-12`
    echo "MAC:[${tmpVar2}]"

    sed -i '1d' /usr/bin/8168GEF.cfg
    sed -i "1i NODEID = ${tmpVar2}" /usr/bin/8168GEF.cfg
    cat /usr/bin/8168GEF.cfg | head -n 1

    sed -i '1d' /usr/bin/8119EF.cfg
    sed -i "1i NODEID = ${tmpVar2}" /usr/bin/8119EF.cfg
    cat /usr/bin/8119EF.cfg | head -n 1

    rmmod r8169
    modprobe pgdrv
    rmmod pgdrv
    modprobe r8169
    sleep 1
    rmmod r8169
    modprobe pgdrv
    cd /usr/bin/
    ./rtnicpg-x86_64 /w /efuse
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    rmmod pgdrv
    modprobe r8169
    log  $rec_return
}

SET_P12V()
{
    local num=174
    local value=$1
    if [ ! -d /sys/class/gpio/gpio$num ]; then
        echo $num > /sys/class/gpio/export
	fi
	echo out > /sys/class/gpio/gpio$num/direction
	echo $value > /sys/class/gpio/gpio$num/value
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

SET_PANEL_SELECT_ID()
{
    local ret=0
    local panel=$1

    set_efivar PanelSelectId "$panel"
    if [ $? != 0 ]; then
        ret=1
    fi
    case "${panel}" in
        "lg_1080p_video")
            set_efivar PwmFreq 937
            ;; 
        "lg_square_video")
            set_efivar PwmFreq 1800
            ;; 
        "hdmi_cc48sm?147")
            set_efivar PwmFreq 1000
            ;; 
        "hdmi_mstar2?16" | "hdmi_mstar2?128")
            set_efivar PwmFreq 3750
            ;; 
    esac
    if [ $ret -eq 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

SET_PWM()
{
    if [ "$1" = "5" ]; then
        set_efivar Brightness "$2"
    fi
    set_efivar Pwm$1 "$2"
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

SET_PWM_FREQ()
{
    set_efivar PwmFreq $1
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

SET_SENSOR_POSITION()
{
    set_efivar SensorPosition "$1"
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

SET_SYS_PN()
{
    set_efivar PartNumber "$1"
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

SET_SYS_SN()
{
    set_efivar SerialNumber "$1"
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log  $rec_return
}

# usage: sudo OONEE_tool.sh VBB_AND_BACKLIGHT_SET <P12V_EN:0/1> <BL_EN:0/1>"
VBB_AND_BACKLIGHT_SET()
{
    if [ -z "$1" ]; then
        echo "Please input 0/1 for P12V_EN"
        echo "Please input 0/1 for BL_EN"
        exit 1
    fi
    local P12V=174
    local BLEN=327

    # P12V
    if [ ! -d /sys/class/gpio/gpio${P12V} ]; then
        echo ${P12V} > /sys/class/gpio/export
	fi
	echo out > /sys/class/gpio/gpio${P12V}/direction
    echo $1 > /sys/class/gpio/gpio${P12V}/value
    P12V_result=$?

    # BLEN
    if [ ! -d /sys/class/gpio/gpio${BLEN} ]; then
        echo ${BLEN} > /sys/class/gpio/export
	fi
	echo out > /sys/class/gpio/gpio${BLEN}/direction
    echo $2 > /sys/class/gpio/gpio${BLEN}/value
    BL_EN_result=$?

    if [ $P12V_result -eq 0 ] && [ $BL_EN_result -eq 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}
VBB_BACKLIGHT_GET()
{
    SDVBB_Test -b
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

# value:0~100
VBB_BACKLIGHT_SET()
{
    if [ -z "$1" ]; then
        echo "Please input backlight value"
        rec_return=$FAIL
    else
        SDVBB_Test -c $1
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

VBB_COLORSPACE_SET()
{
    OONEE_tool.sh PLAY_IMAGE color_space_test_3_2.jpg
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

# usage: sudo OONEE_tool.sh VBB_DEBUG [MSG] [LEN] [P0] [P1] [P2] [P3] [P4] [P5] [P6]
VBB_DEBUG()
{
    SDVBB_Test -d $1 $2 $3 $4 $5 $6 $7 $8 $9
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

VBB_FACTORY_RESET()
{
    SDVBB_Test -d 26
    sleep 50
    rec_return=$SUCC
    log $rec_return
}

VBB_DRIVER_STATUS()
{
    SDVBB_Test -s
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

VBB_LOCALDIMMING_OFF()
{
    SDVBB_Test -d 5A 02 01 00|grep OPCi_R_DEBUG_B0_00_00
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

VBB_LOCALDIMMING_ON()
{
    SDVBB_Test -d 5A 02 01 01|grep OPCi_R_DEBUG_B0_00_00
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

VBB_LOCALDIMMING_STATUS()
{
    tmpVar1=`SDVBB_Test -d 5B 01 01 |grep OPCi_R_DEBUG_B2_01_|sed 's/^OPCi_R_DEBUG_B2_01_//'|sed 's/_00//g'`
    tmpVar2=`echo $tmpVar1 | sed 's/^.//'`
    rec_return="OPCi_R_LOCALDIMMING_"$tmpVar2
    log $rec_return
}


VBB_MODEL_INDEX_GET()
{
    tmpVar1=`SDVBB_Test -d 95 |grep OPCi_R_DEBUG_B2_01_|sed 's/^OPCi_R_DEBUG_B2_01_//'|sed 's/_00//g'`
    rec_return="OPCi_R_MODEL_INDEX_"$tmpVar1
    log $rec_return
}

VBB_MODEL_INDEX_SET_THEN_RESET()
{
    SDVBB_Test -d 94 01 $1 #6ui=0x03, 5ui=0x04, 075-2500(6xti?)=0x05, 8ui-4000=0x06
    RESULT=$?

    if [ $RESULT -eq -1 ]; then
        rec_return=$FAIL
    else
        sleep 1
        SDVBB_Test -d 26
        rec_return=$SUCC
    fi
    log $rec_return
}

VBB_SN_GET()
{
	SDVBB_Test -n
	if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

VBB_SN_SET()
{
    if [ -z "$1" ]; then
        echo "Please input SN"
        rec_return=$FAIL
        echo $rec_return
    else
        SDVBB_Test -o $1
        if [ $? = 0 ]; then
            rec_return=$SUCC
        else
            rec_return=$FAIL
        fi
    fi
    log $rec_return
}

VBB_TEMP_GET()
{
    SDVBB_Test -t
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

VBB_VERSION_GET()
{
    SDVBB_Test -v
    if [ $? = 0 ]; then
        rec_return=$SUCC
    else
        rec_return=$FAIL
    fi
    log $rec_return
}

main()
{
    export ARG_ALL=$@

    # dirty fix for SET_SENSOR_POSITION which contain ';' character.
    if [ $1 = "SET_SENSOR_POSITION" ]; then
            SET_SENSOR_POSITION $2
    elif [ "$(type -t $1)" = "function" ]; then
            eval $ARG_ALL
    else
        rec_return=${FAIL}_CMD_NOT_FOUND
        log  $rec_return
    fi
}
main "$@"
