#!/bin/bash
# https://github.com/f5devcentral/f5-bigip-runtime-init
# gcp
# logging
LOG_FILE=${onboard_log}
if [ ! -e $LOG_FILE ]
then
     touch $LOG_FILE
     exec &>>$LOG_FILE
else
    #if file exists, exit as only want to run once
    exit
fi
exec 1>$LOG_FILE 2>&1
# nic flip
source /usr/lib/bigstart/bigip-ready-functions
wait_bigip_ready
MGMTADDRESS=$(curl -s -f --retry 20 'http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/1/ip' -H 'Metadata-Flavor: Google')
MGMTMASK=$(curl -s -f --retry 20 'http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/1/subnetmask' -H 'Metadata-Flavor: Google')
MGMTGATEWAY=$(curl -s -f --retry 20 'http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/1/gateway' -H 'Metadata-Flavor: Google')
MGMTNETWORK=$(/bin/ipcalc -n $${MGMTADDRESS} $${MGMTMASK} | cut -d= -f2)
# if you want to access via console or password
# generated via: openssl passwd -6 -salt f5f5
#tmsh modify /auth user admin encrypted-password [salted password]
#
# admin
#
# create admin account and password
echo "create admin account"
admin_username='${uname}'
admin_password='${upassword}'
# echo  -e "create cli transaction;
tmsh create auth user $admin_username password \'$${admin_password}\' shell bash partition-access add { all-partitions { role admin } };
# modify /sys db systemauth.primaryadminuser value $admin_username;
# submit cli transaction" | tmsh -q
tmsh list auth user $admin_username
# copy ssh key
mkdir -p /home/$admin_username/.ssh/
cp /home/admin/.ssh/authorized_keys /home/$admin_username/.ssh/authorized_keys
echo " admin account changed"
# end admin account and password
# 
# start modify appdata directory size
echo "setting app directory size"
tmsh show sys disk directory /appdata
# 130,985,984 26,128,384 52,256,768
tmsh modify /sys disk directory /appdata new-size 52256768
tmsh show sys disk directory /appdata
echo "done setting app directory size"
# end modify appdata directory size
#
# save sys config
tmsh save sys config
tmsh modify /sys dns name-servers replace-all-with { 169.254.169.254 }
tmsh delete /sys management-route dhclient_route2
tmsh delete /sys management-route dhclient_route1
tmsh delete /sys management-route default
bigstart stop tmm
#https://clouddocs.f5.com/cloud/public/v1/shared/change_mgmt_nic_google.html
tmsh modify sys db provision.managementeth value eth1
#https://clouddocs.f5.com/cloud/public/v1/google/Google_routes.html
tmsh modify sys db provision.1nicautoconfig value disable
tmsh save sys config
bigstart start tmm
wait_bigip_ready

# modify asm interface
cp /etc/ts/common/image.cfg /etc/ts/common/image.cfg.bak
sed -i "s/iface0=eth0/iface0=eth1/g" /etc/ts/common/image.cfg

# mgmt reboot workaround
#https://support.f5.com/csp/article/K11948
#https://support.f5.com/csp/article/K47835034
chmod +w /config/startup
echo "/config/startup_script_sol11948.sh &" >> /config/startup
echo "/config/startup_script_atc.sh &" >> /config/startup
cat  <<EOF > /config/startup_script_sol11948.sh
#!/bin/bash
source /usr/lib/bigstart/bigip-ready-functions
wait_bigip_ready
# adapted from: https://github.com/F5Networks/f5-google-gdm-templates/blob/9bb0b56aa5e178e10edf1200d5b90362b55f9e56/supported/failover/same-net/via-lb/3nic/existing-stack/byol/f5-existing-stack-same-net-cluster-byol-3nic-bigip.py#L520
tmsh modify sys software update auto-phonehome disabled
tmsh modify sys global-settings mgmt-dhcp disabled
tmsh delete sys management-route all
tmsh delete sys management-ip all
tmsh create sys management-ip ${MGMTADDRESS}/32
tmsh create sys management-route mgmt_gw network ${MGMTGATEWAY}/32 type interface
tmsh create sys management-route mgmt_net network ${MGMTNETWORK}/${MGMTMASK} gateway ${MGMTGATEWAY}
tmsh create sys management-route default gateway ${MGMTGATEWAY}
tmsh modify sys global-settings remote-host add { metadata.google.internal { hostname metadata.google.internal addr 169.254.169.254 } }
tmsh modify sys db failover.selinuxallowscripts value enable
tmsh modify sys management-dhcp sys-mgmt-dhcp-config request-options delete { ntp-servers }
tmsh save sys config
EOF
chmod +x /config/startup_script_sol11948.sh

# install
curl https://cdn.f5.com/product/cloudsolutions/f5-bigip-runtime-init/v0.9.0/scripts/install.sh | bash
# configure
cat  <<EOF > /config/cloud/cloud_config.yaml
runtime_parameters: []
extension_packages:
    install_operations:
        - extensionType: do
          extensionVersion: 1.13.0
          extensionUrl: file:///var/lib/cloud/icontrollx_installs/f5-declarative-onboarding-1.13.0-5.noarch.rpm
          extensionHash: e7c9acb0ddfc9e9949c48b9a8de686c365764f28347aacf194a6de7e3ed183be
        - extensionType: as3
          extensionVersion: 3.20.0
          extensionUrl: https://github.com/F5Networks/f5-appsvcs-extension/releases/download/v3.20.0/f5-appsvcs-3.20.0-3.noarch.rpm
          extensionHash: ba2db6e1c57d2ce6f0ca20876c820555ffc38dd0a714952b4266c4daf959d987
        - extensionType: ilx
          extensionUrl: file:///var/lib/cloud/icontrollx_installs/f5-appsvcs-templates-1.1.0-1.noarch.rpm
          extensionVerificationEndpoint: /mgmt/shared/fast/info
extension_services:
    service_operations: []
pre_onboard_enabled: []
post_onboard_enabled: []
EOF
# run
cat  <<EOF > /config/startup_script_atc.sh
# logging
LOG_FILE="/var/log/startup-atc-script.log"
if [ ! -e \$LOG_FILE ]
then
     touch \$LOG_FILE
     exec &>>\$LOG_FILE
else
    #if file exists, exit as only want to run once
    echo "already run exiting"
    exit
fi
exec 1>\$LOG_FILE 2>&1
# run time init
f5-bigip-runtime-init --config-file /config/cloud/cloud_config.yaml
EOF
chmod +x /config/startup_script_atc.sh
echo "rebooting for nic swap to complete"
reboot
