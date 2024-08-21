#!/bin/bash
#
# Copyright 2024 Tech Equity Cloud Services Ltd
# 
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
# 
#       http://www.apache.org/licenses/LICENSE-2.0
# 
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# 
#################################################################################
############## Install and Configure GKE Enterprise on Baremetal  ###############
#################################################################################

function ask_yes_or_no() {
    read -p "$1 ([y]yes to preview, [n]o to create, [d]del to delete): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        n|no)  echo "no" ;;
        d|del) echo "del" ;;
        *)     echo "yes" ;;
    esac
}

function ask_yes_or_no_proj() {
    read -p "$1 ([y]es to change, or any key to skip): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        y|yes) echo "yes" ;;
        *)     echo "no" ;;
    esac
}

export vxlan0_ip_count=1 # to set network counter to start from 10.200.0.2/24
function vxlan0_ip_counter {
  export vxlan0_ip_count=$((vxlan0_ip_count+1))
}

clear
MODE=1
export TRAINING_ORG_ID=1 # $(gcloud organizations list --format 'value(ID)' --filter="displayName:techequity.training" 2>/dev/null)
export ORG_ID=1 # $(gcloud projects get-ancestors $GCP_PROJECT --format 'value(ID)' 2>/dev/null | tail -1 )
export GCP_PROJECT=$(gcloud config list --format 'value(core.project)' 2>/dev/null)  

echo
echo
echo -e "                        👋  Welcome to Cloud Sandbox! 💻"
echo 
echo -e "              *** PLEASE WAIT WHILE LAB UTILITIES ARE INSTALLED ***"
sudo apt-get -qq install pv > /dev/null 2>&1
echo 
export SCRIPTPATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

mkdir -p `pwd`/gcp-gdcs-admin > /dev/null 2>&1
export PROJDIR=`pwd`/gcp-gdcs-admin
export SCRIPTNAME=gcp-gdcs-admin.sh

if [ -f "$PROJDIR/.env" ]; then
    source $PROJDIR/.env
else
cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT
export GCP_REGION=us-west1
export GCP_ZONE=us-west1-a
export SERVICEMESH_VERSION=1.21.4-asm.5
export ANTHOS_VERSION=1.16.11
EOF
source $PROJDIR/.env
fi

VM_PREFIX=bm-gke
VM_WS=$VM_PREFIX-admin-ws
VM_A_CP1=$VM_PREFIX-admin-cp
VM_U_CP1=$VM_PREFIX-user-cp
VM_U_W1=$VM_PREFIX-user-w1
declare -a VMs=("$VM_WS" "$VM_A_CP1" "$VM_U_CP1" "$VM_U_W1")
declare -a ADMIN_CP_VMs=("$VM_A_CP1")
declare -a USER_CP_VMs=("$VM_U_CP1")
declare -a USER_WORKER_VMs=("$VM_U_W1")
declare -a LB_VMs=("$VM_A_CP1" "$VM_U_CP1")
declare -a IPs=()

echo && echo

# Display menu options
while :
do
clear
cat<<EOF
==============================================================================
Menu for Configuring Anthos GKE Baremetal 
------------------------------------------------------------------------------
Please enter number to select your choice:
 (1) Create network and firewall rules
 (2) Create Virtual Machines
 (3) Connect VMs with vXlan L2 connectivity
 (4) Configure admin workstation
 (5) Create and configure access to admin cluster
 (6) Create and configure access to user cluster
 (7) Configure Anthos Service Mesh
 (8) Configure Cloud Run
 (9) Deploy a Stateless application to Cloud Run
(10) Deploy a Stateless and Stateful application to Kubernetes
(11) Perform node and application troubleshooting
 (G) Launch user guide
 (Q) Quit
------------------------------------------------------------------------------
EOF
echo "Steps performed${STEP}"
echo
echo "What additional step do you want to perform, e.g. enter 0 to select the execution mode?"
read
clear
case "${REPLY^^}" in

