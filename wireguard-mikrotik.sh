#!/bin/bash
# https://github.com/fedor2018/wireguard-mikrotik
# https://github.com/angristan/wireguard-install.git
#
CFG_DIR=$1
PARAMS=$CFG_DIR/.params
CLI_DIR=$CFG_DIR/clients
MK_DIR=$CFG_DIR/mikrotik
CLI_MK_DIR=$MK_DIR/clients
QR_DIR=$CFG_DIR/qr
OW_DIR=$CFG_DIR/openwrt
CLI_OW_DIR=$OW_DIR/clients
DEF_ALLOW_IP="0.0.0.0/1,128.0.0.0/1,::/1,8000::/1"
MTU=1280
KA=25 #keepalive

function paramQuestions() {
	echo "Welcome to the WireGuard generator for Mikrotik!"
	echo "The git repository is available at: https://github.com/fedor2018/wireguard-mikrotik"
	echo ""
	echo "I need to ask you a few questions before starting the setup."
	echo "You can leave the default options and just press enter if you are ok with them."
	echo ""

	read -rp "Server IPv4 or IPv6 public address: " -e -i "${SERVER_PUB_IP}" SERVER_PUB_IP

	until [[ ${SERVER_WG_NIC} =~ ^[a-zA-Z0-9_]+$ && ${#SERVER_WG_NIC} -lt 16 ]]; do
		read -rp "WireGuard interface name: " -e -i wg0 SERVER_WG_NIC
	done

	until [[ ${SERVER_WG_IPV4} =~ ^([0-9]{1,3}\.){3} ]]; do
		read -rp "Server's WireGuard IPv4: " -e -i 10.66.66.1 SERVER_WG_IPV4
	done

	until [[ ${SERVER_WG_IPV6} =~ ^([a-f0-9]{1,4}:){3,4}: ]]; do
		read -rp "Server's WireGuard IPv6: " -e -i fd42:42:42::1 SERVER_WG_IPV6
	done

	# Generate random number within private ports range
	RANDOM_PORT=$(shuf -i49152-65535 -n1)
	until [[ ${SERVER_PORT} =~ ^[0-9]+$ ]] && [ "${SERVER_PORT}" -ge 1 ] && [ "${SERVER_PORT}" -le 65535 ]; do
		read -rp "Server's WireGuard port [1-65535]: " -e -i "${RANDOM_PORT}" SERVER_PORT
	done

	# Adguard DNS by default
	until [[ ${CLIENT_DNS_1} =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
		read -rp "First DNS resolver to use for the clients: " -e -i ${SERVER_WG_IPV4} CLIENT_DNS_1
	done
	until [[ ${CLIENT_DNS_2} =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
		read -rp "Second DNS resolver to use for the clients (optional): " -e -i ${SERVER_WG_IPV4} CLIENT_DNS_2
		if [[ ${CLIENT_DNS_2} == "" ]]; then
			CLIENT_DNS_2="${CLIENT_DNS_1}"
		fi
	done

	echo ""
	echo "You will be able to generate a client at the end of the installation."
}

function srv_mk_gen() {
    ACT=add
    PRIV_KEY=$1
    ADDR=$2
echo "/interface/wireguard/$ACT \\
    listen-port=${SERVER_PORT} mtu=$MTU name=${SERVER_WG_NIC} \\
    private-key=\"${PRIV_KEY}\" comment=\"${SERVER_WG_NIC}\"
/ip/address/$ACT \\
    address=$ADDR/24 interface=${SERVER_WG_NIC} network=${SERVER_WG_IPV4}"0" comment=\"${SERVER_WG_NIC}\"
/interface list member $ACT \\
    interface=${SERVER_WG_NIC} list=LAN comment=\"${SERVER_WG_NIC}\"
/ip/firewall/filter $ACT \\
    action=accept comment="${SERVER_WG_NIC}srv" chain=input dst-port=${SERVER_PORT} protocol=udp \\
/ip/firewall/filter move \\
    [find comment=\"${SERVER_WG_NIC}srv\"] [find comment~\"ICMP\" and chain=input]
"
}

function srv_peer_mk_gen() {
    ACT=add
echo "/interface/wireguard/peers/$ACT \\
    interface=${SERVER_WG_NIC} \\
    comment=\"${SERVER_WG_NIC} peer ${CLIENT_NAME}\" \\
    public-key=\"${CLIENT_PUB_KEY}\" \\
    preshared-key=\"${CLIENT_PRE_SHARED_KEY}\" \\
    allowed-address=${CLIENT_WG_IPV4}/32 \\
    persistent-keepalive=00:00:${KA}"
}

function cli_mk_gen() {
    ACT=add
echo "/interface/wireguard/peers/$ACT \\
    interface=${SERVER_WG_NIC} \\
    comment=\"${SERVER_WG_NIC} peer ${CLIENT_NAME}\" \\
    public-key=\"${SERVER_PUB_KEY}\" \\
    preshared-key=\"${CLIENT_PRE_SHARED_KEY}\" \\
    allowed-address=\"${DEF_ALLOW_IP}\" \\
    endpoint-address=${SERVER_PUB_IP}  \\
    endpoint-port=${SERVER_PORT}  \\
    persistent-keepalive=00:00:${KA}"
}

function srv_mk_remove() {
echo "/interface/list/member remove [find where comment~\"${SERVER_WG_NIC}\"]
/ip/firewall/filter remove [ find where comment~\"${SERVER_WG_NIC}\" ]
/ip/address remove [find where comment~\"${SERVER_WG_NIC}\"]
/interface/wireguard/peers remove [find comment~\"${SERVER_WG_NIC}\"]
/interface/wireguard remove [find comment~\"${SERVER_WG_NIC}\"]
"

}

function srv_ow_gen() {
    PRIV_KEY=$1
    ADDR=$2
echo "uci set network.${SERVER_WG_NIC}=interface
uci set network.${SERVER_WG_NIC}.proto='wireguard'
uci set network.${SERVER_WG_NIC}.private_key='${PRIV_KEY}'
uci set network.${SERVER_WG_NIC}.listen_port='${SERVER_PORT}'
uci set network.${SERVER_WG_NIC}.addresses='$ADDR/24'
uci commit network

uci set \`uci show firewall|grep zone|grep name|grep lan|sed 's/.name.*//'\`.network='lan' '${SERVER_WG_NIC}'

uci add firewall rule # =cfg1292bd
uci set firewall.@rule[-1].dest_port='${SERVER_PORT}'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].name='${SERVER_WG_NIC}'
uci set firewall.@rule[-1].target='ACCEPT'
uci add_list firewall.@rule[-1].proto='udp'
uci commit firewall
"
}
# add to /etc/config/network
function srv_ow_gen_cfg() {
    PRIV_KEY=$1
    ADDR=$2
echo "# example
config interface '${SERVER_WG_NIC}'
        option proto 'wireguard'
        option private_key '${PRIV_KEY}'
        option listen_port '${SERVER_PORT}'
        list addresses '$ADDR/24'
        option mtu '$MTU'
"
}
# peer
function srv_peer_ow_gen() {
	CLI=$1 #CLIENT_NAME
echo "uci add network wireguard_${SERVER_WG_NIC}
uci add_list network.@wireguard_${SERVER_WG_NIC}[-1].allowed_ips='${CLIENT_WG_IPV4}/32'
uci set network.@wireguard_${SERVER_WG_NIC}[-1].public_key='${CLIENT_PUB_KEY}'
uci set network.@wireguard_${SERVER_WG_NIC}[-1].description='${SERVER_WG_NIC} peer ${CLI}'
uci set network.@wireguard_${SERVER_WG_NIC}[-1].persistent_keepalive='${KA}'
uci set network.@wireguard_${SERVER_WG_NIC}[-1].preshared_key='${CLIENT_PRE_SHARED_KEY}'

uci commit network
"
}

# (/etc/config/network)
function srv_peer_ow_gen_cfg() {
	CLI=$1 #CLIENT_NAME
echo "config wireguard_${SERVER_WG_NIC}
        list allowed_ips '${CLIENT_WG_IPV4}/32'
        option public_key '${CLIENT_PUB_KEY}'
        option description '${SERVER_WG_NIC} peer ${CLI}'
        option persistent_keepalive '${KA}'
        option preshared_key '${CLIENT_PRE_SHARED_KEY}'
"
}

# client
function cli_ow_gen() {
	CLI=$1 #CLIENT_NAME
echo "uci add network wireguard_${SERVER_WG_NIC}"
IFS=,
for I in $DEF_ALLOW_IP;do
echo "uci add_list network.@wireguard_${SERVER_WG_NIC}[-1].allowed_ips='$I'"
done
echo "uci set network.@wireguard_${SERVER_WG_NIC}[-1].public_key='${SERVER_PUB_KEY}'
uci set network.@wireguard_${SERVER_WG_NIC}[-1].description='${SERVER_WG_NIC} client ${CLI}'
uci set network.@wireguard_${SERVER_WG_NIC}[-1].endpoint_host='${SERVER_PUB_IP}'
uci set network.@wireguard_${SERVER_WG_NIC}[-1].endpoint_port='${SERVER_PORT}'
uci set network.@wireguard_${SERVER_WG_NIC}[-1].persistent_keepalive='${KA}'
uci set network.@wireguard_${SERVER_WG_NIC}[-1].preshared_key='${CLIENT_PRE_SHARED_KEY}'
uci set network.@wireguard_${SERVER_WG_NIC}[-1].route_allowed_ips='1'

uci commit network
"
}
# (/etc/config/network)
function cli_ow_gen_cfg() {
	CLI=$1 #CLIENT_NAME
echo "config wireguard_${SERVER_WG_NIC}"
IFS=,
for I in $DEF_ALLOW_IP;do
echo "        list allowed_ips '$I'"
done
echo "        list allowed_ips '128.0.0.0/1'
        option public_key '${CLIENT_PUB_KEY}'
        option description '${SERVER_WG_NIC} client ${CLI}'
        option endpoint_host '${SERVER_PUB_IP}'
        option endpoint_port '${SERVER_PORT}'
        option persistent_keepalive '${KA}'
        option preshared_key '${CLIENT_PRE_SHARED_KEY}'
        option route_allowed_ips '1'
"
}

function srv_gen() {
	# Add server interface
[ -n "${SERVER_WG_IPV6}" ] && TMP=,${SERVER_WG_IPV6}/64
	echo "[Interface]
Address = ${SERVER_WG_IPV4}1/24$TMP
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}"

[ -z "${SERVER_PUB_NIC}" ] && TMP="#" &&  SERVER_PUB_NIC="<ext interface>"
echo "${TMP}PostUp = iptables -A FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT; \
iptables -A FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; \
iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE; \
ip6tables -A FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; \
ip6tables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
${TMP}PostDown = iptables -D FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT; \
iptables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; \
iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE; \
ip6tables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; \
ip6tables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
"
}

function srv_peer_gen() {
    TMP=$1
echo -e "\n### Client ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32${TMP}
"
}

function cli_gen() {
    TMP=$1
echo "[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_WG_IPV4}/32${TMP}
DNS = ${CLIENT_DNS_1},${CLIENT_DNS_2}
ListenPort = ${SERVER_PORT}
MTU=$MTU

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
PersistentKeepalive = ${KA}
Endpoint = ${ENDPOINT}
AllowedIPs = ${DEF_ALLOW_IP}
"
}

function coreConfig() {
	# Run setup questions first

	SERVER_PRIV_KEY=$(wg genkey)
	SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)
	SERVER_PRE_KEY=$(wg genpsk)
	SERVER_WG_IPV4=$(echo $SERVER_WG_IPV4|awk -F"." '{print $1"."$2"."$3"."}')

	# Save WireGuard settings
	echo "SERVER_PUB_IP=${SERVER_PUB_IP}
#SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${SERVER_WG_NIC}
SERVER_WG_IPV4=${SERVER_WG_IPV4}
SERVER_WG_IPV6=${SERVER_WG_IPV6}
SERVER_PORT=${SERVER_PORT}
MTU=$MTU
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}" > $PARAMS
#
srv_gen >"$CFG_DIR/${SERVER_WG_NIC}.conf"
#
srv_mk_gen ${SERVER_PRIV_KEY} ${SERVER_WG_IPV4}1 > "$MK_DIR/server.rsc"
srv_mk_remove > "$MK_DIR/remove.rsc"
#
srv_ow_gen ${SERVER_PRIV_KEY} ${SERVER_WG_IPV4}1 > "$OW_DIR/server.uci"
srv_ow_gen_cfg ${SERVER_PRIV_KEY} ${SERVER_WG_IPV4}1 > "$OW_DIR/network"
}

function newClient() {
	ENDPOINT="${SERVER_PUB_IP}:${SERVER_PORT}"

	echo ""
	echo "Tell me a name for the client."
	echo "The name must consist of alphanumeric character. It may also include an underscore or a dash and can't exceed 15 chars."

	until [[ ${CLIENT_NAME} =~ ^[a-zA-Z0-9_-]+$ && ${CLIENT_EXISTS} == '0' && ${#CLIENT_NAME} -lt 16 ]]; do
		read -rp "Client name: " -e CLIENT_NAME
		CLIENT_EXISTS=$(grep -c -E "^### Client ${CLIENT_NAME}\$" "$CFG_DIR/${SERVER_WG_NIC}.conf")

		if [[ ${CLIENT_EXISTS} == '1' ]]; then
			echo ""
			echo "A client with the specified name was already created, please choose another name."
			echo ""
		fi
	done

	for DOT_IP in {2..254}; do
		DOT_EXISTS=$(grep -c "${SERVER_WG_IPV4}${DOT_IP}" "$CFG_DIR/${SERVER_WG_NIC}.conf")
		if [[ ${DOT_EXISTS} == '0' ]]; then
			break
		fi
	done

	if [[ ${DOT_EXISTS} == '1' ]]; then
		echo ""
		echo "The subnet configured supports only 253 clients."
		exit 1
	fi

	BASE_IP=$(echo "$SERVER_WG_IPV4" | awk -F '.' '{ print $1"."$2"."$3 }')
	until [[ ${IPV4_EXISTS} == '0' ]]; do
		read -rp "Client's WireGuard IPv4: ${BASE_IP}." -e -i "${DOT_IP}" DOT_IP
		CLIENT_WG_IPV4="${BASE_IP}.${DOT_IP}"
		IPV4_EXISTS=$(grep -c "$CLIENT_WG_IPV4/24" "$CFG_DIR/${SERVER_WG_NIC}.conf")

		if [[ ${IPV4_EXISTS} == '1' ]]; then
			echo ""
			echo "A client with the specified IPv4 was already created, please choose another IPv4."
			echo ""
		fi
	done

	BASE_IP=$(echo "$SERVER_WG_IPV6" | awk -F '::' '{ print $1 }')
	until [[ ${IPV6_EXISTS} == '0' ]]; do
		[ -z "${IPV6_EXISTS}" ] && break
		read -rp "Client's WireGuard IPv6: ${BASE_IP}::" -e -i "${DOT_IP}" DOT_IP
		CLIENT_WG_IPV6="${BASE_IP}::${DOT_IP}"
		IPV6_EXISTS=$(grep -c "${CLIENT_WG_IPV6}/64" "$CFG_DIR/${SERVER_WG_NIC}.conf")

		if [[ ${IPV6_EXISTS} == '1' ]]; then
			echo ""
			echo "A client with the specified IPv6 was already created, please choose another IPv6."
			echo ""
		fi
	done


        CLIENT_PRIV_KEY=$(wg genkey)
        CLIENT_PUB_KEY=$(echo "${CLIENT_PRIV_KEY}" | wg pubkey)
        CLIENT_PRE_SHARED_KEY=$(wg genpsk)

    [ -n "${CLIENT_WG_IPV6}" ] && TMP=,${CLIENT_WG_IPV6}
    NAME=${CLIENT_NAME}
	# Create client file and add the server as a peer

cli_gen $TMP > "${CLI_DIR}/${NAME}.conf"
srv_peer_gen $TMP >>"$CFG_DIR/${SERVER_WG_NIC}.conf"
#
srv_peer_mk_gen > "${MK_DIR}/${CLIENT_NAME}-peer.rsc"
srv_mk_gen $CLIENT_PRIV_KEY ${CLIENT_WG_IPV4}  > "${CLI_MK_DIR}/${CLIENT_NAME}.rsc"
cli_mk_gen >> "${CLI_MK_DIR}/${CLIENT_NAME}.rsc"
#??
srv_peer_ow_gen ${CLIENT_NAME} >> $OW_DIR/server.uci
srv_peer_ow_gen_cfg ${CLIENT_NAME} >> $OW_DIR/network
srv_ow_gen $CLIENT_PRIV_KEY ${CLIENT_WG_IPV4}  > "${CLI_OW_DIR}/${CLIENT_NAME}.uci"
cli_ow_gen ${CLIENT_NAME} >> "${CLI_OW_DIR}/${CLIENT_NAME}.uci"

srv_ow_gen_cfg ${CLIENT_PRIV_KEY} ${CLIENT_WG_IPV4} > "${CLI_OW_DIR}/${CLIENT_NAME}.cfg"
cli_ow_gen_cfg ${CLIENT_NAME} >> "${CLI_OW_DIR}/${CLIENT_NAME}.cfg"
#
qrencode -t png -l L -r "${CLI_DIR}/${NAME}.conf" -o "${QR_DIR}/${NAME}.png"
}

function help() {
    echo "$0 <config dir>"
    exit
}

which wg >/dev/null
[ $? -ne 0 ] && echo "wg not installed" && exit
which qrencode >/dev/null
[ $? -ne 0 ] && echo "qrencode not installed" && exit

[ -z "$CFG_DIR" ] && help

if [ -f $PARAMS ];then
    source $PARAMS
    newClient
else
    mkdir -p $CLI_DIR
    mkdir -p $CLI_MK_DIR
    mkdir -p $QR_DIR
    mkdir -p $CLI_OW_DIR
    paramQuestions
    coreConfig
fi
