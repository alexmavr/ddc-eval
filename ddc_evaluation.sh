#!/bin/bash
# =======================================================================================
#
#    .---. .---.  .--.        _                           .-.               
#    : .  :: .  :: .--'      :_;                          : :               
#    : :: :: :: :: :   _____ .-.,-.,-. _____  .--.  _____ : `-.  .--. .-.,-.
#    : :; :: :; :: :__:_____:: :: ,. ::_____:' .; ;:_____:' .; :' .; :`.  .'
#    :___.':___.'`.__.'      :_;:_;:_;       `.__,_;      `.__.'`.__.':_,._;
#
#              Evaluation Installer for Docker Datacenter v1.0
#
#		   	 - Docker Universal Control Plane v1.0.1
#		   	 - Docker Trusted Registry v1.4.3
#                                                                      
# 	Instructions:	Place this script in the same directory as a license file 
#			called "docker_subscription.lic" and execute with bash:
#				bash ./ddc_evaluation.sh
#
#			or, just cd to the same directory as the license and run:
#				bash<(curl -L <URL_of_this_script>)
#					
#			The first argument to the script can be an absolute path to a license file:
#				bash ./ddc_evaluation ~/other_docker_subscription.lic
#
#	Platforms: 		- Mac OSX with Docker Toolbox 1.10 or above, or docker-machine
#				- Linux with docker-machine
#				- Windows with (Git Bash or CygWin) and (Docker Toolbox 1.10 or above or docker-machine)
#
#	System requirements:	- 16 GB hard drive space 
#				- 2 GB of RAM
#				- Internet Connectivity (downloads ~4 GB )
#				- docker-machine & bash
#				- Default docker-machine driver is virtualbox. An alternate driver
#				  can be specified with $MACHINE_DRIVER
#      
#                       O          .
#                    O            ' '
#                      o         '   .
#                    o         .'
#                 __________.-'       '...___
#              .-'                      ###  '''...__
#             /   a###                 ##            ''--.._ ______
#             '.                      #     ########        '   .-'
#               '-._          ..**********####  ___...---'''\   '
#                   '-._     __________...---'''             \   l
#                       \   |                                 '._|
#                        \__;
#       
#			 ** What's in the box? **
#
#	This script creates a boot2docker VM named "ddc-evaluation', containing DTR, UCP
#	and a dnsmasq container. The DTR and UCP instances are licensed with the provided
#	license and are cross-configured to recognize each other. Also, a UCP admin bundle 
#	is located at /home/docker/ucp_admin_bundle.zip
#
#   LEGAL DISCLAIMER
#   EXCEPT WHERE EXPRESSLY PROVIDED OTHERWISE, THE SCRIPT, AND ALL CONTENT 
#   PROVIDED, ARE PROVIDED ON AN "AS IS" AND "AS AVAILABLE" BASIS. DOCKER  
#   EXPRESSLY DISCLAIMS ALL WARRANTIES OF ANY KIND, WHETHER EXPRESS OR IMPLIED,  
#   INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS 
#   FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT WITH RESPECT TO THIS 
#   CONTENT. DOCKER SHALL HAVE NO  
#   RESPONSIBILITY FOR ANY DAMAGE TO YOUR COMPUTER SYSTEM OR LOSS OF DATA THAT 
#   RESULTS FROM THE DOWNLOAD OR USE OF THIS SCRIPT.
#   DOCKER RESERVES THE RIGHT TO MAKE CHANGES OR UPDATES TO
#   THE SCRIPT AT ANY TIME WITHOUT NOTICE.
#
# =======================================================================================
echo "Docker Datacenter Evaluation Installer"
echo "This script is intended to install the Docker Datacenter software for evaluation purposes only."
echo "This script is not to be used to simulate a production or even scalable test environment or proof-of-concept."
echo "Please read the disclaimer section contained within the document for usage and disclaimers related to the use of this script."
echo ""

set -e
MACHINE_NAME='ddc-eval'