"0")
start=`date +%s`
source $PROJDIR/.env
echo
echo "Do you want to run script in preview mode?"
export ANSWER=$(ask_yes_or_no "Are you sure?")
if [[ ! -z "$TRAINING_ORG_ID" ]]  &&  [[ $ORG_ID == "$TRAINING_ORG_ID" ]]; then
    export STEP="${STEP},0"
    MODE=1
    if [[ "yes" == $ANSWER ]]; then
        export STEP="${STEP},0i"
        MODE=1
        echo
        echo "*** Command preview mode is active ***" | pv -qL 100
    else 
        if [[ -f $PROJDIR/.${GCP_PROJECT}.json ]]; then
            echo 
            echo "*** Authenticating using service account key $PROJDIR/.${GCP_PROJECT}.json ***" | pv -qL 100
            echo "*** To use a different GCP project, delete the service account key ***" | pv -qL 100
        else
            while [[ -z "$PROJECT_ID" ]] || [[ "$GCP_PROJECT" != "$PROJECT_ID" ]]; do
                echo 
                echo "$ gcloud auth login --brief --quiet # to authenticate as project owner or editor" | pv -qL 100
                gcloud auth login  --brief --quiet
                export ACCOUNT=$(gcloud config list account --format "value(core.account)")
                if [[ $ACCOUNT != "" ]]; then
                    echo
                    echo "Copy and paste a valid Google Cloud project ID below to confirm your choice:" | pv -qL 100
                    read GCP_PROJECT
                    gcloud config set project $GCP_PROJECT --quiet 2>/dev/null
                    sleep 3
                    export PROJECT_ID=$(gcloud projects list --filter $GCP_PROJECT --format 'value(PROJECT_ID)' 2>/dev/null)
                fi
            done
            gcloud iam service-accounts delete ${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com --quiet 2>/dev/null
            sleep 2
            gcloud --project $GCP_PROJECT iam service-accounts create ${GCP_PROJECT} 2>/dev/null
            gcloud projects add-iam-policy-binding $GCP_PROJECT --member serviceAccount:$GCP_PROJECT@$GCP_PROJECT.iam.gserviceaccount.com --role=roles/owner > /dev/null 2>&1
            gcloud --project $GCP_PROJECT iam service-accounts keys create $PROJDIR/.${GCP_PROJECT}.json --iam-account=${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com 2>/dev/null
            gcloud --project $GCP_PROJECT storage buckets create gs://$GCP_PROJECT > /dev/null 2>&1
        fi
        export GOOGLE_APPLICATION_CREDENTIALS=$PROJDIR/.${GCP_PROJECT}.json
        cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT
export GCP_REGION=$GCP_REGION
export GCP_ZONE=$GCP_ZONE
export SERVICEMESH_VERSION=$SERVICEMESH_VERSION
export ANTHOS_VERSION=$ANTHOS_VERSION
EOF
        gsutil cp $PROJDIR/.env gs://${GCP_PROJECT}/${SCRIPTNAME}.env > /dev/null 2>&1
        echo
        echo "*** Google Cloud project is $GCP_PROJECT ***" | pv -qL 100
        echo "*** Google Cloud region is $GCP_REGION ***" | pv -qL 100
        echo "*** Google Cloud zone is $GCP_ZONE ***" | pv -qL 100
        echo "*** Anthos Service Mesh version is $SERVICEMESH_VERSION ***" | pv -qL 100
        echo "*** Anthos version is $ANTHOS_VERSION ***" | pv -qL 100
        echo
        echo "*** Update environment variables by modifying values in the file: ***" | pv -qL 100
        echo "*** $PROJDIR/.env ***" | pv -qL 100
        if [[ "no" == $ANSWER ]]; then
            MODE=2
            echo
            echo "*** Create mode is active ***" | pv -qL 100
        elif [[ "del" == $ANSWER ]]; then
            export STEP="${STEP},0"
            MODE=3
            echo
            echo "*** Resource delete mode is active ***" | pv -qL 100
        fi
    fi
else 
    if [[ "no" == $ANSWER ]] || [[ "del" == $ANSWER ]] ; then
        export STEP="${STEP},0"
        if [[ -f $SCRIPTPATH/.${SCRIPTNAME}.secret ]]; then
            echo
            unset password
            unset pass_var
            echo -n "Enter access code: " | pv -qL 100
            while IFS= read -p "$pass_var" -r -s -n 1 letter
            do
                if [[ $letter == $'\0' ]]
                then
                    break
                fi
                password=$password"$letter"
                pass_var="*"
            done
            while [[ -z "${password// }" ]]; do
                unset password
                unset pass_var
                echo
                echo -n "You must enter an access code to proceed: " | pv -qL 100
                while IFS= read -p "$pass_var" -r -s -n 1 letter
                do
                    if [[ $letter == $'\0' ]]
                    then
                        break
                    fi
                    password=$password"$letter"
                    pass_var="*"
                done
            done
            export PASSCODE=$(cat $SCRIPTPATH/.${SCRIPTNAME}.secret | openssl enc -aes-256-cbc -md sha512 -a -d -pbkdf2 -iter 100000 -salt -pass pass:$password 2> /dev/null)
            if [[ $PASSCODE == 'AccessVerified' ]]; then
                MODE=2
                echo && echo
                echo "*** Access code is valid ***" | pv -qL 100
                if [[ -f $PROJDIR/.${GCP_PROJECT}.json ]]; then
                    echo 
                    echo "*** Authenticating using service account key $PROJDIR/.${GCP_PROJECT}.json ***" | pv -qL 100
                    echo "*** To use a different GCP project, delete the service account key ***" | pv -qL 100
                else
                    while [[ "$GCP_PROJECT" != "$PROJECT_ID" ]]; do
                        echo 
                        echo "$ gcloud auth login --brief --quiet # to authenticate as project owner or editor" | pv -qL 100
                        gcloud auth login  --brief --quiet
                        export ACCOUNT=$(gcloud config list account --format "value(core.account)")
                        if [[ $ACCOUNT != "" ]]; then
                            echo
                            echo "Copy and paste a valid Google Cloud project ID below to confirm your choice:" | pv -qL 100
                            read GCP_PROJECT
                            gcloud config set project $GCP_PROJECT --quiet 2>/dev/null
                            sleep 3
                            export PROJECT_ID=$(gcloud projects list --filter $GCP_PROJECT --format 'value(PROJECT_ID)' 2>/dev/null)
                        fi
                    done
                    gcloud iam service-accounts delete ${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com --quiet 2>/dev/null
                    sleep 2
                    gcloud --project $GCP_PROJECT iam service-accounts create ${GCP_PROJECT} 2>/dev/null
                    gcloud projects add-iam-policy-binding $GCP_PROJECT --member serviceAccount:$GCP_PROJECT@$GCP_PROJECT.iam.gserviceaccount.com --role=roles/owner > /dev/null 2>&1
                    gcloud --project $GCP_PROJECT iam service-accounts keys create $PROJDIR/.${GCP_PROJECT}.json --iam-account=${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com 2>/dev/null
                    gcloud --project $GCP_PROJECT storage buckets create gs://$GCP_PROJECT > /dev/null 2>&1
                fi
                export GOOGLE_APPLICATION_CREDENTIALS=$PROJDIR/.${GCP_PROJECT}.json
                cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT
export GCP_REGION=$GCP_REGION
export GCP_ZONE=$GCP_ZONE
export SERVICEMESH_VERSION=$SERVICEMESH_VERSION
export ANTHOS_VERSION=$ANTHOS_VERSION
EOF
                gsutil cp $PROJDIR/.env gs://${GCP_PROJECT}/${SCRIPTNAME}.env > /dev/null 2>&1
                echo
                echo "*** Google Cloud project is $GCP_PROJECT ***" | pv -qL 100
                echo "*** Google Cloud region is $GCP_REGION ***" | pv -qL 100
                echo "*** Google Cloud zone is $GCP_ZONE ***" | pv -qL 100
                echo "*** Anthos Service Mesh version is $SERVICEMESH_VERSION ***" | pv -qL 100
                echo "*** Anthos version is $ANTHOS_VERSION ***" | pv -qL 100
                echo
                echo "*** Update environment variables by modifying values in the file: ***" | pv -qL 100
                echo "*** $PROJDIR/.env ***" | pv -qL 100
                if [[ "no" == $ANSWER ]]; then
                    MODE=2
                    echo
                    echo "*** Create mode is active ***" | pv -qL 100
                elif [[ "del" == $ANSWER ]]; then
                    export STEP="${STEP},0"
                    MODE=3
                    echo
                    echo "*** Resource delete mode is active ***" | pv -qL 100
                fi
            else
                echo && echo
                echo "*** Access code is invalid ***" | pv -qL 100
                echo "*** You can use this script in our Google Cloud Sandbox without an access code ***" | pv -qL 100
                echo "*** Contact support@techequity.cloud for assistance ***" | pv -qL 100
                echo
                echo "*** Command preview mode is active ***" | pv -qL 100
            fi
        else
            echo
            echo "*** You can use this script in our Google Cloud Sandbox without an access code ***" | pv -qL 100
            echo "*** Contact support@techequity.cloud for assistance ***" | pv -qL 100
            echo
            echo "*** Command preview mode is active ***" | pv -qL 100
        fi
    else
        export STEP="${STEP},0i"
        MODE=1
        echo
        echo "*** Command preview mode is active ***" | pv -qL 100
    fi
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"1")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},1i"
    echo
    echo "$ gcloud compute networks create anthos-network --subnet-mode custom # to create custom network" | pv -qL 100
    echo
    echo "$ gcloud compute networks subnets create \$GCP_REGION-subnet --network anthos-network --region \$GCP_REGION --range 10.1.0.0/24" | pv -qL 100
    echo
    echo "$ gcloud compute firewall-rules create abm-allow-cp --network=\"anthos-network\" --allow=\"UDP:6081,TCP:22,TCP:6444,TCP:2379-2380,TCP:10250-10252,TCP:4240\" --source-ranges=\"10.0.0.0/8\" --target-tags=\"cp\" # to allow traffic to the control plane servers" | pv -qL 100
    echo
    echo "$ gcloud compute firewall-rules create abm-allow-worker --network=\"anthos-network\" --allow=\"UDP:6081,TCP:22,TCP:10250,TCP:30000-32767,TCP:4240\" --source-ranges=\"10.0.0.0/8\" --target-tags=\"worker\" # to allow inbound traffic to the worker nodes" | pv -qL 100
    echo
    echo "$ gcloud compute firewall-rules create abm-allow-lb --network=\"anthos-network\" --allow=\"UDP:6081,TCP:22,TCP:443,TCP:7946,UDP:7496,TCP:4240\" --source-ranges=\"10.0.0.0/8\" --target-tags=\"lb\" # to allow inbound traffic to the load balancer nodes" | pv -qL 100
    echo
    echo "$ gcloud compute firewall-rules create allow-gfe-to-lb --network=\"anthos-network\" --allow=\"TCP:443\" --source-ranges=\"10.0.0.0/8,130.211.0.0/22,35.191.0.0/16\" --target-tags=\"lb\" # to allow traffic from Google Frontend to load balancers" | pv -qL 100
    echo
    echo "$ gcloud compute firewall-rules create abm-allow-multi --network=\"anthos-network\" --allow=\"TCP:22,TCP:443\" --source-tags=\"admin\" --target-tags=\"user\" # to allow multi-cluster traffic" | pv -qL 100
    echo
    echo "$ gcloud compute firewall-rules create iap --network=\"anthos-network\" --allow=\"TCP:22\" --source-ranges=\"35.235.240.0/20\" --target-tags=\"lb\" # to allow SSH via IAP" | pv -qL 100
    echo
    echo "$ gcloud compute firewall-rules create vxlan --network=\"anthos-network\" --allow=\"udp:4789\" --source-tags=\"vxlan\" # to allow vxlan networking" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},1"
    echo
    echo "$ gcloud compute networks create anthos-network --subnet-mode custom # to create custom network" | pv -qL 100
    gcloud compute networks create anthos-network  --subnet-mode custom
    echo
    echo "$ gcloud compute networks subnets create $GCP_REGION-subnet --network anthos-network --region $GCP_REGION --range 10.1.0.0/24" | pv -qL 100
    gcloud compute networks subnets create $GCP_REGION-subnet --network anthos-network --region $GCP_REGION --range 10.1.0.0/24
    echo
    echo "$ gcloud compute firewall-rules create abm-allow-cp --network=\"anthos-network\" --allow=\"UDP:6081,TCP:22,TCP:6444,TCP:2379-2380,TCP:10250-10252,TCP:4240\" --source-ranges=\"10.0.0.0/8\" --target-tags=\"cp\" # to allow traffic to the control plane servers" | pv -qL 100
    gcloud compute firewall-rules create abm-allow-cp --network="anthos-network" --allow="UDP:6081,TCP:22,TCP:6444,TCP:2379-2380,TCP:10250-10252,TCP:4240" --source-ranges="10.0.0.0/8" --target-tags="cp"
    echo
    echo "$ gcloud compute firewall-rules create abm-allow-worker --network=\"anthos-network\" --allow=\"UDP:6081,TCP:22,TCP:10250,TCP:30000-32767,TCP:4240\" --source-ranges=\"10.0.0.0/8\" --target-tags=\"worker\" # to allow inbound traffic to the worker nodes" | pv -qL 100
    gcloud compute firewall-rules create abm-allow-worker --network="anthos-network" --allow="UDP:6081,TCP:22,TCP:10250,TCP:30000-32767,TCP:4240" --source-ranges="10.0.0.0/8" --target-tags="worker"
    echo
    echo "$ gcloud compute firewall-rules create abm-allow-lb --network=\"anthos-network\" --allow=\"UDP:6081,TCP:22,TCP:443,TCP:7946,UDP:7496,TCP:4240\" --source-ranges=\"10.0.0.0/8\" --target-tags=\"lb\" # to allow inbound traffic to the load balancer nodes" | pv -qL 100
    gcloud compute firewall-rules create abm-allow-lb --network="anthos-network" --allow="UDP:6081,TCP:22,TCP:443,TCP:7946,UDP:7496,TCP:4240" --source-ranges="10.0.0.0/8" --target-tags="lb"
    echo
    echo "$ gcloud compute firewall-rules create allow-gfe-to-lb --network=\"anthos-network\" --allow=\"TCP:443\" --source-ranges=\"10.0.0.0/8,130.211.0.0/22,35.191.0.0/16\" --target-tags=\"lb\" # to allow traffic from Google Frontend to load balancers" | pv -qL 100
    gcloud compute firewall-rules create allow-gfe-to-lb --network="anthos-network" --allow="TCP:443" --source-ranges="10.0.0.0/8,130.211.0.0/22,35.191.0.0/16" --target-tags="lb"
    echo
    echo "$ gcloud compute firewall-rules create abm-allow-multi --network=\"anthos-network\" --allow=\"TCP:22,TCP:443\" --source-tags=\"admin\" --target-tags=\"user\" # to allow multi-cluster traffic" | pv -qL 100
    gcloud compute firewall-rules create abm-allow-multi --network="anthos-network" --allow="TCP:22,TCP:443" --source-tags="admin" --target-tags="user"
    echo
    echo "$ gcloud compute firewall-rules create iap --network=\"anthos-network\" --allow=\"TCP:22\" --source-ranges=\"35.235.240.0/20\" --target-tags=\"lb\" # to allow SSH via IAP" | pv -qL 100
    gcloud compute firewall-rules create iap --network="anthos-network" --allow="TCP:22" --source-ranges="35.235.240.0/20"
    echo
    echo "$ gcloud compute firewall-rules create vxlan --network=\"anthos-network\" --allow=\"udp:4789\" --source-tags=\"vxlan\" # to allow vxlan networking" | pv -qL 100
    gcloud compute firewall-rules create vxlan --network="anthos-network" --allow="udp:4789" --source-tags="vxlan"
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},1x"
    echo
    echo "$ gcloud compute networks delete anthos-network # to delete custom network" | pv -qL 100
    gcloud compute networks delete anthos-network --quiet 2>/dev/null
