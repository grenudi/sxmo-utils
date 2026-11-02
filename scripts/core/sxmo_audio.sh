#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright 2022 Sxmo Contributors

# shellcheck source=configs/default_hooks/sxmo_hook_icons.sh
. sxmo_hook_icons.sh
. sxmo_common.sh

set -e

notifyvol() {
	vol="$1"
	case "$vol" in
		"-") vol="$(cat)" ;;
		"muted") vol=0 ;;
	esac
	if [ -z "$SXMO_WOB_DISABLE" ]; then
		printf "%s\n" "$vol" > "$XDG_RUNTIME_DIR"/sxmo.obsock
	else
		notify-send -r 999 "$icon_audio Volume $vol"
	fi
}

# adjust *output* vol/mute
volup() {
	pactl set-sink-volume @DEFAULT_SINK@ +"${1:-5}%"
}

voldown() {
	pactl set-sink-volume @DEFAULT_SINK@ -"${1:-5}%"
}

voltogglemute() {
	pactl set-sink-mute @DEFAULT_SINK@ toggle
}

volismuted() {
	pactl get-sink-mute @DEFAULT_SINK@ | grep -q "Mute: yes"
}

volget() {
	if volismuted; then
		printf "muted"
	else
		pactl get-sink-volume @DEFAULT_SINK@ | head -n1 | \
			cut -d'/' -f2 | sed 's/ //g' | sed 's/\%//'
	fi
}

volset() {
	pactl set-sink-volume @DEFAULT_SINK@ "$1"%
}

# adjust *input* vol/mute
micvolup() {
	pactl set-source-volume @DEFAULT_SOURCE@ +"${1:-5}%"
}

micvoldown() {
	pactl set-source-volume @DEFAULT_SOURCE@ -"${1:-5}%"
}

mictogglemute() {
	pactl set-source-mute @DEFAULT_SOURCE@ toggle
}

micismuted() {
	pactl get-source-mute @DEFAULT_SOURCE@ | grep -q "Mute: yes"
}

micvolget() {
	if micismuted; then
		printf "muted"
	else
		pactl get-source-volume @DEFAULT_SOURCE@ | head -n1 | \
			cut -d'/' -f2 | sed 's/ //g' | sed 's/\%//'
	fi
}

micvolset() {
	pactl set-source-volume @DEFAULT_SOURCE@ "$1"%
}

# set the *active port* for output
deviceset() {
	pactl set-sink-port @DEFAULT_SINK@ "[Out] $1"
}

# set the *active port* for input
devicesetinput() {
	pactl set-source-port @DEFAULT_SOURCE@ "[In] $1"
}

# get the current source pactl data
devicegetinput() {
	default_source="$1"
	if [ -z "$default_source" ]; then
		default_source="$(pactl get-default-source)"
	fi
	pactl --format=json list sources | \
		jq -r ".[] | select(.name == \"$default_source\")"
}

# get the current sink pactl data
deviceget() {
	default_sink="$1"
	if [ -z "$default_sink" ]; then
		default_sink="$(pactl get-default-sink)"
	fi
	pactl --format=json list sinks | \
		jq -r ".[] | select(.name == \"$default_sink\")"
}

# get the default sink
devicegetdefaultsink() {
	pactl get-default-sink
}

# get the default source
devicegetdefaultsource() {
	pactl get-default-source
}

sourceset() {
	pactl set-default-source "$1"
}

sinkset() {
	pactl set-default-sink "$1"
}

profileset() {
	pactl set-card-profile "$1" "$2"
}

# get a list of sinks
_sinkssubmenu() {
	default_sink="$1"
	if [ -z "$default_sink" ]; then
		default_sink="$(pactl get-default-sink)"
	fi
	pactl --format=json list sinks | jq -r '.[] | .name, .description' | \
		while read -r line; do

		name="$line"
		read -r description
		if [ "$default_sink" = "$name" ]; then
			printf "%s %s %s ^ sinkset %s\n" \
				"$icon_chk" "$icon_spk" "$description" "$name"
		else
			printf "  %s %s ^ sinkset %s\n" \
				"$icon_spk" "$description" "$name"
		fi
	done
}