# Extract license path from argument, or detect in current directory
if [[ $1 != '' ]]; then
	LICENSE_FILE=$1
else 
	if [[ -f "docker_subscription.lic" ]]; then
		LICENSE_FILE="$(pwd)/docker_subscription.lic"
	else
		echo "Could not detect a docker_subscription.lic file in the current folder."
		echo "Please run this script again and provide the path to your docker subscription license file, as follows:"
		echo "./ddc_evaluation.sh /path/to/docker_subscription.lic"
		exit 1
	fi
fi

LICENSE_FILE=$(printf "%q\n" "$LICENSE_FILE")
echo "Using Docker License located at: $LICENSE_FILE"

#TODO: detect machine driver, fail if docker-machine is not accessible
if [[ $MACHINE_DRIVER == '' ]]; then
	echo "The MACHINE_DRIVER variable was not set, defaulting to the virtualbox driver for docker-machine"
	MACHINE_DRIVER='virtualbox'
	MACHINE_DRIVER_FLAGS="--virtualbox-memory 2048 --virtualbox-disk-size 16000"
fi
if [[ $MACHINE_DRIVER == 'kvm' ]]; then
	MACHINE_DRIVER_FLAGS="--kvm-memory 2048 --kvm-disk-size 16000"
fi

echo "Using $MACHINE_DRIVER as a virtualization driver. To use another driver, restart this script with the MACHINE_DRIVER and MACHINE_DRIVER_FLAGS environment variables set"

UCP_IMAGE="docker/ucp"
UCP_TAG="1.0.1"

DTR_IMAGE="docker/trusted-registry"
DTR_TAG="1.4.3"

echo "UCP Image: $UCP_IMAGE:$UCP_TAG"
echo "DTR Image: $DTR_IMAGE:$DTR_TAG"

echo "Creating a VM..."
docker-machine create --driver "$MACHINE_DRIVER" \
	--engine-insecure-registry ddc.eval.docker.com \
	--engine-insecure-registry 127.0.0.1 \
	--engine-opt dns=127.0.0.1\
	$MACHINE_DRIVER_FLAGS $MACHINE_NAME

echo "VM created"

# External IP
MACHINE_IP=$(docker-machine ip $MACHINE_NAME)

# Copy the license file to the VM
docker-machine scp $LICENSE_FILE "$MACHINE_NAME":/home/docker/docker_subscription.lic

echo $MACHINE_IP | docker-machine ssh "$MACHINE_NAME" "tee > /home/docker/machine_ip"

# Jump in the box
docker-machine ssh "$MACHINE_NAME" "sudo sh" << 'EOF'
MACHINE_IP=$(cat /home/docker/machine_ip)

echo "Starting syslog"
syslogd

echo "Starting up dnsmasq"
echo "
listen-address=0.0.0.0
listen-address=127.0.0.1
interface=eth1
interface=eth0
user=root

no-resolv
server=8.8.8.8
server=8.8.4.4

address=/ddc.eval.docker.com/127.0.0.1
" > /opt/dnsmasq.conf


# TODO: thin out this image
docker run \
	--name dnsmasq \
	-d \
	-p 0.0.0.0:53:53/udp \
	-p 8080:8080 \
	-v /opt/dnsmasq.conf:/etc/dnsmasq.conf \
	quay.io/jpillora/dnsmasq-gui:latest

echo "nameserver 127.0.0.1" > /etc/resolv.conf

# Copy UCP license
cp /home/docker/docker_subscription.lic /home/docker/ucp_license.lic

echo "Installing UCP"
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
	-v /home/docker/ucp_license.lic:/docker_subscription.lic --name ucp docker/ucp:1.0.1 \
	install --host-address $MACHINE_IP --san $MACHINE_IP --fresh-install \
	--dns 127.0.0.1 --swarm-port 8888 --controller-port 444


echo "Installing DTR"
docker run docker/trusted-registry:1.4.3 install | sh

