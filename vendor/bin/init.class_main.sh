#! /vendor/bin/sh

# Copyright (c) 2013-2014, 2019 The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of The Linux Foundation nor
#       the names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON-INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

#
# start ril-daemon only for targets on which radio is present
#
baseband=`getprop ro.baseband`
sgltecsfb=`getprop persist.vendor.radio.sglte_csfb`
datamode=`getprop persist.vendor.data.mode`
qcrild_status=true

target=`getprop ro.board.platform`
manufacturer=`getprop ro.product.vendor.brand`
if [ -f /sys/devices/soc0/soc_id ]; then
    soc_hwid=`cat /sys/devices/soc0/soc_id` 2> /dev/null
else
    soc_hwid=`cat /sys/devices/system/soc/soc0/id` 2> /dev/null
fi

case "$baseband" in
    "apq" | "sda" | "qcs" )
    setprop ro.vendor.radio.noril yes
    stop ril-daemon
    stop vendor.ril-daemon
    stop vendor.qcrild
    start vendor.ipacm
esac

case "$baseband" in
    "msm" | "csfb" | "svlte2a" | "mdm" | "mdm2" | "sglte" | "sglte2" | "dsda2" | "unknown" | "dsda3" | "sdm" | "sdx" | "sm6")

    # For older modem packages launch ril-daemon.
    if [ -f /vendor/firmware_mnt/verinfo/ver_info.txt ]; then
        modem=`cat /vendor/firmware_mnt/verinfo/ver_info.txt |
                sed -n 's/^[^:]*modem[^:]*:[[:blank:]]*//p' |
                sed 's/.*MPSS.\(.*\)/\1/g' | cut -d \. -f 1`
        if [ "$modem" = "AT" ]; then
            version=`cat /vendor/firmware_mnt/verinfo/ver_info.txt |
                    sed -n 's/^[^:]*modem[^:]*:[[:blank:]]*//p' |
                    sed 's/.*AT.\(.*\)/\1/g' | cut -d \- -f 1`
            if [ ! -z $version ]; then
                if [ "$version" \< "3.1" ]; then
                    qcrild_status=false
                fi
            fi
        elif [ "$modem" = "TA" ]; then
            version=`cat /vendor/firmware_mnt/verinfo/ver_info.txt |
                    sed -n 's/^[^:]*modem[^:]*:[[:blank:]]*//p' |
                    sed 's/.*TA.\(.*\)/\1/g' | cut -d \- -f 1`
            if [ ! -z $version ]; then
                if [ "$version" \< "3.0" ]; then
                    qcrild_status=false
                fi
            fi
        elif [ "$modem" = "JO" ]; then
            version=`cat /vendor/firmware_mnt/verinfo/ver_info.txt |
                    sed -n 's/^[^:]*modem[^:]*:[[:blank:]]*//p' |
                    sed 's/.*JO.\(.*\)/\1/g' | cut -d \- -f 1`
            if [ ! -z $version ]; then
                if [ "$version" \< "3.2" ]; then
                    qcrild_status=false
                fi
            fi
        elif [ "$modem" = "TH" ]; then
            qcrild_status=false
        fi
    fi

    if [ "$manufacturer" = "asus" ]; then
        case "$target" in
            "msm8937" | "msm8940")
                case "$soc_hwid" in
                    294|295|296|297|298|313|353|354|363|364)
                        if [ $soc_hwid = 313 ]; then
                            # msm8940 modem info -- "modem": "MPSS.TA.2.3.c1-00576-8953_GEN_PACK-1",
                            # This modem version (TA - 2.0.c1) just support radio 1.1
                            qcrild_status=false
                        else
                            # msm8937 modem info -- "modem": "MPSS.JO.3.0-00398-8937_GENNS_PACK-1.146270.0.147147.1"
                            # This modem version (JO - 3.0) just support radio 1.1
                            qcrild_status=false
                        fi
                        ;;
                    303|307|308|309|320)
                        # msm8917 modem info -- "modem": "MPSS.JO.3.0-00398-8937_GENNS_PACK-1.131040.1",
                        # This modem version (JO - 3.0) just support radio 1.1
                        qcrild_status=false
                        ;;
                esac
        esac
    fi

    log -t RADIO -p i "MSM target '$target', soc_hwid '$soc_hwid', manufacturer '$manufacturer', qcrild_status '$qcrild_status'"

    if [ "$qcrild_status" = "true" ]; then
        # Make sure both rild, qcrild are not running at same time.
        # This is possible with vanilla aosp system image.
        stop ril-daemon
        stop vendor.ril-daemon

        start vendor.qcrild
    else
        start ril-daemon
        start vendor.ril-daemon
    fi

    start vendor.ipacm
    case "$baseband" in
        "svlte2a" | "csfb")
          start qmiproxy
        ;;
        "sglte" | "sglte2" )
          if [ "x$sgltecsfb" != "xtrue" ]; then
              start qmiproxy
          else
              setprop persist.vendor.radio.voice.modem.index 0
          fi
        ;;
    esac

    multisim=`getprop persist.radio.multisim.config`

    if [ "$multisim" = "dsds" ] || [ "$multisim" = "dsda" ]; then
        if [ "$qcrild_status" = "true" ]; then
          start vendor.qcrild2
        else
          start vendor.ril-daemon2
        fi
    elif [ "$multisim" = "tsts" ]; then
        if [ "$qcrild_status" = "true" ]; then
          start vendor.qcrild2
          start vendor.qcrild3
        else
          start vendor.ril-daemon2
          start vendor.ril-daemon3
        fi
    fi

    case "$datamode" in
        "tethered")
            start vendor.dataqti
            start vendor.dataadpl
            ;;
        "concurrent")
            start vendor.dataqti
            start vendor.dataadpl
            ;;
        *)
            ;;
    esac
esac

#
# Allow persistent faking of bms
# User needs to set fake bms charge in persist.vendor.bms.fake_batt_capacity
#
fake_batt_capacity=`getprop persist.vendor.bms.fake_batt_capacity`
case "$fake_batt_capacity" in
    "") ;; #Do nothing here
    * )
    echo "$fake_batt_capacity" > /sys/class/power_supply/battery/capacity
    ;;
esac
