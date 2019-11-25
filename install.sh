#!/bin/bash

set -eu -o pipefail # fail on error , debug all lines

LOG_LOCATION=/root/
exec > >(tee -i $LOG_LOCATION/cnode.log)
exec 2>&1

read -p "What is your email address?: " email
read -p "What is your server name?: " servername
read -p "What is your wallet private key?: " pkey
read -p "What is your wallet seed?: " seed

exec 3<>/dev/tcp/icanhazip.com/80 
echo -e 'GET / HTTP/1.0\r\nhost: icanhazip.com\r\n\r' >&3 
while read i
do
 [ "$i" ] && serverip="$i" 
done <&3 

serverurl=https://$servername

adduser --gecos "" --disabled-password coti
adduser coti sudo
add-apt-repository ppa:certbot/certbot -y
apt-get update -y && sudo apt-get upgrade -y
apt install software-properties-common openjdk-8-jdk maven nginx certbot python-certbot-nginx ufw nano git -y
java -version
mvn -version
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 7070
ufw --force enable
cd /home/coti/
git clone https://github.com/coti-io/coti-fullnode.git
chown -R coti: /home/coti/coti-fullnode/
cd /home/coti/coti-fullnode/
sudo -u coti mvn initialize && sudo -u coti mvn clean compile && sudo -u coti mvn -Dmaven.test.skip=true package

cat <<EOF >/home/coti/coti-fullnode/fullnode.properties
network=TestNet
server.ip=$serverip
server.port=7070
server.url=$serverurl
application.name=FullNode
logging.file.name=FullNode1
database.folder.name=rocksDB1
resetDatabase=false
global.private.key=$pkey
fullnode.seed=$seed
minimumFee=0.01
maximumFee=100
fee.percentage=1
zero.fee.user.hashes=9c37d52ae10e6b42d3bb707ca237dd150165daca32bf8ef67f73d1e79ee609a9f88df0d437a5ba5a6cf7c68d63c077fa2c63a21a91fc192dfd9c1fe4b64bb959
kycserver.public.key=c10052a39b023c8d4a3fc406a74df1742599a387c58bcea2a2093bd85103f3bd22816fa45bbfb26c1f88a112f0c0b007755eb1be1fad3b45f153adbac4752638
kycserver.url=https://cca.coti.io
node.manager.ip=52.59.142.53
node.manager.port=7090
node.manager.propagation.port=10001
allow.transaction.monitoring=true
whitelist.ips=127.0.0.1,0:0:0:0:0:0:0:1
EOF

FILE=/home/coti/coti-fullnode/FullNode1_clusterstamp.csv
if [ -f "$FILE" ]; then
    echo "$FILE already exists, no need to download"
else 
    echo "$FILE does not exist, downloading now"
    wget -q --show-progress --progress=bar:force 2>&1 https://www.dropbox.com/s/rpyercs56zmay0z/FullNode1_clusterstamp.csv -P /home/coti/coti-fullnode/
fi

chown coti /home/coti/coti-fullnode/FullNode1_clusterstamp.csv
chgrp coti /home/coti/coti-fullnode/FullNode1_clusterstamp.csv
chown coti /home/coti/coti-fullnode/fullnode.properties
chgrp coti /home/coti/coti-fullnode/fullnode.properties

certbot certonly --nginx --non-interactive --agree-tos -m $email -d $servername

cat <<'EOF' >/etc/nginx/sites-enabled/coti_fullnode.conf
server {
    listen      80;
    return 301  https://$host$request_uri;
}server {
    listen      443 ssl;
    listen [::]:443;
    server_name
    ssl_certificate
    ssl_key
    ssl_session_timeout 5m;
    gzip on;
    gzip_comp_level    5;
    gzip_min_length    256;
    gzip_proxied       any;
    gzip_vary          on;
    gzip_types
        text/css
        application/json
        application/x-javascript
        text/javascript
        application/javascript
        image/png
        image/jpg
        image/jpeg
        image/svg+xml
        image/gif
        image/svg;location  / {
        proxy_redirect off;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_pass http://127.0.0.1:7070;
    }
}
EOF

sed -i "s/server_name/server_name $servername;/g" /etc/nginx/sites-enabled/coti_fullnode.conf
sed -i "s:ssl_certificate:ssl_certificate /etc/letsencrypt/live/$servername/fullchain.pem;:g" /etc/nginx/sites-enabled/coti_fullnode.conf
sed -i "s:ssl_key:ssl_certificate_key /etc/letsencrypt/live/$servername/privkey.pem;:g" /etc/nginx/sites-enabled/coti_fullnode.conf

service nginx restart

cat <<EOF >/etc/systemd/system/cnode.service
[Unit]
Description=COTI Fullnode Service
[Service]
WorkingDirectory=/home/coti/coti-fullnode/
ExecStart=/usr/bin/java -Xmx256m -jar /home/coti/coti-fullnode/fullnode/target/fullnode-1.0.2-SNAPSHOT.jar --spring.config.additional-location=fullnode.properties
SuccessExitStatus=143
User=coti
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cnode.service
systemctl start cnode.service
echo "Waiting for Coti Node to Start"
sleep 5
tail -f /home/coti/coti-fullnode/logs/FullNode1.log | while read line; do
echo $line  
echo $line | grep -q 'COTI FULL NODE IS UP' && break;
done
sleep 2
echo "Your node is registered and running on the COTI Network"