else
    export STEP="${STEP},1i"
    echo
    echo "1. Create custom network" | pv -qL 100
    echo "2. Create subnet" | pv -qL 100
    echo "3. Configure firewall rules" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"2")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},2i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute project-info add-metadata --metadata enable-oslogin=FALSE # to disable OS login" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute instances create \$VM_WS --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone \$GCP_ZONE --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network anthos-network --subnet \$GCP_REGION-subnet --tags vxlan --min-cpu-platform \"Intel Haswell\" --scopes cloud-platform --machine-type n1-standard-4 # to create admin workstation VM" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute instances create \$VM_A_CP1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone \$GCP_ZONE --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network anthos-network --subnet \$GCP_REGION-subnet --tags cp,admin,vxlan,lb --min-cpu-platform \"Intel Haswell\" --scopes cloud-platform --machine-type n1-standard-4 --metadata \"cluster_id=bm-gke-admin-cluster,bmctl_version=\${ANTHOS_VERSION}\" # to create admin cluster control plane VM" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute instances create \$VM_U_CP1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone \$GCP_ZONE --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network anthos-network --subnet \$GCP_REGION-subnet --tags cp,user,vxlan,lb --min-cpu-platform \"Intel Haswell\" --scopes cloud-platform --machine-type n1-standard-4 --metadata \"cluster_id=\$VM_PREFIX-user-cluster,bmctl_version=\${ANTHOS_VERSION}\" # to create user cluster control plane VM" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute instances create \$VM_U_W1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone \$GCP_ZONE --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network anthos-network --subnet \$GCP_REGION-subnet --tags worker,user,vxlan --min-cpu-platform \"Intel Haswell\" --scopes cloud-platform --machine-type n1-standard-4 --metadata \"cluster_id=\$VM_PREFIX-user-cluster,bmctl_version=\${ANTHOS_VERSION}\" # to create user cluster node VM" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},2"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute project-info add-metadata --metadata enable-oslogin=FALSE # to disable OS login" | pv -qL 100
    gcloud --project $GCP_PROJECT compute project-info add-metadata --metadata enable-oslogin=FALSE
    echo
    echo "$ gcloud --project $GCP_PROJECT compute instances create $VM_WS --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone $GCP_ZONE --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network anthos-network --subnet $GCP_REGION-subnet --tags vxlan --min-cpu-platform \"Intel Haswell\" --enable-nested-virtualization --scopes cloud-platform --machine-type n1-standard-4 # to create admin workstation VM" | pv -qL 100
    gcloud --project $GCP_PROJECT compute instances create $VM_WS --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone $GCP_ZONE --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network anthos-network --subnet $GCP_REGION-subnet --tags vxlan --min-cpu-platform "Intel Haswell" --enable-nested-virtualization --scopes cloud-platform --machine-type n1-standard-4
    echo
    echo "$ gcloud --project $GCP_PROJECT compute instances create $VM_A_CP1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone $GCP_ZONE --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network anthos-network --subnet $GCP_REGION-subnet --tags cp,admin,vxlan,lb --min-cpu-platform \"Intel Haswell\" --enable-nested-virtualization --scopes cloud-platform --machine-type n1-standard-4 --metadata \"cluster_id=bm-gke-admin-cluster,bmctl_version=${ANTHOS_VERSION}\" # to create admin cluster control plane VM" | pv -qL 100
    gcloud --project $GCP_PROJECT compute instances create $VM_A_CP1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone $GCP_ZONE --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network anthos-network --subnet $GCP_REGION-subnet --tags cp,admin,vxlan,lb --min-cpu-platform "Intel Haswell" --enable-nested-virtualization --scopes cloud-platform --machine-type n1-standard-4 --metadata "cluster_id=bm-gke-admin-cluster,bmctl_version=${ANTHOS_VERSION}"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute instances create $VM_U_CP1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone $GCP_ZONE --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network anthos-network --subnet $GCP_REGION-subnet --tags cp,user,vxlan,lb --min-cpu-platform \"Intel Haswell\" --enable-nested-virtualization --scopes cloud-platform --machine-type n1-standard-4 --metadata \"cluster_id=$VM_PREFIX-user-cluster,bmctl_version=${ANTHOS_VERSION}\" # to create user cluster control plane VM" | pv -qL 100
    gcloud --project $GCP_PROJECT compute instances create $VM_U_CP1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone $GCP_ZONE --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network anthos-network --subnet $GCP_REGION-subnet --tags cp,user,vxlan,lb --min-cpu-platform "Intel Haswell" --enable-nested-virtualization --scopes cloud-platform --machine-type n1-standard-4 --metadata "cluster_id=$VM_PREFIX-user-cluster,bmctl_version=${ANTHOS_VERSION}"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute instances create $VM_U_W1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone $GCP_ZONE --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network anthos-network --subnet $GCP_REGION-subnet --tags worker,user,vxlan --min-cpu-platform \"Intel Haswell\" --enable-nested-virtualization --scopes cloud-platform --machine-type n1-standard-4 --metadata \"cluster_id=$VM_PREFIX-user-cluster,bmctl_version=${ANTHOS_VERSION}\" # to create user cluster node VM" | pv -qL 100
    gcloud --project $GCP_PROJECT compute instances create $VM_U_W1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone $GCP_ZONE --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network anthos-network --subnet $GCP_REGION-subnet --tags worker,user,vxlan --min-cpu-platform "Intel Haswell" --enable-nested-virtualization --scopes cloud-platform --machine-type n1-standard-4 --metadata "cluster_id=$VM_PREFIX-user-cluster,bmctl_version=${ANTHOS_VERSION}"
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},2x"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute instances delete $VM_WS --zone $GCP_ZONE # to delete admin workstation VM" | pv -qL 100
    gcloud --project $GCP_PROJECT compute instances delete $VM_WS --zone $GCP_ZONE
    echo
    echo "$ gcloud --project $GCP_PROJECT compute instances delete $VM_A_CP1 --zone $GCP_ZONE # to delete admin cluster control plane VM" | pv -qL 100
    gcloud --project $GCP_PROJECT compute instances delete $VM_A_CP1 --zone $GCP_ZONE
    echo
    echo "$ gcloud --project $GCP_PROJECT compute instances delete $VM_U_CP1 --zone $GCP_ZONE # to delete user cluster control plane VM" | pv -qL 100
    gcloud --project $GCP_PROJECT compute instances delete $VM_U_CP1 --zone $GCP_ZONE
    echo
    echo "$ gcloud --project $GCP_PROJECT compute instances delete $VM_U_W1 --zone $GCP_ZONE # to delete user cluster node VM" | pv -qL 100
    gcloud --project $GCP_PROJECT compute instances delete $VM_U_W1 --zone $GCP_ZONE
else
    export STEP="${STEP},2i"
    echo
    echo "1. Disable OS login" | pv -qL 100
    echo "2. Create virtual machines" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"3")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},3i"
    echo
    echo "$ eval \`ssh-agent\` # to enable SSH agent" | pv -qL 100
    echo
    echo "$ ssh-add ~/.ssh/google_compute_engine # to add identity" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
echo \"y\" | ssh-keygen -t rsa -N \"\" -f /root/.ssh/id_rsa
sed 's/ssh-rsa/root:ssh-rsa/' /root/.ssh/id_rsa.pub > ssh-metadata
for vm in \${VMs[@]}
do
    echo
    ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub root@\\\$vm # to configure machines to accept SSH key
done
EOF" | pv -qL 100
    echo
    echo "$ for vm in \"\${VMs[@]}\"
do
    IP=\$(gcloud --project \$GCP_PROJECT compute instances describe \$vm --zone \$GCP_ZONE --format='get(networkInterfaces[0].networkIP)')
    IPs+=(\"\$IP\")
done # to store VM IPs in array" | pv -qL 100
    echo
    echo "$ for vm in \"\${VMs[@]}\"
do
    echo \"Disabling UFW on \$vm\"
    gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$vm --zone \$GCP_ZONE --tunnel-through-iap  << EOF
        sudo ufw disable
EOF
done # to disable Uncomplicated Firewall (UFW)" | pv -qL 100
    echo
    echo "$ i=2
for vm in \"\${VMs[@]}\"
do
    gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE << EOF
        set -x
        apt-get -qq update > /dev/null
        apt-get -qq install -y jq > /dev/null
        ip link add vxlan0 type vxlan id 42 dev ens4 dstport 0
        current_ip=\\\$(ip --json a show dev ens4 | jq '.[0].addr_info[0].local' -r)
        for ip in \${IPs[@]}; do
            if [ \"\\\$ip\" != \"\\\$current_ip\" ]; then
                bridge fdb append to 00:00:00:00:00:00 dst \\\$ip dev vxlan0
            fi
        done
        ip addr add 10.200.0.\$i/24 dev vxlan0
        ip link set up dev vxlan0
EOF
    i=\$((i+1))
done" | pv -qL 100
    echo
    echo "$ i=2
for vm in \"\${VMs[@]}\"
do
    echo \"Disabling UFW on \$vm\"
    gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$vm --zone \$GCP_ZONE --tunnel-through-iap --command=\"hostname -I\"; 
    i=\$((i+1));
done # Check vxlan IPs associated with VMs" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},3"
    echo
    echo "$ eval \`ssh-agent\` # to enable SSH agent" | pv -qL 100
    eval `ssh-agent`
    echo
    echo "$ ssh-add ~/.ssh/google_compute_engine # to add identity" | pv -qL 100
    ssh-add ~/.ssh/google_compute_engine
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
echo \"y\" | ssh-keygen -t rsa -N \"\" -f /root/.ssh/id_rsa
sed 's/ssh-rsa/root:ssh-rsa/' /root/.ssh/id_rsa.pub > ssh-metadata
for vm in \${VMs[@]}
do
    echo
    ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub root@\\\$vm # to configure machines to accept SSH key
done
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
echo "y" | ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
sed 's/ssh-rsa/root:ssh-rsa/' /root/.ssh/id_rsa.pub > ssh-metadata
sleep 5
for vm in ${VMs[@]}
do
    echo
    ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub root@\$vm # to configure machines to accept SSH key
done
EOF
eval `ssh-agent`
ssh-add ~/.ssh/google_compute_engine
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
echo "y" | ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
sed 's/ssh-rsa/root:ssh-rsa/' /root/.ssh/id_rsa.pub > ssh-metadata
sleep 5
for vm in ${VMs[@]}
do
    echo
    ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub root@\$vm # to configure machines to accept SSH key
done
EOF
    echo
    echo "$ for vm in \"\${VMs[@]}\"
do
    IP=\$(gcloud --project $GCP_PROJECT compute instances describe \$vm --zone $GCP_ZONE --format='get(networkInterfaces[0].networkIP)')
    IPs+=(\"\$IP\")
done # to store VM IPs in array" | pv -qL 100
for vm in "${VMs[@]}"
do
    IP=$(gcloud --project $GCP_PROJECT compute instances describe $vm --zone $GCP_ZONE --format='get(networkInterfaces[0].networkIP)')
    IPs+=("$IP")
done
    echo
    echo "$ for vm in \"\${VMs[@]}\"
do
    echo \"Disabling UFW on \$vm\"
    gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$vm --zone $GCP_ZONE --tunnel-through-iap  << EOF
        sudo ufw disable
EOF
done # to disable Uncomplicated Firewall (UFW)" | pv -qL 100
for vm in "${VMs[@]}"
do
    echo "Disabling UFW on $vm"
    gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$vm --zone $GCP_ZONE --tunnel-through-iap  << EOF
        sudo ufw disable
EOF
done
    echo
    echo "$ i=2
for vm in \"\${VMs[@]}\"
do
    gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE << EOF
        set -x
        apt-get -qq update > /dev/null
        apt-get -qq install -y jq > /dev/null
        ip link add vxlan0 type vxlan id 42 dev ens4 dstport 0
        current_ip=\\\$(ip --json a show dev ens4 | jq '.[0].addr_info[0].local' -r)
        for ip in \${IPs[@]}; do
            if [ \"\\\$ip\" != \"\\\$current_ip\" ]; then
                bridge fdb append to 00:00:00:00:00:00 dst \\\$ip dev vxlan0
            fi
        done
        ip addr add 10.200.0.\$i/24 dev vxlan0
        ip link set up dev vxlan0
EOF
    i=\$((i+1))
done" | pv -qL 100
i=2
for vm in "${VMs[@]}"
do
    gcloud compute ssh --ssh-flag="-A" root@$vm --zone $GCP_ZONE --tunnel-through-iap << EOF
        # update package list on VM
        apt-get -qq update > /dev/null
        apt-get -qq install -y jq > /dev/null
        # print executed commands to terminal
        set -x
        # create new vxlan configuration
        ip link add vxlan0 type vxlan id 42 dev ens4 dstport 4789
        current_ip=\$(ip --json a show dev ens4 | jq '.[0].addr_info[0].local' -r)
        echo "VM IP address is: \$current_ip"
        for ip in ${IPs[@]}; do
            if [ "\$ip" != "\$current_ip" ]; then
                bridge fdb append to 00:00:00:00:00:00 dst \$ip dev vxlan0
            fi
        done
        ip addr add 10.200.0.$i/24 dev vxlan0
        ip link set up dev vxlan0
EOF
    i=$((i+1))
done
    echo
    echo "$ i=2
for vm in \"\${VMs[@]}\"
do
    echo \"Disabling UFW on $vm\"
    gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$vm --zone \$GCP_ZONE --tunnel-through-iap --command=\"hostname -I\"; 
    i=\$((i+1));
done # Check vxlan IPs associated with VMs" | pv -qL 100
i=2
for vm in "${VMs[@]}";
do
    echo $vm;
    gcloud compute ssh --ssh-flag="-A" root@$vm --zone $GCP_ZONE --tunnel-through-iap --command="hostname -I"; 
    i=$((i+1));
done
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},3x"
    echo
    echo "*** Nothing to delete ***" | pv -qL 100
else
    export STEP="${STEP},3i"
    echo
    echo "1. Verify that SSH is ready on all virtual machines" | pv -qL 100
    echo "2. disable Uncomplicated Firewall (UFW)" | pv -qL 100
    echo "3. Connect VMs with Linux vXlan L2 connectivity" | pv -qL 100
    echo "4. Check vxlan IPs associated with VMs" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"4")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},4i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
sudo snap remove google-cloud-sdk # remove the GCE-specific version of the SDK
sudo curl https://sdk.cloud.google.com | bash # install the SDK as you would on a non-GCE server
sudo snap install kubectl --classic
exec -l \$SHELL # to restart shell
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
gcloud iam service-accounts keys create installer.json --iam-account=\$VM_PREFIX-sa-key@\$VM_PREFIX-sa-key.iam.gserviceaccount.com # Create keys for a service account with the same permissions
mkdir -p baremetal && cd baremetal
gsutil cp gs://anthos-baremetal-release/bmctl/\$ANTHOS_VERSION/linux-amd64/bmctl .
chmod a+x bmctl
mv bmctl /usr/local/sbin/
cd ~
echo \"Installing docker\"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
git clone https://github.com/ahmetb/kubectx /opt/kubectx
ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
ln -s /opt/kubectx/kubens /usr/local/bin/kubens
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},4"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
sudo snap remove google-cloud-sdk # remove the GCE-specific version of the SDK
sudo curl https://sdk.cloud.google.com | bash # install the SDK as you would on a non-GCE server
sudo snap install kubectl --classic
exec -l \$SHELL # to restart shell
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
sudo snap remove google-cloud-sdk # remove the GCE-specific version of the SDK
sudo curl https://sdk.cloud.google.com | bash # install the SDK as you would on a non-GCE server # restart your shell
sudo snap install kubectl --classic
exec -l \$SHELL # to restart shell
EOF
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
gcloud iam service-accounts keys create installer.json --iam-account=\${VM_PREFIX}-sa-key@\${GCP_PROJECT}.iam.gserviceaccount.com # to create keys for a service account
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
mkdir -p baremetal && cd baremetal
gsutil cp gs://anthos-baremetal-release/bmctl/$ANTHOS_VERSION/linux-amd64/bmctl .
chmod a+x bmctl
mv bmctl /usr/local/sbin/
cd ~
echo \"Installing docker\"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
git clone https://github.com/ahmetb/kubectx /opt/kubectx
ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
ln -s /opt/kubectx/kubens /usr/local/bin/kubens
EOF" | pv -qL 100
    gcloud iam service-accounts delete ${VM_PREFIX}-sa-key@${GCP_PROJECT}.iam.gserviceaccount.com --quiet > /dev/null 2>&1
    sleep 2
    echo
    echo "$ gcloud --project $GCP_PROJECT iam service-accounts create ${VM_PREFIX}-sa-key  # to create install service account"
    gcloud --project $GCP_PROJECT iam service-accounts create ${VM_PREFIX}-sa-key 
    echo
    echo "$ gcloud projects add-iam-policy-binding $GCP_PROJECT --member serviceAccount:${VM_PREFIX}-sa-key@$GCP_PROJECT.iam.gserviceaccount.com --role=roles/owner # to assign role"
    gcloud projects add-iam-policy-binding $GCP_PROJECT --member serviceAccount:${VM_PREFIX}-sa-key@$GCP_PROJECT.iam.gserviceaccount.com --role=roles/owner > /dev/null 2>&1
    gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
