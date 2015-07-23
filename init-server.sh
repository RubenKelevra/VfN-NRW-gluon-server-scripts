#!/bin/bash 

set -e

#Warning: This script is for Arch-Linux only, use carefully, it overwrites several config-files without any queries!

#check enviroment
if [ ! -f '/etc/arch-release' ]; then
	echo 'this linux seems not to be an ArchLinux, so we exit now.'
	exit 1
fi

if [ "$(whoami)" == 'root' ]; then
	echo 'Do not run as root. Use an account with sudo-rights.'
	exit 1
fi

#settings
install_folder='basic-config'
packagelist='iproute2 base-devel net-tools bird bird6 dhcp radvd bind openvpn haveged bridge-utils tinc fastd batctl batman-adv'

#install packages
yaourt -S $packagelist --needed --noconfirm
unset packagelist

#prepare system
sudo useradd --system --no-create-home --shell /bin/false fastd || true
sudo useradd --system --no-create-home --shell /bin/false openvpn || true

#create config-files
[ "$install_folder" == '' ] && exit 1

declare -a fns
fns+=('/etc/iptables/iptables.rules')
fns+=('/etc/openvpn/tun-01.conf')
fns+=('/etc/openvpn/tun-01_pass.txt')
fns+=('/etc/openvpn/tun-01_up.sh')
fns+=('/etc/sysctl.d/99-sysctl.conf')
fns+=('/etc/dhcpd.conf')
fns+=('/etc/named.conf')
fns+=('/etc/radvd.conf')
fns+=('/etc/bird.conf')
fns+=('/usr/local/bin/tun-01_check.sh')

#now copy default content to config files, if they doesn't exit, but the folders
#touch them before filling them, else exit
for fn in $fns; do
	[ "$fn" == '' ] && exit 1
	if [ ! -f "$fn" ]; then
		if [ ! `sudo touch "$fn"` ]; then
			echo "folder for file $fn does not exist, exiting"
			exit 1
		fi
	fi
	if [ ! -f "${install_folder}${fn}" ]; then
		echo "file $fn which is marked for installation could not be found"
		exit 1
	fi
	sudo cp  "${install_folder}${fn}" "${fn}"
done

unset fn fns

#fixing rp-filter
sudo touch /etc/sysctl.d/50-default.conf

#fixing rights
sudo chmod +x /etc/openvpn/tun-01_up.sh
sudo chmod +x /usr/local/bin/tun-01_check.sh

#enabling services
sudo systemctl enable bird bird6 radvd named iptables openvpn@tun-01

#starting services
#FIXME wait for adding openvpn@tun-01 account infos
#FIXME ask for ROUTERID for bird
sudo systemctl start bird bird6 radvd named iptables openvpn@tun-01
