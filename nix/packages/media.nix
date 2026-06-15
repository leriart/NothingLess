# Media packages: video, audio, players
{ pkgs }:

with pkgs; [
  gpu-screen-recorder
  mpvpaper

  ffmpeg
  x264
  playerctl

  # Wireless display backends
  uxplay
  miraclecast
  gnome-network-displays

  # Audio
  pipewire
  wireplumber
]
