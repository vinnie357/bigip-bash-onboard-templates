# bigip-bash-onboard-templates
bash basic onboard scripts for aws,azure,gcp for bigip to use with terrraform


## overview

templates are expected to be used with cloud-init user-data.

templates install, and verify the state of the f5 automation tool chain

devices should be ready to accept f5 automation tool chain declarations after the script has completed.

## example templating:

```hcl
# gcp
data "http" "template_gcp" {
    url = "https://raw.githubusercontent.com/vinnie357/bigip-bash-onboard-templates/master/gcp/onboard.sh"
}
data "template_file" "vm_onboard_gcp" {
    
    template = "${data.http.template_gcp.body}"
    vars = {
        uname        	      = "admin"
        upassword        	  = "12343"
        doVersion             = "latest"
        #example version:
        #as3Version           = "3.16.0"
        as3Version            = "latest"
        tsVersion             = "latest"
        cfVersion             = "latest"
        fastVersion           = "0.2.0"
        libs_dir              = "/config/gcp/libs"
        onboard_log           = "/var/log/onboard.log"
        projectPrefix         = "project-"
        buildSuffix           = "random-name"
    }
}
resource "local_file" "onboard_file_gcp" {
    content     = "${data.template_file.vm_onboard_gcp.rendered}"
    filename    = "${path.module}/onboard-gcp-debug-bash.sh"
}
# azure
data "http" "template_azure" {
    url = "https://raw.githubusercontent.com/vinnie357/bigip-bash-onboard-templates/master/azure/onboard.sh"
}
data "template_file" "vm_onboard_azure" {
    
    template = "${data.http.template_azure.body}"
    vars = {
        uname        	      = "admin"
        upassword        	  = "12343"
        doVersion             = "latest"
        #example version:
        #as3Version           = "3.16.0"
        as3Version            = "latest"
        tsVersion             = "latest"
        cfVersion             = "latest"
        fastVersion           = "0.2.0"
        libs_dir              = "/config/azure/libs"
        onboard_log           = "/var/log/onboard.log"
        projectPrefix         = "project-"
        buildSuffix           = "random-name"
    }
}
resource "local_file" "onboard_azure_file" {
    content     = "${data.template_file.vm_onboard_azure.rendered}"
    filename    = "${path.module}/onboard-azure-debug-bash.sh"
}
# aws
data "http" "template_aws" {
    url = "https://raw.githubusercontent.com/vinnie357/bigip-bash-onboard-templates/master/aws/onboard.sh"
}
data "template_file" "vm_onboard_aws" {
    
    template = "${data.http.template_aws.body}"
    vars = {
        uname        	      = "admin"
        upassword        	  = "12343"
        doVersion             = "latest"
        #example version:
        #as3Version           = "3.16.0"
        as3Version            = "latest"
        tsVersion             = "latest"
        cfVersion             = "latest"
        fastVersion           = "0.2.0"
        libs_dir              = "/config/aws/libs"
        onboard_log           = "/var/log/onboard.log"
        projectPrefix         = "project-"
        buildSuffix           = "random-name"
        secret_id             = "mysecretid"
    }
}
resource "local_file" "onboard_aws_file" {
    content     = "${data.template_file.vm_onboard_aws.rendered}"
    filename    = "${path.module}/onboard-aws-debug-bash.sh"
}
```