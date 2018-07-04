#! /usr/bin/env sh

source /usr/local/etc/xcolor2shell

# TODO: Change this to pulse !!!
MIXER="default"
SCONTROL="Master"
STEP="1"

case $BLOCK_BUTTON in
  3) amixer -q -D $MIXER sset $SCONTROL toggle ;;  # right click, mute/unmute
  4) amixer -q -D $MIXER sset $SCONTROL ${STEP}+ unmute ;; # scroll up, increase
  5) amixer -q -D $MIXER sset $SCONTROL ${STEP}- unmute ;; # scroll down, decrease
esac

echo $(amixer -D "default" get "Master" | grep '%' | sed -nr 's/.*\[([0-9]+%)\].*/\1/p')
echo
echo $colorBlueLight
