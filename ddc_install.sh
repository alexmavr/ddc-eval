#!/bin/bash
echo "Docker Datacenter Evaluation Installer"
echo "This script is intended to install the Docker Datacenter software for evaluation purposes only."
echo "This script is not to be used to simulate a production or even scalable test environment or proof-of-concept."
echo "Please read the disclaimer section contained within the document for usage and disclaimers related to the use of this script."
echo ""

set -e

UCP_IMAGE="docker/ucp"
UCP_TAG="1.1.2"

DTR_IMAGE="docker/dtr"
DTR_TAG="2.0.1"

echo "Discovering IP"
CONTAINER_IP=$(docker run --rm --net host alpine ip route get 8.8.8.8 | awk '{print $7}')
echo $CONTAINER_IP

echo "Running dind"
docker run -d --privileged --name try-ddc -P alexmavr/ddc-dind
sleep 3

UCP_PORT=$(docker inspect --format='{{(index (index .NetworkSettings.Ports "444/tcp") 0).HostPort}}' try-ddc)
DTR_PORT=$(docker inspect --format='{{(index (index .NetworkSettings.Ports "443/tcp") 0).HostPort}}' try-ddc)

echo "Installing UCP"
docker run --link try-ddc:docker docker:1.11.2 \
	run --rm -v /var/run/docker.sock:/var/run/docker.sock \
	-e UCP_ADMIN_PASSWORD=ddcpassword \
	--name ucp $UCP_IMAGE:$UCP_TAG \
	install --fresh-install --san localhost --san $CONTAINER_IP \
	--controller-port 444 


UCP_URL=https://$CONTAINER_IP:$UCP_PORT

sleep 3
# Get the UCP CA
curl -k $UCP_URL/ca > ucp-ca.pem

echo "Installing DTR"
docker run --link try-ddc:docker docker:1.11.2 \
	run --rm $DTR_IMAGE:$DTR_TAG install --ucp-url $UCP_URL \
	--dtr-external-url $CONTAINER_IP:$DTR_PORT \
	--ucp-username admin \
	--ucp-password ddcpassword \
	--ucp-ca "$(cat ucp-ca.pem)" 

sleep 3

DTR_URL=https://$CONTAINER_IP:$DTR_PORT

echo "Configuring DTR to trust UCP"
docker run --link try-ddc:docker docker:1.11.2 \
	run --rm -v /var/run/docker.sock:/var/run/docker.sock --name ucp $UCP_IMAGE:$UCP_TAG dump-certs --cluster -ca > ucp_root_ca.pem
DTR_CONFIG_DATA="{\"authBypassCA\":\"$(cat ucp_root_ca.pem | sed ':begin;$!N;s|\n|\\n|;tbegin')\"}"
curl -u admin:ddcpassword -k  -H "Content-Type: application/json" $DTR_URL/api/v0/meta/settings -X POST --data-binary "$DTR_CONFIG_DATA" 

echo "Configuring UCP to use DTR"
wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
chmod +x ./jq-linux64
TOKEN=$(curl -k -c jar $UCP_URL/auth/login -d '{"username": "admin", "password": "ddcpassword"}' -X POST -s | ./jq-linux64 -r ".auth_token")
UCP_CONFIG_DATA="{\"url\":\"$DTR_URL\", \"insecure\":true }"
curl -k -s -c jar -H "Authorization: Bearer ${TOKEN}" $UCP_URL/api/config/registry -X POST --data "$UCP_CONFIG_DATA" 


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
echo "The Docker Trusted Registry can be accessed as a registry at $CONTAINER_IP:$DTR_PORT"
echo ""
echo "The certificates used to sign UCP and DTR will not be trusted by your browser."
echo ""
echo "To remove this installation, run the following command on another terminal:"
echo " docker rm -f -v try-ddc"
echo "========================================================================"