# allocateFloatingIP.rb
#
# Description: Allocate and associate a new floating IP to a VM.  Works in the context of a button.
#              Expects the name of the floating network in "dialog_floating_network" or it will pick the first available
#
# Author: Dave Costakos <david.costakos@redhat.com>
begin

  def log(level, msg)
    @method = 'allocateFloatingIP'
    $evm.log(level, "#{@method}: #{msg}")
  end 

  def dump_root()
    log(:info, "Root:<$evm.root> Begin $evm.root.attributes")
    $evm.root.attributes.sort.each { |k, v| log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}")}
    log(:info, "Root:<$evm.root> End $evm.root.attributes")
    log(:info, "")
  end

  # Error logging convenience
  def log_err(err)
    log(:error, "#{err.class} #{err}")
    log(:error, "#{err.backtrace.join("\n")}")
  end
  
  # basic retry logic
  def retry_method(retry_time=1.minute)
    log(:info, "Sleeping for #{retry_time} seconds")
    $evm.root['ae_result'] = 'retry'
    $evm.root['ae_retry_interval'] = retry_time
    exit MIQ_OK
  end
  
  def get_fog_object(ext_mgt_system, type="Compute", tenant="admin", auth_token=nil, encrypted=false, verify_peer=false)
    proto = "http"
    proto = "https" if encrypted
    require 'fog'
    begin
      return Object::const_get("Fog").const_get("#{type}").new({
        :provider => "OpenStack",
        :openstack_api_key => ext_mgt_system.authentication_password,
        :openstack_username => ext_mgt_system.authentication_userid,
        :openstack_auth_url => "#{proto}://#{ext_mgt_system[:hostname]}:#{ext_mgt_system[:port]}/v2.0/tokens",
        :openstack_auth_token => auth_token,
        :connection_options => { :ssl_verify_peer => verify_peer, :ssl_version => :TLSv1 },
        :openstack_tenant => tenant
        })
    rescue Excon::Errors::SocketError => sockerr
      raise unless sockerr.message.include?("end of file reached (EOFError)")
      log(:error, "Looks like potentially an ssl connection due to error: #{sockerr}")
      return get_fog_object(ext_mgt_system, type, tenant, auth_token, true, verify_peer)
    rescue => loginerr
      log(:error, "Error logging [#{ext_mgt_system}, #{type}, #{tenant}, #{auth_token rescue "NO TOKEN"}]")
      log_err(loginerr)
      log(:error, "Returning nil")
    end
    return nil
  end  

  def list_external_networks(conn)
    array = []
    networks = conn.list_networks.body
    log(:info, "Networks: #{networks.inspect}")
    for network in networks["networks"]
      array.push(network) if network["router:external"]
    end
    return array
  end

  log(:info, "Begin Automate Method")

  dump_root

  floating_network = "external"
  log(:info, "floating_network: #{floating_network}")

  require 'fog'
  
  prov = $evm.root['miq_provision']
  
  # get vm object from miq_provision. This assumes that the vm container on the management system is present
  vm = prov.vm

  # Since this is provisioning we need to put in retry logic to wait the vm is present
  if vm.nil?
    log(:warn, "$evm.root['miq_provision'].vm not present.")
    retry_method()
  end

  log(:info, "Found VM: #{vm.inspect}")
  log(:info, "Nova UUID for vm is #{vm.ems_ref}")

  tenant_name = $evm.vmdb(:cloud_tenant).find_by_id(vm.cloud_tenant_id).name

  log(:info, "Connecting to tenant #{tenant_name}")

  conn = get_fog_object(vm.ext_management_system, "Compute", tenant_name)

  log(:info, "Got Compute connection #{conn.class} #{conn.inspect}")

  netconn = get_fog_object(vm.ext_management_system, "Network", tenant_name)

  log(:info, "Got Network connection #{netconn.class} #{netconn.inspect}")

  pool_name = floating_network
  pool_name = list_external_networks(netconn).first["name"] if pool_name.nil?

  log(:info, "Allocating IP from #{pool_name}")

  address = conn.allocate_address(pool_name).body
  log(:info, "Allocated #{address['floating_ip'].inspect}")

  res = conn.associate_address("#{vm.ems_ref}", "#{address['floating_ip']['ip']}")
  log(:info, "Associate: Response: #{res.inspect}")
  vm.custom_set("NEUTRON_floating_ip", "#{address['floating_ip']['ip']}")
  vm.custom_set("NEUTRON_floating_id", "#{address['floating_ip']['id']}")
  vm.refresh

  log(:info, "End Automate Method")

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end
