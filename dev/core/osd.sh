#!/usr/bin/env bash
# OSD helper: reads the current volume/brightness and tells Quickshell to show the OSD.
# Usage: osd.sh volume | brightness | mute
KIND="${1:-volume}"

case "$KIND" in
    volume)
        out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
        val=$(echo "$out" | awk '{print int($2*100)}')
        # a muted sink still reports its volume level; show 0 instead
        echo "$out" | grep -q "MUTED" && val=0
        ;;
    brightness)
        val=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%')
        val=${val%.*}
        ;;
    mic)
        out=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)
        val=100
        echo "$out" | grep -q "MUTED" && val=0
        KIND="mute"
        ;;
    *)
        exit 0
        ;;
esac

[ -z "$val" ] && exit 0
quickshell ipc -n call shell osd "$KIND" "$val" 2>/dev/null || true
