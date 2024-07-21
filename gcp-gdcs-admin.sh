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
####### Migrate VMWare virtual machine using Migrate to Virtual Machines ########
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
export VMM_REGION="us-west2"
export VMM_ZONE="us-west2-a"
export VMM_NETWORK="migrate-training"
export VMM_SUBNET="migrate-training"
export VMM_COURSE_ID="mtb" 
export VCENTER_USER="administrator@psolab.local"
export VCENTER_PASSWORD="ps0Lab!admin"
export VCENTER_IP="172.16.10.2"
export VCENTER_MFCE_USER="MFCE@psolab.local"
export VCENTER_MFCE_PASSWORD="ps0Lab!admin"
export ESXI_USER_NAME="labUser"
export ESXI_USER_PASSWORD="ps0lab!"
EOF
source $PROJDIR/.env
fi

# Display menu options
while :
do
clear
cat<<EOF
============================================================================
Menu for VM Migration Lab for ${VMM_COURSE_ID} Class
----------------------------------------------------------------------------
Please enter number to select your choice:
 (1) Access Bastion Host
 (2) Enable API and Create Firewall Rules
 (3) Install Migrate to Virtual Machines Backend
 (4) Install MFCE Backend
 (5) Configure and Perform Migration
 (G) Launch step by step guide
 (Q) Quit
----------------------------------------------------------------------------
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
        echo
        echo "*** Enter STUDENT ID ***"
        unset VMM_STUDENT_ID
        while [ -z ${VMM_STUDENT_ID} ]; do
            read VMM_STUDENT_ID
        done
        echo
        echo "*** Enter student username ***"
        unset VMM_STUDENT_USERNAME
        while [ -z ${VMM_STUDENT_USERNAME} ]; do
            read VMM_STUDENT_USERNAME
        done
        echo
        echo "*** Enter student password ***"
        unset VMM_STUDENT_PASSWORD
        while [ -z ${VMM_STUDENT_PASSWORD} ]; do
            read VMM_STUDENT_PASSWORD
        done
        cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT
export VMM_REGION="us-west2"
export VMM_ZONE="us-west2-a"
export VMM_NETWORK="migrate-training"
export VMM_SUBNET="migrate-training"
export VMM_COURSE_ID="mtb"
export VCENTER_USER="administrator@psolab.local"
export VCENTER_PASSWORD="ps0Lab!admin"
export VCENTER_IP="172.16.10.2"
export VCENTER_MFCE_USER="MFCE@psolab.local"
export VCENTER_MFCE_PASSWORD="ps0Lab!admin"
export ESXI_USER_NAME="labUser"
export ESXI_USER_PASSWORD="ps0lab!"
EOF
        source $PROJDIR/.env
        gsutil cp $PROJDIR/.env gs://${GCP_PROJECT}/$SCRIPTNAME.env > /dev/null 2>&1
        echo
        echo "*** Google Cloud project is $GCP_PROJECT ***" | pv -qL 100
        echo "*** Google Cloud VMM region is $VMM_REGION ***" | pv -qL 100
        echo "*** Google Cloud VMM zone is $VMM_ZONE ***" | pv -qL 100
        echo "*** Google Cloud VMM network is $VMM_NETWORK ***" | pv -qL 100
        echo "*** Google Cloud VMM subnet is $VMM_SUBNET ***" | pv -qL 100
        echo "*** Google Cloud VMM course ID is $VMM_COURSE_ID ***" | pv -qL 100
        echo "*** Google Cloud vCenter user is $VCENTER_USER ***" | pv -qL 100
        echo "*** Google Cloud vCenter password is $VCENTER_PASSWORD ***" | pv -qL 100
        echo "*** Google Cloud vCenter IP is $VCENTER_IP ***" | pv -qL 100
        echo "*** Google Cloud vCenter MFCE user is $VCENTER_MFCE_USER ***" | pv -qL 100
        echo "*** Google Cloud vCenter MFCE password is $VCENTER_MFCE_PASSWORD ***" | pv -qL 100
        echo "*** Google Cloud ESXI user is $ESXI_USER_NAME ***" | pv -qL 100
        echo "*** Google Cloud ESXI password is $ESXI_USER_PASSWORD ***" | pv -qL 100
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
                    echo "*** Authenticating using service account key $PROJDIR/.${GCP_PROJECT}.json ***"
                    echo "*** To use a different GCP project, delete the service account key ***"
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
                echo
                echo "*** Enter STUDENT ID ***"
                unset VMM_STUDENT_ID
                while [ -z ${VMM_STUDENT_ID} ]; do
                    read VMM_STUDENT_ID
                done
                echo
                echo "*** Enter student username ***"
                unset VMM_STUDENT_USERNAME
                while [ -z ${VMM_STUDENT_USERNAME} ]; do
                    read VMM_STUDENT_USERNAME
                done
                echo
                echo "*** Enter student password ***"
                unset VMM_STUDENT_PASSWORD
                while [ -z ${VMM_STUDENT_PASSWORD} ]; do
                    read VMM_STUDENT_PASSWORD
                done
                cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT
