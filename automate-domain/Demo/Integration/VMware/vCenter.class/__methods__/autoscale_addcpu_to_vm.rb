# AddCPU_to_VM.rb
# 
# Description: This method is used to modify vCPUs to an existing VM running on VMware
#

# Get vm object from root
vm = $evm.root['vm']
raise "Missing $evm.root['vm'] object" if vm.nil?

# Check to ensure that the VM in question is vmware
vendor = vm.vendor.downcase rescue nil
raise "Invalid vendor detected: #{vendor}" unless vendor == 'vmware'

if vm.num_cpu == 2
  $evm.log(:info, "Already scaled to 2 vCPUs.  No further action required")
else
  $evm.log(:info, "Adding 1 vCPU(s) to VM: #{vm.name} current vCPU count: #{vm.num_cpu}")
  vcpus += 1
  vm.set_number_of_cpus(vcpus, :sync=>true)
end
