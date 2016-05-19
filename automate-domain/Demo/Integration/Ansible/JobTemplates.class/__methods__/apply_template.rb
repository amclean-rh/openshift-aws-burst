begin
  
  require 'open3'
  require 'json'
  require 'time'
  
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

      # Addresses the issue where we watch the output of a job to wait for it to complete.  We get non-JSON values in
      # stoudout stating 'Current status:' then a dump of JSON.  This is really a bug in tower-cli since we've asked for
      # JSON output on our commandline.
      pruned_output=[]
      stdout.readlines.each { |line|
        unless line.match(/^Current status/)
          pruned_output.push(line)
        end
      }

      return(JSON.parse(pruned_output.join()))
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

  job_template_name=$evm.root["job_template_name"] || $evm.object["job_template_name"]
  
  template=find_by_name("job_template", job_template_name)

  unless template["id"]
    raise "Unable to find a valid job_template ID using name <#{job_template_name}>"
  end

  output=call_tower_cli(["job", "launch", "--job-template", template["id"], "--monitor"])

  service=$evm.root["service"]

  service.custom_set("ANSIBLE_LAST_JOB_ID", output["id"])
  service.custom_set("ANSIBLE_LAST_JOB_STATUS", output["status"])
  service.custom_set("ANSIBLE_LAST_JOB_START", output["started"])
  service.custom_set("ANSIBLE_LAST_JOB_END", output["finished"])  
  service.custom_set("ANSIBLE_LAST_JOB_DURATION (SEC)", output["elapsed"])

# Set Ruby rescue behavior
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end
