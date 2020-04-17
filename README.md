# bigip-bash-onboard-templates
bash basic onboard scripts for aws,azure,gcp for bigip to use with terrraform


## overview

templates are expected to be used with cloud-init user-data.

templates install, and verify the state of the f5 automation tool chain

devices should be ready to accept f5 automation tool chain declarations after the script has completed.

## example templating:

```hcl
    data "http" "template" {
        url = "https://raw.githubusercontent.com/vinnie357/bigip-bash-onboard-templates/master/gcp/onboard.sh"
    }
    data "template_file" "vm_onboard" {
    template = "${path.module}/f5_onboard.tmpl"

    vars = {
        uname        	      = "${var.adminAccountName}"
        upassword        	  = "${var.adminPass != "" ? "${var.adminPass}" : "${random_password.password.result}"}"
        doVersion             = "latest"
        #example version:
        #as3Version            = "3.16.0"
        as3Version            = "latest"
        tsVersion             = "latest"
        cfVersion             = "latest"
        fastVersion           = "0.2.0"
        libs_dir		      = "${var.libsDir}"
        onboard_log		      = "${var.onboardLog}"
        projectPrefix         = "${var.projectPrefix}"
        buildSuffix           = "${var.buildSuffix}"
    }
    }
```