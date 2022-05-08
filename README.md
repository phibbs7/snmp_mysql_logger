
# snmp\_mysql\_logger

This project is a SNMP (Simple Network Management Protocol) manager daemon written in Ruby that logs the values it monitors to a specified MySQL database.

###Installing: 
This project uses the [_mysql2_](https://github.com/brianmario/mysql2), [_iniparse_](https://github.com/antw/iniparse), and [_netsnmp_](https://github.com/swisscom/ruby-netsnmp) Ruby gems. You'll need to either fetch them using `gem install`, or alternatively install them via your OS's package manager.

Note: For Debian based systems, `sudo apt install ruby-mysql2 ruby-iniparse && gem install netsnmp` As _netsnmp_ is not currently packaged by Debian.

###Configuration

The logger has it's own configuration file (in INI format) and you'll need to modify it to contain the proper values for your environment.

_Warning_ The configuration file contains user credentials for the DBMS and any SNMPv3 user. In addition, some may consider the SNMPv1/2 community information confidential as well. As such, the configuration file should be considered sensitive and it's access permissions set accordingly.

To create the example configuration file run: `ruby /path/to/snmp_mysql_logger.rb -g`

At the bare miniumum you will need to know the following:

    * Hostname / IP address of the SNMP agent you want to query.
    * The SNMP version of the agent.
    * The SNMP OID(s) and index numbers of the values you want to query.

Depending on the SNMP agent's configuration you may need more information. Check your device's configuration / documentation for more details.

After setting up the configuration file, you'll need to create the tables in the MySQL database. To do this run: `ruby /path/to/snmp_mysql_logger.rb -c /path/to/config_file -t` You can also provide the `-f` option to force a DROP of the previous tables prior to recreating them.

* Note: This requires that the user defined in the configuration file have the proper CREATE and DROP permissions on the configured database. If you do not wish to keep these permissions after running this command, you can restrict them. The only queries issued by the logger at runtime are "INSERT / UPDATE / SELECT / SHOW TABLE / SHOW COLUMNS".

* For those wanting more information about the queries issued to the DBMS you can run the logger with the `--dry-run`, or `--enable-sql-errors` to monitor the generated SQL queries on STDOUT. Note: A valid configuration file and a functioning user account on the DBMS is required for these arguments to generate SQL query dumps.

#####Static VS. Dynamic SNMP values
The daemon has two modes for logging values to MySQL:

    * Static
    * Dynamic

In Static mode, the SNMP values are logged into the `snmp_values_static` table and contain only one entry per value / OID. This mode is intended for SNMP values that do not update often and / or values where only the most recent information is needed. (E.x. Firmware Version, Max Phase Load, Alarm Level, etc.) The `entry_time` field in the table will be updated with each refresh of the values.

In Dynamic mode, the SNMP values are logged into the `snmp_values_dynamic` table and contain multiple entries per value / OID. This mode is intended for SNMP values that change over time and retainment of the previous values is needed for comparison / data visualization. (E.x. Uptime, Current Amps Readout, Number of faulty packets, etc.) The `entry_time` field in the table is the time that the SNMP value was inserted into the table.

###Running the logger.

It is recommended that you use a service manager to handle starting and stopping the logger. An example systemd service file is provided in the distribution for this purpose.

#####Arguments:
For those wanting to experiment prior to deployment, or who wish to implement their own support, the following command line arguments are supported:

* -c, --config-file: Path to configuration file.
* -d, --dry-run: Enable dry run mode. (No commits to database are performed.)
* -t, --create-tables: Create table structure in the configured mysql database.
* -f, --force-create-tables: Forcibly create table structure in the configured mysql database. (WARNING: Any existing tables will be DROPPED!!!)
* -g, --generate-config-file: Create an example config file. (Uses the path given by the -c | --config-file option.)
* -s, --enable-sql-errors: Turns on SQL error reporting when dry run mode is disabled.
* -v, --version: Output the current version information.

###Database Format
Information about each SNMP host (Hostname) is stored in the `hosts` table under the `hostname` column.

Information about the SNMP OIDs whose values exist in the database, are found in the `snmp_value_ids` table under the `entry_name` column.

The SNMP values in the database are stored based on the "mode" that they were configured with at the time they were fetched from the SNMP agent:

    * "Dynamic" values are stored in the `snmp_values_dynamic` table under the `entry_value` column, and the `entry_time` column contains the most recent date/time that the value was last successfully updated in the database after a successful fetch / refresh from the SNMP agent.
    * "Static" values are stored in the `snmp_values_static` table under the `entry_value` column, and the `entry_time` column contains the date/time that the row was initially inserted into the database.

In addition, the tables for both modes provide foreign keys to match the value to the SNMP agent hostname and SNMP OID they belong to. `fk_hostID` and `fk_valueID` respectively.


