# Arch Linux
Scripts and tools for the daily usage of Arch Linux.

### Symlinks for ~/data

```bash
# Spotify, requires redownloading of all offline songs
rm -rf ~/.cache/spotify
#rm -rf ~/.config/spotify
mkdir -p ~/data/spotify
ln -s ~/data/spotify ~/.cache/spotify

# Setup fullscreen mode
nano .config/spotify/prefs
--------------------------
app.window.position.y=0
app.window.position.height=1080
app.window.position.width=1920
```

#### Git send-mail
```
[arch@arch trunk]$ git config --global sendemail.smtpencryption ssl
[arch@arch trunk]$ git config --global sendemail.smtpserver sslout.df.eu
[arch@arch trunk]$ git config --global sendemail.smtpuser mail@nicohood.de
[arch@arch trunk]$ git config --global sendemail.smtpserverport 465
git config --global sendemail.from archlinux@nicohood.de
[arch@arch archweb]$ git config sendemail.to arch-projects@archlinux.org
git send-email -1 --subject-prefix "archweb] [PATCH"
```

### Pulseaudio Loopback Device
https://unix.stackexchange.com/questions/263274/pipe-mix-line-in-to-output-in-pulseaudio

```txt
~/.config/pulse/default.pa
--------------------------
.include /etc/pulse/default.pa
load-module module-loopback --latency-msec=5
```

Stream audio from linux to windows (with lag)
```
# Do NOT use "module-tunnel-sink-new", otherwis combine fails
pactl load-module module-tunnel-sink server=192.168.0.126 sink_name=julian

pactl load-module module-combine-sink slaves=tunnel.zebes.local.alsa_output.usb-M-AUDIO_M-Track_Hub-00.analog-stereo,tunnel.aether.local.alsa_output.pci-0000_00_14.2.analog-stereo,julian,bluez_sink.08_DF_1F_DD_20_9E.a2dp_sink,tunnel.sr388-2.local.alsa_output.platform-soc_audio.analog-mono,tunnel.sr388-2.local.alsa_output.usb-0d8c_C-Media_USB_Headphone_Set-00.analog-stereo resample_method=src-sinc-best-quality adjust_time=1

# On the windows machine (zeroconf does not work)
pulseaudio.exe -D --load="module-native-protocol-tcp auth-anonymous=1" --load="module-esound-protocol-tcp auth-anonymous=1"
#--load=module-zeroconf-publish
```

### Format External HDD

```bash
# Create and mount luks encrypted filesystem
sudo cryptsetup luksFormat -c aes-xts-plain64 -s 512 -h sha512 --use-random /dev/sdX
sudo cryptsetup luksOpen /dev/sdX cryptdisc
sudo dd bs=512 count=4 if=/dev/random of=/root/cryptdisc_keyfile.bin iflag=fullblock
sudo cryptsetup luksAddKey /dev/sdX /root/cryptdisc_keyfile.bin
sudo mkfs.btrfs /dev/mapper/cryptdisc
sudo mount /dev/mapper/cryptdisc /mnt
sudo chown $USER:$USER /mnt

# Edit crypttab
sudo nano /etc/crypttab
cryptdisc UUID=<lsblk -f> /root/cryptdisc_keyfile.bin luks,timeout=30,nofail
sudo shutdown -r now
```

### Rip a new CD
```
rip cd rip --offset 6 --track-temvirtualbox virtualbox-host-dkms virtualbox-guest-iso
rip cd rip --offset 6 --track-template="%R/%A/%d/%t. %n" --disc-template="%R/%A/%d/%A - %d" -U
```

## TODO
* shellcheck
* AUR package
* Makefile
* Script names?
Fix bug with subvolumes in nautilus https://gitlab.gnome.org/GNOME/glib/issues/1271