# get a list of output ports
_outportssubmenu() {
	default_sink="$1"
	if [ -z "$default_sink" ]; then
		default_sink="$(pactl get-default-sink)"
	fi
	active_out_port="$(deviceget "$default_sink")"
	pactl --format=json list sinks | \
		jq -r ".[] | select(.name == \"$default_sink\" )
		| .ports[] | select(.availability != \"not available\" )
		| .name" | sed 's/\[Out] //' |
		while read -r line; do

		[ "$active_out_port" = "$line" ] && \
			icon="$icon_ton" || icon="$icon_tof"
		printf "  %s %s ^ deviceset %s\n" "$icon" "$line" "$line"
	done
}

# get a list of input sources
_sourcessubmenu() {
	default_source="$1"
	if [ -z "$default_source" ]; then
		default_source="$(pactl get-default-source)"
	fi
	pactl --format=json list sources | \
		jq -r '.[] | select(.monitor_source == "")
		| .name, .description' | while read -r line; do

		name="$line"
		read -r description
		if [ "$default_source" = "$name" ]; then
			printf "%s %s %s ^ sourceset %s\n" "$icon_chk" "$icon_mic" "$description" "$name"
		else
			printf "  %s %s ^ sourceset %s\n" "$icon_mic" "$description" "$name"
		fi
	done
}

_cardssubmenu() {
	cards="$(pactl -f json list cards)"
	printf "%s\n" "$cards" | \
		jq -r '.[] | [.name, .active_profile] | @tsv' | \
		while IFS="	" read -r card active_profile; do

		printf "%s %s\n" "$icon_nte" "$card"
		printf "%s\n" "$cards" | \
			jq -r ".[] | select(.name == \"$card\")
			| .profiles | to_entries[] | select(.value.available)
			| [.key, .value.description] | @tsv" | \
			while IFS="	" read -r profile desc; do

			if [ "$profile" = "$active_profile" ]; then
				printf "%s %s ^ true\n" "$icon_chk" "$desc"
			else
				printf "  %s ^ profileset %s \"%s\"\n" \
					"$desc" "$card" "$profile"
			fi
		done
	done
}

# get a list of input ports
_inportssubmenu() {
	# if the Headset is NOT plugged in, then do not display Headset
	# as a option, as clicking on it causes pulse to unset the source!!
	default_source="$1"
	if [ -z "$default_source" ]; then
		default_source="$(pactl get-default-source)"
	fi
	active_in_port="$(devicegetinput "$default_source")"
	pactl --format=json list sources | \
		jq -r ".[] | select(.name == \"$default_source\" )
		| .ports[] | select(.availability != \"not available\" )
		| .name" | sed 's/\[In] //' | \
		while read -r line; do

		[ "$active_in_port" = "$line" ] && \
			icon="$icon_ton" || icon="$icon_tof"
		printf "  %s %s ^ devicesetinput %s\n" "$icon" "$line" "$line"
	done
}

_ringmodesubmenu() {
	if [ -f "$XDG_CONFIG_HOME"/sxmo/.noring ]; then
		printf ' %s Ring ^ rm -f "%s"/sxmo/.noring\n' \
			"$icon_tof" "$XDG_CONFIG_HOME"
	else
		printf ' %s Ring ^ touch "%s"/sxmo/.noring\n' \
			"$icon_ton" "$XDG_CONFIG_HOME"
	fi
	if [ -f "$XDG_CONFIG_HOME"/sxmo/.novibrate ]; then
		printf ' %s Vibrate ^ rm -f "%s"/sxmo/.novibrate\n' \
			"$icon_tof" "$XDG_CONFIG_HOME"
	else
		printf ' %s Vibrate ^ touch "%s"/sxmo/.novibrate\n' \
			"$icon_ton" "$XDG_CONFIG_HOME"
	fi
	if [ -f "$XDG_CONFIG_HOME"/sxmo/.busy ]; then
		end="$(cat "$XDG_CONFIG_HOME"/sxmo/.busy)"
		if [ -n "$end" ] && [ "$(date +%s)" -gt "$end" ]; then
			rm "$XDG_CONFIG_HOME"/sxmo/.busy
		fi
	fi
	if [ -f "$XDG_CONFIG_HOME"/sxmo/.busy ]; then
		printf ' %s Busy ^ rm -f "%s"/sxmo/.busy\n' \
			"$icon_ton" "$XDG_CONFIG_HOME"
	else
		printf ' %s Busy ^ touch "%s"/sxmo/.busy\n' \
			"$icon_tof" "$XDG_CONFIG_HOME"
		printf ' %s Busy for 15 min ^ date "+%%s+15*60" | bc > "%s"/sxmo/.busy\n' \
			"$icon_tmr" "$XDG_CONFIG_HOME"
		printf ' %s Busy for 30 min ^ date "+%%s+30*60" | bc > "%s"/sxmo/.busy\n' \
			"$icon_tmr" "$XDG_CONFIG_HOME"
		printf ' %s Busy for 1 hour ^ date "+%%s+60*60" | bc > "%s"/sxmo/.busy\n' \
			"$icon_tmr" "$XDG_CONFIG_HOME"
		printf ' %s Busy for 2 hour ^ date "+%%s+2*60*60" | bc > "%s"/sxmo/.busy\n' \
			"$icon_tmr" "$XDG_CONFIG_HOME"
		printf ' %s Busy for 3 hour ^ date "+%%s+3*60*60" | bc > "%s"/sxmo/.busy\n' \
			"$icon_tmr" "$XDG_CONFIG_HOME"
	fi
}

menuchoices() {
	cur_vol="$(volget)"
	cur_mic_vol="$(micvolget)"
	default_sink_name="$(devicegetdefaultsink)"
	default_source_name="$(devicegetdefaultsource)"
	grep . <<-EOF
		$icon_cls Close Menu  ^ exit
		Output:
		$(_sinkssubmenu "$default_sink_name")
		$(
			if [ "$cur_vol" != "muted" ]; then
				printf "  %s Volume (%s%%) ^ volup\n" \
					"$icon_aru" "$cur_vol"
				printf "  %s Volume (%s%%) ^ voldown\n" \
					"$icon_ard" "$cur_vol"
				printf "  %s Output Mute ^ voltogglemute\n" \
					"$icon_tof"
			else
				printf "  %s Output Mute ^ voltogglemute\n" \
					"$icon_ton"
			fi
		)
		$(_outportssubmenu "$default_sink_name")
		Input:
		$(_sourcessubmenu "$default_source_name")
		$(
		if [ "$cur_mic_vol" != "muted" ]; then
			printf "  %s Volume (%s%%) ^ micvolup\n" \
				"$icon_aru" "$cur_mic_vol"
			printf "  %s Volume (%s%%) ^ micvoldown\n" \
				"$icon_ard" "$cur_mic_vol"
			printf "  %s Input Mute ^ mictogglemute\n" \
				"$icon_tof"
		else
			printf "  %s Input Mute ^ mictogglemute\n" \
				"$icon_ton"
		fi
		)
		$(_inportssubmenu "$default_source_name")
		Cards:
		$(_cardssubmenu)
		$(_ringmodesubmenu)
	EOF
}

if [ -n "$SXMO_NO_AUDIO" ]; then
	sxmo_log "Audio is disabled."
	exit
fi

if [ -z "$*" ]; then
	set -- menu
fi

cmd="$1"
shift
case "$cmd" in
	menu)
		while : ; do
			CHOICES="$(menuchoices)"
			PICKED="$(
				printf "%s\n" "$CHOICES" |
					cut -d'^' -f1 |
					sxmo_dmenu.sh -i -p "Audio"
			)"

			CMD="$(printf "%s\n" "$CHOICES" | \
				grep -m1 -F "$PICKED" | cut -d '^' -f2)"

			eval "$CMD"
		done
		;;
	vol)
		verb="$1"
		shift
		vol"$verb" "$@"
		;;
	mic)
		verb="$1"
		shift
		mic"$verb" "$@"
		;;
	device)
		verb="$1"
		shift
		device"$verb" "$1"
		;;
	notify)
		notifyvol "$(volget)"
		;;
	micnotify)
		notifyvol "$(micvolget)"
		;;
esac
