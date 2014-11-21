#!/bin/bash 

##preconditions:
#pacman -S iproute2 base-devel net-tools bird bird6 dhcp radvd bind openvpn haveged bridge-utils tinc
#yaourt -S fastd batctl batman-adv
#useradd --system --no-create-home --shell /bin/false fastd
#useradd --system --no-create-home --shell /bin/false openvpn
#config-files from folder basic-config


function input_str { # $1 is output
  ret=""
  while [ -z $ret ]; do
    read -p "$1 " ret
    [ -z $ret ] && echo "enter a value!"
  done
}

servername="rig"
servernumber="04" #for ipv6 cXX
server_pubip4="62.141.34.115"
server_pubip6=""
gateway_ip4="1" # 10.xx.n.0 we set n here

community=""
community_short=""
dialing_code=""
ipv4_2=""
fastd_port=15000
pubkey=""
privkey=""
tmp=""

input_str "Name for the new Community (lowercase):"
community="$ret"

echo "please make sure that the community '$community' has been added to mysql-database."

input_str "Short-name for the new Community (max 4 letters!, lowercase):"
community_short="$ret"

#FIXME add check

input_str "First 3-4 numbers of the dialing_code of the townhall, without leading zero!:"
dialing_code="$ret"

#FIXME add check

input_str "Enter the second group of private IP4 (10.xx.0.0/16):"
ipv4_2="$ret"

#FIXME add check

fastd_port=$(expr $fastd_port + $ret)

echo "Generating fastd-config..."

mkdir -p /etc/fastd/$community/nodes

cd /etc/fastd/$community

tmp=$(fastd --generate-key)

pubkey=$(echo $tmp | awk '{print $4}')
privkey=$(echo $tmp | awk '{print $2}')
unset tmp

echo "key \"$pubkey\"; #public key" > nodes/$servername.server
[ ! -z "$server_pubip4" ] && echo "remote $server_pubip4:$fastd_port;" >> nodes/$servername.server
[ ! -z "$server_pubip6" ] && echo "remote $server_pubip6:$fastd_port;" >> nodes/$servername.server

touch fastd.conf
[ ! -z "$server_pubip4" ] && echo "bind $server_pubip4:$fastd_port;" >> fastd.conf
[ ! -z "$server_pubip6" ] && echo "bind [$server_pubip6]:$fastd_port;" >> fastd.conf
echo "mode tap;
interface \"ff$community_short-mesh-vpn\";
log to syslog level error;
user \"fastd\";
method \"salsa2012+gmac\";
include \"secret.conf\";
# public $pubkey
mtu 1426;
secure handshakes yes;

include peers from \"nodes\";

on up \"
    ip link set up dev \$INTERFACE
    batctl -m mesh-$community_short if add \$INTERFACE
    ip link set up dev mesh-$community_short
    batctl -m mesh-$community_short it 5000
    batctl -m mesh-$community_short nc 0
    batctl -m mesh-$community_short mm 0
    batctl -m mesh-$community_short dat 1
    echo '120' > /sys/class/net/mesh-$community_short/mesh/hop_penalty
    ip rule add iif freifunk-$community_short lookup 42
    brctl addif freifunk-$community_short mesh-$community_short
\";

on down \"
    sudo /usr/bin/brctl delif freifunk-$community_short mesh-$community_short
    sudo /usr/bin/batctl -m mesh-$community_short if del \$INTERFACE
\";" >> fastd.conf


echo "secret \"$privkey\";" > secret.conf
unset privkey

echo "generating netctl-profile for bridge-interface"
cd /etc/netctl

touch freifunk-$community_short
echo "Description='Freifunk-Bridge for $community'
Interface=freifunk-$community_short
Connection=bridge
BindsToInterfaces=()
IP=static
Address=('10.$ipv4_2.$gateway_ip4.0/16')

## For IPv6 static address configuration
IP6=static
Address6=('fda0:747e:ab29:$dialing_code::c$servernumber/64')
SkipForwardingDelay=yes" >> freifunk-$community_short

echo "starting bridge..."
netctl start freifunk-$community_short
netctl enable freifunk-$community_short

systemctl enable fastd@$community
systemctl start fastd@$community

sed -i -e "s/#=+#/\n\
# $community.freifunk.net subnet and dhcp range for server\n\
\n\
subnet 10.$ipv4_2.0.0 netmask 255.255.0.0 {\n\
  range 10.$ipv4_2.$gateway_ip4.1 10.$ipv4_2.$(expr $gateway_ip4 + 9).255;\n\
  option broadcast-address 10.$ipv4_2.255.255;\n\
  option routers 10.$ipv4_2.$gateway_ip4.0;\n\
  option domain-name-servers 10.$ipv4_2.$gateway_ip4.0;\n\
  option ntp-servers 10.$ipv4_2.$gateway_ip4.0;\n\
  interface freifunk-$community_short;\n\
}\n\
\n\
#=+#/" /etc/dhcpd.conf

systemctl restart dhcpd4

sed -i -e "s/\/\/#6+#/fda0:747e:ab29:$dialing_code::c$servernumber;\n\
        \/\/#6+#/" /etc/named.conf
        
sed -i -e "s/\/\/#4+#/10.$ipv4_2.$gateway_ip4.0;\n\
        \/\/#4+#/" /etc/named.conf

systemctl restart named

#radvd missing

#bird missing

#bird6 missing 

systemctl restart ntpd

echo "

MESH=mesh-$community_short

OLD_STATE=\"\$(cat /sys/class/net/\$MESH/mesh/gw_mode)\"
if [ \"\$OLD_STATE\" != \"\$NEW_STATE\" ]; then
  echo \$NEW_STATE > /sys/class/net/\$MESH/mesh/gw_mode
  echo 96MBit/96MBit > /sys/class/net/\$MESH/mesh/gw_bandwidth
fi
" >> /usr/local/bin/tun-vpn-01_check.sh
