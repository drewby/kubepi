# kubepi
Set of scripts to provision and manage a kuberenetes cluster on raspberry pi. 
This script automates provisioning of raspberry pi onto a master and set of worker 
nodes.  It assumes the master is also a network gateway and the workers are not 
directly connected to the "public" network.  

## Attributions
* The code for provisioning the master node is based on the excellent 
guide from Alex Ellis at https://github.com/alexellis/k8s-on-raspbian
* Bash Wizard was used to generate the script with input parameter handling. 
https://github.com/joelong01/Bash-Wizard

## Documentation
The script `provision-kubepi.sh` automates the process of imaging and configuring 
Rasperry PI devices into a kubernetes network. There are two modes to the script: 
provision the master node and then provision any number of worker nodes.


### Usage
Parameters can be passed in the command line or in the input file. The command line overrides the setting in the input file.

```
Usage: ./provision-kubepi.sh  -t|--target-device -r|--raspbian-image -s|--sha-raspbian -h|--hostname --external-static-ip --external-gateway --external-dns -m|--master -z|--zsh --internal-static-ip --internal-gateway --internal-dns -i|--input-file --wifi-ssid --wifi-password

 -t | --target-device          Required     The block device to write raspbian image to.
 -r | --raspbian-image         Optional     Compressed (zip) raspbian OS image.
 -s | --sha-raspbian           Optional     SHA value to validate the raspbian OS image file.
 -h | --hostname               Required     Hostname of the new node
      --external-static-ip     Optional     External static IP address (used for master wlan0 only)
      --external-gateway       Optional     External router address (used for master wlan0 only)
      --external-dns           Optional     External name server (DNS) address (used for master wlan0 only)
 -m | --master                 Optional     Configure the master node (default is to configure slave nodes)
 -z | --zsh                    Optional     Install ZSH shell (and oh-my-zsh) on the node as default shell
      --internal-static-ip     Optional     Internal network static IP address (for private kube network)
      --internal-gateway       Optional     Internal network default gateway (for slave nodes only)
      --internal-dns           Optional     Internal network name server (DNS) address (for slave nodes only)
 -i | --input-file             Optional     the name of the input file. pay attention to /home/drewby/src/kubepi when setting this
      --wifi-ssid              Optional     SSID for external wireless network (used for master wlan0 only)
      --wifi-password          Optional     Password for external wireless network (used for master wlan0 only)
```

You can also pass parameters through an input file. 

### Example input file:

```
{
    "provision-kubepi.sh": {
        "target-device": "",
        "raspbian-image": "~/Downloads/2018-11-13-raspbian-stretch-lite.zip",
        "sha-raspbian": "47ef1b2501d0e5002675a50b6868074e693f78829822eef64f3878487953234d",
        "hostname": "rpi301",
        "internal-static-ip": "192.168.3.101",
        "internal-gateway": "192.168.3.1",
        "internal-dns": "192.168.2.1",
        "master": "",
        "zsh": ""
    }
}
```

### Provisioning the master node follows these steps:

1. __Write raspbian image to target__ - The image is located at 
*--raspbian-image* and the image is verified using the checksum in 
*--sha-raspian*. The image is written to *--target-device*. The target device 
cannot have any active mounts.  

1. __Mount the target device__ - The image is mounted to a temporary directory 
created by mktemp -d.

