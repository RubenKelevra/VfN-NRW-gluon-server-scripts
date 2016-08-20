#!/bin/bash 

##preconditions:
#server init script has been run

#old preconditions
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
#echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
#echo 1 > /proc/sys/net/ipv6/conf/default/forwarding
#echo 1 > /proc/sys/net/ipv4/ip_forward_use_pmtu
#touch /etc/sysctl.d/50-default.conf
#install a tun-check-script vom server-script repo

#add the following to /etc/sudoers
 # ### give the user fastd the capability to control batctl
 # fastd ALL=(ALL)NOPASSWD:/usr/bin/batctl
 # fastd ALL=(ALL)NOPASSWD:/usr/bin/brctl
 # fastd ALL=(ALL)NOPASSWD:/usr/bin/ifconfig
 # fastd ALL=(ALL)NOPASSWD:/usr/bin/ip

if [ "$(whoami)" != 'root' ]; then
	echo 'Do run as root.'
	exit 1
fi

if [ ! -f '/etc/sudoers.installed_by_gluon-server-scripts' ]; then
  echo "init-server script seems to have never been run here..."
  exit 1
fi

if [ -z "$1" ]; then
  echo "community has not been selected, enter it as first parameter"
  exit 1
fi
community="$1"

fn="communityprofiles/$community"

if [ ! -f "$fn" ]; then
  echo "community profile could not be found."
  exit 1
fi
source "$fn"
unset fn

HOSTNAME="$(hostname --short)"

fn="serverprofiles/$HOSTNAME"

if [ ! -f "$fn" ]; then
  echo "server profile could not be found."
  exit 1
fi
source "$fn"
unset fn

basic_fastd_port=15000
basic_fastd_port_HMTU=30000
pubkey=""
privkey=""
tmp=""

ipv4_2=$(echo $ipv4_23 | cut -d '.' -f 1)
ipv4_3_netmask=$(echo $ipv4_23 | cut -d '.' -f 2)
ipv4_3=$(($ipv4_3_netmask+$gateway_ip4))

if [ -z "$ipv4_3_netmask" ]; then
  echo "community-profile has a bad net-ip definition"
  exit 1
fi

if [ -z "$ipv4_3_netmask" ]; then
  echo "community-profile has a bad net-ip definition only /17 and /16 is supported"
  exit 1
fi

if [ -z "$fastd_port" ]; then
  echo "community-profile is missing a fastd-port definition"
  exit 1
fi

if [ -z "$subnetmask" ]; then
  echo "community-profile is missing a subnetmask definition"
  exit 1
fi

if [ "$subnetmask" -ne 16 ] && [ "$subnetmask" -ne 17 ]; then
  echo "community-profile's subnetmask definition is unsupported"
  exit 1
fi

if [ -z "$community_short" ]; then
  echo "community-profile is missing a community shortname definition"
  exit 1
fi

if [ "${#community_short}" -gt 4 ]; then
  echo "community-profile's definition of community shortname is to long"
  exit 1
fi

if [ -z "$dialing_code" ]; then
  echo "community-profile is missing a dialing code definition"
  exit 1
fi

if [ -z "$ipv4_23" ]; then
  echo "community-profile is missing a ipv4 subnet definition"
  exit 1
fi

echo "setting up '$community' ..."

echo "please make sure that the community '$community' has been added to mysql-database!"

fastd_port_config=$(($basic_fastd_port+$fastd_port))

sudo mkdir -p /etc/fastd/$community/nodes

pregen_pubkey="pregenerated_keys/$HOSTNAME-$community.pub"
pregen_privkey="pregenerated_keys/private_keys/$HOSTNAME-$community.priv"

if [ -f "$pregen_pubkey" ]; then
  echo "found pregenerated pubkey for community $community..."
  if [ ! -f "$pregen_privkey" ]; then
    echo "could not locate pregenerated privkey..."
    exit 1
  fi
  pubkey="$(cat $pregen_pubkey)"
  privkey="$(cat $pregen_privkey)"
else
  tmp=$(fastd --generate-key)

  pubkey=$(echo $tmp | awk '{print $4}')
  privkey=$(echo $tmp | awk '{print $2}')
  unset tmp
fi

old_dir="$(pwd)"
cd /etc/fastd/$community

echo "key \"$pubkey\"; #public key" > nodes/$servername.server
[ ! -z "$server_pubip4" ] && echo "remote $server_pubip4:$fastd_port_config;" >> nodes/$servername.server
[ ! -z "$server_pubip6" ] && echo "remote [$server_pubip6]:$fastd_port_config;" >> nodes/$servername.server

