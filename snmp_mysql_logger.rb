require 'iniparse'
require 'mysql2'
require 'netsnmp'

# Define globals.
$my_dry_run = false
$my_sql_err = false
$my_create_tables = false
$my_force_table_creation = false
$my_generate_conf_file = false
$my_config_file = ""

def my_print_version()
	puts "snmp_mysql_logger Version 1.0.0\n"
end

def my_print_usage()
	my_print_version
	puts "Arguments:\n"
	puts "-c, --config-file: Path to configuration file.\n"
	puts "-d, --dry-run: Enable dry run mode. (No commits to database are performed.)\n"
	puts "-t, --create-tables: Create table structure in the configured mysql database.\n"
	puts "-f, --force-create-tables: Forcibly create table structure in the configured mysql database. (WARNING: Any existing tables will be DROPPED!!!)\n"
	puts "-g, --generate-config-file: Create an example config file. (Uses the path given by the -c | --config-file option.)\n"
	puts "-s, --enable-sql-errors: Turns on SQL error reporting when dry run mode is disabled.\n"
	puts "-v, --version: Output the current version information.\n"
	Kernel.exit!
end

# Parse arguments.
if ARGV.length > 0
	i = 0
	while i < ARGV.length
		if ARGV[i] == "-d" || ARGV[i] == "--dry-run"
			$my_dry_run = true
		else
			if ARGV[i] == "-c" || ARGV[i] == "--config-file"
				if (i + 1) < ARGV.length && ARGV[(i + 1)].length > 0
					$my_config_file = ARGV[(i + 1)]
					i += 1
				else
					my_print_usage()
				end
			else
				if ARGV[i] == "-t" || ARGV[i] == "--create-tables"
					$my_create_tables = true
				else
					if ARGV[i] == "-f" || ARGV[i] == "--force-create-tables"
						$my_create_tables = true
						$my_force_table_creation = true
					else
						if ARGV[i] == "-g" || ARGV[i] == "--generate-config-file"
							$my_generate_conf_file = true
						else
							if ARGV[i] == "-s" || ARGV[i] == "--enable-sql-errors"
								$my_sql_err = true
							else
								if ARGV[i] == "-v" || ARGV[i] == "--version"
									my_print_version()
									Kernel.exit!
								else
									my_print_usage()
								end
							end
						end
					end
				end
			end
		end
		# Increment i.
		i += 1
	end

	# Check for required args.
	if $my_config_file.length <= 0
		my_print_usage()
	end
else
	# No args.
	my_print_usage()
end

if $my_generate_conf_file
	def gen_config_file(confFile)
		ini = IniParse.gen do | doc |
			doc.section('sNMPV1', :comment => "A SNMPv1 / SNMPv2 host defintion.") do | sNMPV1 |
				sNMPV1.option('type', 'snmp_host')
				sNMPV1.option('address', 'h1.example.com')
				sNMPV1.option('query_interval_seconds', '10', :comment => "(Default) Interval that defines how often to query the SNMP host in seconds.")
				sNMPV1.option('query_interval_skip', 0, :comment => "(Default) How many intervals must pass before querying the SNMP host again.")
				sNMPV1.option('snmp_version', '1')
				sNMPV1.option('community', 'public')
			end
			doc.section('sNMPV3_NOAUTHNOPRIV', :comment => "A SNMPv3 host definition using only a user name.") do | sNMPV3_NOAUTHNOPRIV |
				sNMPV3_NOAUTHNOPRIV.option('type', 'snmp_host')
				sNMPV3_NOAUTHNOPRIV.option('address', 'h2.example.com')
				sNMPV3_NOAUTHNOPRIV.option('query_interval_seconds', '20')
				sNMPV3_NOAUTHNOPRIV.option('query_interval_skip', 1, :comment => "E.x. Effectively doubles the given interval.")
				sNMPV3_NOAUTHNOPRIV.option('snmp_version', '3')
				sNMPV3_NOAUTHNOPRIV.option('username', 'bob')
                                sNMPV3_NOAUTHNOPRIV.option('context', 'public')
			end
			doc.section('sNMPV3_AUTHNOPRIV', :comment => "A SNMPv3 host definition using AUTH only mode.") do | sNMPV3_AUTHNOPRIV |
				sNMPV3_AUTHNOPRIV.option('type', 'snmp_host')
				sNMPV3_AUTHNOPRIV.option('address', 'h3.example.com')
				sNMPV3_AUTHNOPRIV.option('query_interval_seconds', '20')
				sNMPV3_AUTHNOPRIV.option('query_interval_skip', 1)
				sNMPV3_AUTHNOPRIV.option('snmp_version', '3')
				sNMPV3_AUTHNOPRIV.option('username', 'rob')
				sNMPV3_AUTHNOPRIV.option('auth_password', 'foo')
				sNMPV3_AUTHNOPRIV.option('auth_protocol', 'md5')
                                sNMPV3_AUTHNOPRIV.option('context', 'public')
			end
			doc.section('sNMPV3_AUTHPRIV', :comment => "A SNMPv3 host definition using AUTH+PRIV mode.") do | sNMPV3_AUTHPRIV |
				sNMPV3_AUTHPRIV.option('type', 'snmp_host')
				sNMPV3_AUTHPRIV.option('address', 'h4.example.com')
				sNMPV3_AUTHPRIV.option('query_interval_seconds', '30')
				sNMPV3_AUTHPRIV.option('query_interval_skip', 0, :comment => "E.x. Host is queried on each interval.")
				sNMPV3_AUTHPRIV.option('snmp_version', '3')
				sNMPV3_AUTHPRIV.option('username', 'alice')
				sNMPV3_AUTHPRIV.option('auth_password', 'bar')
                                sNMPV3_AUTHPRIV.option('auth_protocol', 'md5')
				sNMPV3_AUTHPRIV.option('priv_password', 'batteryhorsestaplecorrect')
                                sNMPV3_AUTHPRIV.option('priv_protocol', 'des')
				sNMPV3_AUTHPRIV.option('context', 'public')
			end
			doc.section('snmp_values_dynamic', :comment => "SNMP OIDs to query and log over time on each SNMP host.") do | value |
				value.option('type', 'snmp_values_dynamic', :comment => "snmp_values_dynamic: Log and retain values over time.")
				value.option('query_interval_seconds', '10', :comment => "(Optional: Overrrides host section.) Interval that defines how often to query the SNMP host in seconds.")
				value.option('query_interval_skip', 0, :comment => "(Optional: Overrrides host section.) How many intervals must pass before querying the SNMP host again.")
				value.option(1,'1.3.6.1.2.1.2.2.1.7.1', :comment => "E.x. LBMSH-MIB ifAdminStatus (on index 1)")
				value.option(2,'1.3.6.1.2.1.2.2.1.14.1', :comment => "E.x. LBMSH-MIB ifInErrors (on index 1)")
			end
			doc.section('snmp_values_static', :comment => "SNMP OIDs to query and retain most recent value on each SNMP host.") do | value |
				value.option('type', 'snmp_values_static', :comment => "snmp_values_static: Log and retain only the most recently seen value.")
				value.option('query_interval_seconds', '10', :comment => "(Optional: Overrrides host section.) Interval that defines how often to query the SNMP host in seconds.")
				value.option('query_interval_skip', 0, :comment => "(Optional: Overrrides host section.) How many intervals must pass before querying the SNMP host again.")
				value.option(1, '1.3.6.1.2.1.1.5', :comment => "E.x. SNMPv2-MIB sysName")
				value.option(2, '1.3.6.1.2.1.1.3', :comment => "E.x. SNMPv2-MIB sysUpTime")
			end
			doc.section('database', :comment => "MySQL / MariaDB database connection info.") do | db |
				db.option('type', 'mysql_database')
				db.option('servername', 'db.example.com')
				db.option('username', 'alice')
				db.option('password', 'foobar')
				db.option('dbname', 'network_snmp_values')
			end
		end
		begin
			File.write(confFile, ini, mode: "w")
		rescue Exception => e
			puts "ERROR: Could not write config file ( #{confFile} ).\nException Raised: "
			puts e
			puts "\n"
		end
	end
end

