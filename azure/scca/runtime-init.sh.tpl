#!/bin/bash
# https://github.com/f5devcentral/f5-bigip-runtime-init
# azure
#
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
# wait bigip
source /usr/lib/bigstart/bigip-ready-functions
wait_bigip_ready

# start modify appdata directory size
echo "setting app directory size"
tmsh show sys disk directory /appdata
# 130,985,984 26,128,384 52,256,768
tmsh modify /sys disk directory /appdata new-size 52256768
tmsh show sys disk directory /appdata
tmsh save sys config
echo "done setting app directory size"
# end modify appdata directory size

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
        environment: azure
        type: compute
        field: name
pre_onboard_enabled:
  - name: provision_rest
    type: inline
    commands:
      - /usr/bin/setdb provision.extramb 500
      - /usr/bin/setdb restjavad.useextramb true
  - name: expand_rest_storage
    type: inline
    commands:
      - /bin/tmsh show sys disk directory /appdata
      - /bin/tmsh modify /sys disk directory /appdata new-size 52256768
      - /bin/tmsh show sys disk directory /appdata
      - /bin/tmsh save sys config
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
  service_operations:
    - extensionType: do
      type: inline
      value: ${DO_Document}
    - extensionType: as3
      type: inline
      value: ${AS3_Document}
EOF
# install run-time-init
initVersion="1.0.0"
curl -o /tmp/f5-bigip-runtime-init-$${initVersion}-1.gz.run https://cdn.f5.com/product/cloudsolutions/f5-bigip-runtime-init/v$${initVersion}/dist/f5-bigip-runtime-init-$${initVersion}-1.gz.run && bash /tmp/f5-bigip-runtime-init-$${initVersion}-1.gz.run -- '--cloud azure'
# run
f5-bigip-runtime-init --config-file /config/cloud/cloud_config.yaml