touch fastd.conf
[ ! -z "$server_pubip4" ] && echo "bind $server_pubip4:$fastd_port_config;" >> fastd.conf
[ ! -z "$server_pubip6" ] && echo "bind [$server_pubip6]:$fastd_port_config;" >> fastd.conf
echo "mode tap;
interface \"ff$community_short-mesh-vpn\";
log to syslog level error;
user \"fastd\";
packet mark 0x42;
method \"salsa2012+umac\";
method \"salsa2012+gmac\";
method \"aes128-ctr+umac\";
method \"aes128-gcm\";
include \"secret.conf\";
# public $pubkey
mtu 1312;
secure handshakes yes;

include peers from \"nodes\";

on up \"
    ip link set up dev \$INTERFACE
    batctl -m mesh-$community_short if add \$INTERFACE
    ip link set up dev mesh-$community_short
    batctl -m mesh-$community_short it 5000
    batctl -m mesh-$community_short nc 0
    batctl -m mesh-$community_short mm 1
    batctl -m mesh-$community_short dat 1
    echo '120' > /sys/class/net/mesh-$community_short/mesh/hop_penalty
    ip rule add iif freifunk-$community_short lookup 42 prio 4200
    ip -6 rule add iif freifunk-$community_short lookup 42 prio 4200
    brctl addif freifunk-$community_short mesh-$community_short
\";

on down \"
    sudo /usr/bin/brctl delif freifunk-$community_short mesh-$community_short
    sudo /usr/bin/batctl -m mesh-$community_short if del \$INTERFACE
    sudo /usr/bin/ip rule del from all iif freifunk-$community_short lookup 42 prio 4200
    sudo /usr/bin/ip -6 rule del from all iif freifunk-$community_short lookup 42 prio 4200
\";

on verify \"/usr/local/bin/fastd-verify\";" | sudo tee fastd.conf > /dev/null


echo "secret \"$privkey\";" | sudo tee secret.conf > /dev/null
unset privkey

sudo chmod go-rwx /etc/fastd/$community/secret.conf

sudo chown fastd: -R /etc/fastd/$community

cd $old_dir

echo "fastd-config done."

fastd_port_config=$(($basic_fastd_port_HMTU+$fastd_port))

sudo mkdir -p /etc/fastd/${community}HMTU/nodes

pregen_pubkey="pregenerated_keys/$HOSTNAME-$community-HMTU.pub"
pregen_privkey="pregenerated_keys/private_keys/$HOSTNAME-$community-HMTU.priv"

if [ -f "$pregen_pubkey" ]; then
  echo "found pregenerated pubkey for community ${community}-HMTU..."
  if [ ! -f "$pregen_privkey" ]; then
    echo "could not locate pregenerated privkey..."
    exit 1
  fi
  pubkey="$(cat $pregen_pubkey)"
  privkey="$(cat $pregen_privkey)"
else
  tmp=$(fastd --generate-key)

  pubkey=$(echo $tmp | awk '{print $4}')
  privkey=$(echo $tmp | awk '{print $2}')
  unset tmp
fi

old_dir="$(pwd)"
cd /etc/fastd/${community}HMTU

echo "key \"$pubkey\"; #public key" > nodes/$servername.server
[ ! -z "$server_pubip4" ] && echo "remote $server_pubip4:$fastd_port_config;" >> nodes/$servername.server
[ ! -z "$server_pubip6" ] && echo "remote [$server_pubip6]:$fastd_port_config;" >> nodes/$servername.server

touch fastd.conf
[ ! -z "$server_pubip4" ] && echo "bind $server_pubip4:$fastd_port_config;" >> fastd.conf
[ ! -z "$server_pubip6" ] && echo "bind [$server_pubip6]:$fastd_port_config;" >> fastd.conf
echo "mode tap;
interface \"ff$community_short-meshvpnH\";
log to syslog level error;
user \"fastd\";
packet mark 0x42;
method \"salsa2012+umac\";
method \"salsa2012+gmac\";
method \"aes128-ctr+umac\";
method \"aes128-gcm\";
include \"secret.conf\";
# public $pubkey
mtu 3064;
secure handshakes yes;

include peers from \"nodes\";