def parse_config_file(cFile)
	ret = 0
	hosts = Array.new
	snmp_vars = Array.new
	db_info = Array.new(4)

	begin
		configFile = IniParse.parse( File.read(cFile) )
		db_loaded = false

		for section in configFile
			if section.has_option?('type')
				if section['type'] == 'mysql_database'
					if db_loaded == false
						# Load the database config.
						if section.has_option?('servername') && section['servername'].length > 0
							db_info[0] = section['servername']
						else
							# Missing database server name.
							ret = nil
						end
						if section.has_option?('username') && section['username'].length > 0
							db_info[1] = section['username']
						else
							# Missing database user name.
							ret = nil
						end
						if section.has_option?('password') && section['password'].length > 0
							db_info[2] = section['password']
						else
							# Missing database password.
							ret = nil
						end
						if section.has_option?('dbname') && section['dbname'].length > 0
							db_info[3] = section['dbname']
						else
							# Missing database name.
							ret = nil
						end
						if ret != nil
							db_loaded = true
						end
					end
				else
					if section['type'] == 'snmp_values_dynamic'
						# Set vars.
						my_interval = 0
						my_skip = 0

						# Check for host section default overrides.
						if section.has_option?('query_interval_seconds')
							my_interval = section['query_interval_seconds'].to_i
						end
						if section.has_option?('query_interval_skip')
							my_skip = section['query_interval_skip'].to_i
						end
						# Begin snmp_values_dynamic section parsing loop.
						for value in section
							if value.key != 'type' && value.key != 'query_interval_seconds' &&
							value.key != 'query_interval_skip' && value.value.length > 0
								if snmp_vars.include?(value.value) == false
									snmp_vars << Array[value.value, false, my_interval, my_skip]
								end
							end
						end # End snmp_values_dynamic section parsing loop.

						# Clean up.
						my_interval = nil
						my_skip = nil
					else
						if section['type'] == 'snmp_values_static'
							# Set vars.
							my_interval = 0
							my_skip = 0

							# Check for host section default overrides.
							if section.has_option?('query_interval_seconds')
								my_interval = section['query_interval_seconds'].to_i
							end
							if section.has_option?('query_interval_skip')
								my_skip = section['query_interval_skip'].to_i
							end
							# Begin snmp_values_static section parsing loop.
							for value in section
								if value.key != 'type' && value.key != 'query_interval_seconds' &&
								value.key != 'query_interval_skip' && value.value.length > 0
									if snmp_vars.include?(value.value) == false
										snmp_vars << Array[value.value, true, my_interval, my_skip]
									end
								end
							end # End snmp_values_static section parsing loop.

							# Clean up.
							my_interval = nil
							my_skip = nil
						else
							if section['type'] == 'snmp_host'
								host = section
								if	host.has_option?('address') && host['address'].length > 0
									host.has_option?('query_interval_seconds') && host['query_interval_seconds'].to_i > 0 &&
									host.has_option?('query_interval_skip')
									host.has_option?('snmp_version')

									if host['snmp_version'].to_i == 3

										if host.has_option?('username') && host['username'].length > 0 &&
										host.has_option?('context') && host['context'].length > 0

											temp = Array.new
											temp << host['address'] << host['query_interval_seconds'].to_i
											temp << host['query_interval_skip'].to_i << host['snmp_version'].to_i
											temp << host['username']

											# These are optional.
											if host.has_option?('auth_password') && host['auth_password'].length > 0 &&
											host.has_option?('auth_protocol') && host['auth_protocol'].length > 0

												temp << host['auth_password']
												temp << host['auth_protocol']
												if host.has_option?('priv_password') && host['priv_password'].length > 0 &&
												host.has_option?('priv_protocol') && host['priv_protocol'].length > 0
													# Priv password and protocol.
													temp << host['priv_password']
													temp << host['priv_protocol']
												else
													# No priv_password, or protocol.
													temp << nil << nil
												end
											else
												# No auth password or protocol (Priv password / protocol is ignored in this case.)
												temp << nil << nil << nil << nil
											end
	
											# Add the context.
											temp << host['context']

											# Append the new host to the list.
											hosts << temp
										else
											# Invalid SNMP host version 3 section.
											next
										end
									else
										if host.has_option?('community') && host['community'].length > 0
											temp = Array.new
											temp << host['address'] << host['query_interval_seconds'].to_i
											temp << host['query_interval_skip'].to_i << host['snmp_version'].to_i
											temp << host['community']

											# Append the new host to the list.
											hosts << temp
										else
											# Invalid SNMP host version 1 / 2 section.
											next
										end
									end
								else
									puts "WARNING: Missing a required option in a hosts section #{host.key}, skipping section.\n"
								end
							end
						end
					end
				end
			end
		end

		if $my_dry_run
			print "INFO: Read config file at ( #{cFile} ).\n"		
			print "INFO: DB Server: ( #{db_info[0]} ), Username: ( #{db_info[1]} ), Database: ( #{db_info[3]} ).\n"
			print "INFO: Number of snmp_values in config: #{snmp_vars.length}\n"
			for i in (0...snmp_vars.length)
				print "INFO: SNMP_VALUES[#{i}]: #{snmp_vars[i][0]} Static Type: #{snmp_vars[i][1]} "
				print "Override Hosts Query Interval (Secs.): #{snmp_vars[i][2] != 0 ? snmp_vars[i][2] : false}. "
				print "Override Hosts Query Interval Skip (Secs.): #{snmp_vars[i][3] != 0 ? snmp_vars[i][3] : false}.\n"
			end
			print "INFO: Number of hosts in config: #{hosts.length}\n"
			for i in (0...hosts.length)
				print "INFO: HOST[#{i}]: Hostname: #{hosts[i][0]} Query Interval (Secs.): #{hosts[i][1]} "
				print "Query Interval Skip (Secs.): #{hosts[i][2]} SNMP Ver: #{hosts[i][3]} "
				if hosts[i][2] == 3
					print "Username: #{hosts[i][4]} Auth Password Defined: #{hosts[i][5] != nil} "
					print "Auth Protocol Given: #{hosts[i][6]} "
					print "Priv Password Defined: #{hosts[i][7] != nil} Priv Protocol Given: #{hosts[i][8]} "
					print "Context: #{hosts[i][9]}\n"
				else
					print "Community: #{hosts[i][4]}\n"
				end
			end
		end

		# Clean up and set return values.
		configFile = nil
		if ret == nil || hosts.length <= 0 || snmp_vars.length <= 0
			hosts = nil
			snmp_vars = nil
			db_info = nil
		else
			ret = 1
		end

		return ret, hosts, snmp_vars, db_info
	rescue Exception => e
		# Exception.
		configFile = nil
		hosts = nil
		intervals = nil
		db_info = nil
		if $my_dry_run
			puts "ERROR: Unable to read config file at ( #{cFile} ).\nException Raised: #{e}\n"
		end
		return nil
	end

	# This should not execute, but in case it does...
	return nil
end

def mysql_connect(server, username, password, dbname)
	dbh = nil
	begin
		dbh = Mysql2::Client.new(:host => server, :username => username, :password => password, :database => dbname)
	rescue Exception => e
		dbh = nil
		if $my_dry_run
			puts "ERROR: Unable to connect to ( #{server}/#{dbname} ).\nException Raised: #{e}\n"
		end
	end
	return dbh
end

def mysql_close(dbh)
	if dbh
		dbh.close
	end
end

# Mysql datatypes (At least the ones we use...)
DB_SHOW_COL_DATATYPE_INT = "INTEGER"
DB_SHOW_COL_DATATYPE_BIGINT = "BIGINT"
DB_SHOW_COL_DATATYPE_TEXT = "TEXT"
DB_SHOW_COL_DATATYPE_DATETIME = "DATETIME"

# Names of the mysql show columns output.
DB_SHOW_COL_FIELD = "Field"
DB_SHOW_COL_TYPE = "Type"
DB_SHOW_COL_NULL = "Null"
DB_SHOW_COL_KEY = "Key"
DB_SHOW_COL_DEFAULT = "Default"
DB_SHOW_COL_EXTRA = "Extra"
DB_SHOW_COL_VAL_NO = "NO"
DB_SHOW_COL_VAL_YES = "YES"
DB_SHOW_COL_VAL_NULL = "NULL"
DB_SHOW_COL_VAL_NOW = "NOW()"
DB_SHOW_COL_VAL_AUTOINC = "auto_increment"
DB_SHOW_COL_VAL_ONUPCURTIME = "on update current_timestamp()"
DB_SHOW_COL_VAL_CURRENTTS = "current_timestamp()"
DB_SHOW_COL_VAL_PRI = "PRI"
DB_SHOW_COL_VAL_UNI = "UNI"
DB_SHOW_COL_VAL_MUL = "MUL"
DB_SHOW_COL_VAL_UNSIGNED = "unsigned"

# Foreign key info. (When used on a column, that column becomes a foreign key that refs the tbl/col defined with the keys below.)
DB_FK_REF_TBL_NAME = "FK_REF_TBL_NAME"
DB_FK_REF_COL_NAME = "FK_REF_COL_NAME"

# AUTO INSERT ON CREATE TABLE FLAG. (When used on a column, It tells us insert the column with the default value after the table is created.)
DB_AUTO_INSERT_CT_FLAG = "AUTO_INSERT_CT_FLAG"

# Unique constraint array label. (When used on a column, makes the column part of the unique constraint defined with the key below.)
DB_UNI_CONST_NAME = "UNI_CONST_NAME"

# Unsigned flag. (When used on a column defintion, makes the column an unsigned column.)
DB_SET_UNSIGNED_FLAG = "SET_UNSIGNED_FLAG"

# Generic primary key name.
DB_VALUE_PK_NAME = "entry_id"

