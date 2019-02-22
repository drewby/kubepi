#!/bin/bash
#---------- see https://github.com/joelong01/Bash-Wizard----------------
# bashWizard version 0.907
# this will make the error text stand out in red - if you are looking at these errors/warnings in the log file
# you can use cat <logFile> to see the text in color.
function echoError() {
    RED=$(tput setaf 1)
    NORMAL=$(tput sgr0)
    echo "${RED}${1}${NORMAL}"
}
function echoWarning() {
    YELLOW=$(tput setaf 3)
    NORMAL=$(tput sgr0)
    echo "${YELLOW}${1}${NORMAL}"
}
function echoInfo {
    GREEN=$(tput setaf 2)
    NORMAL=$(tput sgr0)
    echo "${GREEN}${1}${NORMAL}"
}
# make sure this version of *nix supports the right getopt
! getopt --test 2>/dev/null
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echoError "'getopt --test' failed in this environment. please install getopt."
    read -r -p "install getopt using brew? [y,n]" response
    if [[ $response == 'y' ]] || [[ $response == 'Y' ]]; then
        ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" < /dev/null 2> /dev/null
        brew install gnu-getopt
        #shellcheck disable=SC2016
        echo 'export PATH="/usr/local/opt/gnu-getopt/bin:$PATH"' >> ~/.bash_profile
        echoWarning "you'll need to restart the shell instance to load the new path"
    fi
   exit 1
fi
# we have a dependency on jq
    if [[ ! -x "$(command -v jq)" ]]; then
        echoError "'jq is needed to run this script. Please install jq - see https://stedolan.github.io/jq/download/"
        exit 1
    fi
function usage() {
    echoWarning "Parameters can be passed in the command line or in the input file. The command line overrides the setting in the input file."
    echo "Provisions master and slave kubernetes nodes on Raspberry PI devices. "
    echo ""
    echo "Usage: $0  -t|--target-device -r|--raspbian-image -s|--sha-raspbian -h|--hostname -|--external-static-ip -|--external-gateway -|--external-dns -m|--master -z|--zsh -|--internal-static-ip -|--internal-gateway -|--internal-dns -i|--input-file " 1>&2
    echo ""
    echo " -t | --target-device          Required     The block device to write raspbian image to."
    echo " -r | --raspbian-image         Optional     Compressed (zip) raspbian OS image."
    echo " -s | --sha-raspbian           Optional     SHA value to validate the raspbian OS image file."
    echo " -h | --hostname               Required     Hostname of the new node"
    echo " - | --external-static-ip     Optional     External static IP address (used for master wlan0 only)"
    echo " - | --external-gateway       Optional     External router address (used for master wlan0 only)"
    echo " - | --external-dns           Optional     External name server (DNS) address (used for master wlan0 only) "
    echo " -m | --master                 Optional     Configure the master node (default is to configure slave nodes)"
    echo " -z | --zsh                    Optional     Install ZSH shell (and oh-my-zsh) on the node as default shell"
    echo " - | --internal-static-ip     Optional     Internal network static IP address (for private kube network)"
    echo " - | --internal-gateway       Optional     Internal network default gateway (for slave nodes only)"
    echo " - | --internal-dns           Optional     Internal network name server (DNS) address (for slave nodes only)"
    echo " -i | --input-file             Optional     the name of the input file. pay attention to $PWD when setting this"
    echo ""
    exit 1
}
function echoInput() {
    echo "provision-kubepi.sh:"
    echo -n "    target-device......... "
    echoInfo "$target_device"
    echo -n "    raspbian-image........ "
    echoInfo "$raspbian_image"
    echo -n "    sha-raspbian.......... "
    echoInfo "$raspbian_sha"
    echo -n "    hostname.............. "
    echoInfo "$hostname"
    echo -n "    external-static-ip.... "
    echoInfo "$network_static_ip"
    echo -n "    external-gateway...... "
    echoInfo "$network_router"
    echo -n "    external-dns.......... "
    echoInfo "$network_name_server"
    echo -n "    master................ "
    echoInfo "$config_master"
    echo -n "    zsh................... "
    echoInfo "$install_zsh"
    echo -n "    internal-static-ip.... "
    echoInfo "$network_internal_static_ip"
    echo -n "    internal-gateway...... "
    echoInfo "$network_internal_router"
    echo -n "    internal-dns.......... "
    echoInfo "$network_internal_name_server"
    echo -n "    input-file............ "
    echoInfo "$inputFile"

}