gcloud iam service-accounts keys create installer.json --iam-account=${VM_PREFIX}-sa-key@${GCP_PROJECT}.iam.gserviceaccount.com # to create keys for a service account
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
mkdir -p baremetal && cd baremetal
gsutil cp gs://anthos-baremetal-release/bmctl/$ANTHOS_VERSION/linux-amd64/bmctl .
chmod a+x bmctl
mv bmctl /usr/local/sbin/
cd ~
echo "Installing docker"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
git clone https://github.com/ahmetb/kubectx /opt/kubectx
ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
ln -s /opt/kubectx/kubens /usr/local/bin/kubens
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},4x"
    echo
    echo "*** Nothing to delete ***" | pv -qL 100
else
    export STEP="${STEP},4i"
    echo
    echo "1. Replace GCE-specific version of the SDK" | pv -qL 100
    echo "2. Create installer service account key" | pv -qL 100
    echo "3. Install kubectl and bmctl" | pv -qL 100
    echo "4. Install docker" | pv -qL 100
    echo "5. Install kubectx and kubens" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"5")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},5i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
bmctl create config -c \\\$clusterid --enable-apis --create-service-accounts --project-id=\$GCP_PROJECT # to generate cluster config yaml
bmctl create cluster -c \\\$clusterid # to create cluster
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
kubectl get nodes # to get nodes
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships generate-gateway-rbac --membership=\\\$clusterid --role=clusterrole/cluster-admin --users=\$(gcloud config get-value core/account) --project=\$GCP_PROJECT --kubeconfig=\\\$KUBECONFIG --context=\\\$clusterid-admin@\\\$clusterid --apply # to enable clusters to authorize requests from Google Cloud console
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},5"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export clusterid=$VM_PREFIX-admin-cluster 
sudo rm -rf bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml
bmctl create config -c \\\$clusterid --enable-apis --create-service-accounts --project-id=$GCP_PROJECT # to generate cluster config yaml
sed -r -i \\\"s|sshPrivateKeyPath: <path to SSH private key, used for node access>|sshPrivateKeyPath: /root/.ssh/id_rsa|g\\\" bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml # to configure SSK key path
sed -r -i \\\"s|type: hybrid|type: admin|g\\\" bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml # to configure LB CP IP
sed -r -i \\\"s|# enableApplication: false|enableApplication: true|g\\\" bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml # to configure LB CP IP
sed -r -i \\\"s|- address: <Machine 1 IP>|- address: 10.200.0.98|g\\\" bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml # to configure LB CP IP
sed -r -i \\\"s|controlPlaneVIP: 10.0.0.8|controlPlaneVIP: 10.200.0.3|g\\\" bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml # to configure CP VIP
head -n -11 bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml > temp_file && mv temp_file bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml # to delete node pool configuration
bmctl create cluster -c \\\$clusterid # to create cluster
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-admin-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
sudo rm -rf bmctl-workspace/bm-gke-admin-cluster/bm-gke-admin-cluster.yaml
bmctl create config -c \$clusterid --enable-apis --create-service-accounts --project-id=$GCP_PROJECT
sed -r -i "s|sshPrivateKeyPath: <path to SSH private key, used for node access>|sshPrivateKeyPath: /root/.ssh/id_rsa|g" bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml
sed -r -i "s|type: hybrid|type: admin|g" bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml
sed -r -i "s|# enableApplication: false|enableApplication: true|g" bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml
sed -r -i "s|- address: <Machine 1 IP>|- address: 10.200.0.3|g" bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml
sed -r -i "s|controlPlaneVIP: 10.0.0.8|controlPlaneVIP: 10.200.0.98|g" bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml
head -n -11 bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml > temp_file && mv temp_file bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster.yaml
bmctl create cluster -c \$clusterid
EOF
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-admin-cluster
export KUBECONFIG=bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
kubectl get nodes # to get nodes
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-admin-cluster
export KUBECONFIG=bmctl-workspace/\$clusterid/\$clusterid-kubeconfig
kubectl get nodes # to get nodes
EOF
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-admin-cluster
export KUBECONFIG=bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships generate-gateway-rbac --membership=\\\$clusterid --role=clusterrole/cluster-admin --users=\$(gcloud config get-value core/account) --project=\$GCP_PROJECT --kubeconfig=\\\$KUBECONFIG --context=\\\$clusterid-admin@\\\$clusterid --apply # to enable clusters to authorize requests from Google Cloud console
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-admin-cluster
export KUBECONFIG=bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships generate-gateway-rbac --membership=\$clusterid --role=clusterrole/cluster-admin --users=$(gcloud config get-value core/account) --project=$GCP_PROJECT --kubeconfig=\$KUBECONFIG --context=\$clusterid-admin@\$clusterid --apply # to enable clusters to authorize requests from Google Cloud console
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},5x"
    echo
    echo "$ export EMAIL=\$(gcloud config get-value core/account) # to set email" | pv -qL 100
    export EMAIL=$(gcloud config get-value core/account)
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-admin-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships unregister \\\$clusterid --project=$GCP_PROJECT --kubeconfig=\\\$KUBECONFIG --context=\\\$clusterid-admin@\\\$clusterid # to unregister clusters
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-admin-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships unregister \$clusterid --project=$GCP_PROJECT --kubeconfig=\$KUBECONFIG --context=\$clusterid-admin@\$clusterid # to unregister clusters
EOF
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-admin-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
export clusterid=$VM_PREFIX-admin-cluster
bmctl reset --cluster \\\$clusterid
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-admin-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
export clusterid=$VM_PREFIX-admin-cluster
bmctl reset --cluster \$clusterid
EOF
else
    export STEP="${STEP},5i"
    echo
    echo "1. Create baremetal admin cluster" | pv -qL 100
    echo "2. Enable access to baremetal admin cluster" | pv -qL 100
fi
echo
read -n 1 -s -r -p "$ "
;;