# Current database version that this script supports.
CURRENT_DB_MAJOR_VERSION = 1

# Names of the version mysql table.
DB_TBL_NAME_VERSION = "version"
DB_VERSION_COL_VERMAJOR = "major_version"

# tblArr format of the version mysql table.
DB_VERSION_tblArr = Array[Hash[DB_SHOW_COL_FIELD => DB_VERSION_COL_VERMAJOR, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_INT, DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO,
			DB_SHOW_COL_KEY => DB_SHOW_COL_VAL_UNI, DB_SHOW_COL_DEFAULT => CURRENT_DB_MAJOR_VERSION.to_s, DB_SHOW_COL_EXTRA => "",
			DB_AUTO_INSERT_CT_FLAG => 1],
			Hash[DB_SHOW_COL_FIELD => DB_VALUE_PK_NAME, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_INT, DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO,
			DB_SHOW_COL_KEY => DB_SHOW_COL_VAL_PRI, DB_SHOW_COL_DEFAULT => "", DB_SHOW_COL_EXTRA => DB_SHOW_COL_VAL_AUTOINC]]

# Names of the hosts mysql table.
DB_TBL_NAME_HOSTS = "hosts"
DB_HOSTS_COL_HOSTNAME = "hostname"

# tblArr format of the hosts mysql table.
DB_HOSTS_tblArr = Array[Hash[DB_SHOW_COL_FIELD => DB_HOSTS_COL_HOSTNAME, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_TEXT, DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO,
			DB_SHOW_COL_KEY => DB_SHOW_COL_VAL_UNI, DB_SHOW_COL_DEFAULT => "", DB_SHOW_COL_EXTRA => ""],
			Hash[DB_SHOW_COL_FIELD => DB_VALUE_PK_NAME, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_INT, DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO,
			DB_SHOW_COL_KEY => DB_SHOW_COL_VAL_PRI, DB_SHOW_COL_DEFAULT => "", DB_SHOW_COL_EXTRA => DB_SHOW_COL_VAL_AUTOINC]]

# Names of the snmp_value_ids mysql table.
DB_TBL_NAME_SNMP_VALUE_IDS = "snmp_value_ids"
DB_SNMP_VALUE_IDS_COL_ENTRY_NAME = "entry_name"

# tblArr format of the snmp_value_ids mysql table.
DB_SNMP_VALUE_IDS_tblArr = Array[Hash[DB_SHOW_COL_FIELD => DB_SNMP_VALUE_IDS_COL_ENTRY_NAME, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_TEXT,
			DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO,	DB_SHOW_COL_KEY => DB_SHOW_COL_VAL_UNI, DB_SHOW_COL_DEFAULT => "",
			DB_SHOW_COL_EXTRA => ""],
			Hash[DB_SHOW_COL_FIELD => DB_VALUE_PK_NAME, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_INT, DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO,
			DB_SHOW_COL_KEY => DB_SHOW_COL_VAL_PRI, DB_SHOW_COL_DEFAULT => "", DB_SHOW_COL_EXTRA => DB_SHOW_COL_VAL_AUTOINC]]

# Names of the snmp_values_dynamic mysql table.
DB_TBL_NAME_SNMP_VALUES_DYNAMIC = "snmp_values_dynamic"
DB_SNMP_VALUES_FK_VALUEID = "fk_valueID"
DB_SNMP_VALUES_FK_HOSTID = "fk_hostID"
DB_SNMP_VALUES_COL_ENTRY_TIME = "entry_time"
DB_SNMP_VALUES_COL_ENTRY_VALUE = "entry_value"
DB_SNMP_VALUES_DYNAMIC_UNI_CONST_NAME = "snmp_vals_dynamic_unique"

# tblArr format of the snmp_values_dynamic mysql table.
DB_SNMP_VALUES_DYNAMIC_tblArr = Array[Hash[DB_SHOW_COL_FIELD => DB_SNMP_VALUES_FK_HOSTID, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_INT,
				DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO, DB_SHOW_COL_KEY => DB_SHOW_COL_VAL_MUL, DB_SHOW_COL_DEFAULT => "",
				DB_SHOW_COL_EXTRA => "", DB_FK_REF_TBL_NAME => DB_TBL_NAME_HOSTS, DB_FK_REF_COL_NAME => DB_VALUE_PK_NAME,
				DB_UNI_CONST_NAME => DB_SNMP_VALUES_DYNAMIC_UNI_CONST_NAME],
				#
				Hash[DB_SHOW_COL_FIELD => DB_SNMP_VALUES_FK_VALUEID, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_INT,
				DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO, DB_SHOW_COL_KEY => DB_SHOW_COL_VAL_MUL, DB_SHOW_COL_DEFAULT => "",
				DB_SHOW_COL_EXTRA => "", DB_FK_REF_TBL_NAME => DB_TBL_NAME_SNMP_VALUE_IDS, DB_FK_REF_COL_NAME => DB_VALUE_PK_NAME,
				DB_UNI_CONST_NAME => DB_SNMP_VALUES_DYNAMIC_UNI_CONST_NAME],
				#
				Hash[DB_SHOW_COL_FIELD => DB_SNMP_VALUES_COL_ENTRY_TIME, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_DATETIME,
				DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO, DB_SHOW_COL_KEY => "", DB_SHOW_COL_DEFAULT => DB_SHOW_COL_VAL_CURRENTTS,
				DB_SHOW_COL_EXTRA => "", DB_UNI_CONST_NAME => DB_SNMP_VALUES_DYNAMIC_UNI_CONST_NAME],
				#
				Hash[DB_SHOW_COL_FIELD => DB_SNMP_VALUES_COL_ENTRY_VALUE, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_TEXT,
				DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO, DB_SHOW_COL_KEY => "", DB_SHOW_COL_DEFAULT => "",
				DB_SHOW_COL_EXTRA => ""],
				#
				Hash[DB_SHOW_COL_FIELD => DB_VALUE_PK_NAME, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_BIGINT, DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO,
				DB_SHOW_COL_KEY => DB_SHOW_COL_VAL_PRI, DB_SHOW_COL_DEFAULT => "", DB_SHOW_COL_EXTRA => DB_SHOW_COL_VAL_AUTOINC,
				DB_SET_UNSIGNED_FLAG => true]]

# Names of the snmp_values_static mysql table.
DB_TBL_NAME_SNMP_VALUES_STATIC = "snmp_values_static"
DB_SNMP_VALUES_STATIC_UNI_CONST_NAME = "snmp_vals_static_unique"

# tblArr format of the snmp_values_static mysql table.
DB_SNMP_VALUES_STATIC_tblArr = Array[Hash[DB_SHOW_COL_FIELD => DB_SNMP_VALUES_FK_HOSTID, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_INT,
				DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO, DB_SHOW_COL_KEY => DB_SHOW_COL_VAL_MUL, DB_SHOW_COL_DEFAULT => "",
				DB_SHOW_COL_EXTRA => "", DB_FK_REF_TBL_NAME => DB_TBL_NAME_HOSTS, DB_FK_REF_COL_NAME => DB_VALUE_PK_NAME,
				DB_UNI_CONST_NAME => DB_SNMP_VALUES_STATIC_UNI_CONST_NAME],
				#
				Hash[DB_SHOW_COL_FIELD => DB_SNMP_VALUES_FK_VALUEID, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_INT,
				DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO, DB_SHOW_COL_KEY => DB_SHOW_COL_VAL_MUL, DB_SHOW_COL_DEFAULT => "", DB_SHOW_COL_EXTRA => "",
				DB_FK_REF_TBL_NAME => DB_TBL_NAME_SNMP_VALUE_IDS, DB_FK_REF_COL_NAME => DB_VALUE_PK_NAME,
				DB_UNI_CONST_NAME => DB_SNMP_VALUES_STATIC_UNI_CONST_NAME],
				#
				Hash[DB_SHOW_COL_FIELD => DB_SNMP_VALUES_COL_ENTRY_TIME, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_DATETIME,
				DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO, DB_SHOW_COL_KEY => "", DB_SHOW_COL_DEFAULT => DB_SHOW_COL_VAL_CURRENTTS,
				DB_SHOW_COL_EXTRA => DB_SHOW_COL_VAL_ONUPCURTIME],
				#
				Hash[DB_SHOW_COL_FIELD => DB_SNMP_VALUES_COL_ENTRY_VALUE, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_TEXT,
				DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO, DB_SHOW_COL_KEY => "", DB_SHOW_COL_DEFAULT => "",
				DB_SHOW_COL_EXTRA => ""],
				#
				Hash[DB_SHOW_COL_FIELD => DB_VALUE_PK_NAME, DB_SHOW_COL_TYPE => DB_SHOW_COL_DATATYPE_BIGINT, DB_SHOW_COL_NULL => DB_SHOW_COL_VAL_NO,
				DB_SHOW_COL_KEY => DB_SHOW_COL_VAL_PRI, DB_SHOW_COL_DEFAULT => "", DB_SHOW_COL_EXTRA => DB_SHOW_COL_VAL_AUTOINC,
				DB_SET_UNSIGNED_FLAG => true]]

