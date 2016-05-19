begin
  
  require 'open3'
  require 'json'
  
  # Method for logging
  def log(level, message)
    @method = 'refresh_inventory'
    $evm.log(level, "#{@method} - #{message}")
  end

  # dump_root
  def dump_root()
    log(:info, "Root:<$evm.root> Begin $evm.root.attributes")
    $evm.root.attributes.sort.each { |k, v| log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}")}
    log(:info, "Root:<$evm.root> End $evm.root.attributes")
    log(:info, "")
  end

  def call_tower_cli(args=[])
    tower_cli_cmd="/usr/bin/tower-cli"
    # Remove any formatting commands we may be passed.  We will force JSON
    [ "-f", "--format", "json", "human" ].each { | search |
      if args.index(search)
        args=args.pop(args.index(search))
      end
    }

    args.push("-f").push("json")

    Open3.popen3(tower_cli_cmd + " " + args.join(" ")) { | stdin, stdout, stderr, wait_thr |

      exit_status=wait_thr.value.exitstatus

      if exit_status != 0
        raise "Command <#{tower_cli_cmd}> Arguments <#{args.join(", ")} Returned <#{exit_status}>.  STDOUT: <#{stdout.readlines} STDERR: <#{stderr.readlines}"
      end

      return(JSON.parse(stdout.readlines.join()))
    }
  end

  def find_by_name(type, name)
    finished=0
    tower_cli_arguments=[type, "list"]
    until finished == 1
      output=call_tower_cli( tower_cli_arguments )
      output["results"].each { | type_hash |
        if type_hash["name"] == name
          return(type_hash)
        end
      }
      if output["next"]
        tower_cli_arguments=[type, "list", "--page", output["next"]]
      else
        finished=1
      end
    end

    return({})
  end

  def add_attributes_to_host(host_name, attributes)

    host=find_by_name("host", host_name)

    unless host["id"]
      raise "Unable to find a valid host ID using name <#{host_name}>.  Has inventory been refreshed after the host was provisioned?"
    end

    # Build our attributes yaml.
    content=["---"]
    attributes.each { | name, value |
      content.push("#{name}: #{value}");
    }

    # write our attributes hash out to temporary file.
    File.write("/tmp/ansible-#{$$}.yaml", content.join("\n") + "\n")

    call_tower_cli(["host", "modify", host["id"], "--variables", "/tmp/ansible-#{$$}.yaml"])
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

  vms.each { | vm |
    # FIXME: some hard coded stuff here that should live in tags or gleaned some other way.
    attributes={}
    log(:info, "VM data: " + vm.inspect)
    log(:info, "VM Vendor: " + vm.vendor)
    if vm.vendor.downcase == "openstack"
      log(:info, "Determined this is an openstack host, some fixed values will be added")
      attributes["ansible_ssh_host"]=vm.floating_ip[:address]
      attributes["ansible_ssh_user"]="cloud-user"
      attributes["ansible_become"]="yes"
      attributes["ansible_become_user"]="root"
      attributes["ansible_become_method"]="sudo"
    else
      attributes["ansible_ssh_host"]=vm.ipaddresses[0]
    end

    log(:info, "Adding attributes to host #{vm.name} " + attributes.inspect)
    add_attributes_to_host(vm.name, attributes)
  }

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end