function parseInput() {
    
    local OPTIONS=t:r:s:h::::mz:::i:
    local LONGOPTS=target-device:,raspbian-image:,sha-raspbian:,hostname:,external-static-ip:,external-gateway:,external-dns:,master,zsh,internal-static-ip:,internal-gateway:,internal-dns:,input-file:

    # -use ! and PIPESTATUS to get exit code with errexit set
    # -temporarily store output to be able to check for errors
    # -activate quoting/enhanced mode (e.g. by writing out "--options")
    # -pass arguments only via -- "$@" to separate them correctly
    ! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        # e.g. return value is 1
        # then getopt has complained about wrong arguments to stdout
        usage
        exit 2
    fi
    # read getopt's output this way to handle the quoting right:
    eval set -- "$PARSED"
    while true; do
        case "$1" in
        -t | --target-device)
            target_device=$2
            shift 2
            ;;
        -r | --raspbian-image)
            raspbian_image=$2
            shift 2
            ;;
        -s | --sha-raspbian)
            raspbian_sha=$2
            shift 2
            ;;
        -h | --hostname)
            hostname=$2
            shift 2
            ;;
        - | --external-static-ip)
            network_static_ip=$2
            shift 2
            ;;
        - | --external-gateway)
            network_router=$2
            shift 2
            ;;
        - | --external-dns)
            network_name_server=$2
            shift 2
            ;;
        -m | --master)
            config_master=1
            shift 1
            ;;
        -z | --zsh)
            install_zsh=1
            shift 1
            ;;
        - | --internal-static-ip)
            network_internal_static_ip=$2
            shift 2
            ;;
        - | --internal-gateway)
            network_internal_router=$2
            shift 2
            ;;
        - | --internal-dns)
            network_internal_name_server=$2
            shift 2
            ;;
        -i | --input-file)
            inputFile=$2
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echoError "Invalid option $1 $2"
            exit 3
            ;;
        esac
    done
}
# input variables 
declare target_device=
declare raspbian_image=~/Downloads/2018-11-13-raspbian-stretch-lite.zip
declare raspbian_sha=47ef1b2501d0e5002675a50b6868074e693f78829822eef64f3878487953234d
declare hostname=
declare network_static_ip=192.168.2.200
declare network_router=192.168.2.1
declare network_name_server=192.168.2.1
declare config_master=
declare install_zsh=
declare network_internal_static_ip=192.168.3.1
declare network_internal_router=192.168.3.1
declare network_internal_name_server=192.168.2.1
declare inputFile=

parseInput "$@"

# if command line tells us to parse an input file
if [ "${inputFile}" != "" ]; then
    # load parameters from the file
    configSection=$(jq . <"${inputFile}" | jq '."provision-kubepi.sh"')
    if [[ -z $configSection ]]; then
        echoError "$inputFile or provision-kubepi.sh section not found "
        exit 3
    fi
    target_device=$(echo "${configSection}" | jq '.["target-device"]' --raw-output)
    raspbian_image=$(echo "${configSection}" | jq '.["raspbian-image"]' --raw-output)
    raspbian_sha=$(echo "${configSection}" | jq '.["sha-raspbian"]' --raw-output)
    hostname=$(echo "${configSection}" | jq '.["hostname"]' --raw-output)
    network_static_ip=$(echo "${configSection}" | jq '.["external-static-ip"]' --raw-output)
    network_router=$(echo "${configSection}" | jq '.["external-gateway"]' --raw-output)
    network_name_server=$(echo "${configSection}" | jq '.["external-dns"]' --raw-output)
    config_master=$(echo "${configSection}" | jq '.["master"]' --raw-output)
    install_zsh=$(echo "${configSection}" | jq '.["zsh"]' --raw-output)
    network_internal_static_ip=$(echo "${configSection}" | jq '.["internal-static-ip"]' --raw-output)
    network_internal_router=$(echo "${configSection}" | jq '.["internal-gateway"]' --raw-output)
    network_internal_name_server=$(echo "${configSection}" | jq '.["internal-dns"]' --raw-output)

    # we need to parse the again to see if there are any overrides to what is in the config file
    parseInput "$@"