if $my_create_tables || $my_force_table_creation
	def create_mysql_table(dbh, tblName, tblArr)
		# Init ret code.
		ret = 0

		if dbh != nil && tblName != nil && tblName.length > 0 && tblArr != nil && tblArr.kind_of?(Array) && tblArr.length > 0

			# Init vars.
			found_col = false
			stmt = ""
			pkstmt = ""
			fkstmt = ""
			aiFstmt = ""
			aiVstmt = ""
			uniHash = Hash.new

			# Begin constructing the create table statement.
			stmt += "CREATE TABLE IF NOT EXISTS #{tblName} ( "

			# Start iteration of the tblArr.
			for col in tblArr

				# Reset colTemp.
				colStr = nil

				if 	col.kind_of?(Hash) && col.key?(DB_SHOW_COL_FIELD) && col.key?(DB_SHOW_COL_TYPE) &&
					col.key?(DB_SHOW_COL_NULL) && col.key?(DB_SHOW_COL_KEY) && col.key?(DB_SHOW_COL_DEFAULT)

					# Check the values and make sure they are valid.
					if	col[DB_SHOW_COL_FIELD].length > 0 && col[DB_SHOW_COL_TYPE].length > 0 && col[DB_SHOW_COL_NULL].length > 0

						colStr = "#{col[DB_SHOW_COL_FIELD]} #{col[DB_SHOW_COL_TYPE]} "

						if col.has_key?(DB_SET_UNSIGNED_FLAG) && col[DB_SET_UNSIGNED_FLAG]
							colStr += "UNSIGNED "
						end

						if col[DB_SHOW_COL_NULL] == DB_SHOW_COL_VAL_NO
							colStr += "NOT NULL "
						end

						# Check if we need to set auto_increment.
						if col.key?(DB_SHOW_COL_EXTRA) && col[DB_SHOW_COL_EXTRA] == DB_SHOW_COL_VAL_AUTOINC
							colStr += "AUTO_INCREMENT "
						else
							# Check if we need to set current time stamp on update.
							if col.key?(DB_SHOW_COL_EXTRA) && col[DB_SHOW_COL_EXTRA] == DB_SHOW_COL_VAL_ONUPCURTIME
								colStr += "ON UPDATE CURRENT_TIMESTAMP() "
							end
						end

						# Check if we need to add a default.
						if col[DB_SHOW_COL_DEFAULT].length > 0
							colStr += "DEFAULT #{col[DB_SHOW_COL_DEFAULT]} "
						end

						# Check if we need to add a constraint.
						if col[DB_SHOW_COL_KEY] == DB_SHOW_COL_VAL_UNI
							# Check if this is part of a more complicated unique constraint.
							if col.key?(DB_UNI_CONST_NAME) && col[DB_UNI_CONST_NAME].length > 0
								if uniHash.key?(col[DB_UNI_CONST_NAME])
									if 	uniHash[col[DB_UNI_CONST_NAME]].kind_of?(Array) &&
										uniHash[col[DB_UNI_CONST_NAME]].length > 0
										# Existing unique constraint.
										uniHash[col[DB_UNI_CONST_NAME]] << col[DB_SHOW_COL_FIELD]
									else
										# Name conflict with existing unique column.
										print "ERROR: Unique constraint name conflicts with a "
										print "simple unique column name in table ( #{tblName} ).\n"
										stmt = nil
										break
									end
								else
									# New unique constraint.
									uniHash[col[DB_UNI_CONST_NAME]] = Array[col[DB_SHOW_COL_FIELD]]
									uniHash.rehash
								end
							else
								# Check for a foreign key.
								if 	((col.key?(DB_FK_REF_TBL_NAME) && col[DB_FK_REF_TBL_NAME].length > 0
									col.key?(DB_FK_REF_COL_NAME) && col[DB_FK_REF_COL_NAME].length > 0) == false)
									# New simple unique column.
									uniHash[col[DB_SHOW_COL_FIELD]] = "UNIQUE (#{col[DB_SHOW_COL_FIELD]}) "
									uniHash.rehash
								end
							end
						else
							if col[DB_SHOW_COL_KEY] == DB_SHOW_COL_VAL_MUL
								# Check if this is part of a more complicated unique constraint.
								if col.key?(DB_UNI_CONST_NAME) && col[DB_UNI_CONST_NAME].length > 0
									if uniHash.key?(col[DB_UNI_CONST_NAME])
                                                                   	     if	uniHash[col[DB_UNI_CONST_NAME]].kind_of?(Array) &&
										uniHash[col[DB_UNI_CONST_NAME]].length > 0
                                                                                	# Existing unique constraint.
	                                                                                uniHash[col[DB_UNI_CONST_NAME]] << col[DB_SHOW_COL_FIELD]
        	                                                                else
                	                                                                # Name conflict with existing unique column.
                        	                                                        print "ERROR: Unique constraint name conflicts with a "
                                	                                                print "simple unique column name in table ( #{tblName} ).\n"
                                        	                                        stmt = nil
                                                	                                break
                                                        	                end
	                                                                else
        	                                                                # New unique constraint.
                	                                                        uniHash[col[DB_UNI_CONST_NAME]] = Array[col[DB_SHOW_COL_FIELD]]
                        	                                                uniHash.rehash
                                	                                end
								else
									# Not sure what this is, abort.
									print "ERROR: Multiple key type given for column ( #{col[DB_SHOW_COL_FIELD]} ) "
									print "without a unique constraint name in table ( #{tblName} ).\n"
									stmt = nil
									break
								end
							else
								if col[DB_SHOW_COL_KEY] == DB_SHOW_COL_VAL_PRI
									if pkstmt.length == 0
										pkstmt = "PRIMARY KEY (#{col[DB_SHOW_COL_FIELD]}) "
									else
										print "ERROR: Multiple primary key constraints defined for table ( #{tblName} ).\n"
										stmt = nil
										break
									end
								else
									# Check if this is a composite key.
									if col.key?(DB_UNI_CONST_NAME) && col[DB_UNI_CONST_NAME].length > 0

										if uniHash.key?(col[DB_UNI_CONST_NAME])
											if uniHash[col[DB_UNI_CONST_NAME]].kind_of?(Array) &&
											uniHash[col[DB_UNI_CONST_NAME]].length > 0
												# Existing unique constraint.
												uniHash[col[DB_UNI_CONST_NAME]] << col[DB_SHOW_COL_FIELD]
											else
												# Name conflict with existing unique column.
												print "ERROR: Unique constraint name conflicts with a "
												print "simple unique column name in table ( #{tblName} ).\n"
												stmt = nil
												break
											end
										else
											# New unique constraint.
											uniHash[col[DB_UNI_CONST_NAME]] = Array[col[DB_SHOW_COL_FIELD]]
											uniHash.rehash
										end
									end
								end
							end
						end

						# Check if this has a foreign key constraint.
						if	col.key?(DB_FK_REF_TBL_NAME) && col[DB_FK_REF_TBL_NAME].length > 0 &&
							col.key?(DB_FK_REF_COL_NAME) && col[DB_FK_REF_COL_NAME].length > 0

							if fkstmt.length > 0
								fkstmt += ", "
							end
							fkstmt += "FOREIGN KEY (#{col[DB_SHOW_COL_FIELD]}) "
							fkstmt += "REFERENCES #{col[DB_FK_REF_TBL_NAME]}(#{col[DB_FK_REF_COL_NAME]}) "
							fkstmt += "ON UPDATE CASCADE ON DELETE CASCADE "

						end

						# Check if we need to create an auto insert string.
						if col.key?(DB_AUTO_INSERT_CT_FLAG)
							# Add the column to the auto insert string.
							if aiFstmt.length > 0
								aiFstmt += ", "
								aiVstmt += ", "
							end
							aiFstmt += col[DB_SHOW_COL_FIELD]
							aiVstmt += col[DB_SHOW_COL_DEFAULT]
						end

						# If colStr is valid add it to the stmt.
						if colStr != nil
							if found_col == true
								stmt += ", "
							end
							stmt += colStr
							if found_col == false
								found_col = true
							end
						end
					else
						# Invalid column definition.
						print "ERROR: Invalid column definition in table ( #{tblName} ), please report this to the developer.\n"
						stmt = nil
						break
					end
				else
					# Invalid table definition.
					print "ERROR: Invalid table definition for table ( #{tblName} ), please report this to the developer.\n"
					stmt = nil
					break
				end
			end # End iteration of the tblArr.

			# Check if we still have a statement to execute.
			if stmt != nil

				# Generate the unique constraint statements.
				uniHash.each_pair do | key, uni |
					if uni.kind_of?(String)
						stmt += ", "
						stmt += uni
					else
						if uni.kind_of?(Array)
							stmt += ", CONSTRAINT #{key} UNIQUE ( "
							for i in (0...uni.length)
								stmt += uni[i]
								if (i + 1) < uni.length
									stmt += ", "
								end
							end
							stmt += " ) "
						end
					end
				end

				# Combine the remaining strings.
				if pkstmt != nil && pkstmt.length > 0
					stmt += ", "
					stmt += pkstmt
				end
				if fkstmt != nil && fkstmt.length > 0
					stmt += ", "
					stmt += fkstmt
				end

				# Close the table statement.
				stmt += " ) "

				# Create the auto insert statement.
				aistmt = nil
				if aiFstmt != nil && aiVstmt != nil && aiFstmt.length > 0 && aiVstmt.length > 0
					aistmt = "INSERT INTO #{tblName} ( #{aiFstmt} ) "
					aistmt += "VALUES ( #{aiVstmt} ) "
				end

				begin
					# Execute the statement.
					if $my_dry_run
						print "INFO: Dry run mode, not actually creating tables. Query that would be executed printed below:\n"
						print "#{stmt}; "
						if aistmt != nil
							print "#{aistmt}; "
						end
						print "\n"
					else
						dbh.query(stmt)

						if aistmt != nil
							dbh.query(aistmt)
						end	
					end
					ret = 1
				rescue Exception => e
					print "ERROR: Unable to create table ( #{tblName} ).\nError Message: "
					puts e
					ret = 0
				end
			end
		end

		return ret
	end
