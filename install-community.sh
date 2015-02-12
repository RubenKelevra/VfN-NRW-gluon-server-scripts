#!/bin/bash 

##preconditions:
#pacman -S iproute2 base-devel net-tools bird bird6 dhcp radvd bind openvpn haveged bridge-utils tinc
#yaourt -S fastd batctl batman-adv
#useradd --system --no-create-home --shell /bin/false fastd
#useradd --system --no-create-home --shell /bin/false openvpn
#create openvpn@tun-01 config 
#chmod +x /etc/openvpn/tun-01_up.sh
#config-files from folder basic-config
#systemctl enable named iptables openvpn@tun-01
#systemctl start named iptables openvpn@tun-01
#echo 1 > /proc/sys/net/ipv4/ip_forward
#echo 1 > /proc/sys/net/ipv4/ip_forward_use_pmtu
#touch /etc/sysctl.d/50-default.conf



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
bPublic_ip6=0
radvd_AdvLinkMTU=1448

community=""
community_short=""
dialing_code=""
ipv4_2=""
fastd_port=15000
pubkey=""
privkey=""
tmp=""

input_str "Name for the new community (lowercase):"
community="$ret"

echo "please make sure that the community '$community' has been added to mysql-database."

input_str "Short-name for the new Community (max 4 letters!, lowercase):"
community_short="$ret"

#FIXME add check

input_str "First 3-4 numbers of the dialing code of the townhall, without leading zero!:"
dialing_code="$ret"

#FIXME add check

input_str "Enter the second group of private IP4 (10.xx.0.0/16):"
ipv4_2="$ret"

#FIXME add check

fastd_port=$(expr $fastd_port + $ret)

mkdir -p /etc/fastd/$community/nodes

cd /etc/fastd/$community

tmp=$(fastd --generate-key)

pubkey=$(echo $tmp | awk '{print $4}')
privkey=$(echo $tmp | awk '{print $2}')
unset tmp

echo "key \"$pubkey\"; #public key" > nodes/$servername.server
[ ! -z "$server_pubip4" ] && echo "remote $server_pubip4:$fastd_port;" >> nodes/$servername.server
[ ! -z "$server_pubip6" ] && echo "remote [$server_pubip6]:$fastd_port;" >> nodes/$servername.server

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

echo "fastd-config done."

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

echo "netctl-config done."


netctl start freifunk-$community_short
netctl enable freifunk-$community_short

echo "bridge started."

systemctl enable fastd@$community
systemctl start fastd@$community

echo "fastd started."

#generate blockranges
blockranges=""
if [ $gateway_ip4 -eq 1 ]; then
  blockranges="  pool {\n\
    range 10.$ipv4_2.11.1 10.$ipv4_2.254.255;\n\
    deny all clients;\n\
  }"
else
  blockonestart=$(expr $gateway_ip4 - 10)
  blockoneend=$(expr $gateway_ip4 - 1)
  blocktwostart=$(expr $gateway_ip4 + 19)
  blockranges="    pool {\n\
        range 10.$ipv4_2.$blockonestart.1 10.$ipv4_2.$blockoneend.255;\n\
        deny all clients;\n\
    }\n\
    pool {\n\
        range 10.$ipv4_2.$blocktwostart.1 10.$ipv4_2.254.255;\n\
        deny all clients;\n\
    }"
fi


sed -i -e "s/#=+#/\n\
# $community.freifunk.net subnet and dhcp range for server\n\
\n\
subnet 10.$ipv4_2.0.0 netmask 255.255.0.0 {\n\
  range 10.$ipv4_2.$gateway_ip4.1 10.$ipv4_2.$(expr $gateway_ip4 + 9).255; #main\n\
  $blockranges\n\
  option broadcast-address 10.$ipv4_2.255.255;\n\
  option routers 10.$ipv4_2.$gateway_ip4.0;\n\
  option domain-name-servers 10.$ipv4_2.$gateway_ip4.0;\n\
  option ntp-servers 10.$ipv4_2.$gateway_ip4.0;\n\
  interface freifunk-$community_short;\n\
}\n\
\n\
#=+#/" /etc/dhcpd.conf

echo "dhcpd-config done."

systemctl restart dhcpd4

echo "dhcpd restarted."

sed -i -e "s/\/\/#6+#/fda0:747e:ab29:$dialing_code::c$servernumber;\n\
        \/\/#6+#/" /etc/named.conf

if [ $bPublic_ip6 -eq 1 ]; then
  sed -i -e "s/\/\/#6+#/2001:bf7:100:$dialing_code::c$servernumber;\n\
        \/\/#6+#/" /etc/named.conf
fi

sed -i -e "s/\/\/#4+#/10.$ipv4_2.$gateway_ip4.0;\n\
        \/\/#4+#/" /etc/named.conf

echo "named-config done."

systemctl restart named

echo "named restarted."

if [ $bPublic_ip6 -eq 1 ]; then
  sed -i -e "s/#=+#/\n\
  interface freifunk-$community_short #$community\n\
  {\n\
      AdvSendAdvert on;\n\
      IgnoreIfMissing on;\n\
      MaxRtrAdvInterval 200;\n\
      AdvLinkMTU $radvd_AdvLinkMTU;\n\
  \n\
      prefix 2001:bf7:100:$dialing_code::/64\n\
      {\n\
      };\n\
  \n\
      RDNSS 2001:bf7:100:$dialing_code::c$servernumber\n\
      {\n\
      };\n\
  };\n\
  #=+#/" /etc/radvd.conf
  
  echo "radvd-config done."
  
  systemctl restart radvd
  
  echo "radvd restarted."
else
  echo "skipping radvd..."
fi

#configure bird
sed -i -e "s/#=+1#/\n\
  if net ~ 10.$ipv4_2.0.0/16 then reject;\n\
  #=+1#/" /etc/bird.conf

sed -i -e "s/#=+2#/\n\
  route 10.$ipv4_2.0.0/16 via "freifunk-$community_short";\n\
  #=+2#/" /etc/bird.conf

echo "bird-config done."  

systemctl restart bird

echo "bird restarted."

#configure bird6
if [ $bPublic_ip6 -eq 1 ]; then
  sed -i -e "s/#=+1#/\n\
    route 2001:bf7:100:$dialing_code::/64 via "freifunk-$community_short";\n\
    #=+1#/" /etc/bird6.conf
fi

sed -i -e "s/#=+2#/\n\
  route fda0:747e:ab29:$dialing_code::/64 via "freifunk-$community_short";\n\
  #=+2#/" /etc/bird6.conf
  
echo "bird6-config done."  
  
systemctl restart bird6

echo "bird6 restarted."

systemctl restart ntpd

echo "ntpd restarted."

echo "

MESH=mesh-$community_short

OLD_STATE=\"\$(cat /sys/class/net/\$MESH/mesh/gw_mode)\"
if [ \"\$OLD_STATE\" != \"\$NEW_STATE\" ]; then
  echo \$NEW_STATE > /sys/class/net/\$MESH/mesh/gw_mode
  echo 96MBit/96MBit > /sys/class/net/\$MESH/mesh/gw_bandwidth
fi
" >> /usr/local/bin/tun-vpn-01_check.sh

echo "tun-check-script updated... in 60 seconds online at most.

Goodbye!"