fi
#verify required parameters are set
if [ -z "${target_device}" ] || [ -z "${hostname}" ]; then
    echo ""
    echoError "Required parameter missing! "
    echoInput #make it easy to see what is missing
    echo ""
    usage
    exit 2
fi


    # --- BEGIN USER CODE ---

function writeImageToTargetDevice {
    local stage="[write-image]"
    if [ -b $target_device ]; then
        echoInfo "$stage Found target device $target_device."
    else
        echoError "$stage Target device $target_device does not exist."
        return 1
    fi

    if [ "$(df | grep $target_device)" == "" ]; then
        echoInfo "$stage Target device $target_device is not mounted."
    else
        echoError "$stage Target device $target_device is mounted at:"
        echoError "$( df | grep $target_device )"
        return 1
    fi

    if [ "$( sha256sum $raspbian_image | awk '{print $1;}' )" == "$raspbian_sha" ]; then
        echoInfo "$stage SHA256 checksum verified on raspbian image."
    else
        echoError "$stage Failed SHA256 checksum on raspbian image. May be corrupt."
        return 1
    fi

    echo "All data on $target_device will be erased. Do you want to continue?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) break;;
            No ) return 1;;
        esac
    done

    unzip -p $raspbian_image | sudo dd of=$target_device bs=4M status=progress conv=fsync 

    if [ $? -eq 0 ]; then
        echoInfo "$stage Wrote raspbian image to $target_device"
    else
        echoError "$stage Failed to write raspbian image to $target_device"
        return 1
    fi
}

function mountDeviceToTemp {
    local stage="[mount-device]"
    mount_dir=$(mktemp -d)
    echoInfo "$stage Mounting "$target_device"2 to $mount_dir"
    sudo mount $target_device"2" $mount_dir
    if [ $? -ne 0 ]; then
        echoError "$stage Could not mount "$target_device"2"
        return 1
    fi

    echoInfo "$stage Mounting "$target_device"1 to $mount_dir/boot"
    sudo mount $target_device"1" $mount_dir/boot
    if [ $? -ne 0 ]; then
        echoError "$stage Could not mount "$target_device"1"
        return 1
    fi
}

function cleanUpMountDir {
    local stage="[umount-device]"
    sudo umount $mount_dir/boot
    echoInfo "$stage Unmounted "$target_device"1 from $mount_dir/boot"
    
    sudo umount $mount_dir
    echoInfo "$stage Unmounted "$target_device"2 from $mount_dir"
    
    rmdir $mount_dir
    echoInfo "$stage Removed directory $mount_dir"
}

function enableSshOnRaspbian {
    local stage="[configure-ssh]"
    echoInfo "$stage Enabling ssh in raspbian" 
    sudo touch $mount_dir/boot/ssh

    if [ $config_master]; then
        echoInfo "$stage Generating ssh server keys"
        sudo mkdir -p $mount_dir/etc/ssh

        sudo ssh-keygen -A -v -f $mount_dir

        echoInfo "$stage Removing service to regenerate ssh host keys"
        sudo rm $mount_dir/etc/systemd/system/multi-user.target.wants/regenerate_ssh_host_keys.service

        local known_server_key=$(sudo cat $mount_dir/etc/ssh/ssh_host_ecdsa_key.pub | awk '{print $1; print $2;}')

        echoInfo "$stage Adding new server key to known hosts"
        sed -i '/^'$network_static_ip'/d' ~/.ssh/known_hosts
        echo $network_static_ip $known_server_key >> ~/.ssh/known_hosts

        echoInfo "$stage Copying id_rsa.pub to authorized_keys"
        sudo mkdir $mount_dir/home/pi/.ssh
        sudo cp ~/.ssh/id_rsa.pub $mount_dir/home/pi/.ssh/authorized_keys
        sudo chmod a+r $mount_dir/home/pi/.ssh/authorized_keys
    fi
}