end

def get_table_column_names(dbh, tbl)
	ret = Array.new
	temp = Array.new
	ret << 0
	if dbh != nil && tbl.length > 0
		begin
			dbh.query("SHOW COLUMNS FROM #{DB_TBL_NAME_HOSTS};").each do | field, type, nullable, key, default_value, extra_data |
				if field.length > 0
					temp << field
				end
			end

			if temp.length > 0
				ret[0] = 1
				ret << temp
			end
		rescue Exception => e
			ret[0] = 0
			if $my_dry_run
				puts "ERROR: Unable to fetch column names.\nERROR: Exception Raised: #{e}\n"
			end
		end
	end
	return ret
end

def verify_mysql_data_type(src, check, unsigned)
	ret = 0
	if check == nil
		if src.length == 0
			ret = 1
		end
	else
		mycheck = check.upcase
		if src == DB_SHOW_COL_DATATYPE_INT
			if mycheck[0..2] == "INT"
				ret = 1
			end
		else
			if src == DB_SHOW_COL_DATATYPE_BIGINT
				if mycheck[0..5] == "BIGINT"
					ret = 1
				end
			else
				if src == mycheck
					ret = 1
				end
			end
		end
		if ret == 1 && unsigned != nil
			if unsigned
				if !mycheck.include?("UNSIGNED")
					ret = 0
				end
			else
				if mycheck.include?("UNSIGNED")
					ret = 0
				end
			end
		end
		mycheck = nil
	end
	return ret
end

#
# tblArr format:
# 	{ Hash: {"field" => name of the column, "type" => column data type, "null" => can column be null, "key" => is column a key, "default" => default value for column, "extra" (optional) => extra field in mysql for the column. } }
#
#	Each index in the tblArr is a Hash object that contains the same column data as returned by the
#	"SHOW COLUMNS FROM #{tblName}" mysql query.
#
#	All data is required except the "extra" column. (As it's not always used / defined in mysql.)
#
#	Returns 1 if verification succeeds, otherwise returns 0.
def check_table_columns(dbh, tblName, tblArr)
	ret = 0
	if dbh != nil && tblName != nil && tblName.length > 0 && tblArr != nil && tblArr.kind_of?(Array) && tblArr.length > 0
		begin
			# Get the table.
			results = dbh.query("SHOW COLUMNS FROM #{tblName};")

			for col in tblArr
				if col.kind_of?(Hash) && col.key?(DB_SHOW_COL_FIELD) &&
				col.key?(DB_SHOW_COL_TYPE) && col.key?(DB_SHOW_COL_NULL) &&
				col.key?(DB_SHOW_COL_KEY) && col.key?(DB_SHOW_COL_DEFAULT)
					# Reset found_col.
					found_col = false
					# Begin query.
					results.each(:as => :array) do | row |
						if row.length == 6
						#row format:  field, type, nullable, key, default_value, extra_data
							# Check for the correct field.
							if row[0] == col[DB_SHOW_COL_FIELD]
								# Pre-emptively set the flag.
								found_col = true

								# Check type.
								if verify_mysql_data_type(col[DB_SHOW_COL_TYPE], row[1],
								col.has_key?(DB_SET_UNSIGNED_FLAG) ? col[DB_SET_UNSIGNED_FLAG] : nil) != 1
									found_col = false
									if $my_dry_run
										print "INFO: Invalid type for #{row[0]}: is "
										if row[1] == nil
											print "\'\' "
										else
											print "#{row[1]} "
										end
										print "should be #{col[DB_SHOW_COL_TYPE]}.\n"
									end
								end

								# Check NULL column.
								if row[2] != col[DB_SHOW_COL_NULL]
									found_col = false
									if $my_dry_run
										print "INFO: Invalid null for #{row[0]}: is [#{row[2]}] "
										print "should be [#{col[DB_SHOW_COL_NULL]}].\n"
									end
								end

								# Check key.
								if row[3] != col[DB_SHOW_COL_KEY]
									found_col = false
									if $my_dry_run
										print "INFO: Invalid key for #{row[0]}: is [#{row[3]}] "
										print "should be [#{col[DB_SHOW_COL_KEY]}].\n"
									end
								end

								# Perform optional col checks.
								if col[DB_SHOW_COL_DEFAULT].length > 0
									if row[4] != col[DB_SHOW_COL_DEFAULT]
										found_col = false
										if $my_dry_run
											print "INFO: Invalid default for #{row[0]}: is [#{row[4]}] "
											print "should be [#{col[DB_SHOW_COL_DEFAULT]}]\n"
										end
									end
								else
									if row[4] != nil && row[4].length != 0
										found_col = false
										if $my_dry_run
											puts "INFO: Invalid default for #{row[0]}: is [#{row[4]}] should be [\'\']\n"
										end
									end
								end
								if col.key?(DB_SHOW_COL_EXTRA) && col[DB_SHOW_COL_EXTRA].length > 0
									if row[5] != col[DB_SHOW_COL_EXTRA]
										found_col = false
										if $my_dry_run
											print "INFO: Invalid extra for #{row[0]}: is [#{row[5]}] "
											print "should be [#{col[DB_SHOW_COL_EXTRA]}]\n"
										end
									end
								else
									if row[5] != nil && row[5].length != 0
										found_col = false
										if $my_dry_run
											puts "INFO: Invalid extra for #{row[0]}: is [#{row[5]}] should be [\'\']\n"
										end
									end
								end
								break
							end
						end
					end

					if found_col == false
						# Column doesn't match the given config in tblName.
						break
					end
				end
			end

			# If we get here, and found_col is true, we've verified the entire table.
			if found_col == true
				ret = 1
			end
		rescue Exception => e
			ret = 0
			if $my_dry_run
				puts "ERROR: Could not verify table structure for table #{tblName}.\nERROR: Exception Raised: #{e}\n"
			end
		end
	end
	return ret
end

