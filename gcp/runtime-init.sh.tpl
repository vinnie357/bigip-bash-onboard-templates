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
MGMTNETWORK=$(/bin/ipcalc -n $MGMTADDRESS $MGMTMASK | cut -d= -f2)
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
tmsh create sys management-ip $${MGMTADDRESS}/32
tmsh create sys management-route mgmt_gw network $${MGMTGATEWAY}/32 type interface
tmsh create sys management-route mgmt_net network $${MGMTNETWORK}/$${MGMTMASK} gateway $${MGMTGATEWAY}
tmsh create sys management-route default gateway $${MGMTGATEWAY}
tmsh modify sys global-settings remote-host add { metadata.google.internal { hostname metadata.google.internal addr 169.254.169.254 } }
tmsh modify sys db failover.selinuxallowscripts value enable
tmsh modify sys management-dhcp sys-mgmt-dhcp-config request-options delete { ntp-servers }
tmsh save sys config
EOF
chmod +x /config/startup_script_sol11948.sh

# tmos init
# configure
mkdir -p /config/cloud
# https://github.com/f5devcentral/f5-bigip-runtime-init/blob/develop/src/schema/base_schema.json
cat  <<EOF > /config/cloud/cloud_config.yaml
---
runtime_parameters:
  - name: HOST_NAME
    type: metadata
    metadataProvider:
        environment: gcp
        type: compute
        field: name
extension_packages:
  install_operations:
    - extensionType: do
      extensionVersion: 1.15.0
    - extensionType: as3
      extensionVersion: 3.20.0
    - extensionType: ts
      extensionVersion: 1.14.0
    - extensionType: cf
      extensionVersion: 1.5.0
    - extensionType: ilx
      extensionUrl: https://github.com/F5Networks/f5-appsvcs-templates/releases/download/v1.3.0/f5-appsvcs-templates-1.3.0-1.noarch.rpm
      extensionVersion: 1.3.0
      extensionVerificationEndpoint: /mgmt/shared/fast/info
extension_services:
  service_operations: []
EOF
# run
cat  <<'EOF' > /config/startup_script_atc.sh
# logging
LOG_FILE="/var/log/startup-atc-script.log"
if [ ! -e $LOG_FILE ]
then
     touch $LOG_FILE
     exec &>>$LOG_FILE
else
    #if file exists, exit as only want to run once
    echo "already run exiting"
    exit
fi
exec 1>$LOG_FILE 2>&1
# run time init
source /usr/lib/bigstart/bigip-ready-functions
wait_bigip_ready
# CHECK TO SEE NETWORK IS READY
count=0
while true
do
  STATUS=$(curl -s -k -I example.com | grep HTTP)
  if [[ $STATUS == *"200"* ]]; then
    echo "internet access check passed"
    break
  elif [ $count -le 6 ]; then
    echo "Status code: $STATUS  Not done yet..."
    count=$[$count+1]
  else
    echo "GIVE UP..."
    break
  fi
  sleep 10
done
# install
#curl https://cdn.f5.com/product/cloudsolutions/f5-bigip-runtime-init/v0.9.0/scripts/install.sh | bash
initVersion="1.0.0"
curl -o /tmp/f5-bigip-runtime-init-$${initVersion}-1.gz.run https://cdn.f5.com/product/cloudsolutions/f5-bigip-runtime-init/v$${initVersion}/dist/f5-bigip-runtime-init-$${initVersion}-1.gz.run && bash /tmp/f5-bigip-runtime-init-$${initVersion}-1.gz.run -- '--cloud gcp'
# run
f5-bigip-runtime-init --config-file /config/cloud/cloud_config.yaml
EOF
chmod +x /config/startup_script_atc.sh
echo "rebooting for nic swap to complete"
reboot
