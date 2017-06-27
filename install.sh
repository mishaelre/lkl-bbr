#! /bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
#=================================================================#
#   System Required:  Debian8_x64                                   #
#   Description: One click Install lkl-bbr kcp               #
#   Adapt from: 91yun <https://twitter.com/91yun>                     #
#   Thanks: @allient neko   @linrong                            #
#=================================================================#

if [[ $EUID -ne 0 ]]; then
   echo "Error:This script must be run as root!" 1>&2
   exit 1
fi


Get_Dist_Name()
{
    if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
        release='CentOS'
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        release='Debian'
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        release='Ubuntu'
	else
        release='unknow'
    fi
    
}
Get_Dist_Name
function getversion(){
    if [[ -s /etc/redhat-release ]];then
        grep -oE  "[0-9.]+" /etc/redhat-release
    else    
        grep -oE  "[0-9.]+" /etc/issue
    fi    
}
ver=""
CentOSversion() {
    if [ "${release}" == "CentOS" ]; then
        local version="$(getversion)"
        local main_ver=${version%%.*}
		ver=$main_ver
    else
        ver="$(getversion)"
    fi
}
CentOSversion
Get_OS_Bit()
{
    if [[ `getconf WORD_BIT` = '32' && `getconf LONG_BIT` = '64' ]] ; then
        bit='x64'
    else
        bit='x32'
    fi
}
Get_OS_Bit

if [ "${release}" == "CentOS" ]; then
	yum install -y bc
else
	apt-get update
	apt-get install -y bc
fi

iddver=`ldd --version | grep ldd | awk '{print $NF}'`
dver=$(echo "$iddver < 2.14" | bc)
if [ $dver -eq 1 ]; then
	ldd --version
	echo "idd的版本低于2.14，系统不支持。请尝试Centos7，Debian8，Ubuntu16"
	exit 1
fi

if [ "$bit" -ne "x64" ]; then
	echo "脚本目前只支持64bit系统"
	exit 1
fi	





if [ "${release}" == "CentOS" ]; then
	yum install -y haproxy
elif [[ "${release}" == "Debian" && "$ver" == "7" ]]; then
	echo "deb http://ftp.debian.org/debian wheezy-backports main" >> /etc/apt/sources.list
	apt-get install debian-archive-keyring
	apt-key update
	apt-get update
	apt-get install -y haproxy
	update-rc.d haproxy disable
else
	apt-get update
	apt-get install -y haproxy
	update-rc.d haproxy disable
fi

mkdir /root/lkl
cd /root/lkl
cat > /root/lkl/haproxy.cfg<<-EOF
global

defaults
log global
mode tcp
option dontlognull
timeout connect 5000
timeout client 50000
timeout server 50000

frontend proxy-in
bind *:12420
default_backend proxy-out

backend proxy-out
server server1 10.0.0.1 maxconn 20480

EOF
	
wget --no-check-certificate https://raw.githubusercontent.com/mishaelre/ovz/master/liblkl-hijack.so

cat > /root/lkl/lkl.sh<<-EOF
LD_PRELOAD=/root/lkl/liblkl-hijack.so LKL_HIJACK_NET_QDISC="root|fq" LKL_HIJACK_SYSCTL="net.ipv4.tcp_congestion_control=bbr;net.ipv4.tcp_wmem=4096 16384 30000000" LKL_HIJACK_OFFLOAD="0x9983" LKL_HIJACK_NET_IFTYPE=tap LKL_HIJACK_NET_IFPARAMS=lkl-tap LKL_HIJACK_NET_IP=10.0.0.2 LKL_HIJACK_NET_NETMASK_LEN=24 LKL_HIJACK_NET_GATEWAY=10.0.0.1 haproxy -f /root/lkl/haproxy.cfg
EOF



cat > /root/lkl/run.sh<<-EOF
ip tuntap add lkl-tap mode tap
ip addr add 10.0.0.1/24 dev lkl-tap
ip link set lkl-tap up
sysctl -w net.ipv4.ip_forward=1
iptables -P FORWARD ACCEPT 
iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE
iptables -t nat -A PREROUTING -i venet0 -p tcp --dport 12420 -j DNAT --to-destination 10.0.0.2

nohup /root/lkl/lkl.sh &

p=\`ping 10.0.0.2 -c 3 | grep ttl\`
if [ $? -eq 0 ]; then
	echo "success "\$(date '+%Y-%m-%d %H:%M:%S') > /root/lkl/log.log
else
	echo "fail "\$(date '+%Y-%m-%d %H:%M:%S') > /root/lkl/log.log
fi

EOF


chmod +x lkl.sh
chmod +x run.sh

#写入自动启动
if [[ "$release" = "CentOS" && "$ver" = "7" ]]; then
	echo "/root/lkl/run.sh" >> /etc/rc.d/rc.local
	chmod +x /etc/rc.d/rc.local
else
	sed -i "s/exit 0/ /ig" /etc/rc.local
	echo "/root/lkl/run.sh" >> /etc/rc.local
fi


./run.sh

mkdir /root/kcptun
cd /root/kcptun
wget --no-check-certificate https://github.com/xtaci/kcptun/releases/download/v20170329/kcptun-linux-amd64-20170329.tar.gz
tar -zxf kcptun-linux-amd64-*.tar.gz

cat > /root/kcptun/start.sh<<-EOF
#!/bin/bash
cd /root/kcptun/
./server_linux_amd64 -c /root/kcptun/server-config.json > kcptun.log 2>&1 &
echo "Kcptun started."
EOF

cat > /root/kcptun/server-config.json<<-EOF
{
    "listen": ":20900",
    "target": "127.0.0.1:12420",
    "key": "kcpforvir",
    "crypt": "salsa20",
    "mode": "normal",
    "mtu": 1350,
    "sndwnd": 1024,
    "rcvwnd": 1024,
    "datashard": 70,
    "parityshard": 30,
    "dscp": 46,
    "nocomp": false,
    "acknodelay": false,
    "nodelay": 0,
    "interval": 40,
    "resend": 0,
    "nc": 0,
    "sockbuf": 4194304,
    "keepalive": 10
}
EOF

chmod +x /etc/rc.local;echo "sh /root/kcptun/start.sh" >> /etc/rc.local

cd /root
apt-get install -y git
git clone -b manyuser https://github.com/shadowsocksr/shadowsocksr.git
bash /root/shadowsocksr/initcfg.sh
rm -f /root/shadowsocksr/user-config.json
cat > /root/shadowsocksr/user-config.json<<-EOF
{
    "server":"0.0.0.0",
    "server_ipv6":"::",
    "local_address":"127.0.0.1",
    "local_port":1080,
    "port_password":{
        "12420":{"protocol":"origin", "password":"133hhlovell!"}
    },
    "timeout":300,
    "method":"rc4-md5",
    "protocol": "origin",
    "protocol_param": "",
    "obfs": "tls1.2_ticket_auth",
    "obfs_param": "",
    "redirect": "",
    "dns_ipv6": false,
    "fast_open": false,
    "workers": 1
}
EOF

apt-get install -y cron

#判断是否启动
p=`ping 10.0.0.2 -c 3 | grep ttl`
if [ "$p" == "" ]; then
	echo "fail"
else
	echo "success"
fi
