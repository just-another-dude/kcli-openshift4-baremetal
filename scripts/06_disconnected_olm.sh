#!/usr/bin/env bash

# Variables to set, suit to your installation
cd /root
export PATH=/root/bin:$PATH
export OCP_RELEASE="$(/root/bin/openshift-baremetal-install version | head -1 | cut -d' ' -f2 | cut -d'.' -f 1,2)"
export OCP_PULLSECRET_AUTHFILE='/root/openshift_pull.json'
PRIMARY_NIC=$(ls -1 /sys/class/net | grep 'eth\|en' | head -1)
IP=$(ip -o addr show $PRIMARY_NIC | head -1 | awk '{print $4}' | cut -d'/' -f1)
REGISTRY_NAME=$(echo $IP | sed 's/\./-/g' | sed 's/:/-/g').sslip.io
REGISTRY_PORT={{ 8443 if disconnected_quay else 5000 }}
export LOCAL_REGISTRY=$REGISTRY_NAME:$REGISTRY_PORT
export LOCAL_REGISTRY_INDEX_TAG=olm-index/redhat-operator-index:v$OCP_RELEASE
export LOCAL_REGISTRY_IMAGE_TAG=olm

# Login registries
REGISTRY_USER={{ "init" if disconnected_quay else disconnected_user }}
REGISTRY_PASSWORD={{ "super" + disconnected_password if disconnected_quay and disconnected_password|length < 8 else disconnected_password }}
podman login -u $REGISTRY_USER -p $REGISTRY_PASSWORD $LOCAL_REGISTRY
#podman login registry.redhat.io --authfile /root/openshift_pull.json
REDHAT_CREDS=$(cat /root/openshift_pull.json | jq .auths.\"registry.redhat.io\".auth -r | base64 -d)
RHN_USER=$(echo $REDHAT_CREDS | cut -d: -f1)
RHN_PASSWORD=$(echo $REDHAT_CREDS | cut -d: -f2)
podman login -u "$RHN_USER" -p "$RHN_PASSWORD" registry.redhat.io

which opm >/dev/null 2>&1
if [ "$?" != "0" ] ; then
curl -k -s https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/opm-linux.tar.gz | tar xvz -C /usr/bin/
chmod u+x /usr/bin/opm
fi

# Set these values to true for the catalog and miror to be created
export RH_OP='true'
export RH_OP_INDEX="registry.redhat.io/redhat/redhat-operator-index:v${OCP_RELEASE}"
export CERT_OP_INDEX="registry.redhat.io/redhat/certified-operator-index:v${OCP_RELEASE}"
export COMM_OP_INDEX="registry.redhat.io/redhat/community-operator-index:v${OCP_RELEASE}"
export MARKETPLACE_OP_INDEX="registry.redhat.io/redhat-marketplace-index:v${OCP_RELEASE}"
#export RH_OP_PACKAGES='local-storage-operator,performance-addon-operator,ptp-operator,sriov-network-operator'
export RH_OP_PACKAGES='{{ disconnected_operators|join(",") }}'

time opm index prune --from-index $RH_OP_INDEX --packages $RH_OP_PACKAGES --tag $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG
podman push $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG --authfile $OCP_PULLSECRET_AUTHFILE
time oc adm catalog mirror $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG $LOCAL_REGISTRY/$LOCAL_REGISTRY_IMAGE_TAG --registry-config=$OCP_PULLSECRET_AUTHFILE --max-per-registry=100

oc apply -f /root/manifests-redhat-operator-index-*/imageContentSourcePolicy.yaml 2>/dev/null || cp /root/manifests-redhat-operator-index-*/imageContentSourcePolicy.yaml /root/manifests
oc apply -f /root/manifests-redhat-operator-index-*/catalogSource.yaml 2>/dev/null || cp /root/manifests-redhat-operator-index-*/catalogSource.yaml /root/manifests
