#!/bin/bash
cd ~
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

## Error checks

perl -i -ne 'print if ! $a{$_}++' /etc/network/interfaces

if [ ! -d "/root/bin" ]; then
mkdir /root/bin
fi

## Setup

if [ ! -f "/root/bin/dep" ]
then
  clear
  echo -e "Installing ${GREEN}Transcendence dependencies${NC}. Please wait."
  sleep 2
  apt update 
  apt -y upgrade
  apt update
  apt install -y zip unzip bc curl nano lshw gawk ufw
  
  ## Checking for Swap
  
  if [ ! -f /var/swap.img ]
  then
  echo -e "${RED}Creating swap. This may take a while.${NC}"
  dd if=/dev/zero of=/var/swap.img bs=2048 count=1M
  chmod 600 /var/swap.img
  mkswap /var/swap.img 
  swapon /var/swap.img 
  free -m
  echo "/var/swap.img none swap sw 0 0" >> /etc/fstab
  fi
  
  ufw allow ssh/tcp
  ufw limit ssh/tcp
  ufw logging on
  echo "y" | ufw enable 
  ufw allow 8051
  echo 'export PATH=~/bin:$PATH' > ~/.bash_aliases
  echo ""
  cd
  sysctl vm.swappiness=30
  sysctl vm.vfs_cache_pressure=200
  echo 'vm.swappiness=30' | tee -a /etc/sysctl.conf
  echo 'vm.vfs_cache_pressure=200' | tee -a /etc/sysctl.conf
  touch /root/bin/dep
fi

## Constants