"6")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},6i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
bmctl create config -c \\\$clusterid --project-id=\$GCP_PROJECT
bmctl create cluster -c \\\$clusterid --kubeconfig bmctl-workspace/\$VM_PREFIX-admin-cluster/\$VM_PREFIX-admin-cluster-kubeconfig
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
kubectl get nodes # to get nodes
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships generate-gateway-rbac --membership=\\\$clusterid --role=clusterrole/cluster-admin --users=\$(gcloud config get-value core/account) --project=\$GCP_PROJECT --kubeconfig=\\\$KUBECONFIG --context=\\\$clusterid-admin@\\\$clusterid --apply # to enable clusters to authorize requests from Google Cloud console
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},6"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
sudo rm -rf bmctl-workspace/\\\$clusterid/\\\$clusterid.yaml
bmctl create config -c \\\$clusterid --project-id=\$GCP_PROJECT
tail -n +11 bmctl-workspace/\\\$clusterid/\\\$clusterid.yaml > temp_file && mv temp_file bmctl-workspace/\\\$clusterid/\\\$clusterid.yaml
sed -i '1 i\\sshPrivateKeyPath: /root/.ssh/id_rsa' bmctl-workspace/\\\$clusterid/\\\$clusterid.yaml
sed -r -i \"s|type: hybrid|type: user|g\" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i \"s|# enableApplication: false|enableApplication: true|g\" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i \"s|- address: <Machine 1 IP>|- address: 10.200.0.4|g\" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i \"s|controlPlaneVIP: 10.0.0.8|controlPlaneVIP: 10.200.0.99|g\" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i \"s|# ingressVIP: 10.0.0.2|ingressVIP: 10.200.0.100|g\" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i \"s|# addressPools:|addressPools:|g\" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i \"s|# - name: pool1|- name: pool1|g\" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i \"s|#   addresses:|  addresses:|g\" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i \"s|#   - 10.0.0.1-10.0.0.4|  - 10.200.0.100-10.200.0.200|g\" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i \"s|# disableCloudAuditLogging: false|disableCloudAuditLogging: false|g\" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i \"s|# enableApplication: false|enableApplication: true|g\" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i \"s|name: node-pool-1|name: user-cluster-central-pool-1|g\" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i \"s|- address: <Machine 2 IP>|- address: 10.200.0.5|g\" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i \"s|- address: <Machine 3 IP>|# - address: <Machine 3 IP>|g\" bmctl-workspace/\$clusterid/\$clusterid.yaml
bmctl create cluster -c \\\$clusterid --kubeconfig bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster-kubeconfig
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
sudo rm -rf bmctl-workspace/\$clusterid/\$clusterid.yaml
bmctl create config -c \$clusterid --project-id=$GCP_PROJECT
tail -n +11 bmctl-workspace/\$clusterid/\$clusterid.yaml > temp_file && mv temp_file bmctl-workspace/\$clusterid/\$clusterid.yaml # to delete credential references
sed -i '1 i\sshPrivateKeyPath: /root/.ssh/id_rsa' bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i "s|type: hybrid|type: user|g" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i "s|# enableApplication: false|enableApplication: true|g" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i "s|- address: <Machine 1 IP>|- address: 10.200.0.4|g" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i "s|controlPlaneVIP: 10.0.0.8|controlPlaneVIP: 10.200.0.99|g" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i "s|# ingressVIP: 10.0.0.2|ingressVIP: 10.200.0.100|g" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i "s|# addressPools:|addressPools:|g" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i "s|# - name: pool1|- name: pool1|g" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i "s|#   addresses:|  addresses:|g" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i "s|#   - 10.0.0.1-10.0.0.4|  - 10.200.0.100-10.200.0.200|g" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i "s|# disableCloudAuditLogging: false|disableCloudAuditLogging: false|g" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i "s|# enableApplication: false|enableApplication: true|g" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i "s|name: node-pool-1|name: user-cluster-central-pool-1|g" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i "s|- address: <Machine 2 IP>|- address: 10.200.0.5|g" bmctl-workspace/\$clusterid/\$clusterid.yaml
sed -r -i "s|- address: <Machine 3 IP>|# - address: <Machine 3 IP>|g" bmctl-workspace/\$clusterid/\$clusterid.yaml
bmctl create cluster -c \$clusterid --kubeconfig bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster-kubeconfig
EOF
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
kubectl get nodes # to get nodes
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=bmctl-workspace/\$clusterid/\$clusterid-kubeconfig
kubectl get nodes # to get nodes
EOF
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
gcloud --project $GCP_PROJECT services enable gkeonprem.googleapis.com 
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships generate-gateway-rbac --membership=\\\$clusterid --role=clusterrole/cluster-admin --users=\$(gcloud config get-value core/account) --project=\$GCP_PROJECT --kubeconfig=\\\$KUBECONFIG --context=\\\$clusterid-admin@\\\$clusterid --apply # to enable clusters to authorize requests from Google Cloud console
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
gcloud --project $GCP_PROJECT services enable gkeonprem.googleapis.com 
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships generate-gateway-rbac --membership=\$clusterid --role=clusterrole/cluster-admin --users=$(gcloud config get-value core/account) --project=$GCP_PROJECT --kubeconfig=\$KUBECONFIG --context=\$clusterid-admin@\$clusterid --apply # to enable clusters to authorize requests from Google Cloud console
EOF
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-admin-cluster
export KUBECONFIG=bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
gcloud alpha container bare-metal admin-clusters enroll \\\$clusterid --project=\$GCP_PROJECT --admin-cluster-membership=\\\$clusterid --location=\$GCP_REGION # to enroll the admin cluster with the GKE On-Prem API
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-admin-cluster
export KUBECONFIG=bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},6x"
    echo
    echo "$ export EMAIL=\$(gcloud config get-value core/account) # to set email" | pv -qL 100
    export EMAIL=$(gcloud config get-value core/account)
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships unregister \\\$clusterid --project=\$GCP_PROJECT --kubeconfig=\\\$KUBECONFIG --context=\\\$clusterid-admin@\\\$clusterid # to unregister clusters
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships unregister \$clusterid --project=$GCP_PROJECT --kubeconfig=\$KUBECONFIG --context=\$clusterid-admin@\$clusterid # to unregister clusters
EOF
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
bmctl reset --cluster \\\$clusterid --admin-kubeconfig /root/bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster-kubeconfig
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
bmctl reset --cluster \$clusterid --admin-kubeconfig /root/bmctl-workspace/$VM_PREFIX-admin-cluster/$VM_PREFIX-admin-cluster-kubeconfig

EOF
else
    export STEP="${STEP},6i"
    echo
    echo "1. Create baremetal user cluster" | pv -qL 100
    echo "2. Enable access to baremetal user cluster" | pv -qL 100
fi
echo
read -n 1 -s -r -p "$ "
;;

"7")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},7i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
export clusterid=\$VM_PREFIX-user-cluster
export KUBECONFIG=bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig
kubectl create clusterrolebinding cluster-admin --clusterrole=cluster-admin --user=\$(gcloud config get-value core/account) # to grant cluster admin role to user
curl -LO https://storage.googleapis.com/gke-release/asm/istio-\${SERVICEMESH_VERSION}-linux-amd64.tar.gz # to download the Anthos Service Mesh
tar xzf istio-\${SERVICEMESH_VERSION}-linux-amd64.tar.gz # to extract the contents of the file to file system
kubectl create namespace istio-system # to create a namespace called istio-system
apt-get update
apt-get -y install make
make -f /root/istio-\${SERVICEMESH_VERSION}/tools/certs/Makefile.selfsigned.mk root-ca # to generate a root certificate and key
make -f /root/istio-\${SERVICEMESH_VERSION}/tools/certs/Makefile.selfsigned.mk cluster1-cacerts # to generate an intermediate certificate and key
kubectl create secret generic cacerts -n istio-system --from-file=cluster1/ca-cert.pem --from-file=cluster1/ca-key.pem --from-file=cluster1/root-cert.pem --from-file=cluster1/cert-chain.pem # to create a secret cacerts
/root/istio-\${SERVICEMESH_VERSION}/bin/istioctl install --set profile=asm-multicloud -y # to install Anthos Service Mesh
echo && echo
kubectl wait --for=condition=available --timeout=600s deployment --all -n istio-system # to wait for deployment to finish
kubectl get pod -n istio-system # to check control plane Pods
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},7"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig
kubectl create clusterrolebinding cluster-admin --clusterrole=cluster-admin --user=\$(gcloud config get-value core/account) # to grant cluster admin role to user
curl -LO https://storage.googleapis.com/gke-release/asm/istio-${SERVICEMESH_VERSION}-linux-amd64.tar.gz # to download the Anthos Service Mesh
tar xzf istio-${SERVICEMESH_VERSION}-linux-amd64.tar.gz # to extract the contents of the file to file system
kubectl create namespace istio-system # to create a namespace called istio-system
apt-get update
apt-get -y install make
make -f /root/istio-${SERVICEMESH_VERSION}/tools/certs/Makefile.selfsigned.mk root-ca # to generate a root certificate and key
make -f /root/istio-${SERVICEMESH_VERSION}/tools/certs/Makefile.selfsigned.mk cluster1-cacerts # to generate an intermediate certificate and key
kubectl create secret generic cacerts -n istio-system --from-file=cluster1/ca-cert.pem --from-file=cluster1/ca-key.pem --from-file=cluster1/root-cert.pem --from-file=cluster1/cert-chain.pem # to create a secret cacerts
/root/istio-${SERVICEMESH_VERSION}/bin/istioctl install --set profile=asm-multicloud -y # to install Anthos Service Mesh
echo && echo
kubectl wait --for=condition=available --timeout=600s deployment --all -n istio-system # to wait for deployment to finish
kubectl get pod -n istio-system # to check control plane Pods
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl delete controlplanerevision -n istio-system 2> /dev/null
kubectl delete validatingwebhookconfiguration,mutatingwebhookconfiguration -l operator.istio.io/component=Pilot 2> /dev/null
/root/istio-${SERVICEMESH_VERSION}/bin/istioctl x uninstall --purge -y 2> /dev/null
kubectl delete namespace istio-system asm-system --ignore-not-found=true 2> /dev/null
kubectl create clusterrolebinding cluster-admin --clusterrole=cluster-admin --user=$(gcloud config get-value core/account)  2> /dev/null # to grant cluster admin role to user
curl -LO https://storage.googleapis.com/gke-release/asm/istio-${SERVICEMESH_VERSION}-linux-amd64.tar.gz # to download the Anthos Service Mesh
tar xzf istio-${SERVICEMESH_VERSION}-linux-amd64.tar.gz # to extract the contents of the file to file system
kubectl create namespace istio-system # to create a namespace called istio-system
apt-get update
apt-get -y install make
make -f /root/istio-${SERVICEMESH_VERSION}/tools/certs/Makefile.selfsigned.mk root-ca # to generate a root certificate and key
make -f /root/istio-${SERVICEMESH_VERSION}/tools/certs/Makefile.selfsigned.mk cluster1-cacerts # to generate an intermediate certificate and key
kubectl create secret generic cacerts -n istio-system --from-file=cluster1/ca-cert.pem --from-file=cluster1/ca-key.pem --from-file=cluster1/root-cert.pem --from-file=cluster1/cert-chain.pem 2> /dev/null # to create a secret cacerts
/root/istio-${SERVICEMESH_VERSION}/bin/istioctl install --set profile=asm-multicloud -y # to install Anthos Service Mesh
echo && echo
kubectl wait --for=condition=available --timeout=600s deployment --all -n istio-system # to wait for deployment to finish
kubectl get pod -n istio-system # to check control plane Pods
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},7x"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl delete controlplanerevision -n istio-system 2> /dev/null
kubectl delete validatingwebhookconfiguration,mutatingwebhookconfiguration -l operator.istio.io/component=Pilot 2> /dev/null
kubectl delete namespace istio-system asm-system --ignore-not-found=true 2> /dev/null
kubectl delete clusterrolebinding cluster-admin # to delete cluster admin role
kubectl delete namespace istio-system # to delete a namespace called istio-system
kubectl delete secret cacerts -n istio-system # to delete a secret cacerts
/root/istio-${SERVICEMESH_VERSION}/bin/istioctl x uninstall --purge -y 2> /dev/null
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl delete controlplanerevision -n istio-system 2> /dev/null
kubectl delete validatingwebhookconfiguration,mutatingwebhookconfiguration -l operator.istio.io/component=Pilot 2> /dev/null
kubectl delete namespace istio-system asm-system --ignore-not-found=true 2> /dev/null
kubectl delete clusterrolebinding cluster-admin # to delete cluster admin role
kubectl delete namespace istio-system # to delete a namespace called istio-system
kubectl delete secret cacerts -n istio-system # to delete a secret cacerts
/root/istio-${SERVICEMESH_VERSION}/bin/istioctl x uninstall --purge -y 2> /dev/null
EOF
else
    export STEP="${STEP},7i"
    echo
    echo "1. Grant cluster admin role" | pv -qL 100
    echo "2. Download the Anthos Service Mesh" | pv -qL 100
    echo "3. Generate a root certificate and key" | pv -qL 100
    echo "4. Generate an intermediate certificate and key" | pv -qL 100
    echo "5. Create a secret cacerts" | pv -qL 100
    echo "6. Install Anthos Service Mesh" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"8")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},8i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
