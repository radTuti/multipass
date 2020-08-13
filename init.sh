#!/bin/bash

# Copyright (c) 2020 Tigera, Inc. All rights reserved.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

control=control1

echo Checking $control status
multipass info $control > /dev/null
if [ $? -ne 0 ]; then
	echo Launching $control
	multipass launch -n $control
	echo Installing k3s on $control
	multipass exec $control -- sh -c "curl -sfL \"https://get.k3s.io\" | INSTALL_K3S_EXEC=\"--flannel-backend=none --cluster-cidr=192.168.0.0/16\" sh -"
else
	echo Already online: $control
fi

for i in `seq 1 10`;
do
	multipass exec $control -- sh -c 'sudo kubectl get nodes -A' >/dev/null
	if [ $? -eq 0 ]; then
		echo k3s cluster is up!
		break
	else
		echo Waiting for k3s to become available.
		sleep 10
	fi

	if [ $i -eq 9 ]; then
		echo "k3s has failed to come online. Please take a look at $control to investigate why (multipass info $control)".
		exit 1
	fi
done

TOKEN=$(multipass exec $control -- sh -c 'sudo cat /var/lib/rancher/k3s/server/node-token')
IP=$(multipass info $control | grep IPv4 | cut -f2 -d: | tr -d [:space:])

echo Acquired Token for Master: $TOKEN
echo Acquired IP for Master: $IP

for i in `seq 1 2`;
do
	node=node$i
	multipass info $node
	if [ $? -ne 0 ]; then
		echo Launching $node
		multipass launch -n $node
		echo Installing k3s on $node
		multipass exec $node -- sh -c "curl -sfL \"https://get.k3s.io\" | K3S_URL=https://$IP:6443 K3S_TOKEN=$TOKEN sh -"
	else
		echo Already online: $node
	fi
done

echo Installing Kubeconfig to ~/.kube/config
multipass exec $control -- sh -c "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config
sed -i "s/127.0.0.1/$IP/" ~/.kube/config

multipass exec $control -- sh -c 'sudo kubectl get deployments -n tigera-operator tigera-operator' > /dev/null
if [ $? -ne 0 ]; then
	echo Installing the Calico Operator
	multipass exec $control -- sh -c 'sudo kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml'
	echo Installing Calico Custom-Resources
	multipass exec $control -- sh -c 'sudo kubectl create -f https://docs.projectcalico.org/manifests/custom-resources.yaml'
fi