def check_needed_table_structures(dbh)
	ret = 0

	found_version = false
	found_hosts = false
	found_value_ids = false
	found_values_dynamic = false
	found_values_static = false

	if (dbh != nil)
		begin
			dbh.query("SHOW TABLES;").each(:as => :array) do | row |
				row.each do | tbl |
					if tbl == DB_TBL_NAME_VERSION
						found_version = true
						next
					end
					if tbl == DB_TBL_NAME_HOSTS
						found_hosts = true
						next
					end
					if tbl == DB_TBL_NAME_SNMP_VALUE_IDS
						found_value_ids = true
						next
					end
					if tbl == DB_TBL_NAME_SNMP_VALUES_DYNAMIC
						found_values_dynamic = true
						next
					end
					if tbl == DB_TBL_NAME_SNMP_VALUES_STATIC
						found_values_static = true
						next
					end
				end
			end
		rescue Exception => e
			ret = 0
			if $my_dry_run
				puts "ERROR: Could not search tables.\nException Raised: #{e}\n"
			end
		end

		# Check if we found all of the tables.
		if found_version && found_hosts && found_value_ids && found_values_dynamic
			# Check the tables.
			begin
				# Reset the vars.
				found_version = false
				found_hosts = false
				found_value_ids = false
				found_values_dynamic = false
				found_values_static = false

				# Check the version table.
				dbh.query("SELECT #{DB_VERSION_COL_VERMAJOR} FROM #{DB_TBL_NAME_VERSION};").each(:as => :array) do | row |
					row.each do | ver |
						if ver == CURRENT_DB_MAJOR_VERSION
							found_version = true
							break
						end
					end
					if found_version
						break
					end
				end
				if found_version == false
					if $my_dry_run
						puts "ERROR: Table #{DB_TBL_NAME_VERSION} is invalid.\n"
					end
				end

				if check_table_columns(dbh, DB_TBL_NAME_HOSTS, DB_HOSTS_tblArr) == 1
					found_hosts = true
				else
					if $my_dry_run
						puts "ERROR: Table #{DB_TBL_NAME_HOSTS} is invalid.\n"
					end
				end

				if check_table_columns(dbh, DB_TBL_NAME_SNMP_VALUE_IDS, DB_SNMP_VALUE_IDS_tblArr) == 1
					found_value_ids = true
				else
					if $my_dry_run
						puts "ERROR: Table #{DB_TBL_NAME_SNMP_VALUE_IDS} is invalid.\n"
					end
				end

				if check_table_columns(dbh, DB_TBL_NAME_SNMP_VALUES_DYNAMIC, DB_SNMP_VALUES_DYNAMIC_tblArr) == 1
					found_values_dynamic = true
				else
					if $my_dry_run
						puts "ERROR: Table #{DB_TBL_NAME_SNMP_VALUES_DYNAMIC} is invalid.\n"
					end
				end

				if check_table_columns(dbh, DB_TBL_NAME_SNMP_VALUES_STATIC, DB_SNMP_VALUES_STATIC_tblArr) == 1
					found_values_static = true
				else
					if $my_dry_run
						puts "ERROR: Table #{DB_TBL_NAME_SNMP_VALUES_STATIC} is invalid.\n"
					end
				end

				# Final check.
				if found_version && found_hosts && found_value_ids && found_values_dynamic && found_values_static
					ret = 1
				end
			rescue Exception => e
				ret = 0
				if $my_dry_run
					puts "ERROR: Could not search tables.\nException Raised: #{e}\n"
				end
			end
		else
			if $my_dry_run
				if !found_version
					puts "ERROR: Table #{DB_TBL_NAME_VERSION} not found.\n"
				end
				if !found_hosts
					puts "ERROR: Table #{DB_TBL_NAME_HOSTS} not found.\n"
				end
				if !found_value_ids
					puts "ERROR: Table #{DB_TBL_NAME_SNMP_VALUE_IDS} not found.\n"
				end
				if !found_values_dynamic
					puts "ERROR: Table #{DB_TBL_NAME_SNMP_VALUES_DYNAMIC} not found.\n"
				end
				if !found_values_static
					puts "ERROR: Table #{DB_TBL_NAME_SNMP_VALUES_STATIC} not found.\n"
				end
			end
		end
	end

	return ret
end

def insert_new_hosts_into_db(dbh, hostsArr)
	ret = 0
	sel_stmt = "SELECT #{DB_HOSTS_COL_HOSTNAME} FROM #{DB_TBL_NAME_HOSTS} WHERE #{DB_HOSTS_COL_HOSTNAME}=\'"
	ins_stmt = "INSERT INTO #{DB_TBL_NAME_HOSTS} (#{DB_HOSTS_COL_HOSTNAME}) VALUES (\'"

	if dbh != nil && hostsArr.kind_of?(Array) && hostsArr.length > 0
		for i in (0...hostsArr.length)
			host = hostsArr[i]
			if host.kind_of?(Array) && host.length > 0 && host[0].length > 0
				results = nil
				sl = ""
				begin
					# Check if the database has this host in it's hosts table.
					sl << sel_stmt << "#{host[0]}\';"
					results = dbh.query(sl)
				rescue Exception => e
					puts "ERROR: Unable to check for host #{host[0]} in database. Exception Raised: #{e}\n"
					break
				end

				# Check for data.
				if results == nil || results.size == 0
					# Reset results.
					results = nil

					# Need to add the host.
					sl = ""
					sl << ins_stmt << "#{host[0]}\');"
					begin
						if $my_dry_run
							puts "INFO: DRY RUN mode enabled. Query that would have been executed is printed below:\nINFO: #{sl}\n"
						else
							# Actually excute the query.
							dbh.query(sl)
						end
					rescue Exception => e
						puts "ERROR: Unable to insert host #{host[0]} into database. Exception Raised: #{e}\n"
						break
					end
				end

				# Check if we are done.
				if (i + 1) >= hostsArr.length
					ret = 1
				end
			end
		end
	end
	return ret
end

def insert_new_snmp_val_ids_into_db(dbh, snmp_varsArr)
	ret = 0
	sel_stmt = "SELECT #{DB_SNMP_VALUE_IDS_COL_ENTRY_NAME} FROM #{DB_TBL_NAME_SNMP_VALUE_IDS} WHERE #{DB_SNMP_VALUE_IDS_COL_ENTRY_NAME}=\'"
	ins_stmt = "INSERT INTO #{DB_TBL_NAME_SNMP_VALUE_IDS} (#{DB_SNMP_VALUE_IDS_COL_ENTRY_NAME}) VALUES (\'"

	if dbh != nil && snmp_varsArr.kind_of?(Array) && snmp_varsArr.length > 0
		for i in (0...snmp_varsArr.length)
			var = snmp_varsArr[i][0]
			if var.length > 0
				results = nil
				sl = ""
				begin
					# Check if the database has this var in it's snmp_value_ids table.
					sl << sel_stmt << "#{var}\';"
					results = dbh.query(sl)
				rescue Exception => e
					puts "ERROR: Unable to check for snmp value ID #{var} in database. Exception Raised: #{e}\n"
					break
				end

				# Check for data.
				if results == nil || results.size == 0
					# Need to add the var.
					sl = ""
					sl << ins_stmt << "#{var}\');"
					begin
						if $my_dry_run
							puts "INFO: DRY RUN mode enabled. Query that would have been executed is printed below:\nINFO: #{sl}\n"
						else
							# Actually excute the query.
							dbh.query(sl)
						end
					rescue Exception => e
						puts "ERROR: Unable to insert snmp value ID #{var} into database. Exception Raised: #{e}\n"
						break
					end
				end

				# Check if we are done.
				if (i + 1) >= snmp_varsArr.length
					ret = 1
				end
			end
		end
	end
	return ret
end

