begin
  
  require 'open3'
  require 'json'
  
  # Method for logging
  def log(level, message)
    @method = 'set_host_attributes'
    $evm.log(level, "#{@method} - #{message}")
  end
  
  # basic retry logic
  def retry_method(retry_time=1.minute)
    log(:info, "Sleeping for #{retry_time} seconds")
    $evm.root['ae_result'] = 'retry'
    $evm.root['ae_retry_interval'] = retry_time
    exit MIQ_OK
  end
  
  # dump_root
  def dump_root()
    log(:info, "Root:<$evm.root> Begin $evm.root.attributes")
    $evm.root.attributes.sort.each { |k, v| log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}")}
    log(:info, "Root:<$evm.root> End $evm.root.attributes")
    log(:info, "")
  end
  
  def add_ose_scaleup_attributes(vm, attributes)
    log(:info, "Determined host is part of the OSE Scaleup Demo.  Adding special attributes")
    attributes["openshift_public_hostname"]=vm.name
    attributes["openshift_hostname"]=vm.name
    attributes["openshift_ip"]=attributes["ansible_ssh_host"]
    attributes["openshift_scheduleable"]="true"
  end
    
  def add_attributes_to_host(vm, attributes)
    hostvar_prefix=$evm.object['hostvar_prefix'] || $evm.root['hostvar_prefix']
    attributes.each { | name, value | 
      vm.custom_set(hostvar_prefix + name, value)
    }
  end
        
  dump_root
  
  vms=[]

  case $evm.root['vmdb_object_type']

  when 'miq_provision'
    prov = $evm.root['miq_provision']
    log(:info, "Provision:<#{prov.id}> Request:<#{prov.miq_provision_request.id}> Type:<#{prov.type}>")

    # get vm object from miq_provision. This assumes that the vm container on the management system is present
    vm = prov.vm

    # Since this is provisioning we need to put in retry logic to wait the vm is present
    if vm.nil?
      log(:warn, "$evm.root['miq_provision'].vm not present.")
      retry_method()
    end
    
    vms.push(vm)
  when 'vm'
    # get vm from root
    vm = $evm.root['vm']

    vms.push(vm)
  when 'service'
    vms.push(service.vms)
  else
    raise "Invalid $evm.root['vmdb_object_type']:<#{$evm.root['vmdb_object_type']}>. Skipping method."
  end


  # We know what VMs we're operating on assure they all have an IP Address.
  vms.each { | vm |
    ip=nil
    if vm.vendor.downcase == "openstack"
      # Assure we got our floating IP.
      if vm.floating_ip
        ip=vm.floating_ip[:address]
      end
    else
      ip=vm.ipaddresses[0]
    end

    if ip.nil?
      log(:info, "We don't have an IP Address yet, retrying until we have some data")
      # refresh our power states and relationships to get the IP from a provider.
      vm.refresh
      retry_method()
    end
  }

  vms.each { | vm |
    attributes={}
    log(:info, "VM data: " + vm.inspect)
    log(:info, "VM Vendor: " + vm.vendor)
    if vm.vendor.downcase == "openstack"
      # TODO: Inherit the ssh_user from the provisioned template.
      log(:info, "Determined this is an openstack host, fixed values for ssh_user and using floating IP")
      attributes["ansible_ssh_host"]=vm.floating_ip[:address]
      attributes["ansible_ssh_user"]="cloud-user"
      attributes["ansible_become"]="true"
      attributes["ansible_become_user"]="root"
      attributes["ansible_become_method"]="sudo"
    elsif vm.vendor.downcase == "amazon"
      # TODO: Inherit the ssh_user from the provisioned template.
      log(:info, "Determined this is an amazon host, fixed values for ssh_user")
      attributes["ansible_ssh_user"]="ec2-user"
      attributes["ansible_become"]="true"
      attributes["ansible_become_user"]="root"
      attributes["ansible_become_method"]="sudo"
      attributes["ansible_ssh_host"]=vm.ipaddresses[0]
    else
      attributes["ansible_ssh_host"]=vm.ipaddresses[0]
    end
    
    # Handle any special attributes based on group membership
    vm.tags.each { | tag | 
      if tag.match(/ansible_group\/new_nodes/)
        add_ose_scaleup_attributes(vm, attributes)
      end
    }

    log(:info, "Adding attributes to host #{vm.name} " + attributes.inspect)
    add_attributes_to_host(vm, attributes)
  }

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end
