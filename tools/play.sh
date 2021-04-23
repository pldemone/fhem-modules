#!/bin/bash

#
# Wrapper script for sending audio data via AirPlay/AirPlay2 to one or more devices.
# This script should be called from FHEM and requires a modified version of 98_Text2Speech.pm
#
# Definition in FHEM:
#	defmod myTTS Text2Speech hw=1.0
#	attr myTTS TTS_MplayerCall /opt/fhem_tools/play.sh {file} "{options}"
#
# Call from FHEM:
#	set myTTS tts [ROOMS%FHEM_PRESENCE_DEVICE] MESSAGE

# Examples:
# 	Play in default room:
#		set System.tts tts This is a test
# 	Play in a specific room:
#		set System.tts tts [office] This is a test
# 	Play in multiple rooms
#		set System.tts tts [office,living] This is a test
# 	Play in specific room ony if system is present:
#		set System.tts tts [office%%MyMobile] This is a test
# 	Play in specific room ony if one of the systems is present:
#		set System.tts tts [office%%MyMobile||My2Mobile] This is a test
# 	Play in specific room ony if BOTH of the systems are present:
#		set System.tts tts [office%%MyMobile&&My2Mobile] This is a test
# 	Play in multiple rooms if system is present:
#		set System.tts tts [office%%MyMobile,living%%MyMobile] This is a test
# Usage outside from FHEM:
#	./play.sh filename.mp3 "office%%MyMobile"
#
# Copyright: Copyright (c) 2021, Mirko Lindner <demon@pro-linux.de>
# License:   GPL-2
#

# Adapt for your usage

# Sound/Jingle before each voice message
presound="/opt/fhem_tools/data/ding.mp3"

# Default host when called without system definition
defhost="office"

# Preset system definitions. If a system is not found in the list,
# the script searches via DNS for the IP address and the avahi port
declare -A SYSTEMS=( ["office"]="192.168.0.130:7000" ["child"]="192.168.0.131:7000" ["hifi"]="VSX-527.local")

### Nothing to change
#############################################################

# Check tools
which ffmpeg >/dev/null 2>&1 || { echo "ffmpeg required but not found. Aborting." >&2; exit 1; }
which raop_play >/dev/null 2>&1 || { echo "ffmpeg required but not found. Aborting." >&2; exit 1; }
which avahi-browse >/dev/null 2>&1 || { echo "avahi-browse required but not found. Aborting." >&2; exit 1; }
if [ ! -e /opt/fhem/fhem.pl ]; then echo "/opt/fhem/fhem.pl required but not found. Aborting."; fi

infile=$1
playhost=$2

if [ "$infile" == "" ]; then
	echo ERROR
	echo Script requires arguments
	echo "           $0 AUDIOFILE [HOST]"
	echo Exit
	exit 1
fi

if [ "$playhost" == "" ]; then
	playhost=$defhost;
fi

dirname=`dirname "$infile"`
filename=`basename "$infile"`
extension="${filename##*.}"
filename="${filename%.*}"

ffmpeg_ops="-hide_banner -loglevel error"
IFS=', ' read -r -a HOSTS <<< "$playhost"

if [ ! -e "${dirname}/${filename}.wav" ]; then
	# convert mp3
	if [ -e $presound ]; then
	# Use Sound/Jingle if available
		tfile=$(mktemp /tmp/conv.XXXXXXXXX)
		echo "file '$presound'" &> $tfile
		echo "file '${infile}'" >> $tfile
		ffmpeg_in="-f concat -safe 0 -i $tfile"
		ffmpeg ${ffmpeg_in} ${ffmpeg_ops} -vn -ac 2 -ar 44100 -acodec pcm_s16le -f s16le "${dirname}/${filename}.wav"
		rm -f $tfile
	else
	# Play plain without any modification
		ffmpeg_in="-i ${infile}"
		ffmpeg ${ffmpeg_in} ${ffmpeg_ops} -vn -ac 2 -ar 44100 -acodec pcm_s16le -f s16le "${dirname}/${filename}.wav"
	fi
fi

if [ ! -e "${dirname}/${filename}.wav" ]; then
	echo ERROR: Could not find ${filename}.wav
	exit 1
fi

for element in "${HOSTS[@]}"; do
	IFS='%% ' read -r -a OPTIONS <<< "$element"
	host=${OPTIONS[0]}
	if  [ "$host" == "" ]; then continue; fi
	fflag=0

	# Check the presence tag
	if [ "${OPTIONS[2]}" != "" ]; then
		IFS='&& ' read -r -a PRESENCE <<< "${OPTIONS[2]}"
		for presence in "${PRESENCE[@]}"; do
			if  [ "$presence" == "" ]; then continue; fi
			fflag=1
			IFS='|| ' read -r -a ORCHECK <<< "${presence}"
			for orcheck in "${ORCHECK[@]}"; do
				syspres=`perl /opt/fhem/fhem.pl 7072 "LIST $orcheck state" | grep present -c`
				if [[ $syspres -gt 0 ]]; then
					fflag=2
					break
				fi
			done

			if [[ $fflag -eq 1 ]]; then break; fi
		done
	fi

	# Presence - device(s) available
	if [[ $fflag -eq 1 ]]; then continue; fi

	if [ "${SYSTEMS[${host}]}" != "" ]; then
	# Pre-defined device found
		hostname=$(echo ${SYSTEMS[${host}]} | cut -d : -f 1)
		port=$(echo ${SYSTEMS[${host}]} | cut -d : -f 2)
		if [ "$port" == "$hostname" ]; then
			# Port not available. Get from avahi...
			port=`avahi-browse -rpkt _raop._tcp | grep $hostname | cut  -d ";" -f 9`
		fi
		if [ "$port" != "" ]  && [ "$hostname" != "" ]; then
			echo "play ${filename}.wav on ${hostname}:${port}"
			raop_play $hostname -w 200 -v 50 -p $port -d 0 "${dirname}/${filename}.wav"
		fi
	else
	# Device not defined... Check DNS and avahi
		ipaddr=`getent hosts ${host} | awk '{ print $1 }'`
		if [ "$ipaddr" != "" ]; then
			port=`avahi-browse -rpkt _raop._tcp | grep $ipaddr | cut  -d ";" -f 9 | head -1`
			if [ "$port" != "" ]; then
				echo "play ${filename}.wav on $ipaddr:${port} (DNS)"
				raop_play $ipaddr -w 200 -v 50 -p $port -d 0 "${dirname}/${filename}.wav" 
			fi
		else
			echo ${host} not found - neither as definistion in script nor as DNS entry
			exit 1
		fi
	fi
done

exit 0