export clusterid=\$VM_PREFIX-user-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl create namespace knative-serving # to create native-serving namespace
kubectl create secret -n knative-serving generic gcp-logging-secret --from-file=bmctl-workspace/.sa-keys/\${GCP_PROJECT}-anthos-baremetal-cloud-ops.json # to create secret for service account with monitoring.metricsWriter permissions
cat > bmctl-workspace/\\\$clusterid/cloudrunanthos.yaml << 'EOB'
 apiVersion: operator.run.cloud.google.com/v1alpha1
 kind: CloudRun
 metadata:
   name: cloud-run
 spec:
   metricscollector:
     stackdriver:
       projectid: \$GCP_PROJECT
       gcpzone: \$GCP_ZONE
       clustername: \$VM_PREFIX-user-cluster
       secretname: gcp-logging-secret
       secretkey: \$GCP_PROJECT-anthos-baremetal-cloud-ops.json
EOB
gcloud --project \$GCP_PROJECT container fleet cloudrun enable --project=\$GCP_PROJECT # to enable Cloud Run in Anthos fleet
gcloud --project \$GCP_PROJECT container fleet features list --project=\$GCP_PROJECT # to list enabled features
gcloud --project \$GCP_PROJECT container hub cloudrun apply --context \\\$clusterid-admin@\\\$clusterid --kubeconfig=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig --config=bmctl-workspace/\\\$clusterid/cloudrunanthos.yaml  # to install Cloud Run
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},8"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig
kubectl create namespace knative-serving # to create native-serving namespace
kubectl create secret -n knative-serving generic gcp-logging-secret --from-file=bmctl-workspace/.sa-keys/${GCP_PROJECT}-anthos-baremetal-cloud-ops.json # to create secret for service account with monitoring.metricsWriter permissions
cat > bmctl-workspace/\\\$clusterid/cloudrunanthos.yaml << 'EOB'
 apiVersion: operator.run.cloud.google.com/v1alpha1
 kind: CloudRun
 metadata:
   name: cloud-run
 spec:
   metricscollector:
     stackdriver:
       projectid: $GCP_PROJECT
       gcpzone: $GCP_ZONE
       clustername: $VM_PREFIX-user-cluster
       secretname: gcp-logging-secret
       secretkey: $GCP_PROJECT-anthos-baremetal-cloud-ops.json
EOB
gcloud --project $GCP_PROJECT container fleet cloudrun enable --project=$GCP_PROJECT # to enable Cloud Run in Anthos fleet
sleep 120
gcloud --project $GCP_PROJECT container fleet features list --project=$GCP_PROJECT # to list enabled features
gcloud --project $GCP_PROJECT container hub cloudrun apply --context \\\$clusterid-admin@\\\$clusterid --kubeconfig=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig --config=bmctl-workspace/\\\$clusterid/cloudrunanthos.yaml  # to install Cloud Run
EOF" | pv -qL 100
    gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=bmctl-workspace/\$clusterid/\$clusterid-kubeconfig
kubectl delete namespace knative-serving > /dev/null 2>&1
kubectl create namespace knative-serving # to create native-serving namespace
kubectl delete secret -n knative-serving gcp-logging-secret > /dev/null 2>&1
kubectl create secret -n knative-serving generic gcp-logging-secret --from-file=bmctl-workspace/.sa-keys/${GCP_PROJECT}-anthos-baremetal-cloud-ops.json
cat > bmctl-workspace/\$clusterid/cloudrunanthos.yaml << 'EOB'
 apiVersion: operator.run.cloud.google.com/v1alpha1
 kind: CloudRun
 metadata:
   name: cloud-run
 spec:
   metricscollector:
     stackdriver:
       projectid: $GCP_PROJECT
       gcpzone: $GCP_ZONE
       clustername: $VM_PREFIX-user-cluster
       secretname: gcp-logging-secret
       secretkey: $GCP_PROJECT-anthos-baremetal-cloud-ops.json
EOB
# gcloud alpha container hub cloudrun enable --project=$GCP_PROJECT # to enable Cloud Run in Anthos fleet
gcloud container fleet cloudrun enable --project=$GCP_PROJECT # to enable Cloud Run in Anthos fleet
sleep 120
gcloud container fleet features list --project=$GCP_PROJECT # to list enabled features
# kubectl apply --filename bmctl-workspace/\$clusterid/cloudrunanthos.yaml # to install Cloud Run
gcloud --project $GCP_PROJECT container hub cloudrun apply --context \$clusterid-admin@\$clusterid --kubeconfig=\$KUBECONFIG --config=bmctl-workspace/\$clusterid/cloudrunanthos.yaml  # to install Cloud Run
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},8x"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig
gcloud container fleet cloudrun disable --project=$GCP_PROJECT # to enable Cloud Run in Anthos fleet
kubectl delete secret -n knative-serving gcp-logging-secret 
kubectl delete namespace knative-serving 
EOF" | pv -qL 100
    gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=bmctl-workspace/\$clusterid/\$clusterid-kubeconfig
gcloud container fleet cloudrun disable --project=$GCP_PROJECT # to enable Cloud Run in Anthos fleet
kubectl delete secret -n knative-serving gcp-logging-secret 
kubectl delete namespace knative-serving 
EOF
else
    export STEP="${STEP},8i"
    echo
    echo "1. Create namespace" | pv -qL 100
    echo "2. Create Kubernetes secret" | pv -qL 100
    echo "3. Create Cloud Run operator" | pv -qL 100
    echo "4. Enable Cloud Run in Anthos fleet" | pv -qL 100
    echo "5. Install Cloud Run" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"9")
start=`date +%s`
gcloud --project $GCP_PROJECT container clusters get-credentials $GCP_CLUSTER --zone $GCP_ZONE > /dev/null 2>&1 
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},9i"        
    echo
    echo "$ gcloud --project \$GCP_PROJECT projects add-iam-policy-binding \$GCP_PROJECT --member=\"serviceAccount:\$GCP_PROJECT@\$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/viewer\" # to add-iam-policy-binding for image pull service account" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
kubectl create secret docker-registry gcrimagepull --docker-server=gcr.io --docker-username=_json_key --docker-password=\"\\\$(cat ~/installer.json)\" --docker-email=\$EMAIL # to create docker registry secret
kubectl patch serviceaccount default -p '{\"imagePullSecrets\": [{\"name\": \"gcrimagepull\"}]}' # to patch the default k8s service account with docker-registry image pull secret
gcloud --project \$GCP_PROJECT run deploy hello-app --platform kubernetes --image gcr.io/google-samples/hello-app:1.0 # to deploy appication
kubectl port-forward --namespace istio-system service/knative-local-gateway 8080:80 & # to setup a tunnel to the admin workstation
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},9"        
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"serviceAccount:$GCP_PROJECT@$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/viewer\" # to add-iam-policy-binding for image pull service account" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="serviceAccount:$GCP_PROJECT@$GCP_PROJECT.iam.gserviceaccount.com" --role="roles/viewer"
    echo
    echo "$ export EMAIL=\$(gcloud config get-value core/account) # to set email"| pv -qL 100
    export EMAIL=$(gcloud config get-value core/account)
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment 
kubectl create secret docker-registry gcrimagepull --docker-server=gcr.io --docker-username=_json_key --docker-password=\"\\\$(cat ~/installer.json)\" --docker-email=$EMAIL # to create docker registry secret
kubectl patch serviceaccount default -p '{\"imagePullSecrets\": [{\"name\": \"gcrimagepull\"}]}' # to patch the default k8s service account with docker-registry image pull secret
sleep 10
gcloud --project $GCP_PROJECT run deploy hello-app --platform kubernetes --image gcr.io/google-samples/hello-app:1.0 # to deploy appication
sleep 5
kubectl port-forward --namespace istio-system service/knative-local-gateway 8080:80 & # to setup a tunnel to the admin workstation
sleep 15
ps -elf | grep 8080
echo
curl --max-time 5 -H \"Host: hello-app.default.svc.cluster.local\" http://localhost:8080/ # to invoke the service
EOF" | pv -qL 100
    gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment KUBECONFIG environment variable
kubectl delete secret gcrimagepull > /dev/null 2>&1
kubectl create secret docker-registry gcrimagepull --docker-server=gcr.io --docker-username=_json_key --docker-password="\$(cat ~/installer.json)" --docker-email=$EMAIL # to create docker registry secret
kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "gcrimagepull"}]}' # to patch the default k8s service account with docker-registry image pull secret
sleep 10
gcloud --project $GCP_PROJECT run deploy hello-app --platform kubernetes --image gcr.io/google-samples/hello-app:1.0 # to deploy appication
sleep 5
kubectl port-forward --namespace istio-system service/knative-local-gateway 8080:80 & # to setup a tunnel to the admin workstation
sleep 15
ps -elf | grep 8080
echo
curl --max-time 5 -H "Host: hello-app.default.svc.cluster.local" http://localhost:8080/ # to invoke the service
echo
echo "*** Enter CTRL C to exit ***"
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},9x"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment KUBECONFIG environment variable
kubectl delete secret gcrimagepull
gcloud --project $GCP_PROJECT beta run services delete hello-app --platform kubernetes --kubeconfig \\\$KUBECONFIG --context=\\\$clusterid-admin@\\\$clusterid --quiet # to delete services
EOF" | pv -qL 100
    gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl delete secret gcrimagepull
gcloud --project $GCP_PROJECT beta run services delete hello-app --platform kubernetes --kubeconfig \$KUBECONFIG --context=\$clusterid-admin@\$clusterid --quiet
EOF
else
    export STEP="${STEP},9i"        
    echo
    echo "1. Add IAM policy binding for image pull service account" | pv -qL 100
    echo "2. Create docker registry secret" | pv -qL 100
    echo "3. Patch default k8s service account with docker-registry image pull secret" | pv -qL 100
    echo "4. Setup a tunnel to the admin workstation" | pv -qL 100
    echo "5. Invoke the service" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"10")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},10i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