on up \"
    ip link set up dev \$INTERFACE
    batctl -m mesh-$community_short if add \$INTERFACE
    ip link set up dev mesh-$community_short
    batctl -m mesh-$community_short it 5000
    batctl -m mesh-$community_short nc 0
    batctl -m mesh-$community_short mm 1
    batctl -m mesh-$community_short dat 1
    echo '120' > /sys/class/net/mesh-$community_short/mesh/hop_penalty
    ip rule add iif freifunk-$community_short lookup 42 prio 4200
    ip -6 rule add iif freifunk-$community_short lookup 42 prio 4200
    brctl addif freifunk-$community_short mesh-$community_short
\";

on down \"
    sudo /usr/bin/brctl delif freifunk-$community_short mesh-$community_short
    sudo /usr/bin/batctl -m mesh-$community_short if del \$INTERFACE
    sudo /usr/bin/ip rule del from all iif freifunk-$community_short lookup 42 prio 4200
    sudo /usr/bin/ip -6 rule del from all iif freifunk-$community_short lookup 42 prio 4200
\";

on verify \"/usr/local/bin/fastd-verify\";" | sudo tee fastd.conf > /dev/null


echo "secret \"$privkey\";" | sudo tee secret.conf > /dev/null
unset privkey

sudo chmod go-rwx /etc/fastd/${community}HMTU/secret.conf

sudo chown fastd: -R /etc/fastd/${community}HMTU

cd $old_dir

echo "High MTU fastd-config done."

echo "generating netctl-profile for bridge-interface"
old_dir="$(pwd)"
cd /etc/netctl

sudo touch freifunk-$community_short
echo "Description='Freifunk-Bridge for $community'
Interface=freifunk-$community_short
Connection=bridge
BindsToInterfaces=()
IP=static
Address=('10.$ipv4_2.$ipv4_3.0/$subnetmask')

## For IPv6 static address configuration
IP6=static
Address6=('2001:bf7:100:$dialing_code::c$servernumber/64' 'fddf:ebfd:a801:$dialing_code::c$servernumber/64' 'fddf:ebfd:a801:$dialing_code::ac1/64 preferred 0')
SkipForwardingDelay=yes

ExecUpPost=\"ip link set freifunk-$community_short txqueuelen 1000 && tc qdisc replace dev freifunk-$community_short root fq limit 1000 flow_limit 25 buckets 256 quantum 394 initial_quantum 15140 ; echo 0 > /proc/sys/net/ipv6/conf/freifunk-$community_short/accept_dad\"
" | sudo tee freifunk-$community_short > /dev/null

cd $old_dir

echo "netctl-config done."

sudo netctl start freifunk-$community_short
sudo netctl reenable freifunk-$community_short >/dev/null 2>&1 

echo "bridge started."

sudo systemctl enable fastd@$community
sudo systemctl start fastd@$community

sudo systemctl enable fastd@${community}HMTU
sudo systemctl start fastd@${community}HMTU

echo "fastd started."

if [ $subnetmask -eq 16 ]; then
  subnetmask_binary="255.255.0.0"
  broadcast_addr="$(echo 10.$ipv4_2.$(expr $ipv4_3_netmask + 255).255)"
  dhcp_range_start="$(echo 10.$ipv4_2.$(expr $ipv4_3_netmask + 2).0)"
  dhcp_range_end="$(echo 10.$ipv4_2.$(expr $ipv4_3_netmask + 255).254)"

elif [ $subnetmask -eq 17 ]; then
  subnetmask_binary="255.255.128.0"
  broadcast_addr="$(echo 10.$ipv4_2.$(expr $ipv4_3_netmask + 127).255)"
  dhcp_range_start="$(echo 10.$ipv4_2.$(expr $ipv4_3_netmask + 2).0)"
  dhcp_range_end="$(echo 10.$ipv4_2.$(expr $ipv4_3_netmask + 127).254)"
else
  echo "unexpected error 1831"
  exit 1
fi

sudo mkdir -p /etc/dhcp.d-freifunk/

dhcpd_config="/etc/dhcp.d-freifunk/$community.conf"

printf "\n\
# $community.freifunk.net subnet and dhcp range for server\n\
\n\
subnet 10.$ipv4_2.$ipv4_3_netmask.0 netmask $subnetmask_binary {\n\
  range $dhcp_range_start $dhcp_range_end; #main\n\
  option broadcast-address $broadcast_addr;\n\
  option routers 10.$ipv4_2.$ipv4_3.0;\n\
  option domain-name-servers 10.$ipv4_2.$ipv4_3.0;\n\
  option ntp-servers 10.$ipv4_2.$ipv4_3.0;\n\
  server-identifier 10.$ipv4_2.$ipv4_3.0;\n\
  interface freifunk-$community_short;\n\
}\n\
\n" | sudo tee "$dhcpd_config" > /dev/null