1. __Apply changes to mounted image__
    
    1. __Enable SSH__ - Enable SSH to the master node from the local machine. 
    To do this the script generates the server keys and disables the systemd 
    service that does this on first boot.  It then copies the new server public 
    key to $HOME/.ssh/known\_hosts assigning it to the ip in *--external-static-ip*.
    Copy the local users public key (assumed id_rsa.pub) to .ssh/authorized_keys 
    of the pi user. Generate the pi user rsa keys and copy public ket  locally
    to pi.pub for later use with worker nodes. __Password authentication for SSH is
    disabled.__ 
    
    1. __Enable wireless adapter__ - Create the *wpa_supplicant.conf*
    file in /boot which will be used to configure wireless on the first boot. The SSID is 
    defined with *--wifi-ssid* and the password is defined with *--wifi-password*.  If *--wifi-password*
    is not defined then an interactive prompt is used to collect the password. 

    1. __Configure network gateway__ - Configure networking
    to be a gateway between the private/internal physical network and the public/external
    wireless network. Create a script which uses iptables to setup network address
    translation (nat) and packet forwarding from eth0 to wlan0. Create a systemd service
    definition to execute the script on boot.
    
    1. __Update hostname__ - Modify the /etc/hostname and /etc/hosts file to use the
    hostname defined by *--hostname* and IP address defined by *--internal-static-ip*.

    1. __Update network addresses__ - Update /etc/dhcpd.conf to use *--external-static-ip*, 
    *--external-gateway--*, *--external-dns--* for wlan0 and *--internal-static-ip*, 
    *--internal-gateway--*, *--internal-dns--* for eth0.

    1. __Create setup scripts__ - Create kubepi_setup.sh and kubepi_master_setup.sh in
    /home/pi. Then, create an rc.local to execute these scripts on the first boot. The
    rc.local rewrites itself to execute each stage of setup on next boot. The final
    rewrite will restore rc.local to the original file in the raspbian image. Details
    of the setup scripts are described below.
    
1. __Unmount target device__ - The target device is unmounted and ready to insert
into the master raspberry pi. 

1. __Wait for device to boot and setup scripts__ - The script waits for a successful
ssh connection to the booted master node. Then starts to monitor output  from the setup
scripts. Then following changes are made by the setup scripts:
    1. Update package manager (apt-get) source lists
    1. Install git
    1. Install zsh (if *--zsh* flag set)
    1. Install docker
    1. Turn off dphys-swapfile (required to support kubernetes)
    1. Install kubernetes
    1. Add cgroup parameters to kernal command line (/boot/cmndline.txt)
    1. __Reboot__
    1. Run first phases of kubeadm init until control-plane
    1. Update startup thresholds for apiserver so it doesn't fail with slow start
    1. Run remaining phases of kubeadm init
    1. Copy .kube configuration to `pi` user home folder
    1. Apply weave network configuration 
1. __Copy master configuration files to local machine__ - Now that the master node
is setup, the script copies the configuration information to managing kubernetes from
the local machine.  Also, the script captures the join token for use in provisioning 
worker nodes.
    1. .kube configuration (saved to $HOME/.kube/config)
    1. kubeadm join command line with token (saved to kubeadm-join file)

### Provisioning the worker node follows these steps:

1. __Write raspbian image to target__ - The image is located at 
*--raspbian-image* and the image is verified using the checksum in 
*--sha-raspian*. The image is written to *--target-device*. The target device 
cannot have any active mounts.  

1. __Mount the target device__ - The image is mounted to a temporary directory 
created by mktemp -d.

1. __Apply changes to mounted image__
    
    1. __Enable SSH__ - Enable SSH to the worker node from the internal network. 
    If pi.pub exists, it is copied to the worker node to make it easier to SSH
    from the master node. __Password authentication for SSH is disabled.__ 
    
    1. __Update hostname__ - Modify the /etc/hostname and /etc/hosts file to use the
    hostname defined by *--hostname* and IP address defined by *--internal-static-ip*.

    1. __Update network addresses__ - Update /etc/dhcpd.conf *--internal-static-ip*, 
    *--internal-gateway--*, *--internal-dns--* for eth0. _Note that wlan0 is left
    disabled for worker nodes._

    1. __Create setup scripts__ - Create kubepi_setup.sh and kubepi_worker_setup.sh in
    /home/pi. Then, create an rc.local to execute these scripts on the first boot. The
    rc.local rewrites itself to execute each stage of setup on next boot. The final
    rewrite will restore rc.local to the original file in the raspbian image. Details
    of the setup scripts are described below.
    
1. __Unmount target device__ - The target device is unmounted and ready to insert
into the worker raspberry pi. 

1. __Boot and setup scripts__ - Unlike the master node setup, the script 
does not wait for the worker node to boot (in fact, it cannot connect to the
worker node directly). The following changes are made by the setup scripts:
    1. Update package manager (apt-get) source lists
    1. Install git
    1. Install zsh (if *--zsh* flag set)
    1. Install docker
    1. Turn off dphys-swapfile (required to support kubernetes)
    1. Install kubernetes
    1. Add cgroup parameters to kernal command line (/boot/cmndline.txt)
    1. __Reboot__
    1. Run kubeadm join command with the token that was saved after master provisioning. 