kubectl create deployment hello-app --image=gcr.io/google-samples/hello-app:2.0
kubectl expose deployment hello-app --name hello-app-service --type LoadBalancer --port 80 --target-port=8080
kubectl create deployment hello-kubernetes --image=gcr.io/google-samples/node-hello:1.0
kubectl expose deployment hello-kubernetes --name hello-kubernetes-service --type NodePort --port 32123 --target-port=8080
cat <<EOB > nginx-l7.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-l7
spec:
  rules:
  - http:
      paths:
      - path: /greet-the-world
        pathType: Exact
        backend:
          service:
            name: hello-app-service
            port:
              number: 80
      - path: /greet-kubernetes
        pathType: Exact
        backend:
          service:
            name: hello-kubernetes-service
            port:
              number: 32123
EOB
kubectl apply -f nginx-l7.yaml
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \GCP_PROJECT iam service-accounts create gce-pd-csi-sa  # to create service account"
    echo
    echo "$ gcloud --project \$GCP_PROJECT projects add-iam-policy-binding \$GCP_PROJECT --member=\"serviceAccount:gce-pd-csi-sa@\$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/compute.storageAdmin\" # to add-iam-policy-binding for image pull service account" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT projects add-iam-policy-binding \$GCP_PROJECT --member=\"serviceAccount:gce-pd-csi-sa@\$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/iam.serviceAccountUser\" # to add-iam-policy-binding for image pull service account" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
kubectl get csinodes -o jsonpath='{range .items[*]}{.metadata.name} {.spec.drivers} {\\\"\\n\"}{end}'
git clone https://github.com/kubernetes-sigs/gcp-compute-persistent-disk-csi-driver \$GOPATH/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver -b release-1.3
gcloud auth activate-service-account --key-file ~/installer.json
gcloud iam roles create gcp_compute_persistent_disk_csi_driver_custom_role --quiet --project \"\\\$PROJECT\" --file \"\\\$GOPATH/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver/deploy/gcp-compute-persistent-disk-csi-driver-custom-role.yaml\"gcloud iam service-accounts keys create \\\$GCE_PD_SA_DIR/cloud-sa.json --iam-account=\\\$GCE_PD_SA_NAME@\\\$PROJECT.iam.gserviceaccount.com
gcloud iam service-accounts keys create \$GCE_PD_SA_DIR/cloud-sa.json --iam-account=\$GCE_PD_SA_NAME@\$PROJECT.iam.gserviceaccount.com
/root/baremetal/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver/deploy/setup-project.sh 2>/dev/null 
/root/baremetal/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver/deploy/kubernetes/deploy-driver.sh
kubectl get csinodes -o jsonpath='{range .items[*]} {.metadata.name}{\": \"} {range .spec.drivers[*]} {.name}{\"\\n\"} {end}{end}'
cat <<EOB | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gce-pd
  annotations:
    storageclass.kubernetes.io/is-default-class: \"true\"
provisioner: pd.csi.storage.gke.io # CSI driver
parameters: # You provide vendor-specific parameters to this specification
  type: pd-standard # Be sure to follow the vendor's instructions, in our case pd-ssd, pd-standard, or pd-balanced
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOB
echo
cat <<EOB | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: podpvc
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: gce-pd
  resources:
    requests:
      storage: 6Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: web-server
spec:
  containers:
   - name: web-server
     image: nginx
     volumeMounts:
       - mountPath: /var/lib/www/html
         name: mypvc
  volumes:
   - name: mypvc
     persistentVolumeClaim:
       claimName: podpvc
       readOnly: false
EOB
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},10"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl create deployment hello-app --image=gcr.io/google-samples/hello-app:2.0
kubectl expose deployment hello-app --name hello-app-service --type LoadBalancer --port 80 --target-port=8080
echo
sleep 15
curl 10.200.0.101
kubectl create deployment hello-kubernetes --image=gcr.io/google-samples/node-hello:1.0
kubectl expose deployment hello-kubernetes --name hello-kubernetes-service --type NodePort --port 32123 --target-port=8080
cat <<EOB > nginx-l7.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-l7
spec:
  rules:
  - http:
      paths:
      - path: /greet-the-world
        pathType: Exact
        backend:
          service:
            name: hello-app-service
            port:
              number: 80
      - path: /greet-kubernetes
        pathType: Exact
        backend:
          service:
            name: hello-kubernetes-service
            port:
              number: 32123
EOB
kubectl apply -f nginx-l7.yaml
sleep 15
curl 10.200.0.100/greet-the-world
curl 10.200.0.100/greet-kubernetes
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl delete deployment hello-app 2>/dev/null
kubectl create deployment hello-app --image=gcr.io/google-samples/hello-app:2.0
kubectl delete service hello-app-service 2>/dev/null
kubectl expose deployment hello-app --name hello-app-service --type LoadBalancer --port 80 --target-port=8080
sleep 15
echo
echo "Invoking command \"curl 10.200.0.102\""
curl 10.200.0.102
echo
kubectl delete deployment hello-kubernetes > /dev/null 2>&1
kubectl create deployment hello-kubernetes --image=gcr.io/google-samples/node-hello:1.0
kubectl delete service hello-kubernetes-service > /dev/null 2>&1
kubectl expose deployment hello-kubernetes --name hello-kubernetes-service --type NodePort --port 32123 --target-port=8080
cat <<EOB > nginx-l7.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-l7
spec:
  rules:
  - http:
      paths:
      - path: /greet-the-world
        pathType: Exact
        backend:
          service:
            name: hello-app-service
            port:
              number: 80
      - path: /greet-kubernetes
        pathType: Exact
        backend:
          service:
            name: hello-kubernetes-service
            port:
              number: 32123
EOB
kubectl apply -f nginx-l7.yaml
sleep 15
echo
echo "Invoking command \"curl 10.200.0.100/greet-the-world\""
curl 10.200.0.100/greet-the-world
echo
echo "Invoking command \"curl 10.200.0.100/greet-kubernetes\""
curl 10.200.0.100/greet-kubernetes
echo
EOF
    echo
    echo "$ sleep 5 # to wait"
    sleep 5
    echo
    export GCE_PD_SA_NAME=gce-pd-csi-sa
    gcloud --project $GCP_PROJECT iam service-accounts delete $GCE_PD_SA_NAME@$GCP_PROJECT.iam.gserviceaccount.com --quiet 2>/dev/null
    echo "$ gcloud --project $GCP_PROJECT iam service-accounts create gce-pd-csi-sa  # to create service account"
    gcloud --project $GCP_PROJECT iam service-accounts create gce-pd-csi-sa 2>/dev/null
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"serviceAccount:gce-pd-csi-sa@$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/compute.storageAdmin\" # to add-iam-policy-binding for image pull service account" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="serviceAccount:gce-pd-csi-sa@$GCP_PROJECT.iam.gserviceaccount.com" --role="roles/compute.storageAdmin"
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"serviceAccount:gce-pd-csi-sa@$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/iam.serviceAccountUser\" # to add-iam-policy-binding for image pull service account" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="serviceAccount:gce-pd-csi-sa@$GCP_PROJECT.iam.gserviceaccount.com" --role="roles/iam.serviceAccountUser"
    echo
    echo "$ sleep 10 # to wait"
    sleep 10
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
export GOPATH=~/baremetal
export GCE_PD_SA_NAME=gce-pd-csi-sa
export ENABLE_KMS=false
export CREATE_SA=false
export PROJECT=$(gcloud config get-value project)
kubectl get csinodes -o jsonpath='{range .items[*]}{.metadata.name} {.spec.drivers} {\\\"\\n\"}{end}'
git clone https://github.com/kubernetes-sigs/gcp-compute-persistent-disk-csi-driver \$GOPATH/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver -b release-1.3
export GCE_PD_SA_DIR=~/baremetal
export GCE_PD_DRIVER_VERSION=stable
rm -rf \$GCE_PD_SA_DIR/cloud-sa.json
gcloud auth activate-service-account --key-file ~/installer.json
gcloud iam roles create gcp_compute_persistent_disk_csi_driver_custom_role --quiet --project \"\\\$PROJECT\" --file \"\\\$GOPATH/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver/deploy/gcp-compute-persistent-disk-csi-driver-custom-role.yaml\"gcloud iam service-accounts keys create \\\$GCE_PD_SA_DIR/cloud-sa.json --iam-account=\\\$GCE_PD_SA_NAME@\\\$PROJECT.iam.gserviceaccount.com
gcloud iam service-accounts keys create \$GCE_PD_SA_DIR/cloud-sa.json --iam-account=\$GCE_PD_SA_NAME@\$PROJECT.iam.gserviceaccount.com
/root/baremetal/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver/deploy/setup-project.sh 2>/dev/null 
/root/baremetal/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver/deploy/kubernetes/deploy-driver.sh
kubectl get csinodes -o jsonpath='{range .items[*]} {.metadata.name}{\": \"} {range .spec.drivers[*]} {.name}{\"\\n\"} {end}{end}'
cat <<EOB | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gce-pd
  annotations:
    storageclass.kubernetes.io/is-default-class: \"true\"
provisioner: pd.csi.storage.gke.io # CSI driver
parameters: # You provide vendor-specific parameters to this specification
  type: pd-standard # Be sure to follow the vendor's instructions, in our case pd-ssd, pd-standard, or pd-balanced
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOB
echo
cat <<EOB | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: podpvc
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: gce-pd
  resources:
    requests:
      storage: 6Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: web-server
spec:
  containers:
   - name: web-server
     image: nginx
     volumeMounts:
       - mountPath: /var/lib/www/html
         name: mypvc
  volumes:
   - name: mypvc
     persistentVolumeClaim:
       claimName: podpvc
       readOnly: false
EOB
EOF" | pv -qL 100
    echo
    gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
export GOPATH=~/baremetal
export GCE_PD_SA_NAME=gce-pd-csi-sa
export ENABLE_KMS=false
export CREATE_SA=false
export PROJECT=$(gcloud config get-value project)
kubectl get csinodes -o jsonpath='{range .items[*]}{.metadata.name} {.spec.drivers} {"\n"}{end}'
rm -rf \$GOPATH/src
sleep 5
git clone https://github.com/kubernetes-sigs/gcp-compute-persistent-disk-csi-driver \$GOPATH/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver -b release-1.3
export GCE_PD_SA_DIR=~/baremetal
export GCE_PD_DRIVER_VERSION=stable
gcloud auth activate-service-account --key-file ~/installer.json
gcloud iam roles create gcp_compute_persistent_disk_csi_driver_custom_role --quiet --project "\$PROJECT" --file "\$GOPATH/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver/deploy/gcp-compute-persistent-disk-csi-driver-custom-role.yaml"
gcloud iam service-accounts keys create \$GCE_PD_SA_DIR/cloud-sa.json --iam-account=\$GCE_PD_SA_NAME@\$PROJECT.iam.gserviceaccount.com
\$GOPATH/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver/deploy/setup-project.sh 2>/dev/null 
echo # this line is needed to overcome a bug. First character missing from next command otherwise.
\$GOPATH/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver/deploy/kubernetes/deploy-driver.sh
kubectl get csinodes -o jsonpath='{range .items[*]} {.metadata.name}{": "} {range .spec.drivers[*]} {.name}{"\n"} {end}{end}'
kubectl delete StorageClass gce-pd > /dev/null 2>&1
cat <<EOB | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gce-pd
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: pd.csi.storage.gke.io # CSI driver
parameters: # You provide vendor-specific parameters to this specification
  type: pd-standard # Be sure to follow the vendor's instructions, in our case pd-ssd, pd-standard, or pd-balanced
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOB
kubectl delete Pod web-server > /dev/null 2>&1
cat <<EOB | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: podpvc
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: gce-pd
  resources:
    requests:
      storage: 6Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: web-server