export VMM_REGION="us-west2"
export VMM_ZONE="us-west2-a"
export VMM_NETWORK="migrate-training"
export VMM_SUBNET="migrate-training"
export VMM_COURSE_ID="mtb"
export VCENTER_USER="administrator@psolab.local"
export VCENTER_PASSWORD="ps0Lab!admin"
export VCENTER_IP="172.16.10.2"
export VCENTER_MFCE_USER="MFCE@psolab.local"
export VCENTER_MFCE_PASSWORD="ps0Lab!admin"
export ESXI_USER_NAME="labUser"
export ESXI_USER_PASSWORD="ps0lab!"
EOF
                source $PROJDIR/.env
                gsutil cp $PROJDIR/.env gs://${GCP_PROJECT}/$SCRIPTNAME.env > /dev/null 2>&1
                echo
                echo "*** Google Cloud project is $GCP_PROJECT ***" | pv -qL 100
                echo "*** Google Cloud VMM region is $VMM_REGION ***" | pv -qL 100
                echo "*** Google Cloud VMM zone is $VMM_ZONE ***" | pv -qL 100
                echo "*** Google Cloud VMM network is $VMM_NETWORK ***" | pv -qL 100
                echo "*** Google Cloud VMM subnet is $VMM_SUBNET ***" | pv -qL 100
                echo "*** Google Cloud VMM course ID is $VMM_COURSE_ID ***" | pv -qL 100
                echo "*** Google Cloud vCenter user is $VCENTER_USER ***" | pv -qL 100
                echo "*** Google Cloud vCenter password is $VCENTER_PASSWORD ***" | pv -qL 100
                echo "*** Google Cloud vCenter IP is $VCENTER_IP ***" | pv -qL 100
                echo "*** Google Cloud vCenter MFCE user is $VCENTER_MFCE_USER ***" | pv -qL 100
                echo "*** Google Cloud vCenter MFCE password is $VCENTER_MFCE_PASSWORD ***" | pv -qL 100
                echo "*** Google Cloud ESXI user is $ESXI_USER_NAME ***" | pv -qL 100
                echo "*** Google Cloud ESXI password is $ESXI_USER_PASSWORD ***" | pv -qL 100
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
    echo "*** Access Bastion Host ***" | pv -qL 100
    echo
    echo "1) Navigate to https://netservices-\${VMM_COURSE_ID}1\${VMM_STUDENT_ID}.atbs.cso.joonix.net" | pv -qL 100
    echo "2) Sign-in with username \"\$VMM_STUDENT_USERNAME\" and password \"\$VMM_STUDENT_PASSWORD\"" | pv -qL 100
    echo
    echo "3) Launch Google Chrome browser from the desktop icon" | pv -qL 100
    echo "4) Navigate to https://console.cloud.google.com/" | pv -qL 100
    echo "5) Sign-in with username \"\$VMM_STUDENT_USERNAME@cso.joonix.net\" and password \"\$VMM_STUDENT_PASSWORD\"" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},1"
    echo
    echo "*** Access Bastion Host ***" | pv -qL 100
    echo
    echo "1) Navigate to https://netservices-${VMM_COURSE_ID}1${VMM_STUDENT_ID}.atbs.cso.joonix.net" | pv -qL 100
    echo "2) Sign-in with username \"$VMM_STUDENT_USERNAME\" and password \"$VMM_STUDENT_PASSWORD\"" | pv -qL 100
    echo
    echo "3) Launch Google Chrome browser from the desktop icon" | pv -qL 100
    echo "4) Navigate to https://console.cloud.google.com/" | pv -qL 100
    echo "5) Sign-in with username \"$VMM_STUDENT_USERNAME@cso.joonix.net\" and password \"$VMM_STUDENT_PASSWORD\"" | pv -qL 100
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},1x"
    echo
    echo "*** Not implemented ***"
