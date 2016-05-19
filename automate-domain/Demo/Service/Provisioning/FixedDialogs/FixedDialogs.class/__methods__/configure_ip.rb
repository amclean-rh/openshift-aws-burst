#
# Description: <Method description here>
#

  # Method for logging
def log(level, message)
  @method = 'configure_ip'
  $evm.log(level, "#{@method} - #{message}")
end

# dump_root
def dump_root()
  log(:info, "Root:<$evm.root> Begin $evm.root.attributes")
  $evm.root.attributes.sort.each { |k, v| log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}")}
  log(:info, "Root:<$evm.root> End $evm.root.attributes")
  log(:info, "")
end

dump_root

prov = $evm.root["miq_provision"]

log(:info, "Found the VM provisioning request, setting the IP manually")
prov.set_option(:sysprep_spec_override, 'true')
prov.set_option(:addr_mode, ["static", "Static"])
prov.set_option(:ip_addr, "192.168.30.80")
prov.set_option(:subnet_mask, "255.255.255.0")
prov.set_option(:gateway, "192.168.30.1")

log(:info, "Dumping provisioning object : " + prov.inspect)
