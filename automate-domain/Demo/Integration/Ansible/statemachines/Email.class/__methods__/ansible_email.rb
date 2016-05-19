# Override the default appliance IP Address below
appliance ||= $evm.root['miq_server'].hostname || $evm.root['miq_server'].ipaddress

to = "amclean@redhat.com"
# Assign original to_email_Address to orig_to for later use
orig_to = to

# Get from_email_address from model unless specified below
from = nil
from ||= $evm.object['from_email_address']

# Get signature from model unless specified below
signature = nil
signature ||= $evm.object['signature']

job_template_name = nil
job_template_name ||= $evm.object['job_template_name']

subject = "Your ansible job has completed"

body = "Hello, "

body += "Ansible playbook has been applied to your service.  Playbook name: " + job_template_name + "<br>"

$evm.log("info", "Sending email to <#{to}> from <#{from}> subject: <#{subject}> body: <#{body}>")
$evm.execute('send_email', to, from, subject, body)
