# Fixes dialog options that we don't wish to expose to the user in our dialogs.

  # Method for logging
def log(level, message)
  @method = 'lamp_demo'
  $evm.log(level, "#{@method} - #{message}")
end

# dump_root
def dump_root()
  log(:info, "Root:<$evm.root> Begin $evm.root.attributes")
  $evm.root.attributes.sort.each { |k, v| log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}")}
  log(:info, "Root:<$evm.root> End $evm.root.attributes")
  log(:info, "")
end

log(:info, "Dumping root object before modifications")
dump_root

task = $evm.root['service_template_provision_task']

# Provosion option 1 - Web Teir in OpenStack.
task.set_dialog_option(:dialog_option_1_availability_zone, "nova")
task.set_dialog_option(:dialog_option_1_cloud_network, "demo")
task.set_dialog_option(:dialog_option_1_security_groups, "default")
task.set_dialog_option(:dialog_option_1_guest_access_key_pair, "99000000000014")
task.set_dialog_option(:dialog_option_1_guid, "32dee580-d1c5-11e5-9852-00505680e685")
task.set_dialog_option(:dialog_tag_1_function, "lamp_demo")
task.set_dialog_option(:dialog_tag_1_ansible_group, "webservers")

# Provision option 2 - DB Tier in RHEV
task.set_dialog_option(:dialog_option_2_vlan, "Data")
task.set_dialog_option(:dialog_option_2_guid, "f910c534-ceaa-11e5-a7c9-00505680e685")
task.set_dialog_option(:dialog_option_2_linked_clone, true)
task.set_dialog_option(:dialog_tag_2_function, "lamp_demo")
task.set_dialog_option(:dialog_tag_2_ansible_group, "dbservers")

log(:info, "Dumping Task: " + task.inspect)