function enableWirelessWpa {
    local stage="[configure-wireless]"
    echoInfo "$stage Configuring wireless to connect to $wireless_ssid"
    if [ ! $wireless_password ]; then
        read -p "$stage Enter $wireless_ssid wireless password: " wireless_password
    fi
    echo 'ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=JP

network={
 ssid="'$wireless_ssid'"
 psk="'$wireless_password'"
 key_mgmt=WPA-PSK
}' | sudo tee $mount_dir/boot/wpa_supplicant.conf > /dev/null

    echoInfo "$stage Wrote wireless configureation to raspbian"   
}

function updateHostname {
    local stage="[configure-hostname]"
    echoInfo "$stage Updating hostname file with '$hostname'"
    echo $hostname | sudo tee $mount_dir/etc/hostname > /dev/null

    echoInfo "$stage Updating hosts file with '$hostname'"
    # sudo sed -i 's/\(127.0.1.1\s*\).*/\1'$hostname'/g' $mount_dir/etc/hosts
    sudo sed -i 's/127.0.1.1\s*.*/'$network_internal_static_ip' '$hostname'/g' $mount_dir/etc/hosts
}

function updateStaticNetwork {
    local stage="[configure-ip]"
    echoInfo "$stage Updating dhcpcd.conf with static network ip"
    
    if [ $config_master ]; then 
        echo '
interface eth0
static ip_address='$network_internal_static_ip'/24

interface wlan0
static ip_address='$network_static_ip'/24
static routers='$network_router'
static domain_name_servers='$network_name_server' 8.8.8.8' | sudo tee -a $mount_dir/etc/dhcpcd.conf > /dev/null
    else
        echo '
interface eth0
static ip_address='$network_internal_static_ip'/24
static routers='$network_internal_router'
static domain_name_servers='$network_internal_name_server' 8.8.8.8' | sudo tee -a $mount_dir/etc/dhcpcd.conf > /dev/null
    fi

}


function createSetupScripts {
    local stage="[setup-scripts]"
    echoInfo "$stage Creating kubepi_setup.sh script to install kubernetes."
    
    touch $mount_dir/home/pi/rc.output
    
    local zsh_script=""
    if [ $install_zsh ]; then
        touch $mount_dir/home/pi/.zshrc
        zsh_script='
sudo apt-get -y install zsh && usermod --shell /bin/zsh pi && sudo -H -u pi sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
        '
    fi

    echo '#!/bin/sh

until ping -c1 raspbian.raspberrypi.org &>/dev/null; do :; done

sudo apt-get -y update
sudo apt-get -y install git
'$zsh_script'
curl -fsSL get.docker.com -o get-docker.sh && sudo sh get-docker.sh

sudo dphys-swapfile swapoff && \
  sudo dphys-swapfile uninstall && \
  sudo update-rc.d dphys-swapfile remove

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - && \
  echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list && \
  sudo apt-get update -q && \
  sudo apt-get install -qy kubeadm
  
echo Adding " cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory" to /boot/cmdline.txt

sudo cp /boot/cmdline.txt /boot/cmdline_backup.txt
orig="$(head -n1 /boot/cmdline.txt) cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory"
echo $orig | sudo tee /boot/cmdline.txt
echo "kubepi_setup.sh done. Rebooting..."
echo "EOL"
echo ""
sleep 1

sudo reboot
' | sudo tee $mount_dir/home/pi/kubepi_setup.sh > /dev/null
sudo chmod 750 $mount_dir/home/pi/kubepi_setup.sh  

    if [ $config_master ]; then
        echoInfo "$stage Creating kubepi_master_setup.sh to in initalize master node."
        echo '#!/bin/sh
sudo kubeadm config images pull -v3
# sudo kubeadm init --token-ttl=0 --apiserver-advertise-address='$network_internal_static_ip' 

sudo kubeadm init --skip-phases etcd,wait-control-plane,upload-config,mark-control-plane,bootstrap-token,addon --apiserver-advertise-address '$network_internal_static_ip' --apiserver-cert-extra-sans='$network_static_ip'

sudo sed -i "s/failureThreshold: 8/failureThreshold: 20/g" /etc/kubernetes/manifests/kube-apiserver.yaml && \
sudo sed -i "s/initialDelaySeconds: [0-9]\+/initialDelaySeconds: 360/" /etc/kubernetes/manifests/kube-apiserver.yaml

sudo kubeadm init --skip-phases preflight,kubelet-start,certs,kubeconfig,control-plane --token-ttl=0

# get the key for cluster administration
mkdir -p /home/pi/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/pi/.kube/config
sudo chown 1000:1000 /home/pi/.kube /home/pi/.kube/config

kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\''\n'\'')"

