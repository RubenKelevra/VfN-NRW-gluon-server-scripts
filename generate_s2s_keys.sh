if [ "$(whoami)" == 'root' ]; then
	echo 'Do not run as root. Use an account with sudo-rights.'
	exit 1
fi

HOSTNAME="$(hostname --short)"

fn="serverprofiles/$HOSTNAME"

if [ ! -f "$fn" ]; then
  echo "server profile could not be found."
  exit 1
fi
source "$fn"
unset fn

if [ -z "$server_pubip6" ]; then
  echo "no IPv6 for server found"
  exit 0
fi

communitys="$(ls -1 communityprofiles)"

mkdir privkeys -p

for community in $communitys; do
	
	## Generate HTMU-Key
	tmp=$(fastd --generate-key)

	pubkey=$(echo $tmp | awk '{print $4}')
	privkey=$(echo $tmp | awk '{print $2}')
	unset tmp
	
	if [ -f "fastd-peers/$community/$server.server" ]; then
	  echo "warning: server profile for community $community already exists, skipping"
	  continue
	fi
	echo "key \"$pubkey\"; #public key" > "fastd-peers/$community/$server.server"
  [ ! -z "$server_pubip6" ] && echo "remote [$server_pubip6]:$fastd_port_config;" >> "fastd-peers/$community/$server.server"
	
	echo "$privkey" > "privkeys/$server-$community-HMTU.priv"
	
	unset pubkey privkey

	## Generate Normal Key
	tmp=$(fastd --generate-key)

	pubkey=$(echo $tmp | awk '{print $4}')
	privkey=$(echo $tmp | awk '{print $2}')
	unset tmp
	
	echo "$pubkey" > "$server-$community.pub"
	echo "$privkey" > "$server-$community.priv"
	
	unset pubkey privkey
done
