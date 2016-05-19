begin
  
  require 'open3'
  
  # Method for logging
  def log(level, message)
    @method = 'add_host_dns'
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

  def call_curl(args=[])
    curl_cmd="/usr/bin/curl"

    log(:info, "Calling curl command with arguments " + args.join(" "))

    Open3.popen3(curl_cmd+ " " + args.join(" ")) { | stdin, stdout, stderr, wait_thr |

       exit_status=wait_thr.value.exitstatus

      if exit_status != 0
        raise "Command <#{curl_cmd}> Arguments <#{args.join(", ")} Returned <#{exit_status}>.  STDOUT: <#{stdout.readlines} STDERR: <#{stderr.readlines}"
      end
    
      log(:info, "Curl command returned " + stdout.readlines.join(" "))
    }
  end

  dump_root

  vm=nil

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

  when 'vm'
    # get vm from root
    vm = $evm.root['vm']
  else
    raise "Invalid $evm.root['vmdb_object_type']:<#{$evm.root['vmdb_object_type']}>. Skipping method."
  end

  arguments={
    "ipaddress"	=>	nil,
    "hostname"	=>	nil
  }

  ["api_host", "api_port", "api_key", "zone"].each { | required |
    arguments[required]=$evm.root[required] || $evm.object[required]
    unless arguments[required]
      raise "Unable to determine a value for <#{required}>.  Unable to proceed"
    end
  }

  if vm.vendor.downcase == "openstack"
    # Assure we got our floating IP.
    if vm.floating_ip
      arguments["ipaddress"]=vm.floating_ip[:address]
    end
  else
    arguments["ipaddress"]=vm.ipaddresses[0]
  end

  if arguments["ipaddress"].nil?
    log(:info, "We don't have an IP Address yet, retrying until we have some data")
    # refresh our power states and relationships to get the IP from a provider.
    vm.refresh
    retry_method()
  end

  arguments["hostname"]="#{vm.name}.#{arguments["zone"]}"

  curl_args=[
    '-X',
    'PATCH',
    '--data',
    %Q|'{"rrsets": [ {"name": "#{arguments["hostname"]}", "type": "A", "changetype": "REPLACE", "records": [ {"content": "#{arguments["ipaddress"]}", "disabled": false, "name": "#{arguments["hostname"]}", "ttl": 120, "type": "A" } ] } ] }'|,
    '-H',
    %Q|'X-API-Key: #{arguments["api_key"]}'|,
    "http://#{arguments["api_host"]}:#{arguments["api_port"]}/servers/localhost/zones/#{arguments["zone"]}."
  ]

  call_curl(curl_args)

  log(:info, "Added DNS entry to zone <#{arguments["zone"]}> for host <#{arguments["hostname"]}> IP <#{arguments["ipaddress"]}>")

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end