spec:
  containers:
   - name: web-server
     image: nginx
     volumeMounts:
       - mountPath: /var/lib/www/html
         name: mypvc
  volumes:
   - name: mypvc
     persistentVolumeClaim:
       claimName: podpvc
       readOnly: false
EOB
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},10x"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl delete pod web-server
kubectl delete pvc podpvc
kubectl delete StorageClass gce-pd
kubectl delete Ingress nginx-l7
kubectl delete deployment hello-kubernetes
kubectl delete service hello-kubernetes-service
kubectl delete deployment hello-app
kubectl delete service hello-app-service
EOF" | pv -qL 100
    gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig
kubectl delete pod web-server
kubectl delete pvc podpvc
kubectl delete StorageClass gce-pd
kubectl delete Ingress nginx-l7
kubectl delete deployment hello-kubernetes
kubectl delete service hello-kubernetes-service
kubectl delete deployment hello-app
kubectl delete service hello-app-service
EOF
else
    export STEP="${STEP},10i"
    echo
    echo "1. Deploy stateless application to Kubernetes" | pv -qL 100
    echo "2. Install and configure CSI driver" | pv -qL 100
    echo "3. Deploy stateful application to Kubernetes" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"11")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},11i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
kubectl describe node \$VM_PREFIX-user-w1
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
cat <<EOB | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: node-problem-detector-config
  namespace: cluster-\\\$clusterid
data:
  enabled: \"true\"
EOB
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
kubectl describe node \$VM_PREFIX-user-w1
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_U_W1 --zone \$GCP_ZONE --tunnel-through-iap << EOF
sudo systemctl stop containerd
journalctl -u node-problem-detector
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
kubectl describe node \$VM_PREFIX-user-w1
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_U_W1 --zone \$GCP_ZONE --tunnel-through-iap << EOF
sudo systemctl start containerd
journalctl -u node-problem-detector
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
kubectl describe node \$VM_PREFIX-user-w1
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
cat bmctl-workspace/\$VM_PREFIX-user-cluster/\$VM_PREFIX-user-cluster.yaml | grep disableCloudAuditLogging: # to review settings to disable  audit logs collection
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
cat bmctl-workspace/\$VM_PREFIX-user-cluster/\$VM_PREFIX-user-cluster.yaml | grep enableApplication: # to review settings to collect metrics and logs from applications
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
gcloud auth activate-service-account --key-file ~/installer.json # to authenticate gcloud
echo \"gcloud logging read 'logName=\"projects/\$GCP_PROJECT/logs/externalaudit.googleapis.com%2Factivity\"
AND resource.type=\"k8s_cluster\"
AND protoPayload.serviceName=\"anthosgke.googleapis.com\"' --limit 2 --freshness 300d\" > get_audit_logs.sh
sh get_audit_logs.sh # to access audit logs
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
gcloud auth activate-service-account --key-file ~/installer.json # to authenticate gcloud
echo \"gcloud logging read 'resource.type=\"k8s_container\"
AND resource.labels.namespace_name=\"default\"
AND resource.labels.container_name=\"hello-app\"' --limit 2 --freshness 300d\" > get_app_logs.sh
sh get_app_logs.sh # to access application logs
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone \$GCP_ZONE --tunnel-through-iap << EOF
gcloud auth activate-service-account --key-file ~/installer.json # to authenticate gcloud
echo \"gcloud logging read 'resource.type=\"k8s_node\"
AND resource.labels.node_name=\"\$VM_PREFIX-user-w1\"
AND log_name=\"projects/\$GCP_PROJECT/logs/node-problem-detector\"' --limit 2 --freshness 300d\" > get_node_problem_detector_logs.sh
sh get_node_problem_detector_logs.sh # to access application logs
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},11"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl describe node $VM_PREFIX-user-w1
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
echo
kubectl describe node $VM_PREFIX-user-w1
EOF
    echo
    echo "$ sleep 10 # to wait"
    sleep 10
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-admin-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
cat <<EOB | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: node-problem-detector-config
  namespace: cluster-\\\$clusterid
data:
  enabled: \"true\"
EOB
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-admin-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
cat <<EOB | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: node-problem-detector-config
  namespace: cluster-\$clusterid
data:
  enabled: "true"
EOB
EOF
    echo
    echo "$ sleep 5 # to wait"
    sleep 5
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl describe node $VM_PREFIX-user-w1
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
echo
kubectl describe node $VM_PREFIX-user-w1
EOF
    echo
    echo "$ sleep 15 # to wait"
    sleep 15
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_U_W1 --zone $GCP_ZONE --tunnel-through-iap << EOF
sudo systemctl stop containerd
journalctl -u node-problem-detector
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_U_W1 --zone $GCP_ZONE --tunnel-through-iap << EOF
sudo systemctl stop containerd
journalctl -u node-problem-detector
EOF
    echo
    echo "$ sleep 5 # to wait"
    sleep 5
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl describe node $VM_PREFIX-user-w1
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
echo
kubectl describe node $VM_PREFIX-user-w1
EOF
    echo
    echo "$ sleep 15 # to wait"
    sleep 15
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_U_W1 --zone $GCP_ZONE --tunnel-through-iap << EOF
sudo systemctl start containerd
journalctl -u node-problem-detector
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_U_W1 --zone $GCP_ZONE --tunnel-through-iap << EOF
sudo systemctl start containerd
journalctl -u node-problem-detector
EOF
    echo
    echo "$ sleep 5 # to wait"
    sleep 5
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
echo
kubectl describe node $VM_PREFIX-user-w1
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
echo
kubectl describe node $VM_PREFIX-user-w1
EOF
    echo
    echo "$ sleep 10 # to wait"
    sleep 10
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
cat bmctl-workspace/$VM_PREFIX-user-cluster/$VM_PREFIX-user-cluster.yaml | grep disableCloudAuditLogging: # to review settings to disable  audit logs collection
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
echo
cat bmctl-workspace/$VM_PREFIX-user-cluster/$VM_PREFIX-user-cluster.yaml | grep disableCloudAuditLogging: # to review settings to disable audit logs collection
EOF
    echo
    echo "$ sleep 5 # to wait"
    sleep 5
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
cat bmctl-workspace/$VM_PREFIX-user-cluster/$VM_PREFIX-user-cluster.yaml | grep enableApplication: # to review settings to collect metrics and logs from applications
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
cat bmctl-workspace/$VM_PREFIX-user-cluster/$VM_PREFIX-user-cluster.yaml | grep enableApplication: # to review settings to collect metrics and logs from applications
EOF
    echo
    echo "$ sleep 5 # to wait"
    sleep 5
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
gcloud auth activate-service-account --key-file ~/installer.json # to authenticate gcloud
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
echo
echo \"gcloud logging read 'logName=\"projects/\$GCP_PROJECT/logs/externalaudit.googleapis.com%2Factivity\"
AND resource.type=\"k8s_cluster\"
AND protoPayload.serviceName=\"anthosgke.googleapis.com\"' --limit 2 --freshness 300d\" > get_audit_logs.sh
sh get_audit_logs.sh # to access audit logs
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
gcloud auth activate-service-account --key-file ~/installer.json
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
echo
echo "gcloud logging read 'logName="projects/$GCP_PROJECT/logs/externalaudit.googleapis.com%2Factivity"
AND resource.type="k8s_cluster"
AND protoPayload.serviceName="anthosgke.googleapis.com"' --limit 2 --freshness 300d" > get_audit_logs.sh
sh get_audit_logs.sh # to access audit logs
EOF
    echo
    echo "$ sleep 15 # to wait"
    sleep 15
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
gcloud auth activate-service-account --key-file ~/installer.json # to authenticate gcloud
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
echo
echo \"gcloud logging read 'resource.type=\"k8s_container\"
AND resource.labels.namespace_name=\"default\"
AND resource.labels.container_name=\"hello-app\"' --limit 2 --freshness 300d\" > get_app_logs.sh
sh get_app_logs.sh # to access application logs
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
gcloud auth activate-service-account --key-file ~/installer.json
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
echo
echo "gcloud logging read 'resource.type="k8s_container"
AND resource.labels.namespace_name="default"
AND resource.labels.container_name="hello-app"' --limit 2 --freshness 300d" > get_app_logs.sh
sh get_app_logs.sh # to access application logs
EOF
    echo
    echo "$ sleep 15 # to wait"
    sleep 15
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
gcloud auth activate-service-account --key-file ~/installer.json # to authenticate gcloud
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
echo
echo \"gcloud logging read 'resource.type=\"k8s_node\"
AND resource.labels.node_name=\"$VM_PREFIX-user-w1\"
AND log_name=\"projects/\$GCP_PROJECT/logs/node-problem-detector\"' --limit 2 --freshness 300d\" > get_node_problem_detector_logs.sh
sh get_node_problem_detector_logs.sh # to access application logs
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=$VM_PREFIX-user-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
gcloud auth activate-service-account --key-file ~/installer.json
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
echo
echo "gcloud logging read 'resource.type="k8s_node"
AND resource.labels.node_name="$VM_PREFIX-user-w1"
AND log_name="projects/$GCP_PROJECT/logs/node-problem-detector"' --limit 2 --freshness 300d" > get_node_problem_detector_logs.sh
sh get_node_problem_detector_logs.sh # to access application logs
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},11x"
    echo
    echo "*** Nothing to delete ***" | pv -qL 100
else
    export STEP="${STEP},11i"
    echo
    echo "1. Explore node troubleshooting" | pv -qL 100
    echo "2. Explore application troubleshooting" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"R")
echo
echo "
  __                      __                              __                               
 /|            /         /              / /              /                 | /             
( |  ___  ___ (___      (___  ___        (___           (___  ___  ___  ___|(___  ___      
  | |___)|    |   )     |    |   )|   )| |    \   )         )|   )|   )|   )|   )|   )(_/_ 
  | |__  |__  |  /      |__  |__/||__/ | |__   \_/       __/ |__/||  / |__/ |__/ |__/  / / 
                                 |              /                                          
"
echo "
We are a group of information technology professionals committed to driving cloud 
adoption. We create cloud skills development assets during our client consulting 
engagements, and use these assets to build cloud skills independently or in partnership 
with training organizations.
 
You can access more resources from our iOS and Android mobile applications.

iOS App: https://apps.apple.com/us/app/tech-equity/id1627029775
Android App: https://play.google.com/store/apps/details?id=com.techequity.app

Email:support@techequity.cloud 
Web: https://techequity.cloud

Ⓒ Tech Equity 2022" | pv -qL 100
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"G")
cloudshell launch-tutorial $SCRIPTPATH/.tutorial.md
;;

"Q")
echo
exit
;;
"q")
echo
exit
;;
* )
echo
echo "Option not available"
;;
esac
sleep 1
done