echo "kubepi_master_setup.sh done."
echo "done."
echo ""
        ' | sudo tee $mount_dir/home/pi/kubepi_master_setup.sh > /dev/null
        sudo chmod 750 $mount_dir/home/pi/kubepi_master_setup.sh  
    else
        echoInfo "$stage Creating kubepi_slave_setup.sh to join cluster."
        kubeadm_join="$(cat kubeadm-join)"
        echo '#!/bin/sh
'$kubeadm_join'
echo "kubepi_slave_setup.sh done."
echo "EOL"
echo ""
        ' | sudo tee $mount_dir/home/pi/kubepi_slave_setup.sh > /dev/null
        sudo chmod 750 $mount_dir/home/pi/kubepi_slave_setup.sh  
        
    fi

    echoInfo "$stage Creating rc.local to run setup on next boot."
    if [ $config_master ]; then
        echo '#!/bin/bash
# rc.local (one time)
# 
# This script only executes one time and then replaces itself with 
# another rc.local as defined below. 

nohup /home/pi/kubepi_master_setup.sh >> /home/pi/rc.output 2>&1 &

cat <<\EOF > /etc/rc.local
'"$(cat $mount_dir/etc/rc.local)" | sudo tee $mount_dir/etc/rc.local > /dev/null
    else
        echo '#!/bin/bash
# rc.local (one time)
# 
# This script only executes one time and then replaces itself with 
# another rc.local as defined below. 

nohup /home/pi/kubepi_slave_setup.sh >> /home/pi/rc.output 2>&1 &

cat <<\EOF > /etc/rc.local
'"$(cat $mount_dir/etc/rc.local)" | sudo tee $mount_dir/etc/rc.local > /dev/null
    
    fi

    echo '#!/bin/bash
# rc.local (one time)
# 
# This script only executes one time and then replaces itself with 
# another rc.local as defined below. 

nohup /home/pi/kubepi_setup.sh > /home/pi/rc.output 2>&1 &

cat <<\EOF > /etc/rc.local
'"$(cat $mount_dir/etc/rc.local)" | sudo tee $mount_dir/etc/rc.local > /dev/null
}

function getMasterConfig {
    mkdir -p $HOME/.kube
    scp pi@$network_static_ip:/home/pi/.kube/config $HOME/.kube/config
    ssh pi@$network_static_ip "cat /home/pi/rc.output" | grep 'kubeadm join' | tail -1 > kubeadm-join
}

function waitForPiBoot {
    local stage="[waiting]"
    echoInfo "$stage Waiting for raspberryi pi sshd on $hostname."
    ping_cancelled=false    # Keep track of whether the loop was cancelled, or succeeded
    until ssh pi@$network_static_ip 'exit 0' &>/dev/null; do :; done &    # The "&" backgrounds it
    trap "kill $!; ping_cancelled=true" SIGINT
    wait $!          # Wait for the loop to exit, one way or another
    trap - SIGINT    # Remove the trap, now we're done with it
}

if [ $config_master ]; then
    echoWarning "Preparing Master Node"
else
    echoWarning "Preparing Slave Node"
fi

writeImageToTargetDevice
if [ $? -ne 0 ]; then 
    exit 1
fi

mountDeviceToTemp

enableSshOnRaspbian
if [ $config_master ]; then
    enableWirelessWpa
fi
updateHostname
updateStaticNetwork
# TODO: Add script for setting up gateway on master
createSetupScripts

cleanUpMountDir

if [ $config_master ]; then
    waitForPiBoot
    echoInfo "[waiting] Waiting for kubepi_setup"
    ssh pi@$network_static_ip "tail -f ~/rc.output" | sed '/^kubepi_setup.sh done. Rebooting...$/q'
    echoInfo "[waiting] Waiting for kubepi_master_setup"
    ssh pi@$network_static_ip "tail -f ~/rc.output" | sed '/^kubepi_master_setup.sh done.$/q'
    getMasterConfig
fi
  
    # --- END USER CODE ---

