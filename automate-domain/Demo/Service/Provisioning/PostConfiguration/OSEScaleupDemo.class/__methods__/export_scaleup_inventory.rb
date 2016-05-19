########################################################################################
# OSE3 Inventory exporter.
# - Takes our CloudForms generated inventory which lives in Ansible Tower and formats it
#   so that our scaleup.yml will successfully execute to scale our nodes.
# - Reference the following for details on host inventory format.
#   https://access.redhat.com/solutions/2150381
# - This file is later copied to an OpenShift master and executed as the inventory file
#   against the ansible playbook scaleup.yml to scale our OpenShift envirnment.
#
# Author: Adam McLean (amclean@redhat.com)
########################################################################################

# tower-cli alone can't yet serve our purposes for inventory extraction.  See:
# https://github.com/ansible/tower-cli/issues/131
# To address this we go directly to the Tower REST API.  However we will use the tower-cli
#  credentials on the host for connection.  We assume that tower-cli is installed and configured
#  on the Cloudforms appliance(s) running automate.
# This class gives us a clean way of executing queries, getting our result sets and paging them
#  as needed.  Really personal preference.  I like a class interface.
class TowerAPI

  require 'rest_client'
  require 'json'

  def initialize(server, username, password)
    @tower_server=server
    @tower_user=username
    @tower_password=password
    @verify_ssl=false
    self
  end

  def verify_ssl(verify=false)
    @verify_ssl=verify
    self
  end
  
  def call(args)
    args["method"]="GET" unless args["method"]
    args["uri"]="/" unless args["uri"]
    args["body"]=nil unless args["body"]

    request={
      :method => args['method'],
      :url => "https://#{@tower_server}#{args['uri']}",
      :user => @tower_user,
      :password => @tower_password,
      :headers => {
        :accept => 'application/json',
        :content_type => 'application/json'
      },
      :verify_ssl => @verify_ssl
    }

    if args["body"]
      request[:body]=JSON.generate(args["body"])
    end

    response = RestClient::Request.new(request).execute
    @ruby_response=JSON.parse(response.body)
    self
  end

  def response(pretty=false)
    if pretty
      JSON.pretty_generate(@ruby_response)
    else
      return @ruby_response
    end
  end

  def next()

    if @ruby_response['next']
      self.call({ "uri" => @ruby_response['next'] })
    end
    self
  end

  def previous()

    if @ruby_response['previous']
      self.call({ "uri" => @ruby_response['next'] })
    end
    self
  end
end

begin
  
  # Method for logging
  def log(level, message)
    @method = 'export_scaleup_inventory'
    $evm.log(level, "#{@method} - #{message}")
  end

  # dump_root
  def dump_root()
    log(:info, "Root:<$evm.root> Begin $evm.root.attributes")
    $evm.root.attributes.sort.each { |k, v| log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}")}
    log(:info, "Root:<$evm.root> End $evm.root.attributes")
    log(:info, "")
  end
  
  dump_root()

  parent_inventory="OSE3 Demo"

  require 'inifile'
  file = IniFile.load('/root/.tower_cli.cfg')

  general=file["general"]

  api=TowerAPI.new(general["host"], general["username"], general["password"])

  api.call( { "uri" => "/api/v1/inventories/" })

  group_uri=nil
  finished=false
  until finished
    api.response['results'].each { | result |
      if result['name'] == parent_inventory
        group_uri=result["related"]["groups"]
      end
    }
    if api.response['next'].nil?
      finished=true
    else
      api.next() unless api.response['next'].nil?
    end
  end

  raise "Unable to find inventory by name <#{parent_inventory}>" unless group_uri

  api.call({ "uri" => group_uri })

  group_names={}
  api.response['results'].each { | result |
    # We will filter out the group that is tied directly to a custom inventory.  we want the groups it creates.
    next if result['summary_fields']['inventory_source']['source'] == "custom"

    group_names[result['name']]=result['related']['hosts']
  }

  group_contents=[]
  group_names.each { | name, host_uri |

    group_content={}
    api.call( { "uri" => host_uri } )
    group_content["name"]=name
    group_content["hosts"]=[]
    api.response['results'].each { | result |
      group_content["hosts"].push({
        "name" => result["name"],
        # Variables is returned as a JSON string (for some reason)
        "variables" => JSON.parse(result["variables"])
      })
    }
    group_contents.push(group_content)
  }

# Our fixed file header.  As per:
output=<<EOF
[OSEv3:children]
masters
nodes
new_nodes

[OSEv3:vars]
ansible_ssh_user=root
ansible_sudo=true
deployment_type=openshift-enterprise

EOF

  # Now the remainder which we generate from tower by way of CloudForms
  group_contents.each { | group_content | 

    output << "[#{group_content["name"]}]\n"
    group_content["hosts"].each { | host |
      variables=[]
      host["variables"].each { | name, value |
        # The [master] has a slightly different format.  We will tune it here.
        if group_content["name"] == "masters"
          if name == "openshift_hostname"
            variables.push("hostname=#{value}")
          elsif name == "openshift_public_hostname"
            variables.push("public_hostname=#{value}")
          else
            variables.push("#{name}=#{value}")
          end
        else
          variables.push("#{name}=#{value}")
        end
      }
      output << host["name"].tr(" ", "_") + " " + variables.join(" ") + "\n"
    }
    output << "\n"
  }

  file = File.open("/tmp/hosts.ose.scaleup", "w")
  file.write(output)

  log(:info, "Exported OSE Scalup inventory to file /tmp/hosts.ose.scaleup on the CloudForms appliance")
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
ensure
  file.close unless file.nil?
end
