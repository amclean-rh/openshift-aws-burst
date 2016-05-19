#!/usr/bin/python

##########
# Produces an Ansible Tower inventory output compliant with:
# http://docs.ansible.com/ansible/developing_inventory.html
#
# Adopted from https://github.com/jameslabocki/ansible_api/blob/master/python/ansible_tower_cloudforms_inventory.py
#
# Only produces output for hosts tagged with the [ansible] group_tag in the .ini file.
# Using the [ansible] hostvar_prefix retrieves ansible hostvar values from custom attributes.
##########

import sys
import os
import re
import ConfigParser
import requests
import json

######### EDITABLE
# Location of the ini file containing cloudforms connectivity and translation prefixes.
cloudforms_ini_file="/opt/rh/cloudforms.ini"
# Tag filter to use for the inventory output.  If a host does not contain this tag_name + tag_value it will not be
# emitted regardless of the ansible_group tag value.  Passed through re as a Python regex.
tag_filter_name="function"
tag_filter_value="ose3_demo"
##################

# This disables warnings since we don't (likely) have a signed SSL certificate.
# http://urllib3.readthedocs.org/en/latest/security.html#disabling-warnings
requests.packages.urllib3.disable_warnings()

class ConfigError(Exception):
	def __init__(self, value):
		self.value = value
	def __str__(self):
		return repr(self.value)

class CloudFormsInventory(object):

	def __init__(self, ini_file):

		self.ini_file=ini_file

		# Initialize our options with None values.	We will populate with our .ini file contents later.
		self.options={
			"cloudforms_version":		None,
			"cloudforms_hostname":		None,
			"cloudforms_username":		None,
			"cloudforms_password":		None,
			"ansible_group_tag":		None,
			"ansible_hostvar_prefix":	None,
		}

		# Parse our .ini contents in our options dictionary.
		self.read_settings()

		# Query cloudforms for our raw inventory dump.
		self.query_cloudforms()

		# Format and store our inventory into ansible friendly outputs.
		self.build_inventory_json()

	def read_settings(self):
		''' Reads the settings from the cloudforms.ini file '''

		config = ConfigParser.SafeConfigParser()
		cloudforms_ini_path = "/opt/rh/cloudforms.ini"
		config.read(self.ini_file)

		# Read our [cloudsforms] options.
		for testing in [ 'version', 'hostname', 'username', 'password' ]:
			if config.has_option('cloudforms', testing):
				self.options['cloudforms_' + testing] = config.get('cloudforms', testing)

		# Read our [ansible] options.
		for testing in [ 'group_tag', 'hostvar_prefix' ]:
			if config.has_option('ansible', testing):
				self.options['ansible_' + testing] = config.get('ansible', testing)

		# Verify we got values for all of our options.
		for key in self.options.keys():
			if self.options[key] == None:
				raise ConfigError("Check the %s file contents.	Expected a value for %s under heading [%s]" % (self.ini_file, key.split("_")[1], key.split("_")[0]) )

	def query_cloudforms(self):
		''' Gets host from CloudForms '''
		r = requests.get("https://" + self.options['cloudforms_hostname'] + "/api/vms?expand=resources&attributes=name,power_state,tags,custom_attributes", auth=(self.options['cloudforms_username'],self.options['cloudforms_password']), verify=False)

		self.response = r.json()

	def build_inventory_json(self):

		group_inventory={}
		hostvars={}

		# Iterates over our JSON response from CloudForms and determines our list of groups.
		for resource in self.response['resources']:

                      # Skip powered off hosts.
                        if resource["power_state"] != "on":
                                continue

			matches_filter=False
			# Iterate over our global filter tag and see if this host should be emitted.
			for tag in resource['tags']:
				search=re.match(".*\/(.*?)\/(.*?)$" ,tag['name'])
				tag_name=search.group(1)
				tag_value=search.group(2)

				name_search=re.match(tag_filter_name, tag_name)
				value_search=re.match(tag_filter_value, tag_value)

				# We break on any true result so a subsequent tag can't elimite us
				if name_search and value_search:
					matches_filter=True
					break

			# Skip this host if our filter hasn't matched.
			if matches_filter == False:
				continue

			# Process our ansible group names.
			for tag in resource['tags']:
				search=re.search("\/" + self.options['ansible_group_tag'] + "\/(.*)", tag['name'])
				if search:
					if group_inventory.has_key(search.group(1)):
						group_inventory[search.group(1)].append(resource['name'])
					else:
						group_inventory[search.group(1)]=[]
						group_inventory[search.group(1)].append(resource['name'])

			# Build our host variables based on our prefix values and custom attributes
			hostvar_scratch={}
			for custom_attribute in resource['custom_attributes']:
				search=re.match(self.options['ansible_hostvar_prefix'] + "(.*)", custom_attribute['name'])
				if search:
					hostvar_scratch[search.group(1)]=self.scrub_value(custom_attribute['value'])

			if hostvar_scratch:
				hostvars[resource['name']]=hostvar_scratch

		# Save for Tower < 1.0
		self.group_inventory=group_inventory

		# Save for Tower < 1.2 (will be called with --host)
		self.hostvars=hostvars
		
		# For Tower > 1.3
		inventory=group_inventory.copy()
		inventory["_meta"]={}
		inventory["_meta"]["hostvars"]=hostvars
		self.inventory=inventory

	def scrub_value(self, value):

		# Switch our 'true'/'false'/'null' 
		if str(value).lower() == "true":
			return True

		if str(value).lower() == "false":
			return False

		if str(value).lower() == "null":
			return None

		if str(value).lower() == "none":
			return None

		# if we haven't returned return the value unmodified.
		return value

	# Ansible Tower > v1.3 (hostvars are included and the --host method is not called).
	def all_inventory(self):
		return json.dumps(self.inventory)

	# Ansible Tower < 1.3
	def host_variables(self, host):
		if self.hostvars.has_key(host):
			return json.dumps(self.hostvars[host])
		else:
			return json.dumps({})

	# Ansible tower < 1.3
	def group_inventory(self):
		return json.dumps(self.group_inventory)

###############################################################################
# MAIN
# Initialize our class.  This will parse our ini file, get our data from CloudForms and build the inventory data for Ansible.
inventory=CloudFormsInventory(cloudforms_ini_file)

# Output our correct inventory based on our commandline arguments.  For Tower > 1.3 we should only ever get a --list argument. 
# Which includes the host variables in the _meta object in the response.
if len(sys.argv) == 1:
	print "HELP: --list to show all inventory or --host [name] to get a specific host variables"
	sys.exit(0)

if sys.argv[1] == '--list':
	print inventory.all_inventory()
elif sys.argv[1] == '--host':
	print inventory.host_variables(sys.argv[2])
else:
	print "Invalid argument specified"
	sys.exit(1)