else
    export STEP="${STEP},1i"
    echo
    echo "1. Access Bastion Host" | pv -qL 100
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
    echo "*** Explore Networking ***" | pv -qL 100
    echo
    echo "1) Login at https://console.cloud.google.com/ using your Qwiklabs credentials" | pv -qL 100
    echo "2) Select Compute Engine > Migrate to Virtual Machines" | pv -qL 100
    echo "   Enable VM Migration API if prompted" | pv -qL 100
    echo
    echo "*** Run the commands below ***" | pv -qL 100
    echo
    echo "$ gcloud --project migrate-training-\${VMM_STUDENT_ID}-1234 services enable vmmigration.googleapis.com cloudresourcemanager.googleapis.com # to enable API" | pv -qL 100
    echo "$ gcloud --project migrate-training-\${VMM_STUDENT_ID}-1234 compute firewall-rules create default-allow-http --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:80,tcp:443 --source-ranges=0.0.0.0/0 --target-tags=http-server # to create firewall rule" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},2"
    echo
    echo "*** Explore Networking ***" | pv -qL 100
    echo
    echo "1) Login at https://console.cloud.google.com/ using your Qwiklabs credentials" | pv -qL 100
    echo "2) Select Compute Engine > Migrate to Virtual Machines" | pv -qL 100
    echo "   Enable VM Migration API if prompted" | pv -qL 100
    echo
    echo "*** Run the commands below ***" | pv -qL 100
    echo
    echo "$ gcloud --project migrate-training-${VMM_STUDENT_ID}-1234 services enable vmmigration.googleapis.com cloudresourcemanager.googleapis.com # to enable API" | pv -qL 100
    echo "$ gcloud --project migrate-training-${VMM_STUDENT_ID}-1234 compute firewall-rules create default-allow-http --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:80,tcp:443 --source-ranges=0.0.0.0/0 --target-tags=http-server # to create firewall rule" | pv -qL 100
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},2x"
    echo
    echo "*** Not implemented ***"
else
    export STEP="${STEP},2i"
    echo
    echo "1. Enable API and create firewall rules" | pv -qL 100
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
    echo "*** Install Migrate to Virtual Machines Backend ***" | pv -qL 100
    echo
    echo " 1) Navigate on bastion-win browser to https://172.16.10.2" | pv -qL 100
    echo "    Click Advanced and Proceed... > LAUNCH VSPHERE CLIENT (HTML5)" | pv -qL 100
    echo " 2) Log in to vCenter using" | pv -qL 100
    echo "    vCenter user: \$VCENTER_USER" | pv -qL 100
    echo "    vCenter password: \$VCENTER_PASSWORD" | pv -qL 100
    echo " 3) Select the data center > right-click and select Deploy OVF Template… > https://storage.googleapis.com/vmmigration-public-artifacts/migrate-connector-2-5-2209.ova" | pv -qL 100
    echo " 4) Accept all defaults for steps 1–4 by clicking NEXT" | pv -qL 100
    echo " 5) Select virtual disk format: Thin Provision, click \"NEXT\"" | pv -qL 100
    echo " 6) Select VM Network: Internal management" | pv -qL 100
    echo " 7) Launch PuTTYgen > Generate (Move your mouse over the blank area to generate randomness) > Save private key > Yes > m2vm_key > Save private key > Yes" | pv -qL 100
    echo " 8) Copy the entire public key directly from application beginning with “ssh-rsa” all the way to the end" | pv -qL 100
    echo "    Do not click “Save public key”" | pv -qL 100
    echo " 9) Paste in SSH Public Key field, and click NEXT > FINISH" | pv -qL 100
    echo
    echo "*** Wait for \"migrate-connector...\" template to deploy ***" | pv -qL 100
    echo
    echo "10) Select \"migrate-connector...\" instance from left-hand navigation menu and click Power on button" | pv -qL 100
    echo
    echo "*** Wait for the appliance to power on and for IP Address to be allocated ***" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},3"
    echo
    echo "*** Install Migrate to Virtual Machines Backend ***" | pv -qL 100
    echo
    echo " 1) Navigate on bastion-win browser to https://172.16.10.2" | pv -qL 100
    echo "    Click Advanced and Proceed... > LAUNCH VSPHERE CLIENT (HTML5)" | pv -qL 100
    echo " 2) Log in to vCenter using" | pv -qL 100
    echo "    vCenter user: $VCENTER_USER" | pv -qL 100
    echo "    vCenter password: $VCENTER_PASSWORD" | pv -qL 100
    echo " 3) Select the data center > right-click and select Deploy OVF Template… > https://storage.googleapis.com/vmmigration-public-artifacts/migrate-connector-2-5-2209.ova" | pv -qL 100
    echo " 4) Accept all defaults for steps 1–4 by clicking NEXT" | pv -qL 100
    echo " 5) Select virtual disk format: Thin Provision, click \"NEXT\"" | pv -qL 100
    echo " 6) Select VM Network: Internal management" | pv -qL 100
    echo " 7) Launch PuTTYgen > Generate (Move your mouse over the blank area to generate randomness) > Save private key > Yes > m2vm_key > Save private key > Yes" | pv -qL 100
    echo " 8) Copy the entire public key directly from application beginning with “ssh-rsa” all the way to the end" | pv -qL 100
    echo "    Do not click “Save public key”" | pv -qL 100
    echo " 9) Paste in SSH Public Key field, and click NEXT > FINISH" | pv -qL 100
    echo
    echo "*** Wait for \"migrate-connector...\" template to deploy ***" | pv -qL 100
    echo
    echo "10) Select \"migrate-connector...\" instance from left-hand navigation menu and click Power on button" | pv -qL 100
    echo
    echo "*** Wait for the appliance to power on and for IP Address to be allocated ***" | pv -qL 100
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},3x"
    echo
    echo "*** Not implemented ***"
