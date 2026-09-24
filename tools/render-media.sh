#!/bin/zsh
# Regenerate the README images and GIFs in docs/images from the app's real SwiftUI views.
# Needs ffmpeg (brew install ffmpeg). Nothing is shown on screen; frames are rendered offscreen.
set -euo pipefail
cd "${0:A:h}/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp tools/render-media.swift "$tmp/main.swift"          # top-level code must live in main.swift
swiftc -swift-version 5 -O -o "$tmp/render" ${(f)"$(ls src/*.swift | grep -v main.swift)"} "$tmp/main.swift"
OUT="$tmp/f" "$tmp/render"
f="$tmp/f"; o=docs/images; mkdir -p $o
gif() {  # gif <frames dir> <out> <filter> [dither]
  ffmpeg -loglevel error -y -framerate 15 -i "$1/%04d.png" -vf "$3,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=${4:-sierra2_4a}:diff_mode=rectangle" -loop 0 "$2"
}
gif $f/takeover $o/takeover.gif  "fps=12,scale=640:-1:flags=lanczos" "bayer:bayer_scale=4"
gif $f/hold     $o/hold-to-exit.gif "crop=1000:560:460:230,scale=640:-1:flags=lanczos"
gif $f/volume   $o/volume.gif    "crop=760:180:1160:0,scale=560:-1:flags=lanczos"
gif $f/launch   $o/launch.gif    "scale=800:-1:flags=lanczos"
gif $f/rewind   $o/rewind.gif    "scale=800:-1:flags=lanczos"
ffmpeg -loglevel error -y -i $f/now-playing.png -q:v 3 $o/now-playing.jpg
ffmpeg -loglevel error -y -i $f/still-xbox.png -i $f/still-playstation.png -i $f/still-steam.png \
  -filter_complex "[0]scale=640:-1[a];[1]scale=640:-1[b];[2]scale=640:-1[c];[a][b][c]hstack=3" -q:v 3 $o/controllers.jpg
ffmpeg -loglevel error -y -i $f/message-0.png -i $f/message-1.png -i $f/message-2.png \
  -filter_complex "[0]crop=1300:130:310:0[a];[1]crop=1300:130:310:0[b];[2]crop=1300:130:310:0[c];[a][b][c]vstack=3,scale=900:-1" -q:v 3 $o/messages.jpg

# A short tour video (MP4, H.264): the same scenes, 1280x720, fading between them.
v=docs/videos; mkdir -p $v
clip() { ffmpeg -loglevel error -y -framerate 15 -i "$1/%04d.png" -vf "scale=1280:720:flags=lanczos,fps=30,fade=in:d=0.4,reverse,fade=in:d=0.4,reverse,format=yuv420p" -c:v libx264 -crf 24 -preset slow "$tmp/$2.mp4"; }
clip $f/takeover 1; clip $f/launch 2; clip $f/hold 3; clip $f/volume 4; clip $f/rewind 5
printf "file '%s'\n" $tmp/{1,2,3,4,5}.mp4 > $tmp/list.txt
ffmpeg -loglevel error -y -f concat -safe 0 -i $tmp/list.txt -c copy -movflags +faststart $v/console-mode-tour.mp4
ls -la $o $v
