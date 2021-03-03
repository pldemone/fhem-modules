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
#	set System.tts tts This is a test
#	set System.tts tts [office] This is a test
#	set System.tts tts [office,living] This is a test
#
# Usage outside from FHEM:
#	./play.sh filename.mp3 office
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
declare -A SYSTEMS=( ["office"]="192.168.0.130:7000" ["child"]="192.168.0.131:7000" ["child"]="VSX-527.local")

# Nothing to change

# Check tools
which ffmpeg >/dev/null 2>&1 || { echo "ffmpeg required but not found. Aborting." >&2; exit 1; }
which raop_play >/dev/null 2>&1 || { echo "ffmpeg required but not found. Aborting." >&2; exit 1; }
which avahi-browse >/dev/null 2>&1 || { echo "avahi-browse required but not found. Aborting." >&2; exit 1; }

### Nothing to change
infile=$1
playhost=$2
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
		ffmpeg_in="-i '${infile}'"
		ffmpeg ${ffmpeg_in} ${ffmpeg_ops} -vn -ac 2 -ar 44100 -acodec pcm_s16le -f s16le "${dirname}/${filename}.wav"
	fi
fi

for element in "${HOSTS[@]}"; do
	if [ "${SYSTEMS[$element]}" != "" ]; then
	# Pre-defined device found
		hostname=$(echo ${SYSTEMS[$element]} | cut -d : -f 1)
		port=$(echo ${SYSTEMS[$element]} | cut -d : -f 2)
		if [ "$port" == "$hostname" ]; then
			# Port not available. Get from avahi...
			port=`avahi-browse -rpkt _raop._tcp | grep $hostname | cut  -d ";" -f 9`
		fi
		if [ "$port" != "" ]  && [ "$hostname" != "" ]; then
			echo "Play ${filename}.wav on ${hostname}:${port}"
			raop_play $hostname -w 200 -v 50 -p $port "${dirname}/${filename}.wav"
		fi
	else
	# Device not defined... Check DNS and avahi
		ipaddr=`getent hosts $element | awk '{ print $1 }'`
		if [ "$ipaddr" != "" ]; then
			port=`avahi-browse -rpkt _raop._tcp | grep $ipaddr | cut  -d ";" -f 9 | head -1`
			if [ "$port" != "" ]; then
				echo "Play ${filename}.wav on $ipaddr:${port} (DNS)"
				raop_play $ipaddr -w 200 -v 50 -p $port "${dirname}/${filename}.wav"
			fi
		else
			echo $element not found - neither as definistion in script nor as DNS entry
			exit 1
		fi
	fi
done

exit 0