IP4COUNT=$(find /root/.transcendence_* -maxdepth 0 -type d 2>/dev/null | wc -l)
IP6COUNT=$(crontab -l -u root 2>/dev/null | wc -l)
DELETED="$(cat /root/bin/deleted 2>/dev/null | wc -l)"
ALIASES="$(find /root/.transcendence_* -maxdepth 0 -type d 2>/dev/null | cut -c22-)"
face="$(lshw -C network | grep "logical name:" | sed -e 's/logical name:/logical name: /g' | awk '{print $3}' | head -n1)"
IP4=$(curl -s4 api.ipify.org)
version=$(curl -s https://raw.githubusercontent.com/phoenixkonsole/Masternode-tools/master/current)
link=$(curl -s https://raw.githubusercontent.com/phoenixkonsole/Masternode-tools/master/download)
PORT=8051
RPCPORTT=8351
gateway1=$(/sbin/route -A inet6 | grep -v ^fe80 | grep -v ^ff00 | grep -w "$face")
gateway2=${gateway1:0:26}
gateway3="$(echo -e "${gateway2}" | tr -d '[:space:]')"
if [[ $gateway3 = *"128"* ]]; then
  gateway=${gateway3::-5}
fi
if [[ $gateway3 = *"64"* ]]; then
  gateway=${gateway3::-3}
fi
MASK="/64"

## Systemd Function

function configure_systemd() {
  cat << EOF > /etc/systemd/system/transcendenced$ALIAS.service
[Unit]
Description=transcendenced$ALIAS service
After=network.target
 [Service]
User=root
Group=root
Type=forking
#PIDFile=/root/.transcendence_$ALIAS/transcendenced.pid
ExecStart=/root/bin/transcendenced_$ALIAS.sh
ExecStop=/root/bin/transcendence-cli_$ALIAS.sh stop
Restart=always
PrivateTmp=true
TimeoutStopSec=160s
TimeoutStartSec=100s
StartLimitInterval=240s
StartLimitBurst=5
 [Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  sleep 2
  echo "sleep 20" >> /root/bin/start_nodes.sh
  echo "systemctl start transcendenced$ALIAS" >> /root/bin/start_nodes.sh
  chmod +x /root/bin/start_nodes.sh
  systemctl start transcendenced$ALIAS.service
}

function configure_bashrc() {
	echo "alias ${ALIAS}_status=\"transcendence-cli -datadir=/root/.transcendence_${ALIAS} masternode status\"" >> .bashrc
	echo "alias ${ALIAS}_stop=\"systemctl stop transcendenced$ALIAS\"" >> .bashrc
	echo "alias ${ALIAS}_start=\"systemctl start transcendenced$ALIAS\""  >> .bashrc
	echo "alias ${ALIAS}_config=\"nano /root/.transcendence_${ALIAS}/transcendence.conf\""  >> .bashrc
	echo "alias ${ALIAS}_getinfo=\"transcendence-cli -datadir=/root/.transcendence_${ALIAS} getinfo\"" >> .bashrc
	echo "alias ${ALIAS}_getpeerinfo=\"transcendence-cli -datadir=/root/.transcendence_${ALIAS} getpeerinfo\"" >> .bashrc
	echo "alias ${ALIAS}_resync=\"/root/bin/transcendenced_${ALIAS}.sh -resync\"" >> .bashrc
	echo "alias ${ALIAS}_reindex=\"/root/bin/transcendenced_${ALIAS}.sh -reindex\"" >> .bashrc
	echo "alias ${ALIAS}_restart=\"systemctl restart transcendenced$ALIAS\""  >> .bashrc
}

## Check for wallet update

clear

if [ -f "/usr/local/bin/transcendenced" ]
then

if [ ! -f "/root/bin/$version" ]
then

echo -e "${GREEN}Please wait, updating wallet.${NC}"
sleep 1

mnalias=$(find /root/.transcendence_* -maxdepth 0 -type d | cut -c22- | head -n 1)
PROTOCOL=$(transcendence-cli -datadir=/root/.transcendence_${mnalias} getinfo | grep "protocolversion" | sed 's/[^0-9]*//g')

if [ $PROTOCOL != 71006 ]
then
sed -i 's/22123/8051/g' /root/.transcendence*/transcendence.conf
rm .transcendence*/blocks -rf
rm .transcendence*/chainstate -rf
rm .transcendence*/sporks -rf
rm .transcendence*/zerocoin -rf
fi

wget $link -O /root/Linux.zip 
rm /usr/local/bin/transcendence*
unzip Linux.zip -d /usr/local/bin 
chmod +x /usr/local/bin/transcendence*
rm Linux.zip
mkdir /root/bin
touch /root/bin/$version
echo -e "${GREEN}Wallet updated.${NC} ${RED}PLEASE RESTART YOUR NODES OR REBOOT VPS WHEN POSSIBLE.${NC}"
echo ""

fi

fi

## Start of Guided Script
if [ -z $1 ]; then
echo "1 - Create new nodes"
echo "2 - Remove an existing node"
echo "3 - List aliases"
echo "4 - Check node status"
echo "5 - Compile wallet locally"
echo "What would you like to do?"
read DO
echo ""
else
DO=$1
ALIAS=$2
ALIASD=$2
PRIVKEY=$3
fi

if [ $DO = "help" ]
then
echo "Usage:"
echo "./lobohub.sh Action Alias PrivateKey"
fi

## List aliases

if [ $DO = "3" ]
then
echo -e "${GREEN}${ALIASES}${NC}"
echo ""
echo "1 - Create new nodes"
echo "2 - Remove an existing node"
echo "4 - Check for node errors"
echo "5 - Compile wallet locally (optional)"
echo "What would you like to do?"
read DO
echo ""
fi

## Compiling wallet

if [ $DO = "5" ]
then
echo -e "${GREEN}Compiling wallet, this may take some time.${NC}"
sleep 2
systemctl stop transcendenced*

if [ ! -f "/root/bin/depc" ]
then

## Installing pre-requisites

apt install -y zip unzip bc curl nano lshw ufw gawk libdb++-dev git zip automake software-properties-common unzip build-essential libtool autotools-dev autoconf pkg-config libssl-dev libcrypto++-dev libevent-dev libminiupnpc-dev libgmp-dev libboost-all-dev devscripts libsodium-dev libprotobuf-dev protobuf-compiler libcrypto++-dev libminiupnpc-dev gcc-5 g++-5 --auto-remove
thr="$(nproc)"

## Compatibility issues
  
  export LC_CTYPE=en_US.UTF-8
  export LC_ALL=en_US.UTF-8
  apt update
  apt install libssl1.0-dev -y
  apt install libzmq3-dev -y --auto-remove
  update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-5 100
  update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-5 100
  touch /root/bin/depc

fi

## Preparing and building

  git clone https://github.com/phoenixkonsole/transcendence -b 3.0.4
  cd transcendence
  ./autogen.sh
  ./configure --with-incompatible-bdb --disable-tests --without-gui
  make -j $thr
  make install
  touch /root/bin/$version
  
systemctl start transcendenced*

fi

## Checking for node errors

if [ $DO = "4" ]
then

echo $ALIASES > temp1
cat temp1 | grep -o '[^ |]*' > temp2
CN="$(cat temp2 | wc -l)"
rm temp1
let LOOP=0

while [  $LOOP -lt $CN ]
do

LOOP=$((LOOP+1))
CURRENT="$(sed -n "${LOOP}p" temp2)"

echo -e "${GREEN}${CURRENT}${NC}:"
sh /root/bin/transcendence-cli_${CURRENT}.sh masternode status | grep "message"
done


fi

## Properly Deleting node

if [ $DO = "2" ]
then
if [ -z $1 ]; then
echo "Input the alias of the node that you want to delete"
read ALIASD
fi

echo ""
echo -e "${GREEN}Deleting ${ALIASD}${NC}. Please wait."

## Removing service

systemctl stop transcendenced$ALIASD >/dev/null 2>&1
systemctl disable transcendenced$ALIASD >/dev/null 2>&1
rm /etc/systemd/system/transcendenced${ALIASD}.service >/dev/null 2>&1
systemctl daemon-reload >/dev/null 2>&1
systemctl reset-failed >/dev/null 2>&1
lineNum="$(grep -n "${ALIASD}" bin/start_nodes.sh | head -n 1 | cut -d: -f1)"
lineNum2=$((lineNum+1))

sed -i "${lineNum}d;${lineNum2}d" /root/bin/start_nodes.sh

## Removing node files 

rm /root/.transcendence_$ALIASD -r >/dev/null 2>&1
sed -i "/${ALIASD}/d" .bashrc
crontab -l -u root | grep -v $ALIASD | crontab -u root - >/dev/null 2>&1

source ~/.bashrc
echo "1" >> /root/bin/deleted
rm /root/bin/transcendence*_$ALIASD.sh
echo -e "${ALIASD} Successfully deleted."

fi

## Creating new nodes

if [ $DO = "1" ]
then
MAXC="32"
if [ ! -f "/usr/local/bin/transcendenced" ]
then
  ## Downloading and installing wallet 
  echo -e "${GREEN}Downloading precompiled wallet${NC}"
  wget $link -O /root/Linux.zip 
  mkdir /root/bin
  touch /root/bin/$version
  unzip Linux.zip -d /usr/local/bin 
  chmod +x /usr/local/bin/transcendence*
  rm Linux.zip  
fi

## Downloading bootstrap

if [ ! -f bootstrap.zip ]
then
wget https://github.com/ZenH2O/001/releases/download/Latest/block1358538.zip && wget https://github.com/ZenH2O/001/releases/download/Latest/block1358538.z01 && zip -s- block1358538.zip -O /root/bootstrap.zip
fi

## Start of node creation

echo -e "Telos Node currently installed: ${GREEN}${IP4COUNT}${NC}, Telos nodes previously Deleted: ${GREEN}${DELETED}${NC}"
echo ""


if [ $IP4COUNT = "0" ] 
then

echo -e "${RED}Masternode must be ipv4 as ipv6 is not supported anymore since TELOS 2.x.${NC}"
let COUNTER=0
RPCPORT=$(($RPCPORTT+$COUNTER))
  if [ -z $1 ]; then
  echo ""
  echo "Enter alias for first node"
  read ALIAS
  echo ""
  echo "Enter masternode private key for node $ALIAS"
  read PRIVKEY
  fi
  CONF_DIR=/root/.transcendence_$ALIAS
  
  mkdir /root/.transcendence_$ALIAS
  unzip bootstrap.zip -d /root/.transcendence_$ALIAS >/dev/null 2>&1
  echo '#!/bin/bash' > ~/bin/transcendenced_$ALIAS.sh
  echo "transcendenced -daemon -conf=$CONF_DIR/transcendence.conf -datadir=$CONF_DIR "'$*' >> ~/bin/transcendenced_$ALIAS.sh
  echo '#!/bin/bash' > ~/bin/transcendence-cli_$ALIAS.sh
  echo "transcendence-cli -conf=$CONF_DIR/transcendence.conf -datadir=$CONF_DIR "'$*' >> ~/bin/transcendence-cli_$ALIAS.sh
  echo '#!/bin/bash' > ~/bin/transcendence-tx_$ALIAS.sh
  echo "transcendence-tx -conf=$CONF_DIR/transcendence.conf -datadir=$CONF_DIR "'$*' >> ~/bin/transcendence-tx_$ALIAS.sh
  chmod 755 ~/bin/transcendence*.sh

  echo "rpcuser=user"`shuf -i 100000-10000000 -n 1` >> transcendence.conf_TEMP
  echo "rpcpassword=pass"`shuf -i 100000-10000000 -n 1` >> transcendence.conf_TEMP
  echo "rpcallowip=127.0.0.1" >> transcendence.conf_TEMP
  echo "rpcport=$RPCPORT" >> transcendence.conf_TEMP
  echo "listen=1" >> transcendence.conf_TEMP
  echo "server=1" >> transcendence.conf_TEMP
  echo "daemon=1" >> transcendence.conf_TEMP
  echo "logtimestamps=1" >> transcendence.conf_TEMP
  echo "maxconnections=$MAXC" >> transcendence.conf_TEMP
  echo "masternode=1" >> transcendence.conf_TEMP
  echo "dbcache=20" >> transcendence.conf_TEMP
  echo "maxorphantx=5" >> transcendence.conf_TEMP
  echo "maxmempool=100" >> transcendence.conf_TEMP
  echo "" >> transcendence.conf_TEMP
  echo "" >> transcendence.conf_TEMP
  echo "bind=$IP4:$PORT" >> transcendence.conf_TEMP
  echo "externalip=$IP4" >> transcendence.conf_TEMP
  echo "masternodeaddr=$IP4:$PORT" >> transcendence.conf_TEMP
  echo "masternodeprivkey=$PRIVKEY" >> transcendence.conf_TEMP
  
  mv transcendence.conf_TEMP $CONF_DIR/transcendence.conf
  
  crontab -l > cron$ALIAS
  echo "@reboot sh /root/bin/start_nodes.sh" >> cron$ALIAS
  crontab cron$ALIAS
  rm cron$ALIAS
  echo ""
  echo -e "Your ip is ${GREEN}$IP4:$PORT${NC}"
  
	## Setting up .bashrc
	configure_bashrc
	## Creating systemd service
	configure_systemd
fi

if [ $IP4COUNT != "0" ] 
then
if [ -z $1 ]; then
echo "How many ipv6 nodes do you want to install on this server?"
read MNCOUNT
else
MNCOUNT=1
fi

## This can probably be shortened but whatever

let MNCOUNT=MNCOUNT+1
let MNCOUNT=MNCOUNT+IP4COUNT
let MNCOUNT=MNCOUNT+DELETED
let COUNTER=1
let COUNTER=COUNTER+IP4COUNT
let COUNTER=COUNTER+DELETED

while [  $COUNTER -lt $MNCOUNT ]
do
  RPCPORT=$(($RPCPORTT+$COUNTER))
  
  if [ -z $1 ]; then
  echo ""
  echo "Enter alias for new node"
  read ALIAS
  echo ""
  echo "Enter masternode private key for node $ALIAS"
  read PRIVKEY
  fi
  
  CONF_DIR=/root/.transcendence_$ALIAS
  /sbin/ip -6 addr add ${gateway}$COUNTER$MASK dev $face
  mkdir /root/.transcendence_$ALIAS
  
  unzip bootstrap.zip -d ~/.transcendence_$ALIAS >/dev/null 2>&1
  echo '#!/bin/bash' > ~/bin/transcendenced_$ALIAS.sh
  echo "transcendenced -daemon -conf=$CONF_DIR/transcendence.conf -datadir=$CONF_DIR "'$*' >> ~/bin/transcendenced_$ALIAS.sh
  echo '#!/bin/bash' > ~/bin/transcendence-cli_$ALIAS.sh
  echo "transcendence-cli -conf=$CONF_DIR/transcendence.conf -datadir=$CONF_DIR "'$*' >> ~/bin/transcendence-cli_$ALIAS.sh
  echo '#!/bin/bash' > ~/bin/transcendence-tx_$ALIAS.sh
  echo "transcendence-tx -conf=$CONF_DIR/transcendence.conf -datadir=$CONF_DIR "'$*' >> ~/bin/transcendence-tx_$ALIAS.sh
  chmod 755 ~/bin/transcendence*.sh
  
  echo "rpcuser=user"`shuf -i 100000-10000000 -n 1` >> transcendence.conf_TEMP
  echo "rpcpassword=pass"`shuf -i 100000-10000000 -n 1` >> transcendence.conf_TEMP
  echo "rpcallowip=127.0.0.1" >> transcendence.conf_TEMP
  echo "rpcport=$RPCPORT" >> transcendence.conf_TEMP
  echo "listen=1" >> transcendence.conf_TEMP
  echo "server=1" >> transcendence.conf_TEMP
  echo "daemon=1" >> transcendence.conf_TEMP
  echo "logtimestamps=1" >> transcendence.conf_TEMP
  echo "maxconnections=$MAXC" >> transcendence.conf_TEMP
  echo "masternode=1" >> transcendence.conf_TEMP
  echo "dbcache=20" >> transcendence.conf_TEMP
  echo "maxorphantx=5" >> transcendence.conf_TEMP
  echo "maxmempool=100" >> transcendence.conf_TEMP
  echo "bind=[${gateway}$COUNTER]:$PORT" >> transcendence.conf_TEMP
  echo "externalip=[${gateway}$COUNTER]" >> transcendence.conf_TEMP
  echo "masternodeaddr=[${gateway}$COUNTER]:$PORT" >> transcendence.conf_TEMP
  echo "masternodeprivkey=$PRIVKEY" >> transcendence.conf_TEMP
  mv transcendence.conf_TEMP $CONF_DIR/transcendence.conf
  
  crontab -l -u root | grep -v start_nodes.sh | crontab -u root -
  crontab -l > cron$ALIAS
  echo "@reboot /sbin/ip -6 addr add ${gateway}$COUNTER$MASK dev $face # $ALIAS" >> cron$ALIAS
  crontab cron$ALIAS
  rm cron$ALIAS
  crontab -l > cron$ALIAS
  echo "@reboot sh /root/bin/start_nodes.sh" >> cron$ALIAS
  crontab cron$ALIAS
  rm cron$ALIAS
  
  echo ""
  echo -e "Your ip is ${GREEN}[${gateway}$COUNTER]:$PORT${NC}"
  
	## Setting up .bashrc
	configure_bashrc
	## Creating systemd service
	configure_systemd
	COUNTER=$((COUNTER+1))
	
done

fi

echo ""
echo -e "${RED}Please do not set maxconnections lower than 16 and not higher than 32 or your node may not receive rewards as often.${NC}"
echo ""
echo -e "${RED}If every member of the community buys TELOS for 1$ a day we quickly reach a value of 1$ per coin.${NC}"
echo ""
echo "Commands:"
echo "${ALIAS}_start"
echo "${ALIAS}_restart"
echo "${ALIAS}_status"
echo "${ALIAS}_stop"
echo "${ALIAS}_config"
echo "${ALIAS}_getinfo"
echo "${ALIAS}_getpeerinfo"
echo "${ALIAS}_resync"
echo "${ALIAS}_reindex"
fi

echo ""
echo "Lobocain by GrumpyDEV blatantly stolen from lobo & xispita in the name of the Transcendence community "
echo "lobo's Transcendence Address for donations: GWe4v6A6tLg9pHYEN5MoAsYLTadtefd9o6"
echo "xispita's Transcendence Address for donations: GRDqyK7m9oTsXjUsmiPDStoAfuX1H7eSfh" 
echo "GrumpyDEV's Milkpot ................. nah.. enjoy and buy at least for 30$ TELOS" 
echo "Bitcoin Address for donations: oh common !! Who cares about Bitcoin? Shame on you Lobo!"
source ~/.bashrc
