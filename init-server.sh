#!/bin/bash 

#Warning: This script is for Arch-Linux only, use carefully, it overwrites several config-files without any queries!

if [ "$(whoami)" == "root" ]; then
	echo "Do not run as root. Use a account with sudo-rights."
	exit 1
fi

packagelist="iproute2 base-devel net-tools bird bird6 dhcp radvd bind openvpn haveged bridge-utils tinc fastd batctl batman-adv"

yaourt -S $packagelist --needed --noconfirm

unset packagelist

install_folder='basic-config'


[ "$install_folder" == "" ] && exit 1

fns=()
fns+=('/etc/iptables/iptables.rules')
fns+=('/etc/openvpn/tun-01.conf')
fns+=('/etc/openvpn/tun-01_pass.txt')
fns+=('/etc/openvpn/tun-01_up.sh')
fns+=('/etc/sysctl.d/99-sysctl.conf')
fns+=('/etc/dhcpd.conf')
fns+=('/etc/named.conf')
fns+=('/etc/radvd.conf')

for fn in $fns; do
	[ "$fn" == "" ] && exit 1
	if [ ! -f "$fn"]; then
		sudo touch "$fn" || echo "folder for file $fn does not exist, exiting"
		exit 1
	fi
	cat "${install_folder}${fn}" > sudo tee "${fn}"
done
