#!/bin/bash 

if [ "$(whoami)" != "root" ]; then
	echo "Please run as root"
	exit 1
fi

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
		touch "$fn" || echo "folder for file $fn does not exist, exiting"
		exit 1
	fi
	cat "${install_folder}${fn}" > "${fn}"
done