else
    export STEP="${STEP},5i"
    echo
    echo "1. Install Migrate for Compute Engine Backend" | pv -qL 100
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
    echo "*** Register the vCenter environment ***" | pv -qL 100
    echo
    echo " 1) Launch Putty and navigate to Connection > SSH > Auth" | pv -qL 100
    echo " 2) Click Browse and select m2vm_key" | pv -qL 100
    echo " 3) Scroll to the top and select Session" | pv -qL 100
    echo " 4) Enter admin@ followed by IP address of \"migrate-connector...\" instance, e.g. admin@172.16.10.xx > Open > Accept" | pv -qL 100
    echo " 5) Run commands:" | pv -qL 100
    echo "    m2vm status" | pv -qL 100
    echo "    m2vm register" | pv -qL 100
    echo "       vCenter host address: 172.16.10.2 > Y >" | pv -qL 100
    echo "       vCenter MFCE user: administrator@psolab.local" | pv -qL 100
    echo "       vCenter MFCE password: ps0Lab!admin" | pv -qL 100
    echo " 6) Run command \"gcloud auth print-access-token\" and copy code" | pv -qL 100
    echo " 7) Enter authorization code into the migrate appliance console > Enter" | pv -qL 100
    echo " 8) Select Qwiklabs Google Cloud project ID" | pv -qL 100
    echo " 9) Type the region: us-west1" | pv -qL 100
    echo "10) Enter vSphere source name: migrate-vsphere" | pv -qL 100
    echo "11) Please select service account:  xxxxxxxxxxxxx-compute.developer.gserviceaccount.com" | pv -qL 100
    echo "12) m2vm status" | pv -qL 100
    echo "13) Navigate to http://10.27.192.41/v5?num=\${VMM_STUDENT_ID} to configure Shared VPC Service Accounts" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},4"
    echo
    echo "*** Register the vCenter environment ***" | pv -qL 100
    echo
    echo " 1) Launch Putty and navigate to Connection > SSH > Auth" | pv -qL 100
    echo " 2) Click Browse and select m2vm_key" | pv -qL 100
    echo " 3) Scroll to the top and select Session" | pv -qL 100
    echo " 4) Enter admin@ followed by IP address of \"migrate-connector...\" instance, e.g. admin@172.16.10.xx > Open > Accept" | pv -qL 100
    echo " 5) Run commands:" | pv -qL 100
    echo "    m2vm status" | pv -qL 100
    echo "    m2vm register" | pv -qL 100
    echo "       vCenter host address: 172.16.10.2 > Y >" | pv -qL 100
    echo "       vCenter account name: administrator@psolab.local" | pv -qL 100
    echo "       vCenter account password: ps0Lab!admin" | pv -qL 100
    echo " 6) Run command \"gcloud auth print-access-token\" and copy code" | pv -qL 100
    echo " 7) Enter authorization code into the migrate appliance console > Enter" | pv -qL 100
    echo " 8) Select Qwiklabs Google Cloud project ID" | pv -qL 100
    echo " 9) Type the region: us-west2" | pv -qL 100
    echo "10) Enter vSphere source name: migrate-vsphere" | pv -qL 100
    echo "11) Please select service account:  xxxxxxxxxxxxx-compute.developer.gserviceaccount.com" | pv -qL 100
    echo "12) m2vm status" | pv -qL 100
    echo "13) Navigate to http://10.27.192.41/v5?num=${VMM_STUDENT_ID} to configure Shared VPC Service Accounts" | pv -qL 100
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},4x"
    echo
    echo "*** Not implemented ***"
