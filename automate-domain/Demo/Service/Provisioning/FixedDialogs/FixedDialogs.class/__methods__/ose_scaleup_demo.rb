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

task.set_dialog_option(:dialog_option_1_guid, "b9bbc592-0009-11e6-9f05-00505680e685")
task.set_dialog_option(:dialog_option_1_instance_type, "99000000000072")
task.set_dialog_option(:dialog_option_1_guest_access_key_pair, "99000000000022")
task.set_dialog_option(:dialog_option_1_placement_availability_zone, "us-east-1b")
task.set_dialog_option(:dialog_option_1_cloud_network, "AdamLab-Extension")
task.set_dialog_option(:dialog_option_1_cloud_subnet, "99000000000009")
task.set_dialog_option(:dialog_option_1_security_groups, "99000000000010")
task.set_dialog_option(:dialog_option_1_number_of_vms, "2")
task.set_dialog_option(:dialog_tag_1_function, "ose3_demo")
task.set_dialog_option(:dialog_tag_1_ansible_group, "new_nodes")

log(:info, "Dumping Task: " + task.inspect)