def snmp_thread_funct(dryRunMode, enableSqlErrors, snmpMutex, db_infoArr, intervalArr)
	ret = 0

	if snmpMutex.kind_of?(Mutex)
		# Lock the mutex.
		snmpMutex.lock
	end

	if snmpMutex.owned?() && db_infoArr.kind_of?(Array) && db_infoArr.length == 4 &&
	intervalArr.kind_of?(Array) && intervalArr.length == 2 && intervalArr[0].to_i > 0 &&
	intervalArr[1][0].kind_of?(Array) && intervalArr[1][0].length > 0 && intervalArr[1][0][0].kind_of?(Array) && intervalArr[1][0][0].length > 2 &&
	intervalArr[1][1].kind_of?(Array) && intervalArr[1][1].length > 0

		# Set the arrays.
		hostArr = Array.new
		for host in intervalArr[1][0]
			hostArr << host.clone
		end
		snmp_valsArr = Array.new
		for val in intervalArr[1][1]
			snmp_valsArr << val.clone
		end

		# Set our interval.
		my_interval = intervalArr[0].to_i
		puts "INFO: Starting interval thread for interval: #{my_interval}.\n"

		# Unlock the mutex.
		snmpMutex.unlock

		# Connect to the database.
		dbh = mysql_connect(db_infoArr[0], db_infoArr[1], db_infoArr[2], db_infoArr[3])
		if dbh != nil
			puts "INFO: Created mysql connection for interval thread: #{my_interval}.\n"

			# Check the host array.
			for i in (0...intervalArr[1][0].length)
				host = hostArr[i]
				if host.kind_of?(Array) && host.length > 2 && host[0].length > 0
					if host[1] == 3
					# SNMPv3 host.
						if host.length == 8 && host[2].length > 0
							# Open manager connection.
							mgr = NETSNMP::Client.new(host: host[0], username: host[2],
							auth_password: host[3], auth_protocol: host[4] == "md5" ? :md5 : nil,
							priv_password: host[5], priv_protocol: host[6] == "des" ? :des : nil,
							context: host[7])
							if mgr != nil
								host << mgr
								puts "INFO: Created SNMP manager for SNMP host #{host[0]} for interval #{my_interval}.\n"
							else
								msg = "WARNING: Discarded a SNMP host #{host[0]} for processing "
								msg << "on interval #{my_interval}. Connection error.\n"
								puts msg
								msg = nil
								hostArr.delete_at(i)
							end
						else
							puts "WARNING: Discarded a SNMP host #{host[0]} for processing on interval #{my_interval}. Invalid username.\n"
							hostArr.delete_at(i)
						end
					else
						# SNMPv1 / SNMPv2 host.
						if host.length == 3 && host[2].length > 0
							mgr = NETSNMP::Client.new(version: host[1], host: host[0], community: host[2])
							if mgr != nil
								host << mgr
								puts "INFO: Created SNMP manager for SNMP host #{host[0]} for interval #{my_interval}.\n"
							else
								msg = "WARNING: Discarded a SNMP host #{host[0]} for processing "
								msg << "on interval #{my_interval}. Connection error.\n"
								puts msg
								msg = nil
								hostArr.delete_at(i)
							end
						else
							msg = "WARNING: Discarded a SNMP host #{host[0]} for processing "
							msg << "on interval #{my_interval}. Invalid community.\n"
							puts msg
							msg = nil
							hostArr.delete_at(i)
						end
					end
				else
					# Invalid host entry. Discard for processing loop.
					msg = "WARNING: Discarded a SNMP host ( "
					msg << (host[0].length > 0) ? "#{host[0]}" : "INVALID HOSTNAME" << " ) for processing "
					msg << "on interval #{my_interval}.\n"
					puts msg
					msg = nil
					hostArr.delete_at(i)
				end
				host = nil
			end

			# Check the snmp_valsArr.
			for i in (0...snmp_valsArr.length)
				if snmp_valsArr[i].kind_of?(Array) && snmp_valsArr[i].length == 2 && snmp_valsArr[i][0].length <= 0
					# Invalid snmp value id. Discard for processing loop.
					puts "WARNING: Discarded a SNMP value ID for processing on interval #{my_interval}.\n"
					snmp_valsArr.delete_at(i)
				end
			end

			# If we still have anything to process...
			if hostArr.length > 0 && snmp_valsArr.length > 0
				# Set the exit flag.
				Thread.current.thread_variable_set("my_exit", false)

				# Begin host process loop.
				while (!Thread.current.thread_variable_get("my_exit"))
					begin
						# Start the host process loop.
						for host in hostArr
							# Set up the initial queries.
							dyn_query = "INSERT INTO #{DB_TBL_NAME_SNMP_VALUES_DYNAMIC}"
							static_ins_query = "INSERT INTO #{DB_TBL_NAME_SNMP_VALUES_STATIC}"
							gen_query = "(#{DB_SNMP_VALUES_FK_HOSTID}, "
							gen_query << "#{DB_SNMP_VALUES_FK_VALUEID}, #{DB_SNMP_VALUES_COL_ENTRY_VALUE}) VALUES ( "
							gen_query << "(SELECT #{DB_VALUE_PK_NAME} FROM #{DB_TBL_NAME_HOSTS} "
							gen_query << "WHERE #{DB_HOSTS_COL_HOSTNAME}='"
							gen_query << host[0] << "'), "
							gen_query << "(SELECT #{DB_VALUE_PK_NAME} FROM #{DB_TBL_NAME_SNMP_VALUE_IDS} "
							gen_query << "WHERE #{DB_SNMP_VALUE_IDS_COL_ENTRY_NAME}='"
							dyn_query << gen_query
							static_ins_query << gen_query
							gen_query = nil

							# Static update query.
							static_upd0_query = "UPDATE #{DB_TBL_NAME_SNMP_VALUES_STATIC} SET #{DB_SNMP_VALUES_COL_ENTRY_TIME}=NOW(), "
							static_upd0_query << "#{DB_SNMP_VALUES_COL_ENTRY_VALUE}='"
							static_upd1_query = "' WHERE #{DB_SNMP_VALUES_FK_HOSTID}="
							static_upd1_query << "(SELECT #{DB_VALUE_PK_NAME} FROM #{DB_TBL_NAME_HOSTS} "
							static_upd1_query << "WHERE #{DB_HOSTS_COL_HOSTNAME}='"
							static_upd1_query << host[0] << "') AND #{DB_SNMP_VALUES_FK_VALUEID}=(SELECT #{DB_VALUE_PK_NAME} "
							static_upd1_query << "FROM #{DB_TBL_NAME_SNMP_VALUE_IDS} WHERE #{DB_SNMP_VALUE_IDS_COL_ENTRY_NAME}='"
							static_upd2_query = "') "

							# Start the val process loop.
							for vals in snmp_valsArr
								snmp_result = nil
								val = vals[0]

								# Guard against fail.
								begin
									# Obtain mutex lock.
									snmpMutex.synchronize do
										# Query the snmp host.
										temp_result = host[(host[1] == 3 ? 8 : 3)].get(oid: val)
										snmp_result = temp_result.clone
										temp_result = nil
									end

								rescue Exception => e
									snmp_result = nil
									if dryRunMode
										msg = "ERROR: Unable to query SNMP host ( #{host[0]} ) on interval #{my_interval} "
										msg << "for OID: ( #{val} ) "
										msg << "Exception Raised: #{e}\n"
										puts msg
										msg = nil
									end
								end

								# Check for valid data.
								if snmp_result != nil
									# Construct the needed query data.
									sr = String.new
									if vals[1] == true
										# Static value.
										sr << static_upd0_query << dbh.escape(snmp_result.to_s)
										sr << static_upd1_query << val << static_upd2_query
									else
										# Dynamic value.
										sr << dyn_query
										sr << val << "'), "
										sr << "'" << dbh.escape(snmp_result.to_s) << "' ) "
									end

									# Insert the data into the database.
									if dryRunMode
										msg = "INFO: DRY RUN mode enabled. On interval #{my_interval}. "
										msg << "Database Query that would "
										msg << "have been executed is printed below:\nINFO: #{sr}\n"
										puts msg
										msg = nil
									else
										# Guard against fail.
										begin
											if enableSqlErrors
												puts "INFO: Database Query on interval #{my_interval}: #{sr}\n"
											end

											# Actually do it.
											dbh.query(sr)
											if dbh.affected_rows == 0
												msg = "ERROR: Unable to insert / update value "
												msg << "into database. DBMS did nothing with "
												msg << "the query on interval #{my_interval}.\n"

												if vals[1] == true && sr[0, 6] == "UPDATE"
													sr = nil
													sr = String.new
													sr << static_ins_query << val << "'), "
													sr << "'" << dbh.escape(snmp_result.to_s) << "' ) "
													if enableSqlErrors
														msi = "INFO: Database Query on interval "
														msi << "#{my_interval}: "
														msi << " #{sr}\n"
														puts msi
														msi = nil
													end
													dbh.query(sr)
													if dbh.affected_rows == 0 && enableSqlErrors
														puts msg
													end
												else
													if enableSqlErrors
														puts msg
													end
												end
												msg = nil
											end
										rescue Exception => e
											sr = nil
											if enableSqlErrors
												msg = "ERROR: Unable to insert / update value into database "
												msg << "on interval #{my_interval}. Exception Raised: #{e}\n"
												puts msg
												msg = nil
											end
										end
									end

									# Reset sr and snmp_result.
									sr = nil
									snmp_result = nil
								end

								# Reset val.
								val = nil
							end # End the val process loop.

							# Reset queries.
							dyn_query = nil
							static_ins_query = nil
							static_upd0_query = nil
							static_upd1_query = nil
							static_upd2_query = nil

						end # End the host process loop.

						# Wait for interval. (Default is 10 secs.)
						sleep (my_interval != nil && my_interval.to_i > 0) ? my_interval : 10
					rescue Exception => e
						if e.kind_of?(SystemExit)
							Thread.current.thread_variable_set("my_exit", true)
						else
							# Non-standard exit.
							puts "ERROR: Terminating thread for interval #{my_interval} due to Exception Raised: #{e}\n"
							ret = -3
							break
						end
					end
				end
			else
				puts "ERROR: Interval #{my_interval} nothing to do on this thread, terminating thread.\n"
				ret = -2
			end

			# Close the snmp managers.
			for host in hostArr
				if host[3] == 3
					host[8].close
				else
					host[3].close
				end
				puts "INFO: Closed SNMP manager for #{host[0]} for interval #{my_interval}.\n"
			end

			# Close the connection to the database server.
			mysql_close(dbh)
			puts "INFO: Closed mysql connection for interval #{my_interval}.\n"
		else
			puts "ERROR: Could not open mysql connection to #{db_infoArr[0]}/#{db_infoArr[3]} with the given credentials for interval #{my_interval}.\n"
			ret = -1
		end
		puts "INFO: Exiting thread for interval #{my_interval}.\n"
	end
	return ret
end

def test(an_arg)
	puts "Test\n #{an_arg}\n"
end

test("Hwloe")

# Begin "main" function below.
retArr = nil
ret = 0
if $my_generate_conf_file
	gen_config_file($my_config_file)
else
	retArr = parse_config_file($my_config_file)
end