cat /etc/dhcpd.conf | grep -v "$dhcpd_config" > /etc/dhcpd.conf.tmp
cat /etc/dhcpd.conf.tmp > /etc/dhcpd.conf
rm /etc/dhcpd.conf.tmp
echo "include \"$dhcpd_config\";" | sudo tee -a /etc/dhcpd.conf > /dev/null


sudo chmod 644 "$dhcpd_config"

unset dhcpd_config

echo "dhcpd-config done."

sudo systemctl restart dhcpd4

echo "dhcpd restarted."

sudo sed -i -e "s/\/\/#6+#/fddf:ebfd:a801:$dialing_code::c$servernumber;\n\
        fddf:ebfd:a801:$dialing_code::ac1;\n\
        2001:bf7:100:$dialing_code::c$servernumber;\n\
        \/\/#6+#/" /etc/named.conf

sudo sed -i -e "s/\/\/#4+#/10.$ipv4_2.$gateway_ip4.0;\n\
        \/\/#4+#/" /etc/named.conf

echo "named-config done."

sudo systemctl restart named

echo "named restarted."

sudo sed -i -e "s/#=+#/\n\
  interface freifunk-$community_short #$community\n\
  \{\n\
      AdvSendAdvert on;\n\
      IgnoreIfMissing on;\n\
      MaxRtrAdvInterval 200;\n\
      AdvLinkMTU $radvd_AdvLinkMTU;\n\
  \n\
      prefix 2001:bf7:100:$dialing_code::\/64\n\
      \{\n\
      \};\n\
  \n\
      RDNSS 2001:bf7:100:$dialing_code::ac1\n\
      \{\n\
      \};\n\
  \n\
      prefix fddf:ebfd:a801:$dialing_code::\/64\n\
      \{\n\
      \};\n\
  \n\
      RDNSS fddf:ebfd:a801:$dialing_code::ac1\n\
      \{\n\
      \};\n\
  \};\n\
  #=+#/" /etc/radvd.conf

echo "radvd-config done."
sudo systemctl restart radvd
echo "radvd restarted."

sudo systemctl restart ntpd

echo "ntpd restarted."

sudo sed -i -e "s/#=+#/meshdevs+=('mesh-$community_short')\n\
#=+#/" /usr/local/bin/tun-01_check.sh

echo "tun-check-script updated... in 60 seconds online at most."

exit 0

#configure bird
sudo sed -i -e "s/#=+1#/if net ~ 10.$ipv4_2.0.0\/16 then reject;\n\
        #=+1#/" /etc/bird.conf

sudo sed -i -e "s/#=+2#/route 10.$ipv4_2.0.0\/16 via \"freifunk-$community_short\";\n\
        #=+2#/" /etc/bird.conf

echo "bird-config done."  

sudo systemctl restart bird

echo "bird restarted."

#configure bird6
if [ $bPublic_ip6 -eq 1 ]; then
  sed -i -e "s/#=+1#/route 2001:bf7:100:$dialing_code::\/64 via \"freifunk-$community_short\";\n\
        #=+1#/" /etc/bird6.conf
fi

sed -i -e "s/#=+2#/route fddf:ebfd:a801:$dialing_code::\/64 via \"freifunk-$community_short\";\n\
        #=+2#/" /etc/bird6.conf
  
echo "bird6-config done."  
  
sudo systemctl restart bird6

echo "bird6 restarted."

echo ""
echo ""

echo "site.conf sample code for this peer:"
echo ""
echo "
$servername = {
  key = '$pubkey',"
if [ ! -z "$server_pubip4" && ! -z "$server_pubip6" ]; then
  echo "  remotes = {'[$server_pubip6] port $fastd_port', '$server_pubip4 port $fastd_port'},"
elif [ ! -z "$server_pubip4" && -z "$server_pubip6" ]; then
  echo "  remotes = {'$server_pubip4 port $fastd_port'},"
elif [ -z "$server_pubip4" && ! -z "$server_pubip6" ]; then
  echo "  remotes = {'[$server_pubip6] port $fastd_port'},"
elif [ -z "$server_pubip4" && -z "$server_pubip6" ]; then
  echo "  remotes = {},"
echo "},"

echo "

Goodbye!"