sleep 20
# Configure DTR domain
echo "Configuring DTR to authorize UCP traffic"
echo "load_balancer_http_port: 80
load_balancer_https_port: 443
domain_name: \"ddc.eval.docker.com\"
notary_server: \"\"
notary_cert: \"\"
notary_verify_cert: false
auth_bypass_ca: \"\"
auth_bypass_ou: \"\"
extra_env:
HTTP_PROXY: \"\"
HTTPS_PROXY: \"\"
NO_PROXY: \"\"
disable_upgrades: false
release_channel: \"\"
" > /usr/local/etc/dtr/hub.yml

sleep 15
docker run docker/trusted-registry:1.4.3 stop | sh
docker run docker/trusted-registry:1.4.3 install | sh
sleep 35


echo "Configuring DTR"
# Injecting License
tail -c +4 /home/docker/docker_subscription.lic > /home/docker/dtr_license.lic
curl -Lik \
	-X PUT https://$MACHINE_IP/api/v0/admin/settings/license \
	-H 'Content-Type: application/json; charset=UTF-8' \
	-H 'Accept: */*' \
	-H 'X-Requested-With: XMLHttpRequest' \
	--data-binary @/home/docker/dtr_license.lic

sleep 10

# Creating Admin User
curl -k -Lik \
     -X PUT https://$MACHINE_IP/api/v0/admin/settings/auth \
     -H 'Content-Type: application/json; charset=UTF-8' \
     -H 'Accept: */*' \
     -H 'X-Requested-With: XMLHttpRequest' \
     --data-binary '{"method":"managed","managed":{"users":[{"username":"admin","password":"dtrpassword","isNew":true,"isAdmin":true,"isReadWrite":false,"isReadOnly":false,"teamsChanged":true}]}}'

sleep 15
# General DTR settings and UCP bypass auth
echo "Configuring DTR to authorize UCP traffic"
echo "load_balancer_http_port: 80
load_balancer_https_port: 443
domain_name: \"ddc.eval.docker.com\"
notary_server: \"\"
notary_cert: \"\"
notary_verify_cert: false
auth_bypass_ca: \"$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock --name ucp docker/ucp:1.0.1 dump-certs --cluster -ca)\"
auth_bypass_ou: \"\"
extra_env:
HTTP_PROXY: \"\"
HTTPS_PROXY: \"\"
NO_PROXY: \"\"
disable_upgrades: false
release_channel: \"\"
" > /usr/local/etc/dtr/hub.yml

echo "Configuring UCP to use DTR"
wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
chmod +x jq-linux64
TOKEN=$(curl -k -c jar https://$MACHINE_IP:444/auth/login -d '{"username": "admin", "password": "orca"}' -X POST -s | ./jq-linux64 -r ".auth_token")
curl -k -s -c jar -H "Authorization: Bearer ${TOKEN}" https://$MACHINE_IP:444/api/config/registry -X POST --data '{"url": "https://ddc.eval.docker.com:443", "insecure":true}'
curl -k -s -H "Authorization: Bearer ${TOKEN}" https://$MACHINE_IP:444/api/clientbundle -X POST > /home/docker/admin_bundle.zip

rm /home/docker/dtr_license.lic
rm /home/docker/ucp_license.lic
EOF

DTR_URL="https://$MACHINE_IP:443"
UCP_URL="https://$MACHINE_IP:444"
echo ""
echo ""
echo "DDC Installation Completed"
echo "========================================================================="
echo "You may access Docker Datacenter at the following URLs:"
echo ""
echo "Docker Universal Control Plane: $UCP_URL"
echo "- UCP Admin Username: admin"
echo "- UCP Admin Password: orca"
echo ""
echo "Docker Trusted Registry: $DTR_URL"
echo "- DTR Admin Username: admin"
echo "- DTR Admin Password: dtrpassword"
echo ""
echo "The domain name of the Docker Trusted Registry is ddc.eval.docker.com"
echo "To completely remove this evaluation installation, run the following command:"
echo " docker-machine rm ddc-eval"
echo "========================================================================"