if retArr.kind_of?(Array) && retArr.length > 3 && retArr[0] == 1 && retArr[3].kind_of?(Array) && retArr[3].length > 3
	# The retArr array is formatted like:
	# 0: retVal, 1: hosts Arr, 2: snmp_vars Arr, 3: database info Arr.

	# Open mysql connection to the database server.
	dbh = mysql_connect(retArr[3][0], retArr[3][1], retArr[3][2], retArr[3][3])
	if dbh != nil

		if $my_create_tables || $my_force_table_creation
			# Set flag to continue. (If we don't force create tables it's not relevent.)
			safe_cont = 1

			# Drop the tables first. (If needed.)
			if $my_force_table_creation
				# Set the flag so we'll abort later if we fail.
				safe_cont = 0

				# Reverse order deletion.
				begin
					for tbl in Array[DB_TBL_NAME_SNMP_VALUES_STATIC,
							DB_TBL_NAME_SNMP_VALUES_DYNAMIC,
							DB_TBL_NAME_SNMP_VALUE_IDS,
							DB_TBL_NAME_HOSTS,
							DB_TBL_NAME_VERSION]
						stmt = "DROP TABLE IF EXISTS #{tbl};"
						if $my_dry_run
							puts "INFO: DRY RUN mode enabled. Statement that would be executed is printed below:\nINFO: #{stmt}\n"
						else
							# Actually do it.
							dbh.query(stmt)
							puts "INFO: DROPPED table #{tbl}.\n"
						end
					end

					# Set flag so we'll continue with creating tables.
					safe_cont = 1
				rescue Exception => e
					puts "ERROR: Could not drop all tables from the database.\nERROR: Exception Raised: #{e}\n"
					ret = -1
				end
			end

			if safe_cont == 1
				if create_mysql_table(dbh, DB_TBL_NAME_VERSION, DB_VERSION_tblArr) == 1
					puts "INFO: Created ( #{DB_TBL_NAME_VERSION} ) table on #{retArr[3][0]}/#{retArr[3][3]}.\n"
				else
					puts "ERROR: Could not create ( #{DB_TBL_NAME_VERSION} ) on #{retArr[3][0]}/#{retArr[3][3]}.\n"
					ret = -1
				end

				if create_mysql_table(dbh, DB_TBL_NAME_HOSTS, DB_HOSTS_tblArr) == 1
					puts "INFO: Created ( #{DB_TBL_NAME_HOSTS} ) table on #{retArr[3][0]}/#{retArr[3][3]}.\n"
				else
					puts "ERROR: Could not create ( #{DB_TBL_NAME_HOSTS} ) on #{retArr[3][0]}/#{retArr[3][3]}.\n"
					ret = -1
				end

				if create_mysql_table(dbh, DB_TBL_NAME_SNMP_VALUE_IDS, DB_SNMP_VALUE_IDS_tblArr) == 1
					puts "INFO: Created ( #{DB_TBL_NAME_SNMP_VALUE_IDS} ) table on #{retArr[3][0]}/#{retArr[3][3]}.\n"
				else
					puts "ERROR: Could not create ( #{DB_TBL_NAME_SNMP_VALUE_IDS} ) on #{retArr[3][0]}/#{retArr[3][3]}.\n"
					ret = -1
				end

				if create_mysql_table(dbh, DB_TBL_NAME_SNMP_VALUES_DYNAMIC, DB_SNMP_VALUES_DYNAMIC_tblArr) == 1
					puts "INFO: Created ( #{DB_TBL_NAME_SNMP_VALUES_DYNAMIC} ) table on #{retArr[3][0]}/#{retArr[3][3]}.\n"
				else
					puts "ERROR: Could not create ( #{DB_TBL_NAME_SNMP_VALUES_DYNAMIC} ) on #{retArr[3][0]}/#{retArr[3][3]}.\n"
					ret = -1
				end

				if create_mysql_table(dbh, DB_TBL_NAME_SNMP_VALUES_STATIC, DB_SNMP_VALUES_STATIC_tblArr) == 1
					puts "INFO: Created ( #{DB_TBL_NAME_SNMP_VALUES_STATIC} ) table on #{retArr[3][0]}/#{retArr[3][3]}.\n"
				else
					puts "ERROR: Could not create ( #{DB_TBL_NAME_SNMP_VALUES_STATIC} ) on #{retArr[3][0]}/#{retArr[3][3]}.\n"
					ret = -1
				end
			end
		else
			# Check for the database structure.
			has_db_struct = check_needed_table_structures(dbh)

			if has_db_struct == 1

				# Check for any new hosts / SNMP value IDs that we need to add to the database.
				if insert_new_hosts_into_db(dbh, retArr[1]) == 1
					if insert_new_snmp_val_ids_into_db(dbh, retArr[2]) == 1
						# Close the database connection.
						mysql_close(dbh)
						dbh = nil

						# Create a new set of intervals.
						intervals = Hash.new
						# Process the snmp value interval overrides first.
						for val in retArr[2]
							if val[2] > 0
								# These snmp values have a specific interval value.
								intVal = val[2] * (val[3] > 0 ? val[3] : 1)
								if intervals.has_key?(intVal) == true
									# Add to existing array.
									intervals[intVal][1] << Array[val[0], val[1]]
								else
									# Create new array.
									intervals[intVal] = Array[nil, Array[Array[val[0], val[1]]]]
								end
								intVal = nil
							end
						end
						# Now process the host intervals.
						for host in retArr[1]
							intVal = host[1] * (host[2] > 0 ? host[2] : 1)
							hostArr = host
							hostArr.delete_at(2)
							hostArr.delete_at(1)
							if intervals.has_key?(intVal) == true
								if intervals[intVal][0] != nil
									foundHost = false
									for hostVal in intervals[intVal][0]
										if hostVal[0] == hostArr[0]
											foundHost = true
											break
										end
									end
									if !foundHost
										# Add to existing host array.
										intervals[intVal][0] << hostArr
									end
									foundHost = nil
									hostVal = nil
								else
									# Create new host array.
									intervals[intVal][0] = Array[hostArr]
								end
							else
								# Create new interval array.
								intervals[intVal] = Array[Array[hostArr], nil]
							end
							intVal = nil

							# Iterate over the interval list again and place our host wherever it doesn't appear.
							for intVal in intervals.each_value
								if intVal[0] != nil
									foundHost = false
									for a in intVal[0]
										if a[0] == hostArr[0]
											foundHost = true
											break
										end
									end
									if !foundHost
										# Add to existing host array.
										intVal[0] << hostArr
									end
									foundHost = nil
									a = nil
								else
									# Create new host array.
									intVal[0] = Array[hostArr]
								end
							end
							intVal = nil
							hostArr = nil
						end
						# Now process the default interval list.
						for val in retArr[2]
							if val[2] == 0
								for intVal in intervals.each_value
									if intVal[1] != nil
										# Add to existing array.
										foundVar = false
										for a in intVal[1]
											if a[0] == val[0]
												foundVar = true
												break
											end
										end
										if (!foundVar)
											intVal[1] << Array[val[0], val[1]]
										end
										foundVar = nil
										a = nil
									else
										# Create new array.
										intVal[1] = Array[Array[val[0], val[1]]]
									end
								end
							end
						end

						# Clean up the retArr.
						retArr[1] = nil
						retArr[2] = nil

						# Create the snmpMutex and conditional.
						snmpMutex = Mutex.new

						# For each interval, create a new thread to deal with it.
						begin
							thrArr = Array.new
							for i in intervals
								# Create a deep copy of i.
								tempA = i.clone

								# Note the pipes here... Otherwise we get references in the thread
								# that will change when the main thread moves to the next iteration
								# of this loop!
								# I.e. Don't do this: Thread.new {snmp_thread_funct($my_dry_run, retArr[3], i)}
								thrArr << Thread.new($my_dry_run,
								$my_sql_err, snmpMutex,
								retArr[3], tempA) { |a,b,c,d,e| snmp_thread_funct(a,b,c,d,e) }

								# Loose the reference to tempA.
								tempA = nil
							end

							# Wait on the threads to finish.
							for t in thrArr
								if ret == 0
									ret = t.value
								else
									# Error, set exit flag.
									t.thread_variable_set("my_exit", true)
									if t.status != "killed"
										t.run
									end
									t.join
								end
							end
						rescue Interrupt
							for t in thrArr
								t.thread_variable_set("my_exit", true)
								if t.status != "killed"
									t.run
								end
								t.join
							end
						end

						# Clean up.
						thrArr = nil
						intervals = nil
						snmpMutex = nil
						
						puts "<= TO BE CONTINUED!!!!!\n"
					else
						puts "ERROR: Failed to check for new snmp value IDs to insert into the database.\n"
						ret = -1
					end
				else
					puts "ERROR: Failed to check for new hosts to insert into the database.\n"
					ret = -1
				end
			else
				puts "ERROR: Missing mysql database structures on #{retArr[3][0]}/#{retArr[3][3]}. Try running with --create-tables?\n"
				ret = -1
			end
		end

		# Close the connection to the database server.
		if dbh != nil
			mysql_close(dbh)
			dbh = nil
		end
	else
		puts "ERROR: Could not open mysql connection to #{retArr[3][0]}/#{retArr[3][3]} with the given credentials.\n"
		ret = -1
	end
else
	if $my_generate_conf_file == false
		puts "ERROR: Could not load config file at ( #{$my_config_file} ).\n"
		ret = -2
	end
end

# Exit script.
exit ret