else
    export STEP="${STEP},4i"
    echo
    echo "1. Register the vCenter environment" | pv -qL 100
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
    echo "*** Configure and Perform Migration ***" | pv -qL 100
    echo
    echo " 1) On Google Cloud console, navigate to Compute Engine > Migrate to Virtual Machines" | pv -qL 100
    echo " 2) Select SOURCES tab > migrate-training" | pv -qL 100
    echo " 3) Check linux-server > click Add Migrations > click Confirm" | pv -qL 100
    echo " 4) Select Migrations tab > check linux-server > MIGRATION > Start replication" | pv -qL 100
    echo " 5) Select SOURCES tab >  migrate-training" | pv -qL 100 
    echo " 6) Check win1 | win2 > click Add to Group > Enter windowsservers for Group name > ADD TO GROUP" | pv -qL 100
    echo " 7) Select GROUPS tab > Click windowsserver" | pv -qL 100
    echo " 8) Check win1 | win2 > MIGRATION > Start replication" | pv -qL 100
    echo " 9) Select SOURCES tab >  Select linux-server | win1 | win2 > Create report > utilization-report > Time period: Weekly > CREATE" | pv -qL 100
    echo "10) Click View Reports > utilization-report" | pv -qL 100
    echo "11) Navigate to MIGRATIONS > Select linux-server > EDIT TARGET DETAILS" | pv -qL 100
    echo "    Target instance name: linux-server-clone" | pv -qL 100
    echo "    Project: Qwiklabs Google Cloud project ID" | pv -qL 100
    echo "    Zone: us-west1-b" | pv -qL 100
    echo "    Series: e2" | pv -qL 100
    echo "    Machine Type: e2-medium" | pv -qL 100
    echo "    Network: default" | pv -qL 100
    echo "    Subnet: default" | pv -qL 100
    echo "    External IP: Ephemeral" | pv -qL 100
    echo "    Internal IP: Ephemeral (Automatic)" | pv -qL 100
    echo "    Network tags: http-server" | pv -qL 100
    echo "12) Cut-Over and Test-Clone >  Test-Clone" | pv -qL 100
    echo "13) Cut-Over and Test-Clone >  Cut-Over" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},5"
    echo
    echo "*** Configure and Perform Migration ***" | pv -qL 100
    echo
    echo " 1) On Google Cloud console, navigate to Compute Engine > Migrate to Virtual Machines" | pv -qL 100
    echo " 2) Select SOURCES tab > migrate-training" | pv -qL 100
    echo " 3) Check linux-server > click Add Migrations > click Confirm" | pv -qL 100
    echo " 4) Select Migrations tab > check linux-server > MIGRATION > Start replication" | pv -qL 100
    echo " 5) Select SOURCES tab >  migrate-training" | pv -qL 100 
    echo " 6) Check win1 | win2 > click Add to Group > Enter windowsservers for Group name > ADD TO GROUP" | pv -qL 100
    echo " 7) Select GROUPS tab > Click windowsserver" | pv -qL 100
    echo " 8) Check win1 | win2 > MIGRATION > Start replication" | pv -qL 100
    echo " 9) Select SOURCES tab >  Select linux-server | win1 | win2 > Create report > utilization-report > Time period: Weekly > CREATE" | pv -qL 100
    echo "10) Click View Reports > utilization-report" | pv -qL 100
    echo "11) Navigate to MIGRATIONS > Select linux-server > EDIT TARGET DETAILS" | pv -qL 100
    echo "    Target instance name: linux-server-clone" | pv -qL 100
    echo "    Project: Qwiklabs Google Cloud project ID" | pv -qL 100
    echo "    Zone: us-west1-b" | pv -qL 100
    echo "    Series: e2" | pv -qL 100
    echo "    Machine Type: e2-medium" | pv -qL 100
    echo "    Network: default" | pv -qL 100
    echo "    Subnet: default" | pv -qL 100
    echo "    External IP: Ephemeral" | pv -qL 100
    echo "    Internal IP: Ephemeral (Automatic)" | pv -qL 100
    echo "    Network tags: http-server" | pv -qL 100
    echo "12) Cut-Over and Test-Clone >  Test-Clone" | pv -qL 100
    echo "13) Cut-Over and Test-Clone >  Cut-Over" | pv -qL 100
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},5x"
    echo
    echo "*** Not implemented ***"
else
    export STEP="${STEP},5i"
    echo
    echo "1. Configure and Perform Migration" | pv -qL 100
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

Contact us if you are a professional looking for a personalized training experience, 
or a trusted partner looking to deliver customized entry to advanced cloud training.

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
