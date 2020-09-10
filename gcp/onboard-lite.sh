#!/bin/bash
# modified version of: https://raw.githubusercontent.com/vinnie357/bigip-bash-onboard-templates/master/gcp/onboard.sh
# and: https://github.com/F5Networks/f5-google-gdm-templates/blob/9bb0b56aa5e178e10edf1200d5b90362b55f9e56/supported/failover/same-net/via-lb/3nic/existing-stack/byol/f5-existing-stack-same-net-cluster-byol-3nic-bigip.py#L520
LOG_FILE=/var/log/onboard.log
if [ ! -e $LOG_FILE ]
then
     touch $LOG_FILE
     exec &>>$LOG_FILE
else
    #if file exists, exit as only want to run once
    exit
fi

exec 1>$LOG_FILE 2>&1
source /usr/lib/bigstart/bigip-ready-functions
wait_bigip_ready
MGMTADDRESS=$(curl -s -f --retry 20 'http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/1/ip' -H 'Metadata-Flavor: Google')
MGMTMASK=$(curl -s -f --retry 20 'http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/1/subnetmask' -H 'Metadata-Flavor: Google')
MGMTGATEWAY=$(curl -s -f --retry 20 'http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/1/gateway' -H 'Metadata-Flavor: Google')
MGMTNETWORK=$(/bin/ipcalc -n ${MGMTADDRESS} ${MGMTMASK} | cut -d= -f2)
# if you want to access via console or password
# generated via: openssl passwd -6 -salt f5f5
#tmsh modify /auth user admin encrypted-password [salted password]
tmsh modify /sys dns name-servers replace-all-with { 169.254.169.254 }
tmsh delete /sys management-route dhclient_route2
tmsh delete /sys management-route dhclient_route1
tmsh delete /sys management-route default
bigstart stop tmm
#https://clouddocs.f5.com/cloud/public/v1/shared/change_mgmt_nic_google.html
tmsh modify sys db provision.managementeth value eth1
#https://clouddocs.f5.com/cloud/public/v1/google/Google_routes.html
#tmsh modify sys db provision.1nicautoconfig value disable
tmsh save sys config
bigstart start tmm
wait_bigip_ready
#sleep 30
# mgmt reboot workaround
#https://support.f5.com/csp/article/K11948
#https://support.f5.com/csp/article/K47835034
chmod +w /config/startup
echo "/config/startup_script_sol11948.sh &" >> /config/startup
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
reboot
