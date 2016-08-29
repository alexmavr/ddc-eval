#!/bin/bash
# =======================================================================================
#
#    .---. .---.  .--.        _                           .-.               
#    : .  :: .  :: .--'      :_;                          : :               
#    : :: :: :: :: :   _____ .-.,-.,-. _____  .--.  _____ : `-.  .--. .-.,-.
#    : :; :: :; :: :__:_____:: :: ,. ::_____:' .; ;:_____:' .; :' .; :`.  .'
#    :___.':___.'`.__.'      :_;:_;:_;       `.__,_;      `.__.'`.__.':_,._;
#
#              Evaluation Installer for Docker Datacenter v1.1.1
#
#		   	 - Docker Universal Control Plane v1.1.1
#		   	 - Docker Trusted Registry v2.0.1
#                                                                      
# 	Instructions:	Place this script in the same directory as a license file 
#			called "docker_subscription.lic" and execute with bash:
#				bash ./ddc_evaluation.sh
#
#			or, just cd to the same directory as the license and run:
#				curl -L git.io/vVk8S | bash
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
#	This script creates a boot2docker VM named "ddc-eval', containing DTR, UCP
#	and a dnsmasq container. The DTR and UCP instances are licensed with the provided
#	license and are cross-configured to recognize each other. Also, an extracted UCP admin 
#	bundle is located at /home/docker/bundle
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
	MACHINE_DRIVER_FLAGS="--kvm-memory 2048 --kvm-disk-size 16000 --kvm-boot2docker-url file:///home/alexmavr/Downloads/boot2docker-experimental.iso"
fi

echo "Using $MACHINE_DRIVER as a virtualization driver. To use another driver, restart this script with the MACHINE_DRIVER and MACHINE_DRIVER_FLAGS environment variables set"

UCP_IMAGE="docker/ucp"
UCP_TAG="1.1.1"

DTR_IMAGE="docker/dtr"
DTR_TAG="2.0.1"

echo "UCP Image: $UCP_IMAGE:$UCP_TAG"
echo "DTR Image: $DTR_IMAGE:$DTR_TAG"

echo "Creating a VM..."
docker-machine create  \
	--driver "$MACHINE_DRIVER" \
	$MACHINE_DRIVER_FLAGS $MACHINE_NAME

echo "VM created"

# External IP
MACHINE_IP=$(docker-machine ip $MACHINE_NAME)

# Copy the license file to the VM
docker-machine scp localhost:$LICENSE_FILE "$MACHINE_NAME":/home/docker/docker_subscription.lic

# Pass in the environment variables
echo $MACHINE_IP | docker-machine ssh "$MACHINE_NAME" "tee > /home/docker/machine_ip"
echo "$UCP_IMAGE:$UCP_TAG" | docker-machine ssh "$MACHINE_NAME" "tee > /home/docker/ucp_image"
echo "$DTR_IMAGE:$DTR_TAG" | docker-machine ssh "$MACHINE_NAME" "tee > /home/docker/dtr_image"

# Jump in the box
docker-machine ssh "$MACHINE_NAME" "sudo sh" << 'EOF'
MACHINE_IP=$(cat /home/docker/machine_ip)
UCP_IMAGE=$(cat /home/docker/ucp_image)
DTR_IMAGE=$(cat /home/docker/dtr_image)

echo "Starting syslog"
syslogd

echo "Restarting docker daemon in order to trust the VM IP"
echo "EXTRA_ARGS=\"\$EXTRA_ARGS --insecure-registry $MACHINE_IP\"" >> /var/lib/boot2docker/profile
/etc/init.d/docker restart


# TODO: ping the daemon
sleep 10

echo "Installing UCP"
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
	-e UCP_ADMIN_PASSWORD=ddcpassword \
	-v /home/docker/docker_subscription.lic:/docker_subscription.lic --name ucp $UCP_IMAGE \
	install --host-address $MACHINE_IP --san $MACHINE_IP --fresh-install \
	--swarm-port 8888 --controller-port 444 

UCP_URL=https://$MACHINE_IP:444

# Get the UCP CA
curl -k $UCP_URL/ca > ucp-ca.pem
echo "Installing DTR"
docker run --rm $DTR_IMAGE install --ucp-url $UCP_URL \
	--dtr-external-url $MACHINE_IP:443 \
	--ucp-username admin \
	--ucp-password ddcpassword \
	--ucp-ca "$(cat ucp-ca.pem)"

DTR_URL=https://$MACHINE_IP

echo "Configuring DTR to trust UCP"
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock --name ucp $UCP_IMAGE dump-certs --cluster -ca > ucp_root_ca.pem
DTR_CONFIG_DATA="{\"authBypassCA\":\"$(cat ucp_root_ca.pem | sed ':begin;$!N;s|\n|\\n|;tbegin')\"}"
curl -u admin:ddcpassword -k  -H "Content-Type: application/json" $DTR_URL/api/v0/meta/settings -X POST --data-binary "$DTR_CONFIG_DATA"

echo "Configuring UCP to use DTR"
wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
chmod +x /home/docker/jq-linux64
TOKEN=$(curl -k -c jar https://$MACHINE_IP:444/auth/login -d '{"username": "admin", "password": "ddcpassword"}' -X POST -s | /home/docker/jq-linux64 -r ".auth_token")
UCP_CONFIG_DATA="{\"url\":\"$DTR_URL\", \"insecure\":true }"
curl -k -s -c jar -H "Authorization: Bearer ${TOKEN}" $UCP_URL/api/config/registry -X POST --data "$UCP_CONFIG_DATA"
EOF

DTR_URL="https://$MACHINE_IP:443"
UCP_URL="https://$MACHINE_IP:444"

echo ""
echo ""
echo "Docker Datacenter Installation Completed"
echo "========================================================================="
echo "You may access Docker Datacenter at the following URLs:"
echo ""
echo "Docker Universal Control Plane: $UCP_URL"
echo "Docker Trusted Registry: $DTR_URL"
echo ""
echo "- Admin Username: admin"
echo "- Admin Password: ddcpassword"
echo ""
echo "The Docker Trusted Registry can be accessed as a registry at $MACHINE_IP"
echo ""
echo "The certificates used to sign UCP and DTR will not be trusted by your browser."
echo ""
echo "To completely remove this evaluation installation, run the following command:"
echo " docker-machine rm ddc-eval"
echo "========================================================================"