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
  
  # basic retry logic
  def retry_method(retry_time=1.minute)
    log(:info, "Sleeping for #{retry_time} seconds")
    $evm.root['ae_result'] = 'retry'
    $evm.root['ae_retry_interval'] = retry_time
    exit MIQ_OK
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

  dump_root

#  service=$evm.root["service"]

#  log(:info, "Service data " + service.inspect)
#  vms=service.vms
#  log(:info, "VMs Data " + vms.inspect)

#  vms.each { | vm |
#    log(:info, "VM Data " + vm.inspect)
#  }

#  log(:info, "Object data " + $evm.object.inspect)

  #inventory_name="CloudForms Inventory"
  #credential_name="Ansible SSH"

  inventory_name=$evm.root["inventory_name"] || $evm.object["inventory_name"]
  credential_name=$evm.root["credential_name"] || $evm.object["credential_name"]

  inventory=find_by_name("inventory", inventory_name)
  credential=find_by_name("credential", credential_name)

  unless inventory["id"]
    raise "Unable to find a valid inventory ID using name <#{inventory_name}>"
  end

  unless credential["id"]
    raise "Unable to find a valid credential using name <#{credential_name}>"
  end

  adhoc_job_args=[
    "ad_hoc", 
    "launch", 
    "--inventory", 
    inventory["id"],
    "--module-name",
    "ping"
  ]

  if credential["kind"] == "ssh"
    adhoc_job_args.push([ "--machine-credential", credential["id"] ])
  else
    adhoc_job_args.push([ "--cloud-credential", credential["id"] ])
  end

  log(:info, "Calling Inventory refresh with arguments " + adhoc_job_args.join(" "))

  output=call_tower_cli(adhoc_job_args)
  job_id=output["id"]

  finished=0
  until finished == 1
    output=call_tower_cli( [ "ad_hoc", "status", job_id ] )
    if output["elapsed"] > 0
      if output["status"] == "successful"
        finished=1
      else
        log(:info, "Inventory refresh ad-hoc ping not successful.  Setting retry")
        retry_method()
        finished=1
      end
    end
    sleep 5
  end

  log(:info, "Inventory refresh completed")
  # Set Ruby rescue behavior
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end
