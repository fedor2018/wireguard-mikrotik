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

function srv_gen() {
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
#/ip/firewall/filter $ACT \\
#    action=accept comment="${SERVER_WG_NIC}inp" chain=input in-interface=wg0 src-address=${SERVER_WG_IPV4}0/24
#/ip/firewall/filter $ACT \\
#    action=accept comment="${SERVER_WG_NIC}frw" chain=forward in-interface=wg0 src-address=${SERVER_WG_IPV4}0/24
#/ip/firewall/filter move \\
#    [find comment=\"${SERVER_WG_NIC}inp\"] [find comment~\"ICMP\" and chain=input]
#/ip/firewall/filter move \\
#    [find comment=\"${SERVER_WG_NIC}frw\"] [find comment~\"drop inv\" and chain=forward]

}

function srv_peer_gen() {
    ACT=add
echo "/interface/wireguard/peers/$ACT \\
    interface=${SERVER_WG_NIC} \\
    comment=\"${SERVER_WG_NIC} peer ${CLIENT_NAME}\" \\
    public-key=\"${CLIENT_PUB_KEY}\" \\
    preshared-key=\"${CLIENT_PRE_SHARED_KEY}\" \\
    allowed-address=${CLIENT_WG_IPV4}/32 \\
    persistent-keepalive=00:00:25"
# > "${CFG_DIR}/${CLIENT_NAME}-server.rsc"
}

function cli_gen() {
    ACT=add
echo "/interface/wireguard/peers/$ACT \\
    interface=${SERVER_WG_NIC} \\
    comment=\"${SERVER_WG_NIC} peer ${CLIENT_NAME}\" \\
    public-key=\"${SERVER_PUB_KEY}\" \\
    preshared-key=\"${CLIENT_PRE_SHARED_KEY}\" \\
    allowed-address=\"0.0.0.0/0,::/0\" \\
    endpoint-address=${SERVER_PUB_IP}  \\
    endpoint-port=${SERVER_PORT}  \\
    persistent-keepalive=00:00:25"
# >> "${CFG_DIR}/${CLIENT_NAME}-client.rsc"
}

function srv_remove() {
echo "/interface/list/member remove [find where comment~\"${SERVER_WG_NIC}\"]
/ip/firewall/filter remove [ find where comment~\"${SERVER_WG_NIC}\" ]
/ip/address remove [find where comment~\"${SERVER_WG_NIC}\"]
/interface/wireguard/peers remove [find comment~\"${SERVER_WG_NIC}\"]
/interface/wireguard remove [find comment~\"${SERVER_WG_NIC}\"]
"

}

function coreConfig() {
	# Run setup questions first

	SERVER_PRIV_KEY=$(wg genkey)
	SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)
	SERVER_PRE_KEY=$(wg genpsk)
	SERVER_WG_IPV4=$(echo $SERVER_WG_IPV4|awk -F"." '{print $1"."$2"."$3"."}')
	MTU=1280

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

	# Add server interface
[ -n "${SERVER_WG_IPV6}" ] && TMP=,${SERVER_WG_IPV6}/64
	echo "[Interface]
Address = ${SERVER_WG_IPV4}1/24$TMP
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}" >"$CFG_DIR/${SERVER_WG_NIC}.conf"

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
ip6tables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE" >>"$CFG_DIR/${SERVER_WG_NIC}.conf"

srv_gen ${SERVER_PRIV_KEY} ${SERVER_WG_IPV4}1 > "$MK_DIR/server.rsc"
srv_remove > "$MK_DIR/remove.rsc"

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
	echo "[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_WG_IPV4}/32${TMP}
DNS = ${CLIENT_DNS_1},${CLIENT_DNS_2}
ListenPort = ${SERVER_PORT}
MTU=$MTU

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
PersistentKeepalive = 25
Endpoint = ${ENDPOINT}
AllowedIPs = 0.0.0.0/0,::/0" >>"${CLI_DIR}/${NAME}.conf"

	# Add the client as a peer to the server
#,${CLIENT_WG_IPV6}/128
	echo -e "\n### Client ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32${TMP}" >>"$CFG_DIR/${SERVER_WG_NIC}.conf"

qrencode -t png -l L -r "${CLI_DIR}/${NAME}.conf" -o "${QR_DIR}/${NAME}.png"

srv_peer_gen > "${MK_DIR}/${CLIENT_NAME}-peer.rsc"
#srv_peer_gen remove >> "${MK_DIR}/${CLIENT_NAME}-server-remove.rsc"
srv_gen $CLIENT_PRIV_KEY ${CLIENT_WG_IPV4}  > "${CLI_MK_DIR}/${CLIENT_NAME}.rsc"
cli_gen >> "${CLI_MK_DIR}/${CLIENT_NAME}.rsc"

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
    paramQuestions
    coreConfig
fi
