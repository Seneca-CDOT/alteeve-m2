package AN::Tools::ScanCore;
# 
# This module contains methods used to get data from the ScanCore database.
# 

use strict;
use warnings;
use Data::Dumper;
use Text::Diff;
no warnings 'recursion';

our $VERSION  = "0.1.001";
my $THIS_FILE = "ScanCore.pm";

### Methods;
# check_ram_usage
# get_anvils
# get_dr_jobs
# get_dr_targets
# get_hosts
# get_manifests
# get_migration_target
# get_node_name_from_node_uuid
# get_node_uuid_from_node_name
# get_node_health
# get_nodes
# get_nodes_cache
# get_notifications
# get_owners
# get_power_check_data
# get_recipients
# get_servers
# get_smtp
# get_striker_peers
# host_state
# insert_or_update_anvils
# insert_or_update_dr_jobs
# insert_or_update_dr_targets
# insert_or_update_health
# insert_or_update_nodes
# insert_or_update_nodes_cache
# insert_or_update_notifications
# insert_or_update_owners
# insert_or_update_recipients
# insert_or_update_servers
# insert_or_update_states
# insert_or_update_smtp
# insert_or_update_variables
# lock_file
# parse_anvil_data
# parse_install_manifest
# read_cache
# read_variable
# save_install_manifest
# target_power
# update_server_stop_reason

#############################################################################################################
# House keeping methods                                                                                     #
#############################################################################################################

sub new
{
	my $class = shift;
	
	my $self  = {};
	
	bless $self, $class;
	
	return ($self);
}

# Get a handle on the AN::Tools object. I know that technically that is a sibling module, but it makes more 
# sense in this case to think of it as a parent.
sub parent
{
	my $self   = shift;
	my $parent = shift;
	
	$self->{HANDLE}{TOOLS} = $parent if $parent;
	
	return ($self->{HANDLE}{TOOLS});
}

#############################################################################################################
# Provided methods                                                                                          #
#############################################################################################################

# This checks the amount RAM used by ScanCore and exits if it exceeds a maximum_ram bytes. It looks
# for any process with our name and sums the RAM used.
sub check_ram_usage
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "check_ram_usage" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $program_name = defined $parameter->{program_name} ? $parameter->{program_name} : "";
	my $check_usage  = defined $parameter->{check_usage}  ? $parameter->{check_usage}  : 1;
	my $maximum_ram  = defined $parameter->{maximum_ram}  ? $parameter->{maximum_ram}  : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
		name1 => "program_name", value1 => $program_name, 
		name2 => "check_usage",  value2 => $check_usage, 
		name3 => "maximum_ram",  value3 => $maximum_ram, 
	}, file => $THIS_FILE, line => __LINE__});
	if (not $program_name)
	{
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0192", code => 192, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	# If this is a perl module, skip it.
	if ($program_name =~ /^\.pm$/)
	{
		return("");
	}
	
	# Read in how much RAM we're using.
	my $used_ram = $an->Get->ram_used_by_program({program_name => $program_name});
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "used_ram", value1 => $used_ram, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# Exit if I failed to read the amount of RAM in use.
	if ((not $used_ram) or ($used_ram eq "-1"))
	{
		$an->Alert->warning({message_key => "scancore_warning_0023", message_variables => { program_name => $program_name }, quiet => 1, file => $THIS_FILE, line => __LINE__});
		$an->data->{sys}{'exit'} = 1;
	}
	
	# Make sure I have my host system id
	if (not $an->data->{sys}{host_uuid})
	{
		$an->Get->uuid({get => 'host_uuid'});
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "sys::host_uuid", value1 => $an->data->{sys}{host_uuid}, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	# Records the RAM used, if we have a DB connection.
	if (defined $an->data->{sys}{use_db_fh})
	{
		my $query = "
SELECT 
    ram_used_uuid, 
    ram_used_bytes 
FROM 
    ram_used 
WHERE 
    ram_used_by        = ".$an->data->{sys}{use_db_fh}->quote($program_name)." 
AND
    ram_used_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{host_uuid})." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1  => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $ram_used_uuid  = "";
		my $ram_used_bytes = "";
		my $return         = [];
		my $results        = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count          = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$ram_used_uuid  = $row->[0];
			$ram_used_bytes = $row->[1];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "ram_used_uuid",  value1 => $ram_used_uuid, 
				name2 => "ram_used_bytes", value2 => $ram_used_bytes, 
			}, file => $THIS_FILE, line => __LINE__});
			last;
		}
		
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "ram_used_uuid",  value1 => $ram_used_uuid, 
			name2 => "ram_used_bytes", value2 => $ram_used_bytes, 
		}, file => $THIS_FILE, line => __LINE__});
		if (not $ram_used_uuid)
		{
			# Add this agent to the DB
			   $ram_used_uuid = $an->Get->uuid();
			my $query         = "
INSERT INTO 
    ram_used 
(
    ram_used_uuid, 
    ram_used_host_uuid, 
    ram_used_by, 
    ram_used_bytes, 
    modified_date
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($ram_used_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{host_uuid}).", 
    ".$an->data->{sys}{use_db_fh}->quote($program_name).", 
    ".$an->data->{sys}{use_db_fh}->quote($used_ram).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
			$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "query", value1 => $query, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($ram_used_bytes ne $used_ram)
		{
			# It exists and the value has changed.
			my $query = "
UPDATE 
    ram_used 
SET
    ram_used_bytes = ".$an->data->{sys}{use_db_fh}->quote($used_ram).", 
    modified_date  = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
WHERE 
    ram_used_uuid  = ".$an->data->{sys}{use_db_fh}->quote($ram_used_uuid)."
;";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "query", value1 => $query, 
			}, file => $THIS_FILE, line => __LINE__});
			$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
		} # RAM used hasn't changed
	} # No DB connection
	
	if ($check_usage)
	{
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "maximum_ram", value1 => $maximum_ram, 
		}, file => $THIS_FILE, line => __LINE__});
		
		# Set a sane value if Max RAM wasn't set
		if (not $maximum_ram)
		{
			$maximum_ram = $an->data->{scancore}{maximum_ram} ? $an->data->{scancore}{maximum_ram} : (128 * 1048576);
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "maximum_ram", value1 => $maximum_ram, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		if ($maximum_ram =~ /\D/)
		{
			# Bad value, set the default.
			$maximum_ram = 1073741824;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "maximum_ram", value1 => $maximum_ram, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "used_ram",    value1 => $used_ram." (".$an->Readable->bytes_to_hr({'bytes' => $used_ram}).")", 
			name2 => "maximum_ram", value2 => $maximum_ram." (".$an->Readable->bytes_to_hr({'bytes' => $maximum_ram}).")", 
		}, file => $THIS_FILE, line => __LINE__});
		if ($used_ram > $maximum_ram)
		{
			# Much, too much, much music!  err, too much RAM...
			$an->Alert->error({title_key => "an_0003", message_key => "scancore_error_0013", message_variables => { 
				used_ram    => $an->Readable->bytes_to_hr({'bytes' => $used_ram}), 
				maximum_ram => $an->Readable->bytes_to_hr({'bytes' => $maximum_ram})
			}, code => 5, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	return($used_ram);
}

# Get a list of Anvil! systems as an array of hash references
sub get_anvils
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_anvils" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $include_deleted = $parameter->{include_deleted} ? $parameter->{include_deleted} : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "include_deleted", value1 => $include_deleted, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $query = "
SELECT 
    anvil_uuid, 
    anvil_owner_uuid, 
    anvil_smtp_uuid, 
    anvil_name, 
    anvil_description, 
    anvil_note, 
    anvil_password, 
    modified_date 
FROM 
    anvils ";
	if (not $include_deleted)
	{
		$query .= "
WHERE 
    anvil_note IS DISTINCT FROM 'DELETED'";
	}
	$query .= "
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $return  = [];
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		my $anvil_uuid        = $row->[0];
		my $anvil_owner_uuid  = $row->[1];
		my $anvil_smtp_uuid   = $row->[2];
		my $anvil_name        = $row->[3];
		my $anvil_description = $row->[4];
		my $anvil_note        = $row->[5];
		my $anvil_password    = $row->[6];
		my $modified_date     = $row->[7];
		$an->Log->entry({log_level => 3, message_key => "an_variables_0007", message_variables => {
			name1 => "anvil_uuid",        value1 => $anvil_uuid, 
			name2 => "anvil_owner_uuid",  value2 => $anvil_owner_uuid, 
			name3 => "anvil_smtp_uuid",   value3 => $anvil_smtp_uuid, 
			name4 => "anvil_name",        value4 => $anvil_name, 
			name5 => "anvil_description", value5 => $anvil_description, 
			name6 => "anvil_note",        value6 => $anvil_note, 
			name7 => "modified_date",     value7 => $modified_date, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
			name1 => "anvil_password", value1 => $anvil_password, 
		}, file => $THIS_FILE, line => __LINE__});
		push @{$return}, {
			anvil_uuid		=>	$anvil_uuid,
			anvil_owner_uuid	=>	$anvil_owner_uuid, 
			anvil_smtp_uuid		=>	$anvil_smtp_uuid, 
			anvil_name		=>	$anvil_name, 
			anvil_description	=>	$anvil_description, 
			anvil_note		=>	$anvil_note, 
			anvil_password		=>	$anvil_password, 
			modified_date		=>	$modified_date, 
		};
	}
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "return", value1 => $return, 
	}, file => $THIS_FILE, line => __LINE__});
	return($return);
}

# Get a list of DR jobs as an array of hash references.
sub get_dr_jobs
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_dr_jobs" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $include_deleted = $parameter->{include_deleted} ? $parameter->{include_deleted} : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "include_deleted", value1 => $include_deleted, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# Which query we use will depend on what data we got.
	my $query = "
SELECT 
    dr_job_uuid, 
    dr_job_dr_target_uuid, 
    dr_job_anvil_uuid, 
    dr_job_name, 
    dr_job_note, 
    dr_job_servers, 
    dr_job_auto_prune, 
    dr_job_schedule, 
    modified_date 
FROM 
    dr_jobs ";
	if (not $include_deleted)
	{
		$query .= "
WHERE 
    dr_job_note IS DISTINCT FROM 'DELETED'";
	}
	$query .= "
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
	
	my $return  = [];
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		my $dr_job_uuid           =         $row->[0]; 
		my $dr_job_dr_target_uuid =         $row->[1];
		my $dr_job_anvil_uuid     =         $row->[2];
		my $dr_job_name           =         $row->[3];
		my $dr_job_note           = defined $row->[4] ? $row->[4] : "";
		my $dr_job_servers        =         $row->[5];
		my $dr_job_auto_prune     =         $row->[6];
		my $dr_job_schedule       =         $row->[7];
		my $modified_date         =         $row->[8];
		$an->Log->entry({log_level => 3, message_key => "an_variables_0009", message_variables => {
			name1 => "dr_job_uuid",           value1 => $dr_job_uuid, 
			name2 => "dr_job_dr_target_uuid", value2 => $dr_job_dr_target_uuid, 
			name3 => "dr_job_anvil_uuid",     value3 => $dr_job_anvil_uuid, 
			name4 => "dr_job_name",           value4 => $dr_job_name, 
			name5 => "dr_job_note",           value5 => $dr_job_note, 
			name6 => "dr_job_servers",        value6 => $dr_job_servers, 
			name7 => "dr_job_auto_prune",     value7 => $dr_job_auto_prune, 
			name8 => "dr_job_schedule",       value8 => $dr_job_schedule, 
			name9 => "modified_date",         value9 => $modified_date, 
		}, file => $THIS_FILE, line => __LINE__});
		push @{$return}, {
			dr_job_uuid		=>	$dr_job_uuid,
			dr_job_dr_target_uuid	=>	$dr_job_dr_target_uuid, 
			dr_job_anvil_uuid	=>	$dr_job_anvil_uuid, 
			dr_job_name		=>	$dr_job_name, 
			dr_job_note		=>	$dr_job_note, 
			dr_job_servers		=>	$dr_job_servers, 
			dr_job_auto_prune	=>	$dr_job_auto_prune, 
			dr_job_schedule		=>	$dr_job_schedule, 
			modified_date		=>	$modified_date, 
		};
	}
	
	return($return);
}

# Get a list of DR targets as an array of hash references.
sub get_dr_targets
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_dr_targets" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $include_deleted = $parameter->{include_deleted} ? $parameter->{include_deleted} : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "include_deleted", value1 => $include_deleted, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# Which query we use will depend on what data we got.
	my $query = "
SELECT 
    dr_target_uuid, 
    dr_target_name, 
    dr_target_note, 
    dr_target_address, 
    dr_target_password, 
    dr_target_tcp_port, 
    dr_target_use_cache, 
    dr_target_store, 
    dr_target_copies, 
    dr_target_bandwidth_limit, 
    modified_date 
FROM 
    dr_targets ";
	if (not $include_deleted)
	{
		$query .= "
WHERE 
    dr_target_note IS DISTINCT FROM 'DELETED'";
	}
	$query .= "
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
	
	my $return  = [];
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		my $dr_target_uuid            =         $row->[0]; 
		my $dr_target_name            =         $row->[1];
		my $dr_target_note            = defined $row->[2] ? $row->[2] : ""; 
		my $dr_target_address         =         $row->[3]; 
		my $dr_target_password        = defined $row->[4] ? $row->[4] : ""; 
		my $dr_target_tcp_port        = defined $row->[5] ? $row->[5] : ""; 
		my $dr_target_use_cache       =         $row->[6]; 
		my $dr_target_store           =         $row->[7]; 
		my $dr_target_copies          =         $row->[8]; 
		my $dr_target_bandwidth_limit = defined $row->[9] ? $row->[9] : ""; 
		my $modified_date             =         $row->[10];
		$an->Log->entry({log_level => 3, message_key => "an_variables_0010", message_variables => {
			name1  => "dr_target_uuid",            value1  => $dr_target_uuid, 
			name2  => "dr_target_name",            value2  => $dr_target_name, 
			name3  => "dr_target_note",            value3  => $dr_target_note, 
			name4  => "dr_target_address",         value4  => $dr_target_address, 
			name5  => "dr_target_tcp_port",        value5  => $dr_target_tcp_port, 
			name6  => "dr_target_use_cache",       value6  => $dr_target_use_cache, 
			name7  => "dr_target_store",           value7  => $dr_target_store, 
			name8  => "dr_target_copies",          value8  => $dr_target_copies, 
			name9  => "dr_target_bandwidth_limit", value9  => $dr_target_bandwidth_limit, 
			name10 => "modified_date",             value10 => $modified_date, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
			name1 => "dr_target_password", value1 => $dr_target_password, 
		}, file => $THIS_FILE, line => __LINE__});
		push @{$return}, {
			dr_target_uuid		=>	$dr_target_uuid,
			dr_target_name		=>	$dr_target_name, 
			dr_target_note		=>	$dr_target_note, 
			dr_target_address	=>	$dr_target_address, 
			dr_target_password	=>	$dr_target_password, 
			dr_target_tcp_port	=>	$dr_target_tcp_port, 
			dr_target_use_cache	=>	$dr_target_use_cache, 
			dr_target_store		=>	$dr_target_store, 
			dr_target_copies	=>	$dr_target_copies, 
			dr_target_bandwidth_limit =>	$dr_target_bandwidth_limit, 
			modified_date		=>	$modified_date, 
		};
	}
	
	return($return);
}

# Get a list of Anvil! hosts as an array of hash references.
sub get_hosts
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_hosts" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $query = "
SELECT 
    host_uuid, 
    host_location_uuid, 
    host_name, 
    host_type, 
    host_emergency_stop, 
    host_stop_reason, 
    host_health, 
    modified_date 
FROM 
    hosts
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
	
	my $return  = [];
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		my $host_uuid           = $row->[0];
		my $host_location_uuid  = $row->[1] ? $row->[1] : "";
		my $host_name           = $row->[2];
		my $host_type           = $row->[3];
		my $host_emergency_stop = $row->[4] ? $row->[4] : "";
		my $host_stop_reason    = $row->[5] ? $row->[5] : "";
		my $host_health         = $row->[6] ? $row->[6] : "";
		my $modified_date       = $row->[7];
		$an->Log->entry({log_level => 3, message_key => "an_variables_0008", message_variables => {
			name1 => "host_uuid",           value1 => $host_uuid, 
			name2 => "host_location_uuid",  value2 => $host_location_uuid, 
			name3 => "host_name",           value3 => $host_name, 
			name4 => "host_type",           value4 => $host_type, 
			name5 => "host_emergency_stop", value5 => $host_emergency_stop, 
			name6 => "host_stop_reason",    value6 => $host_stop_reason, 
			name7 => "host_health",         value7 => $host_health, 
			name8 => "modified_date",       value8 => $modified_date, 
		}, file => $THIS_FILE, line => __LINE__});
		push @{$return}, {
			host_uuid		=>	$host_uuid,
			host_location_uuid	=>	$host_location_uuid, 
			host_name		=>	$host_name, 
			host_type		=>	$host_type, 
			host_emergency_stop	=>	$host_emergency_stop, 
			host_stop_reason	=>	$host_stop_reason, 
			host_health		=>	$host_health, 
			modified_date		=>	$modified_date, 
		};
		
		# Record the host_uuid in a hash so that the name can be easily retrieved.
		$an->data->{sys}{uuid_to_name}{$host_uuid} = $host_name;
	}
	
	return($return);
}

# Get a list of Anvil! Install Manifests as an array of hash references
sub get_manifests
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_manifests" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $include_deleted = $parameter->{include_deleted} ? $parameter->{include_deleted} : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "include_deleted", value1 => $include_deleted, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $query = "
SELECT 
    manifest_uuid, 
    manifest_data, 
    manifest_note, 
    modified_date 
FROM 
    manifests ";
	if (not $include_deleted)
	{
		$query .= "
WHERE 
    manifest_note IS DISTINCT FROM 'DELETED'";
	}
	$query .= "
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
	
	my $return  = [];
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		my $manifest_uuid = $row->[0];
		my $manifest_data = $row->[1];
		my $manifest_note = $row->[2] ? $row->[2] : "NULL";
		my $modified_date = $row->[3];
		$an->Log->entry({log_level => 3, message_key => "an_variables_0004", message_variables => {
			name1 => "manifest_uuid", value1 => $manifest_uuid, 
			name2 => "manifest_data", value2 => $manifest_data, 
			name3 => "manifest_note", value3 => $manifest_note, 
			name4 => "modified_date", value4 => $modified_date, 
		}, file => $THIS_FILE, line => __LINE__});
		push @{$return}, {
			manifest_uuid	=>	$manifest_uuid,
			manifest_data	=>	$manifest_data, 
			manifest_note	=>	$manifest_note, 
			modified_date	=>	$modified_date, 
		};
	}
	
	return($return);
}

# This returns the migration target of a given server, if it is being migrated.
sub get_migration_target
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_migration_target" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $include_deleted = $parameter->{include_deleted} ? $parameter->{include_deleted} : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "include_deleted", value1 => $include_deleted, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $server = $parameter->{server} ? $parameter->{server} : "";
	if (not $server)
	{
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0101", code => 101, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	my $query  = "
SELECT 
    a.host_name 
FROM 
    hosts a, 
    states b 
WHERE 
    a.host_uuid = b.state_host_uuid 
AND 
    b.state_name = 'migration' 
AND 
    b.state_note = ".$an->data->{sys}{use_db_fh}->quote($server)."
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query, 
	}, file => $THIS_FILE, line => __LINE__});
	my $target = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
	   $target = "" if not $target;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "target", value1 => $target, 
	}, file => $THIS_FILE, line => __LINE__});
	
	return($target);
}

# This takes a node UUID and returns its node (host) name.
sub get_node_name_from_node_uuid
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_node_name_from_node_uuid" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $node_name = "";
	my $node_uuid = $parameter->{node_uuid} ? $parameter->{node_uuid} : "";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "node_name", value1 => $node_name, 
	}, file => $THIS_FILE, line => __LINE__});
	
	if ($an->Validate->is_uuid({uuid => $node_uuid}))
	{
		my $query = "
SELECT 
    host_name 
FROM 
    hosts 
WHERE 
    host_uuid = (
        SELECT 
            node_host_uuid 
        FROM 
            nodes 
        WHERE 
            node_uuid = ".$an->data->{sys}{use_db_fh}->quote($node_uuid)."
        )
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		$node_uuid = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
		$node_uuid = "" if not $node_uuid;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "node_uuid", value1 => $node_uuid, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "node_uuid", value1 => $node_uuid, 
	}, file => $THIS_FILE, line => __LINE__});
	return($node_uuid);
}

# This takes a node name, gets its host uuid and then looks up and returns its node_uuid 
sub get_node_uuid_from_node_name
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_node_uuid_from_node_name" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $node_uuid = "";
	my $node_name = $parameter->{node_name} ? $parameter->{node_name} : "";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "node_name", value1 => $node_name, 
	}, file => $THIS_FILE, line => __LINE__});
	
	if ($node_name)
	{
		my $query = "
SELECT 
    node_uuid 
FROM 
    nodes 
WHERE 
    node_host_uuid = (
        SELECT 
            host_uuid 
        FROM 
            hosts 
        WHERE 
            host_name = ".$an->data->{sys}{use_db_fh}->quote($node_name)."
        )
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		$node_name = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
		$node_name = "" if not $node_name;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "node_name", value1 => $node_name, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "node_name", value1 => $node_name, 
	}, file => $THIS_FILE, line => __LINE__});
	return($node_name);
}

# This returns the health score for a node.
sub get_node_health
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_node_health" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $target = $parameter->{target} ? $parameter->{target} : "host_uuid";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "target", value1 => $target, 
	}, file => $THIS_FILE, line => __LINE__});
	
	if (not $an->Validate->is_uuid({uuid => $target}))
	{
		# Translate the target to a host_uuid
		$target = $an->Get->uuid({get => $target});
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "target", value1 => $target, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $valid = $an->Validate->is_uuid({uuid => $target});
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "valid", value1 => $valid, 
		}, file => $THIS_FILE, line => __LINE__});
		if (not $valid)
		{
			# No host 
			$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0235", message_variables => { target => $parameter->{target} }, code => 235, file => $THIS_FILE, line => __LINE__});
			return("");
		}
	}
	
	# Read in any values.
	my $query = "
SELECT 
    health_agent_name, 
    health_source_name, 
    health_source_weight 
FROM 
    health 
WHERE 
    health_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($target)."
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
		
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "results", value1 => $results
	}, file => $THIS_FILE, line => __LINE__});
	
	# This will have any weights added to it.
	my $health_score = 0;
	foreach my $row (@{$results})
	{
		my $health_agent_name    = $row->[0]; 
		my $health_source_name   = $row->[1]; 
		my $health_source_weight = $row->[2];
		$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
			name1 => "health_agent_name",    value1 => $health_agent_name, 
			name2 => "health_source_name",   value2 => $health_source_name, 
			name3 => "health_source_weight", value3 => $health_source_weight, 
		}, file => $THIS_FILE, line => __LINE__});
		
		$health_score += $health_source_weight;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "health_score", value1 => $health_score, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "health_score", value1 => $health_score, 
	}, file => $THIS_FILE, line => __LINE__});
	return($health_score);
}

# Get a list of Anvil! nodes as an array of hash references
sub get_nodes
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_nodes" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $include_deleted = $parameter->{include_deleted} ? $parameter->{include_deleted} : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "include_deleted", value1 => $include_deleted, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $query = "
SELECT 
    a.node_uuid, 
    a.node_anvil_uuid, 
    a.node_host_uuid, 
    a.node_remote_ip, 
    a.node_remote_port, 
    a.node_note, 
    a.node_bcn, 
    a.node_sn, 
    a.node_ifn, 
    a.node_password,
    b.host_name, 
    b.host_uuid, 
    a.modified_date 
FROM 
    nodes a,
    hosts b 
WHERE 
    a.node_host_uuid =  b.host_uuid ";
	if (not $include_deleted)
	{
		$query .= "
AND 
    a.node_note IS DISTINCT FROM 'DELETED'";
	}
	$query .= "
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
	
	my $return  = [];
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		my $node_uuid        = $row->[0];
		my $node_anvil_uuid  = $row->[1];
		my $node_host_uuid   = $row->[2];
		my $node_remote_ip   = $row->[3] ? $row->[3] : "";
		my $node_remote_port = $row->[4] ? $row->[4] : "";
		my $node_note        = $row->[5] ? $row->[5] : "";
		my $node_bcn         = $row->[6] ? $row->[6] : "";
		my $node_sn          = $row->[7] ? $row->[7] : "";
		my $node_ifn         = $row->[8] ? $row->[8] : "";
		my $node_password    = $row->[9] ? $row->[9] : "";
		my $host_name        = $row->[10];
		my $host_uuid        = $row->[11];
		my $modified_date    = $row->[12];
		$an->Log->entry({log_level => 3, message_key => "an_variables_0012", message_variables => {
			name1  => "node_uuid",        value1  => $node_uuid, 
			name2  => "node_anvil_uuid",  value2  => $node_anvil_uuid, 
			name3  => "node_host_uuid",   value3  => $node_host_uuid, 
			name4  => "node_remote_ip",   value4  => $node_remote_ip, 
			name5  => "node_remote_port", value5  => $node_remote_port, 
			name6  => "node_note",        value6  => $node_note, 
			name7  => "node_bcn",         value7  => $node_bcn, 
			name8  => "node_sn",          value8  => $node_sn, 
			name9  => "node_ifn",         value9  => $node_ifn, 
			name10 => "host_name",        value10 => $host_name, 
			name11 => "host_uuid",        value11 => $host_uuid, 
			name12 => "modified_date",    value12 => $modified_date, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
			name1 => "node_password", value1 => $node_password, 
		}, file => $THIS_FILE, line => __LINE__});
		push @{$return}, {
			node_uuid		=>	$node_uuid,
			node_anvil_uuid		=>	$node_anvil_uuid, 
			node_host_uuid		=>	$node_host_uuid, 
			node_remote_ip		=>	$node_remote_ip, 
			node_remote_port	=>	$node_remote_port, 
			node_note		=>	$node_note, 
			node_bcn		=>	$node_bcn, 
			node_sn			=>	$node_sn, 
			node_ifn		=>	$node_ifn, 
			host_name		=>	$host_name, 
			host_uuid		=>	$host_uuid, 
			node_password		=>	$node_password, 
			modified_date		=>	$modified_date, 
		};
	}
	
	return($return);
}

# Get a list of node's cache as an array of hash references
sub get_nodes_cache
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_nodes_cache" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	# The user may want cache data from all machines but only of a certain type.
	my $include_deleted = $parameter->{include_deleted} ? $parameter->{include_deleted} : 0;
	my $type            = $parameter->{type}            ? $parameter->{type}            : "";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "type",            value1 => $type,
		name2 => "include_deleted", value2 => $include_deleted, 
	}, file => $THIS_FILE, line => __LINE__});
	
	### NOTE: This is NOT restricted to the host because if this host doesn't have cache data for a given
	###       node, it might be able to use data cached by another host.
	my $query = "
SELECT 
    node_cache_uuid, 
    node_cache_host_uuid, 
    node_cache_node_uuid, 
    node_cache_name, 
    node_cache_data, 
    node_cache_note, 
    modified_date 
FROM 
    nodes_cache ";
	my $say_join = "WHERE";
	if (not $include_deleted)
	{
		$say_join =  "AND";
		$query    .= "
WHERE 
   node_cache_data IS DISTINCT FROM 'DELETED'";
	}
	if ($type)
	{
		   $query    .= "
$say_join 
    node_cache_name =  ".$an->data->{sys}{use_db_fh}->quote($type);
	}
	$query .= "
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
	
	my $return  = [];
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		my $node_cache_uuid      = $row->[0];
		my $node_cache_host_uuid = $row->[1];
		my $node_cache_node_uuid = $row->[2];
		my $node_cache_name      = $row->[3];
		my $node_cache_data      = $row->[4] ? $row->[4] : "";
		my $node_cache_note      = $row->[5] ? $row->[5] : "";
		my $modified_date        = $row->[6];
		$an->Log->entry({log_level => 3, message_key => "an_variables_0007", message_variables => {
			name1 => "node_cache_uuid",      value1 => $node_cache_uuid, 
			name2 => "node_cache_host_uuid", value2 => $node_cache_host_uuid, 
			name3 => "node_cache_node_uuid", value3 => $node_cache_node_uuid, 
			name4 => "node_cache_name",      value4 => $node_cache_name, 
			name5 => "node_cache_data",      value5 => $node_cache_data, 
			name6 => "node_cache_note",      value6 => $node_cache_note, 
			name7 => "modified_date",        value7 => $modified_date, 
		}, file => $THIS_FILE, line => __LINE__});
		push @{$return}, {
			node_cache_uuid		=>	$node_cache_uuid, 
			node_cache_host_uuid	=>	$node_cache_host_uuid, 
			node_cache_node_uuid	=>	$node_cache_node_uuid, 
			node_cache_name		=>	$node_cache_name, 
			node_cache_data		=>	$node_cache_data, 
			node_cache_note		=>	$node_cache_note, 
			modified_date		=>	$modified_date, 
		};
	}
	
	return($return);
}

# Get a list of Anvil! Owners as an array of hash references
sub get_notifications
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_notifications" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $include_deleted = $parameter->{include_deleted} ? $parameter->{include_deleted} : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "include_deleted", value1 => $include_deleted, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $query = "
SELECT 
    notify_uuid, 
    notify_name, 
    notify_target, 
    notify_language, 
    notify_level, 
    notify_units, 
    notify_note, 
    modified_date 
FROM 
    notifications ";
	if (not $include_deleted)
	{
		$query .= "
WHERE 
    notify_note IS DISTINCT FROM 'DELETED'";
	}
	$query .= "
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
	
	my $return  = [];
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		my $notify_uuid     = $row->[0];
		my $notify_name     = $row->[1];
		my $notify_target   = $row->[2];
		my $notify_language = $row->[3];
		my $notify_level    = $row->[4];
		my $notify_units    = $row->[5];
		my $notify_note     = $row->[6] ? $row->[6] : "";
		my $modified_date   = $row->[7];
		$an->Log->entry({log_level => 3, message_key => "an_variables_0008", message_variables => {
			name1 => "notify_uuid",     value1 => $notify_uuid, 
			name2 => "notify_name",     value2 => $notify_name, 
			name3 => "notify_target",   value3 => $notify_target, 
			name4 => "notify_language", value4 => $notify_language, 
			name5 => "notify_level",    value5 => $notify_level, 
			name6 => "notify_units",    value6 => $notify_units, 
			name7 => "notify_note",     value7 => $notify_note, 
			name8 => "modified_date",   value8 => $modified_date, 
		}, file => $THIS_FILE, line => __LINE__});
		push @{$return}, {
			notify_uuid	=>	$notify_uuid,
			notify_name	=>	$notify_name, 
			notify_target	=>	$notify_target, 
			notify_language	=>	$notify_language, 
			notify_level	=>	$notify_level, 
			notify_units	=>	$notify_units, 
			notify_note	=>	$notify_note, 
			modified_date	=>	$modified_date, 
		};
	}
	
	return($return);
}

# Get a list of Anvil! Owners as an array of hash references
sub get_owners
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_owners" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $include_deleted = $parameter->{include_deleted} ? $parameter->{include_deleted} : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "include_deleted", value1 => $include_deleted, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $query = "
SELECT 
    owner_uuid, 
    owner_name, 
    owner_note, 
    modified_date 
FROM 
    owners ";
	if (not $include_deleted)
	{
		$query .= "
WHERE 
    owner_note IS DISTINCT FROM 'DELETED'";
	}
	$query .= "
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
	
	my $return  = [];
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		my $owner_uuid    = $row->[0];
		my $owner_name    = $row->[1];
		my $owner_note    = $row->[2] ? $row->[2] : "";
		my $modified_date = $row->[3];
		$an->Log->entry({log_level => 3, message_key => "an_variables_0004", message_variables => {
			name1 => "owner_uuid",    value1 => $owner_uuid, 
			name2 => "owner_name",    value2 => $owner_name, 
			name3 => "owner_note",    value3 => $owner_note, 
			name4 => "modified_date", value4 => $modified_date, 
		}, file => $THIS_FILE, line => __LINE__});
		push @{$return}, {
			owner_uuid	=>	$owner_uuid,
			owner_name	=>	$owner_name, 
			owner_note	=>	$owner_note, 
			modified_date	=>	$modified_date, 
		};
	}
	
	return($return);
}

# This returns an array containing all of the power check commands for nodes that the caller knows about.
sub get_power_check_data
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_power_check_data" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	# If I am a node, I will check the local cluster.conf and override anything that conflicts with cache
	# as the cluster.conf is more accurate.
	my $return   = [];
	my $i_am_a   = $an->Get->what_am_i();
	my $hostname = $an->hostname();
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "i_am_a",   value1 => $i_am_a,
		name2 => "hostname", value2 => $hostname
	}, file => $THIS_FILE, line => __LINE__});
	
	# Parse the cluster.conf file. This will cause the cache to be up to date.
	if (($i_am_a eq "node") && (-e $an->data->{path}{cman_config}))
	{
		# Read and parse our cluster.conf (which updates the cache).
		$an->Striker->_parse_cluster_conf();
	}
	
	# Read the power_check data from cache for all the machines we know about.
	my $power_check_data = $an->ScanCore->get_nodes_cache({type => "power_check"});
	my $node_data        = $an->ScanCore->get_nodes();
	foreach my $hash_ref (@{$node_data})
	{
		my $node_name                                  = $hash_ref->{host_name};
		my $node_uuid                                  = $hash_ref->{node_uuid};
		   $an->data->{node}{uuid_to_name}{$node_uuid} = $node_name;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "node::uuid_to_name::$node_uuid", value1 => $an->data->{node}{uuid_to_name}{$node_uuid}, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	foreach my $hash_ref (@{$power_check_data})
	{
		# Ignore any data cache by other nodes.
		my $node_cache_host_uuid = $hash_ref->{node_cache_host_uuid}; 
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "sys::host_uuid",       value1 => $an->data->{sys}{host_uuid}, 
			name2 => "node_cache_host_uuid", value2 => $node_cache_host_uuid, 
		}, file => $THIS_FILE, line => __LINE__});
		next if $node_cache_host_uuid ne $an->data->{sys}{host_uuid};
		
		my $node_cache_node_uuid = $hash_ref->{node_cache_node_uuid};
		my $node_cache_data      = $hash_ref->{node_cache_data};
		my $node_name            = $an->data->{node}{uuid_to_name}{$node_cache_node_uuid};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
			name1 => "node_cache_node_uuid", value1 => $node_cache_node_uuid, 
			name2 => "node_cache_data",      value2 => $node_cache_data, 
			name3 => "node_name",            value3 => $node_name, 
		}, file => $THIS_FILE, line => __LINE__});
		
		# Find the IPMI entry, if any
		my $power_check_command = ($node_cache_data =~ /(fence_ipmilan .*?);/)[0];
		next if not $power_check_command;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "power_check_command", value1 => $power_check_command, 
		}, file => $THIS_FILE, line => __LINE__});
		
		# I need to remove the double-quotes from the '-p "<password>"'.
		$power_check_command =~ s/-p "(.*?)"/-p $1/;
		
		$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
			name1 => "node_name",            value1 => $node_name, 
			name2 => "node_cache_node_uuid", value2 => $node_cache_node_uuid, 
			name3 => "power_check_command",  value3 => $power_check_command, 
		}, file => $THIS_FILE, line => __LINE__});
		push @{$return}, {
			node_name           => $node_name,
			node_uuid           => $node_cache_node_uuid, 
			power_check_command => $power_check_command,
		};
	}
	
	return($return);
}

# Get a list of recipients (links between Anvil! systems and who receives alert notifications from it).
sub get_recipients
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_recipients" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $include_deleted = $parameter->{include_deleted} ? $parameter->{include_deleted} : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "include_deleted", value1 => $include_deleted, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $query = "
SELECT 
    recipient_uuid, 
    recipient_anvil_uuid, 
    recipient_notify_uuid, 
    recipient_notify_level, 
    recipient_note, 
    modified_date 
FROM 
    recipients ";
	if (not $include_deleted)
	{
		$query .= "
WHERE 
    recipient_note IS DISTINCT FROM 'DELETED'";
	}
	$query .= "
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
	
	my $return  = [];
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		my $recipient_uuid         =         $row->[0];
		my $recipient_anvil_uuid   =         $row->[1];
		my $recipient_notify_uuid  = defined $row->[2] ? $row->[2] : "";
		my $recipient_notify_level = defined $row->[3] ? $row->[3] : "";
		my $recipient_note         = defined $row->[4] ? $row->[4] : "";
		my $modified_date          =         $row->[5];
		$an->Log->entry({log_level => 3, message_key => "an_variables_0006", message_variables => {
			name1 => "recipient_uuid",         value1 => $recipient_uuid, 
			name2 => "recipient_anvil_uuid",   value2 => $recipient_anvil_uuid, 
			name3 => "recipient_notify_uuid",  value3 => $recipient_notify_uuid, 
			name4 => "recipient_notify_level", value4 => $recipient_notify_level, 
			name5 => "recipient_note",         value5 => $recipient_note, 
			name6 => "modified_date",          value6 => $modified_date, 
		}, file => $THIS_FILE, line => __LINE__});
		push @{$return}, {
			recipient_uuid		=>	$recipient_uuid,
			recipient_anvil_uuid	=>	$recipient_anvil_uuid, 
			recipient_notify_uuid	=>	$recipient_notify_uuid, 
			recipient_notify_level	=>	$recipient_notify_level, 
			recipient_note		=>	$recipient_note, 
			modified_date		=>	$modified_date, 
		};
	}
	
	return($return);
}

# Get a list of Anvil! servers as an array of hash references
sub get_servers
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_servers" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $include_deleted = $parameter->{include_deleted} ? $parameter->{include_deleted} : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "include_deleted", value1 => $include_deleted, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $query = "
SELECT 
    server_uuid, 
    server_anvil_uuid, 
    server_name, 
    server_stop_reason, 
    server_start_after, 
    server_start_delay, 
    server_note, 
    server_definition, 
    server_host, 
    server_state, 
    server_migration_type, 
    server_pre_migration_script, 
    server_pre_migration_arguments, 
    server_post_migration_script, 
    server_post_migration_arguments, 
    modified_date 
FROM 
    servers ";
	if (not $include_deleted)
	{
		$query .= "
WHERE 
    server_note IS DISTINCT FROM 'DELETED'";
	}
	$query .= "
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
	
	my $return  = [];
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		my $server_uuid                     =         $row->[0];
		my $server_anvil_uuid               =         $row->[1];
		my $server_name                     =         $row->[2];
		my $server_stop_reason              = defined $row->[3]  ? $row->[3]  : "";
		my $server_start_after              = defined $row->[4]  ? $row->[4]  : "";
		my $server_start_delay              =         $row->[5];
		my $server_note                     = defined $row->[6]  ? $row->[6]  : "";
		my $server_definition               =         $row->[7];
		my $server_host                     = defined $row->[8]  ? $row->[8]  : "";
		my $server_state                    = defined $row->[9]  ? $row->[9]  : "";
		my $server_migration_type           =         $row->[10];
		my $server_pre_migration_script     = defined $row->[11] ? $row->[11] : "";
		my $server_pre_migration_arguments  = defined $row->[12] ? $row->[12] : "";
		my $server_post_migration_script    = defined $row->[13] ? $row->[13] : "";
		my $server_post_migration_arguments = defined $row->[14] ? $row->[14] : "";
		my $modified_date                   =         $row->[15];
		$an->Log->entry({log_level => 3, message_key => "an_variables_0016", message_variables => {
			name1  => "server_uuid",                     value1  => $server_uuid, 
			name2  => "server_anvil_uuid",               value2  => $server_anvil_uuid, 
			name3  => "server_name",                     value3  => $server_name, 
			name4  => "server_stop_reason",              value4  => $server_stop_reason, 
			name5  => "server_start_after",              value5  => $server_start_after, 
			name6  => "server_start_delay",              value6  => $server_start_delay, 
			name7  => "server_note",                     value7  => $server_note, 
			name8  => "server_definition",               value8  => $server_definition, 
			name9  => "server_host",                     value9  => $server_host, 
			name10 => "server_state",                    value10 => $server_state, 
			name11 => "server_migration_type",           value11 => $server_migration_type, 
			name12 => "server_pre_migration_script",     value12 => $server_pre_migration_script, 
			name13 => "server_pre_migration_arguments",  value13 => $server_pre_migration_arguments, 
			name14 => "server_post_migration_script",    value14 => $server_post_migration_script, 
			name15 => "server_post_migration_arguments", value15 => $server_post_migration_arguments, 
			name16 => "modified_date",                   value16 => $modified_date, 
		}, file => $THIS_FILE, line => __LINE__});
		push @{$return}, {
			server_uuid			=>	$server_uuid,
			server_anvil_uuid		=>	$server_anvil_uuid, 
			server_name			=>	$server_name, 
			server_stop_reason		=>	$server_stop_reason, 
			server_start_after		=>	$server_start_after, 
			server_start_delay		=>	$server_start_delay, 
			server_note			=>	$server_note, 
			server_definition		=>	$server_definition, 
			server_host			=>	$server_host, 
			server_state			=>	$server_state, 
			server_migration_type		=>	$server_migration_type, 
			server_pre_migration_script	=>	$server_pre_migration_script, 
			server_pre_migration_arguments	=>	$server_pre_migration_arguments, 
			server_post_migration_script	=>	$server_post_migration_script, 
			server_post_migration_arguments	=>	$server_post_migration_arguments, 
			modified_date			=>	$modified_date, 
		};
	}
	
	return($return);
}

# Get a list of Anvil! SMTP mail servers as an array of hash references
sub get_smtp
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_smtp" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $include_deleted = $parameter->{include_deleted} ? $parameter->{include_deleted} : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "include_deleted", value1 => $include_deleted, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $query = "
SELECT 
    smtp_uuid, 
    smtp_server, 
    smtp_port, 
    smtp_username, 
    smtp_password, 
    smtp_security, 
    smtp_authentication, 
    smtp_helo_domain,
    smtp_alt_server, 
    smtp_alt_port, 
    smtp_note, 
    modified_date 
FROM 
    smtp ";
	if (not $include_deleted)
	{
		$query .= "
WHERE 
    smtp_note IS DISTINCT FROM 'DELETED'";
	}
	$query .= "
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
	
	my $return  = [];
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		my $smtp_uuid           =         $row->[0];
		my $smtp_server         =         $row->[1];
		my $smtp_port           =         $row->[2];
		my $smtp_username       =         $row->[3];
		my $smtp_password       =         $row->[4];
		my $smtp_security       =         $row->[5];
		my $smtp_authentication =         $row->[6];
		my $smtp_helo_domain    =         $row->[7];
		my $smtp_alt_server     = defined $row->[8]  ? $row->[8]  : "";
		my $smtp_alt_port       = defined $row->[9]  ? $row->[9]  : ""; 
		my $smtp_note           = defined $row->[10] ? $row->[10] : "";
		my $modified_date       =         $row->[11];
		$an->Log->entry({log_level => 3, message_key => "an_variables_0011", message_variables => {
			name1  => "smtp_uuid",           value1  => $smtp_uuid, 
			name2  => "smtp_server",         value2  => $smtp_server, 
			name3  => "smtp_port",           value3  => $smtp_port, 
			name4  => "smtp_username",       value4  => $smtp_username, 
			name5  => "smtp_security",       value5  => $smtp_security, 
			name6  => "smtp_authentication", value6  => $smtp_authentication, 
			name7  => "smtp_helo_domain",    value7  => $smtp_helo_domain, 
			name8  => "smtp_alt_server",     value8  => $smtp_alt_server, 
			name9  => "smtp_alt_port",       value9  => $smtp_alt_port, 
			name10 => "smtp_note",           value10 => $smtp_note, 
			name11 => "modified_date",       value11 => $modified_date, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
			name1 => "smtp_password", value1 => $smtp_password, 
		}, file => $THIS_FILE, line => __LINE__});
		
		push @{$return}, {
			smtp_uuid		=>	$smtp_uuid,
			smtp_server		=>	$smtp_server, 
			smtp_port		=>	$smtp_port, 
			smtp_username		=>	$smtp_username, 
			smtp_password		=>	$smtp_password, 
			smtp_security		=>	$smtp_security, 
			smtp_authentication	=>	$smtp_authentication, 
			smtp_helo_domain	=>	$smtp_helo_domain, 
			smtp_alt_server		=>	$smtp_alt_server, 
			smtp_alt_port		=>	$smtp_alt_port, 
			smtp_note		=>	$smtp_note, 
			modified_date		=>	$modified_date, 
		};
	}
	
	return($return);
}

# This gets information on Striker peers.
sub get_striker_peers
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_striker_peers" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	# Loop through the Striker peers that we know of and test access to each.
	my $return_code = 0;
	my $local_db_id = "";
	if ($an->data->{sys}{local_db_id})
	{
		$local_db_id = $an->data->{sys}{local_db_id};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "local_db_id", value1 => $local_db_id, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	else
	{
		my $possible_hosts = $an->Striker->build_local_host_list();
		   $local_db_id    = $an->Striker->get_db_id_from_striker_conf({hosts => $possible_hosts});
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "local_db_id", value1 => $local_db_id, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	foreach my $db_id (sort {$a cmp $b} keys %{$an->data->{scancore}{db}})
	{
		next if (($local_db_id) && ($db_id eq $local_db_id));
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "db_id", value1 => $db_id, 
		}, file => $THIS_FILE, line => __LINE__});
		
		### TODO: We should have a way to know if we need a non-standard port to SSH into a 
		###       peer's dashboard...
		# Try to connect.
		my $target   =  $an->data->{scancore}{db}{$db_id}{host};
			$target   =~ s/:.*//;
		my $port     =  22;
		my $password =  $an->data->{scancore}{db}{$db_id}{password};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "target", value1 => $target, 
			name2 => "port",   value2 => $port, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
			name1 => "password", value1 => $password, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $access =  $an->Check->access({
				target   => $target,
				port     => $port,
				password => $password,
			});
		
		# Record this
		$an->data->{sys}{dashboard}{$target}{use_ip}   = $target;
		$an->data->{sys}{dashboard}{$target}{use_port} = $port; 
		$an->data->{sys}{dashboard}{$target}{password} = $password; 
		$an->data->{sys}{dashboard}{$target}{online}   = 0;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0004", message_variables => {
			name1 => "access",                              value1 => $access, 
			name2 => "sys::dashboard::${target}::use_ip",   value2 => $an->data->{sys}{dashboard}{$target}{use_ip}, 
			name3 => "sys::dashboard::${target}::use_port", value3 => $an->data->{sys}{dashboard}{$target}{use_port}, 
			name4 => "sys::dashboard::${target}::online",   value4 => $an->data->{sys}{dashboard}{$target}{online}, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
			name1 => "sys::dashboard::${target}::password", value1 => $an->data->{sys}{dashboard}{$target}{password}, 
		}, file => $THIS_FILE, line => __LINE__});
		if ($access)
		{
			# Woot!
			$an->data->{sys}{dashboard}{$target}{online} = 1;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "sys::dashboard::${target}::online", value1 => $an->data->{sys}{dashboard}{$target}{online}, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	return(0);
}

# Returns (and sets, if requested) the health of the target.
sub host_state
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "host_state" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	# This will store the state.
	my $state = "";
	
	# If I don't have a target, use the local host.
	my $target = $parameter->{target} ? $parameter->{target} : "host_uuid";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "target", value1 => $target, 
	}, file => $THIS_FILE, line => __LINE__});
	if (not $an->Validate->is_uuid({uuid => $target}))
	{
		# Translate the target to a host_uuid
		$target = $an->Get->uuid({get => $target});
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "target", value1 => $target, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $valid = $an->Validate->is_uuid({uuid => $target});
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "valid", value1 => $valid, 
		}, file => $THIS_FILE, line => __LINE__});
		if (not $valid)
		{
			# No host 
			$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0099", message_variables => { target => $parameter->{target} }, code => 99, file => $THIS_FILE, line => __LINE__});
			return("");
		}
	}
	
	# First, read the current state. We'll update it if needed in a minute.
	my $query = "
SELECT 
    host_health 
FROM 
    hosts 
WHERE 
    host_uuid = ".$an->data->{sys}{use_db_fh}->quote($target)." 
;";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	
	# If the count is '0', the host wasn't found and we've hit a program error.
	if (not $count)
	{
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0100", message_variables => { target => $target }, code => 100, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	my $current_health = "";
	foreach my $row (@{$results})
	{
		$current_health = $row->[0] ? $row->[0] : "";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "current_health", value1 => $current_health, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	# Am I setting?
	my $host_health = $parameter->{set} ? $parameter->{set} : "";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "host_health", value1 => $host_health, 
	}, file => $THIS_FILE, line => __LINE__});
	if ($host_health)
	{
		# Yup. Has it changed?
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "current_health", value1 => $current_health, 
			name2 => "host_health",    value2 => $host_health, 
		}, file => $THIS_FILE, line => __LINE__});
		if ($current_health ne $host_health)
		{
			# It has changed.
			   $current_health = $host_health;
			my $query          = "
UPDATE 
    hosts 
SET 
    host_health   = ".$an->data->{sys}{use_db_fh}->quote($host_health).", 
    modified_date = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    host_uuid     = ".$an->data->{sys}{use_db_fh}->quote($target)." 
";
			$query =~ s/'NULL'/NULL/g;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "query", value1 => $query
			}, file => $THIS_FILE, line => __LINE__});
			$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
		}
	}
	
	# If there is no current health data, assume the node is healthy.
	if ($current_health eq "")
	{
		$current_health = "ok";
		$an->Log->entry({log_level => 1, message_key => "warning_message_0016", message_variables => {
			target => $target, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "current_health", value1 => $current_health, 
	}, file => $THIS_FILE, line => __LINE__});
	return($current_health);
}

# This updates (or inserts) a record in the 'anvils' table.
sub insert_or_update_anvils
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "insert_or_update_anvils" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $anvil_uuid        = $parameter->{anvil_uuid}        ? $parameter->{anvil_uuid}        : "";
	my $anvil_owner_uuid  = $parameter->{anvil_owner_uuid}  ? $parameter->{anvil_owner_uuid}  : "";
	my $anvil_smtp_uuid   = $parameter->{anvil_smtp_uuid}   ? $parameter->{anvil_smtp_uuid}   : "";
	my $anvil_name        = $parameter->{anvil_name}        ? $parameter->{anvil_name}        : "";
	my $anvil_description = $parameter->{anvil_description} ? $parameter->{anvil_description} : "";
	my $anvil_note        = $parameter->{anvil_note}        ? $parameter->{anvil_note}        : "";
	my $anvil_password    = $parameter->{anvil_password}    ? $parameter->{anvil_password}    : "";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0006", message_variables => {
		name1 => "anvil_uuid",        value1 => $anvil_uuid, 
		name2 => "anvil_owner_uuid",  value2 => $anvil_owner_uuid, 
		name3 => "anvil_smtp_uuid",   value3 => $anvil_smtp_uuid, 
		name4 => "anvil_name",        value4 => $anvil_name, 
		name5 => "anvil_description", value5 => $anvil_description, 
		name6 => "anvil_note",        value6 => $anvil_note, 
	}, file => $THIS_FILE, line => __LINE__});
	$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
		name1 => "anvil_password", value1 => $anvil_password, 
	}, file => $THIS_FILE, line => __LINE__});
	if (not $anvil_name)
	{
		# Throw an error and exit.
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0079", code => 79, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	# If we don't have a UUID, see if we can find one for the given Anvil! name.
	if (not $anvil_uuid)
	{
		my $query = "
SELECT 
    anvil_uuid 
FROM 
    anvils 
WHERE 
    anvil_name = ".$an->data->{sys}{use_db_fh}->quote($anvil_name)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$anvil_uuid = $row->[0];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "anvil_uuid", value1 => $anvil_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	# If I still don't have an anvil_uuid, we're INSERT'ing .
	if (not $anvil_uuid)
	{
		# INSERT, *if* we have an owner and smtp UUID.
		if (not $anvil_owner_uuid)
		{
			$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0080", code => 80, file => $THIS_FILE, line => __LINE__});
			return("");
		}
		### NOTE: SMTP UUID is no longer required.
		#if (not $anvil_smtp_uuid)
		#{
		#	$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0081", code => 81, file => $THIS_FILE, line => __LINE__});
		#	return("");
		#}
		
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "anvil_smtp_uuid", value1 => $anvil_smtp_uuid, 
		}, file => $THIS_FILE, line => __LINE__});
		if ($anvil_smtp_uuid)
		{
			$anvil_smtp_uuid = $an->data->{sys}{use_db_fh}->quote($anvil_smtp_uuid);
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "anvil_smtp_uuid", value1 => $anvil_smtp_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		else
		{
			$anvil_smtp_uuid = "NULL";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "anvil_smtp_uuid", value1 => $anvil_smtp_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		
		   $anvil_uuid = $an->Get->uuid();
		my $query      = "
INSERT INTO 
    anvils 
(
    anvil_uuid,
    anvil_owner_uuid,
    anvil_smtp_uuid,
    anvil_name,
    anvil_description,
    anvil_note,
    anvil_password,
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($anvil_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($anvil_owner_uuid).", 
    $anvil_smtp_uuid, 
    ".$an->data->{sys}{use_db_fh}->quote($anvil_name).", 
    ".$an->data->{sys}{use_db_fh}->quote($anvil_description).", 
    ".$an->data->{sys}{use_db_fh}->quote($anvil_note).", 
    ".$an->data->{sys}{use_db_fh}->quote($anvil_password).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Query the rest of the values and see if anything changed.
		my $query = "
SELECT 
    anvil_owner_uuid,
    anvil_smtp_uuid,
    anvil_name,
    anvil_description,
    anvil_note,
    anvil_password 
FROM 
    anvils 
WHERE 
    anvil_uuid = ".$an->data->{sys}{use_db_fh}->quote($anvil_uuid)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			my $old_anvil_owner_uuid  = $row->[0];
			my $old_anvil_smtp_uuid   = $row->[1];
			my $old_anvil_name        = $row->[2];
			my $old_anvil_description = $row->[3];
			my $old_anvil_note        = $row->[4];
			my $old_anvil_password    = $row->[5];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0006", message_variables => {
				name1 => "old_anvil_owner_uuid",  value1 => $old_anvil_owner_uuid, 
				name2 => "old_anvil_smtp_uuid",   value2 => $old_anvil_smtp_uuid, 
				name3 => "old_anvil_name",        value3 => $old_anvil_name, 
				name4 => "old_anvil_description", value4 => $old_anvil_description, 
				name5 => "old_anvil_note",        value5 => $old_anvil_note, 
				name6 => "old_anvil_password",    value6 => $old_anvil_password, 
			}, file => $THIS_FILE, line => __LINE__});
			
			# Anything change?
			if (($old_anvil_owner_uuid  ne $anvil_owner_uuid)  or 
			    ($old_anvil_smtp_uuid   ne $anvil_smtp_uuid)   or 
			    ($old_anvil_name        ne $anvil_name)        or 
			    ($old_anvil_description ne $anvil_description) or 
			    ($old_anvil_note        ne $anvil_note)        or 
			    ($old_anvil_password    ne $anvil_password)) 
			{
				# Something changed, save.
				my $say_smtp = $anvil_smtp_uuid ? $an->data->{sys}{use_db_fh}->quote($anvil_smtp_uuid) : "NULL";
				my $query    = "
UPDATE 
    anvils 
SET 
    anvil_owner_uuid  = ".$an->data->{sys}{use_db_fh}->quote($anvil_owner_uuid).",
    anvil_smtp_uuid   = $say_smtp,
    anvil_name        = ".$an->data->{sys}{use_db_fh}->quote($anvil_name).", 
    anvil_description = ".$an->data->{sys}{use_db_fh}->quote($anvil_description).",
    anvil_note        = ".$an->data->{sys}{use_db_fh}->quote($anvil_note).",
    anvil_password    = ".$an->data->{sys}{use_db_fh}->quote($anvil_password).",
    modified_date     = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    anvil_uuid        = ".$an->data->{sys}{use_db_fh}->quote($anvil_uuid)." 
";
				$query =~ s/'NULL'/NULL/g;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "query", value1 => $query, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	return($anvil_uuid);
}

### NOTE: Use 'lvchange --permission r <lv>' to flip the LV to read-only before starting an image process.
# This updates (or inserts) a record in the 'dr_jobs' table.
sub insert_or_update_dr_jobs
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "insert_or_update_dr_jobs" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $dr_job_uuid           = $parameter->{dr_job_uuid}           ? $parameter->{dr_job_uuid}           : "";
	my $dr_job_dr_target_uuid = $parameter->{dr_job_dr_target_uuid} ? $parameter->{dr_job_dr_target_uuid} : "";
	my $dr_job_anvil_uuid     = $parameter->{dr_job_anvil_uuid}     ? $parameter->{dr_job_anvil_uuid}     : "";
	my $dr_job_name           = $parameter->{dr_job_name}           ? $parameter->{dr_job_name}           : "";
	my $dr_job_note           = $parameter->{dr_job_note}           ? $parameter->{dr_job_note}           : "NULL";
	my $dr_job_servers        = $parameter->{dr_job_servers}        ? $parameter->{dr_job_servers}        : "";
	my $dr_job_auto_prune     = $parameter->{dr_job_auto_prune}     ? $parameter->{dr_job_auto_prune}     : "";
	my $dr_job_schedule       = $parameter->{dr_job_schedule}       ? $parameter->{dr_job_schedule}       : "";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0008", message_variables => {
		name1 => "dr_job_uuid",           value1 => $dr_job_uuid, 
		name2 => "dr_job_dr_target_uuid", value2 => $dr_job_dr_target_uuid, 
		name3 => "dr_job_anvil_uuid",     value3 => $dr_job_anvil_uuid, 
		name4 => "dr_job_name",           value4 => $dr_job_name, 
		name5 => "dr_job_note",           value5 => $dr_job_note, 
		name6 => "dr_job_servers",        value6 => $dr_job_servers, 
		name7 => "dr_job_auto_prune",     value7 => $dr_job_auto_prune, 
		name8 => "dr_job_schedule",       value8 => $dr_job_schedule, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# If we don't have a UUID, see if we can find one for the given host UUID.
	if (not $dr_job_uuid)
	{
		my $query = "
SELECT 
    dr_job_uuid 
FROM 
    dr_jobs 
WHERE 
    dr_job_name = ".$an->data->{sys}{use_db_fh}->quote($dr_job_name)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$dr_job_uuid = $row->[0];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "dr_job_uuid", value1 => $dr_job_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	# If I still don't have a dr_job_uuid, we're INSERT'ing .
	if (not $dr_job_uuid)
	{
		# INSERT.
		$dr_job_uuid = $an->Get->uuid();
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "dr_job_uuid", value1 => $dr_job_uuid, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $query = "
INSERT INTO 
    dr_jobs 
(
    dr_job_uuid,
    dr_job_dr_target_uuid, 
    dr_job_anvil_uuid, 
    dr_job_name, 
    dr_job_note, 
    dr_job_servers, 
    dr_job_auto_prune, 
    dr_job_schedule, 
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($dr_job_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_job_dr_target_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_job_anvil_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_job_name).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_job_note).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_job_servers).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_job_auto_prune).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_job_schedule).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Query the rest of the values and see if anything changed.
		my $query = "
SELECT 
    dr_job_dr_target_uuid, 
    dr_job_anvil_uuid, 
    dr_job_name, 
    dr_job_note, 
    dr_job_servers, 
    dr_job_auto_prune, 
    dr_job_schedule 
FROM 
    dr_jobs 
WHERE 
    dr_job_uuid = ".$an->data->{sys}{use_db_fh}->quote($dr_job_uuid)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			my $old_dr_job_dr_target_uuid =         $row->[0];
			my $old_dr_job_anvil_uuid     =         $row->[1];
			my $old_dr_job_name           =         $row->[2];
			my $old_dr_job_note           = defined $row->[3] ? $row->[3] : "";
			my $old_dr_job_servers        =         $row->[4];
			my $old_dr_job_auto_prune     =         $row->[5];
			my $old_dr_job_schedule       =         $row->[6];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0007", message_variables => {
				name1 => "old_dr_job_dr_target_uuid", value1 => $old_dr_job_dr_target_uuid, 
				name2 => "old_dr_job_anvil_uuid",     value2 => $old_dr_job_anvil_uuid, 
				name3 => "old_dr_job_name",           value3 => $old_dr_job_name, 
				name4 => "old_dr_job_note",           value4 => $old_dr_job_note, 
				name5 => "old_dr_job_servers",        value5 => $old_dr_job_servers, 
				name6 => "old_dr_job_auto_prune",     value6 => $old_dr_job_auto_prune, 
				name7 => "old_dr_job_schedule",       value7 => $old_dr_job_schedule, 
			}, file => $THIS_FILE, line => __LINE__});
			
			# Anything change?
			if (($old_dr_job_dr_target_uuid ne $dr_job_dr_target_uuid) or 
			    ($old_dr_job_anvil_uuid     ne $dr_job_anvil_uuid)     or 
			    ($old_dr_job_name           ne $dr_job_name)           or 
			    ($old_dr_job_note           ne $dr_job_note)           or 
			    ($old_dr_job_servers        ne $dr_job_servers)        or 
			    ($old_dr_job_auto_prune     ne $dr_job_auto_prune)     or 
			    ($old_dr_job_schedule       ne $dr_job_schedule))
			{
				# Something changed, save.
				my $query = "
UPDATE 
    dr_jobs 
SET 
    dr_job_dr_target_uuid = ".$an->data->{sys}{use_db_fh}->quote($dr_job_dr_target_uuid).", 
    dr_job_anvil_uuid     = ".$an->data->{sys}{use_db_fh}->quote($dr_job_anvil_uuid).", 
    dr_job_name           = ".$an->data->{sys}{use_db_fh}->quote($dr_job_name).", 
    dr_job_note           = ".$an->data->{sys}{use_db_fh}->quote($dr_job_note).", 
    dr_job_servers        = ".$an->data->{sys}{use_db_fh}->quote($dr_job_servers).", 
    dr_job_auto_prune     = ".$an->data->{sys}{use_db_fh}->quote($dr_job_auto_prune).", 
    dr_job_schedule       = ".$an->data->{sys}{use_db_fh}->quote($dr_job_schedule).", 
    modified_date         = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    dr_job_uuid           = ".$an->data->{sys}{use_db_fh}->quote($dr_job_uuid)." 
";
				$query =~ s/'NULL'/NULL/g;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "query", value1 => $query, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	return($dr_job_uuid);
}

# This updates (or inserts) a record in the 'dr_targets' table.
sub insert_or_update_dr_targets
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "insert_or_update_dr_targets" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $dr_target_uuid            = $parameter->{dr_target_uuid}            ? $parameter->{dr_target_uuid}            : "";
	my $dr_target_name            = $parameter->{dr_target_name}            ? $parameter->{dr_target_name}            : "";
	my $dr_target_note            = $parameter->{dr_target_note}            ? $parameter->{dr_target_note}            : "NULL";
	my $dr_target_address         = $parameter->{dr_target_address}         ? $parameter->{dr_target_address}         : "";
	my $dr_target_password        = $parameter->{dr_target_password}        ? $parameter->{dr_target_password}        : "NULL";
	my $dr_target_tcp_port        = $parameter->{dr_target_tcp_port}        ? $parameter->{dr_target_tcp_port}        : "NULL";
	my $dr_target_use_cache       = $parameter->{dr_target_use_cache}       ? $parameter->{dr_target_use_cache}       : "";
	my $dr_target_store           = $parameter->{dr_target_store}           ? $parameter->{dr_target_store}           : "";
	my $dr_target_copies          = $parameter->{dr_target_copies}          ? $parameter->{dr_target_copies}          : "";
	my $dr_target_bandwidth_limit = $parameter->{dr_target_bandwidth_limit} ? $parameter->{dr_target_bandwidth_limit} : "NULL";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0009", message_variables => {
		name1 => "dr_target_uuid",            value1 => $dr_target_uuid, 
		name2 => "dr_target_name",            value2 => $dr_target_name, 
		name3 => "dr_target_note",            value3 => $dr_target_note, 
		name4 => "dr_target_address",         value4 => $dr_target_address, 
		name5 => "dr_target_tcp_port",        value5 => $dr_target_tcp_port, 
		name6 => "dr_target_use_cache",       value6 => $dr_target_use_cache, 
		name7 => "dr_target_store",           value7 => $dr_target_store, 
		name8 => "dr_target_copies",          value8 => $dr_target_copies, 
		name9 => "dr_target_bandwidth_limit", value9 => $dr_target_bandwidth_limit, 
	}, file => $THIS_FILE, line => __LINE__});
	$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
		name1 => "dr_target_password", value1 => $dr_target_password, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# If we don't have a UUID, see if we can find one for the given host UUID.
	if (not $dr_target_uuid)
	{
		my $query = "
SELECT 
    dr_target_uuid 
FROM 
    dr_targets 
WHERE 
    dr_target_name = ".$an->data->{sys}{use_db_fh}->quote($dr_target_name)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$dr_target_uuid = $row->[0];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "dr_target_uuid", value1 => $dr_target_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	# If I still don't have a dr_target_uuid, we're INSERT'ing .
	if (not $dr_target_uuid)
	{
		# INSERT.
		   $dr_target_uuid = $an->Get->uuid();
		my $query          = "
INSERT INTO 
    dr_targets 
(
    dr_target_uuid,
    dr_target_name, 
    dr_target_note, 
    dr_target_address, 
    dr_target_password, 
    dr_target_tcp_port, 
    dr_target_use_cache, 
    dr_target_store, 
    dr_target_copies, 
    dr_target_bandwidth_limit, 
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($dr_target_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_target_name).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_target_note).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_target_address).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_target_password).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_target_tcp_port).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_target_use_cache).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_target_store).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_target_copies).", 
    ".$an->data->{sys}{use_db_fh}->quote($dr_target_bandwidth_limit).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Query the rest of the values and see if anything changed.
		my $query = "
SELECT 
    dr_target_name, 
    dr_target_note, 
    dr_target_address, 
    dr_target_password, 
    dr_target_tcp_port, 
    dr_target_use_cache, 
    dr_target_store, 
    dr_target_copies, 
    dr_target_bandwidth_limit 
FROM 
    dr_targets 
WHERE 
    dr_target_uuid = ".$an->data->{sys}{use_db_fh}->quote($dr_target_uuid)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			my $old_dr_target_name            =         $row->[0];
			my $old_dr_target_note            = defined $row->[1] ? $row->[1] : ""; 
			my $old_dr_target_address         =         $row->[2]; 
			my $old_dr_target_password        = defined $row->[3] ? $row->[3] : ""; 
			my $old_dr_target_tcp_port        = defined $row->[4] ? $row->[4] : ""; 
			my $old_dr_target_use_cache       =         $row->[5]; 
			my $old_dr_target_store           =         $row->[6]; 
			my $old_dr_target_copies          =         $row->[7]; 
			my $old_dr_target_bandwidth_limit = defined $row->[8] ? $row->[8] : ""; 
			$an->Log->entry({log_level => 3, message_key => "an_variables_0008", message_variables => {
				name1 => "old_dr_target_name",            value1 => $old_dr_target_name, 
				name2 => "old_dr_target_note",            value2 => $old_dr_target_note, 
				name3 => "old_dr_target_address",         value3 => $old_dr_target_address, 
				name4 => "old_dr_target_tcp_port",        value4 => $old_dr_target_tcp_port, 
				name5 => "old_dr_target_use_cache",       value5 => $old_dr_target_use_cache, 
				name6 => "old_dr_target_store",           value6 => $old_dr_target_store, 
				name7 => "old_dr_target_copies",          value7 => $old_dr_target_copies, 
				name8 => "old_dr_target_bandwidth_limit", value8 => $old_dr_target_bandwidth_limit, 
			}, file => $THIS_FILE, line => __LINE__});
			$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
				name1 => "old_dr_target_password", value1 => $old_dr_target_password, 
			}, file => $THIS_FILE, line => __LINE__});
			
			# Anything change?
			if (($old_dr_target_name            ne $dr_target_name)       or 
			    ($old_dr_target_note            ne $dr_target_note)       or 
			    ($old_dr_target_address         ne $dr_target_address)    or 
			    ($old_dr_target_password        ne $dr_target_password)   or 
			    ($old_dr_target_tcp_port        ne $dr_target_tcp_port)   or 
			    ($old_dr_target_use_cache       ne $dr_target_use_cache)  or 
			    ($old_dr_target_store           ne $dr_target_store)      or 
			    ($old_dr_target_copies          ne $dr_target_copies)     or 
			    ($old_dr_target_bandwidth_limit ne $dr_target_bandwidth_limit))
			{
				# Something changed, save.
				my $query = "
UPDATE 
    dr_targets 
SET 
    dr_target_name            = ".$an->data->{sys}{use_db_fh}->quote($dr_target_name).", 
    dr_target_note            = ".$an->data->{sys}{use_db_fh}->quote($dr_target_note).", 
    dr_target_address         = ".$an->data->{sys}{use_db_fh}->quote($dr_target_address).", 
    dr_target_password        = ".$an->data->{sys}{use_db_fh}->quote($dr_target_password).", 
    dr_target_tcp_port        = ".$an->data->{sys}{use_db_fh}->quote($dr_target_tcp_port).", 
    dr_target_use_cache       = ".$an->data->{sys}{use_db_fh}->quote($dr_target_use_cache).", 
    dr_target_store           = ".$an->data->{sys}{use_db_fh}->quote($dr_target_store).", 
    dr_target_copies          = ".$an->data->{sys}{use_db_fh}->quote($dr_target_copies).", 
    dr_target_bandwidth_limit = ".$an->data->{sys}{use_db_fh}->quote($dr_target_bandwidth_limit).", 
    modified_date             = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    dr_target_uuid        = ".$an->data->{sys}{use_db_fh}->quote($dr_target_uuid)." 
";
				$query =~ s/'NULL'/NULL/g;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "query", value1 => $query, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	return($dr_target_uuid);
}

# This updates (or inserts) a record in the 'health' table. Different from other tables, a new value of '0'
# will delete the record.
sub insert_or_update_health
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 2, title_key => "tools_log_0001", title_variables => { function => "insert_or_update_health" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $health_uuid          = $parameter->{health_uuid}          ? $parameter->{health_uuid}          : "";
	my $health_host_uuid     = $parameter->{health_host_uuid}     ? $parameter->{health_host_uuid}     : $an->data->{sys}{host_uuid};
	my $health_agent_name    = $parameter->{health_agent_name}    ? $parameter->{health_agent_name}    : "";
	my $health_source_name   = $parameter->{health_source_name}   ? $parameter->{health_source_name}   : "";
	my $health_source_weight = $parameter->{health_source_weight} ? $parameter->{health_source_weight} : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0005", message_variables => {
		name1 => "health_uuid",          value1 => $health_uuid, 
		name2 => "health_host_uuid",     value2 => $health_host_uuid, 
		name3 => "health_agent_name",    value3 => $health_agent_name, 
		name4 => "health_source_name",   value4 => $health_source_name, 
		name5 => "health_source_weight", value5 => $health_source_weight, 
	}, file => $THIS_FILE, line => __LINE__});
	
	### TODO: Add checks
	if (not $health_agent_name)
	{
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0025", code => 25, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	if (not $health_source_name)
	{
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0026", code => 26, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	# If I have an old value, we'll store it in this variable.
	my $old_health_source_weight = 0;
	
	# If we don't have a UUID, see if we can find one for the given host UUID.
	if ($health_uuid)
	{
		# Read the old value
		my $query = "
SELECT 
    health_source_weight 
FROM 
    health 
WHERE 
    health_uuid = ".$an->data->{sys}{use_db_fh}->quote($health_uuid)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query
		}, file => $THIS_FILE, line => __LINE__});
			
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "results", value1 => $results
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$old_health_source_weight = $row->[0];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "old_health_source_weight", value1 => $old_health_source_weight, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	else
	{
		my $query = "
SELECT 
    health_uuid,
    health_source_weight 
FROM 
    health 
WHERE 
    health_host_uuid   = ".$an->data->{sys}{use_db_fh}->quote($health_host_uuid)." 
AND 
    health_agent_name  = ".$an->data->{sys}{use_db_fh}->quote($health_agent_name)."
AND 
    health_source_name = ".$an->data->{sys}{use_db_fh}->quote($health_source_name)."
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query
		}, file => $THIS_FILE, line => __LINE__});
			
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "results", value1 => $results
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$health_uuid              = $row->[0]; 
			$old_health_source_weight = $row->[1];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "health_uuid",              value1 => $health_uuid, 
				name2 => "old_health_source_weight", value2 => $old_health_source_weight, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	if ($health_uuid)
	{
		# I have a health_uuid. Do I have a weight? If so, has it changed?
		if (not $health_source_weight)
		{
			# No weight, delete the entry. This is a two-step process to make sure the update to 
			# DELETED and the actually delete happen together.
			my $query = "
UPDATE 
    health 
SET 
    health_source_name = 'DELETED', 
    modified_date      = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
WHERE 
    health_uuid        = ".$an->data->{sys}{use_db_fh}->quote($health_uuid)."
;";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "query", value1 => $query, 
			}, file => $THIS_FILE, line => __LINE__});
			push @{$an->data->{sys}{sql}}, $query;
			
			$query = "
DELETE FROM 
    health 
WHERE 
    health_uuid        = ".$an->data->{sys}{use_db_fh}->quote($health_uuid)."
;";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "query", value1 => $query, 
			}, file => $THIS_FILE, line => __LINE__});
			push @{$an->data->{sys}{sql}}, $query;
			
			# Commit 
			$an->DB->commit_sql({source => $THIS_FILE, line => __LINE__});
			
			# Set the health_uuid to be 'deleted' so the caller knows we cleared it.
			$health_uuid = "deleted";
		}
		elsif ($health_source_weight ne $old_health_source_weight)
		{
			# Update the weight.
			my $query = "
UPDATE 
    health 
SET 
    health_source_weight = ".$an->data->{sys}{use_db_fh}->quote($health_source_weight).", 
    modified_date        = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
WHERE 
    health_uuid          = ".$an->data->{sys}{use_db_fh}->quote($health_uuid)."
;";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "query", value1 => $query, 
			}, file => $THIS_FILE, line => __LINE__});
			$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
		}
	}
	else
	{
		# I don't have a health_uuid. Do I have a weight?
		if ($health_source_weight)
		{
			# Yes, INSERT the new value.
			   $health_uuid = $an->Get->uuid();
			my $query       = "
INSERT INTO 
    health 
(
    health_uuid,
    health_host_uuid, 
    health_agent_name, 
    health_source_name, 
    health_source_weight, 
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($health_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($health_host_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($health_agent_name).", 
    ".$an->data->{sys}{use_db_fh}->quote($health_source_name).", 
    ".$an->data->{sys}{use_db_fh}->quote($health_source_weight).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
			$query =~ s/'NULL'/NULL/g;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "query", value1 => $query, 
			}, file => $THIS_FILE, line => __LINE__});
			$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
		}
	}
	
	return($health_uuid);
}

# This updates (or inserts) a record in the 'nodes' table.
sub insert_or_update_nodes
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "insert_or_update_nodes" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $node_uuid        = $parameter->{node_uuid}        ? $parameter->{node_uuid}        : "";
	my $node_anvil_uuid  = $parameter->{node_anvil_uuid}  ? $parameter->{node_anvil_uuid}  : "";
	my $node_host_uuid   = $parameter->{node_host_uuid}   ? $parameter->{node_host_uuid}   : "";
	my $node_remote_ip   = $parameter->{node_remote_ip}   ? $parameter->{node_remote_ip}   : "NULL";
	my $node_remote_port = $parameter->{node_remote_port} ? $parameter->{node_remote_port} : "NULL";
	my $node_note        = $parameter->{node_note}        ? $parameter->{node_note}        : "NULL";
	my $node_bcn         = $parameter->{node_bcn}         ? $parameter->{node_bcn}         : "NULL";
	my $node_sn          = $parameter->{node_sn}          ? $parameter->{node_sn}          : "NULL";
	my $node_ifn         = $parameter->{node_ifn}         ? $parameter->{node_ifn}         : "NULL";
	my $node_password    = $parameter->{node_password}    ? $parameter->{node_password}    : "NULL";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0009", message_variables => {
		name1 => "node_uuid",        value1 => $node_uuid, 
		name2 => "node_anvil_uuid",  value2 => $node_anvil_uuid, 
		name3 => "node_host_uuid",   value3 => $node_host_uuid, 
		name4 => "node_remote_ip",   value4 => $node_remote_ip, 
		name5 => "node_remote_port", value5 => $node_remote_port, 
		name6 => "node_note",        value6 => $node_note, 
		name7 => "node_bcn",         value7 => $node_bcn, 
		name8 => "node_sn",          value8 => $node_sn, 
		name9 => "node_ifn",         value9 => $node_ifn, 
	}, file => $THIS_FILE, line => __LINE__});
	$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
		name1 => "node_password", value1 => $node_password, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# If we don't have a UUID, see if we can find one for the given host UUID.
	if (not $node_uuid)
	{
		my $query = "
SELECT 
    node_uuid 
FROM 
    nodes 
WHERE 
    node_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($node_host_uuid)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$node_uuid = $row->[0];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "node_uuid", value1 => $node_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	# If I still don't have an anvil_uuid, we're INSERT'ing .
	if (not $node_uuid)
	{
		# INSERT, *if* we have an owner and smtp UUID.
		if (not $node_anvil_uuid)
		{
			$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0082", code => 82, file => $THIS_FILE, line => __LINE__});
			return("");
		}
		if (not $node_host_uuid)
		{
			$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0083", code => 83, file => $THIS_FILE, line => __LINE__});
			return("");
		}
		   $node_uuid = $an->Get->uuid();
		my $query      = "
INSERT INTO 
    nodes 
(
    node_uuid,
    node_anvil_uuid, 
    node_host_uuid, 
    node_remote_ip, 
    node_remote_port, 
    node_note, 
    node_bcn, 
    node_sn, 
    node_ifn, 
    node_password,
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($node_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($node_anvil_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($node_host_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($node_remote_ip).", 
    ".$an->data->{sys}{use_db_fh}->quote($node_remote_port).", 
    ".$an->data->{sys}{use_db_fh}->quote($node_note).", 
    ".$an->data->{sys}{use_db_fh}->quote($node_bcn).", 
    ".$an->data->{sys}{use_db_fh}->quote($node_sn).", 
    ".$an->data->{sys}{use_db_fh}->quote($node_ifn).", 
    ".$an->data->{sys}{use_db_fh}->quote($node_password).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Query the rest of the values and see if anything changed.
		my $query = "
SELECT 
    node_anvil_uuid, 
    node_host_uuid, 
    node_remote_ip, 
    node_remote_port, 
    node_note, 
    node_bcn, 
    node_sn, 
    node_ifn, 
    node_password 
FROM 
    nodes 
WHERE 
    node_uuid = ".$an->data->{sys}{use_db_fh}->quote($node_uuid)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			my $old_node_anvil_uuid  = $row->[0]; 
			my $old_node_host_uuid   = $row->[1]; 
			my $old_node_remote_ip   = $row->[2] ? $row->[2] : "NULL"; 
			my $old_node_remote_port = $row->[3] ? $row->[3] : "NULL"; 
			my $old_node_note        = $row->[4] ? $row->[4] : "NULL"; 
			my $old_node_bcn         = $row->[5] ? $row->[5] : "NULL"; 
			my $old_node_sn          = $row->[6] ? $row->[6] : "NULL"; 
			my $old_node_ifn         = $row->[7] ? $row->[7] : "NULL"; 
			my $old_node_password    = $row->[8] ? $row->[8] : "NULL"; 
			$an->Log->entry({log_level => 3, message_key => "an_variables_0009", message_variables => {
				name1 => "old_node_anvil_uuid",  value1 => $old_node_anvil_uuid, 
				name2 => "old_node_host_uuid",   value2 => $old_node_host_uuid, 
				name3 => "old_node_remote_ip",   value3 => $old_node_remote_ip, 
				name4 => "old_node_remote_port", value4 => $old_node_remote_port, 
				name5 => "old_node_note",        value5 => $old_node_note, 
				name6 => "old_node_bcn",         value6 => $old_node_bcn, 
				name7 => "old_node_sn",          value7 => $old_node_sn, 
				name8 => "old_node_ifn",         value8 => $old_node_ifn, 
				name9 => "old_node_password",    value9 => $old_node_password, 
			}, file => $THIS_FILE, line => __LINE__});
			
			# Anything change?
			if (($old_node_anvil_uuid  ne $node_anvil_uuid)  or 
			    ($old_node_host_uuid   ne $node_host_uuid)   or 
			    ($old_node_remote_ip   ne $node_remote_ip)   or 
			    ($old_node_remote_port ne $node_remote_port) or 
			    ($old_node_note        ne $node_note)        or 
			    ($old_node_bcn         ne $node_bcn)         or 
			    ($old_node_sn          ne $node_sn)          or 
			    ($old_node_ifn         ne $node_ifn)         or 
			    ($old_node_password    ne $node_password)) 
			{
				# Something changed, save.
				my $query = "
UPDATE 
    nodes 
SET 
    node_anvil_uuid  = ".$an->data->{sys}{use_db_fh}->quote($node_anvil_uuid).",  
    node_host_uuid   = ".$an->data->{sys}{use_db_fh}->quote($node_host_uuid).",  
    node_remote_ip   = ".$an->data->{sys}{use_db_fh}->quote($node_remote_ip).",  
    node_remote_port = ".$an->data->{sys}{use_db_fh}->quote($node_remote_port).",  
    node_note        = ".$an->data->{sys}{use_db_fh}->quote($node_note).",  
    node_bcn         = ".$an->data->{sys}{use_db_fh}->quote($node_bcn).",  
    node_sn          = ".$an->data->{sys}{use_db_fh}->quote($node_sn).",  
    node_ifn         = ".$an->data->{sys}{use_db_fh}->quote($node_ifn).",  
    node_password    = ".$an->data->{sys}{use_db_fh}->quote($node_password).", 
    modified_date    = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    node_uuid        = ".$an->data->{sys}{use_db_fh}->quote($node_uuid)." 
";
				$query =~ s/'NULL'/NULL/g;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "query", value1 => $query, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	return($node_uuid);
}

# This updates (or inserts) a record in the 'nodes_cache' table.
sub insert_or_update_nodes_cache
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 2, title_key => "tools_log_0001", title_variables => { function => "insert_or_update_nodes_cache" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $node_cache_uuid      = $parameter->{node_cache_uuid}      ? $parameter->{node_cache_uuid}      : "";
	my $node_cache_host_uuid = $parameter->{node_cache_host_uuid} ? $parameter->{node_cache_host_uuid} : "";
	my $node_cache_node_uuid = $parameter->{node_cache_node_uuid} ? $parameter->{node_cache_node_uuid} : "";
	my $node_cache_name      = $parameter->{node_cache_name}      ? $parameter->{node_cache_name}      : "";
	my $node_cache_data      = $parameter->{node_cache_data}      ? $parameter->{node_cache_data}      : "NULL";
	my $node_cache_note      = $parameter->{node_cache_note}      ? $parameter->{node_cache_note}      : "NULL";
	$an->Log->entry({log_level => 2, message_key => "an_variables_0006", message_variables => {
		name1 => "node_cache_uuid",      value1 => $node_cache_uuid, 
		name2 => "node_cache_host_uuid", value2 => $node_cache_host_uuid, 
		name3 => "node_cache_node_uuid", value3 => $node_cache_node_uuid, 
		name4 => "node_cache_name",      value4 => $node_cache_name, 
		name5 => "node_cache_data",      value5 => $node_cache_data, 
		name6 => "node_cache_note",      value6 => $node_cache_note, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# We need a host_uuid, node_uuid and name
	if (not $node_cache_host_uuid)
	{
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0108", code => 108, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	if (not $node_cache_node_uuid)
	{
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0109", code => 109, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	if (not $node_cache_name)
	{
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0110", code => 110, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	# Verify that the host_uuid is valid. It's possible we're talking to a machine before it's added 
	# itself to the database.
	if ($node_cache_host_uuid)
	{
		my $query = "SELECT COUNT(*) FROM hosts WHERE host_uuid = ".$an->data->{sys}{use_db_fh}->quote($node_cache_host_uuid).";";
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $count = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "count", value1 => $count, 
		}, file => $THIS_FILE, line => __LINE__});
		
		if (not $count)
		{
			# Host doesn't exist yet, return.
			$an->Log->entry({log_level => 1, message_key => "log_0006", message_variables => { host_uuid => $node_cache_host_uuid }, file => $THIS_FILE, line => __LINE__});
			return("");
		}
	}
	if ($node_cache_node_uuid)
	{
		my $query = "SELECT COUNT(*) FROM nodes WHERE node_uuid = ".$an->data->{sys}{use_db_fh}->quote($node_cache_node_uuid).";";
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $count = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "count", value1 => $count, 
		}, file => $THIS_FILE, line => __LINE__});
		
		if (not $count)
		{
			# Host doesn't exist yet, return.
			$an->Log->entry({log_level => 1, message_key => "log_0007", message_variables => { host_uuid => $node_cache_host_uuid }, file => $THIS_FILE, line => __LINE__});
			return("");
		}
	}
	
	# If we don't have a UUID, see if we can find one for the given host UUID.
	if (not $node_cache_uuid)
	{
		my $query = "
SELECT 
    node_cache_uuid 
FROM 
    nodes_cache 
WHERE 
    node_cache_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($node_cache_host_uuid)." 
AND 
    node_cache_node_uuid = ".$an->data->{sys}{use_db_fh}->quote($node_cache_node_uuid)." 
AND 
    node_cache_name      = ".$an->data->{sys}{use_db_fh}->quote($node_cache_name)." 
;";
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$node_cache_uuid = $row->[0];
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "node_cache_uuid", value1 => $node_cache_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	# If I still don't have an anvil_uuid, we're INSERT'ing .
	if (not $node_cache_uuid)
	{
		   $node_cache_uuid = $an->Get->uuid();
		my $query           = "
INSERT INTO 
    nodes_cache 
(
    node_cache_uuid, 
    node_cache_host_uuid, 
    node_cache_node_uuid, 
    node_cache_name, 
    node_cache_data, 
    node_cache_note, 
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($node_cache_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($node_cache_host_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($node_cache_node_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($node_cache_name).", 
    ".$an->data->{sys}{use_db_fh}->quote($node_cache_data).", 
    ".$an->data->{sys}{use_db_fh}->quote($node_cache_note).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Query the rest of the values and see if anything changed.
		my $query = "
SELECT 
    node_cache_uuid, 
    node_cache_host_uuid, 
    node_cache_node_uuid, 
    node_cache_name, 
    node_cache_data, 
    node_cache_note 
FROM 
    nodes_cache 
WHERE 
    node_cache_uuid = ".$an->data->{sys}{use_db_fh}->quote($node_cache_uuid)." 
;";
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			my $old_node_cache_uuid      = $row->[0];
			my $old_node_cache_host_uuid = $row->[1];
			my $old_node_cache_node_uuid = $row->[2];
			my $old_node_cache_name      = $row->[3];
			my $old_node_cache_data      = $row->[4] ? $row->[4] : "NULL";
			my $old_node_cache_note      = $row->[5] ? $row->[5] : "NULL";
			### NOTE: When loading fence cache data, this will usually contain a password, hence log level 4.
			$an->Log->entry({log_level => 2, message_key => "an_variables_0006", message_variables => {
				name1 => "old_node_cache_uuid",      value1 => $old_node_cache_uuid, 
				name2 => "old_node_cache_host_uuid", value2 => $old_node_cache_host_uuid, 
				name3 => "old_node_cache_node_uuid", value3 => $old_node_cache_node_uuid, 
				name4 => "old_node_cache_name",      value4 => $old_node_cache_name, 
				name5 => "old_node_cache_data",      value5 => $old_node_cache_data, 
				name6 => "old_node_cache_note",      value6 => $old_node_cache_note, 
			}, file => $THIS_FILE, line => __LINE__});
			
			# Anything change?
			if (($old_node_cache_uuid      ne $node_cache_uuid)      or 
			    ($old_node_cache_host_uuid ne $node_cache_host_uuid) or 
			    ($old_node_cache_node_uuid ne $node_cache_node_uuid) or 
			    ($old_node_cache_name      ne $node_cache_name)      or 
			    ($old_node_cache_data      ne $node_cache_data)      or 
			    ($old_node_cache_note      ne $node_cache_note))
			{
				# Something changed, save.
				my $query = "
UPDATE 
    nodes_cache 
SET 
    node_cache_uuid      = ".$an->data->{sys}{use_db_fh}->quote($node_cache_uuid).", 
    node_cache_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($node_cache_host_uuid).", 
    node_cache_node_uuid = ".$an->data->{sys}{use_db_fh}->quote($node_cache_node_uuid).", 
    node_cache_name      = ".$an->data->{sys}{use_db_fh}->quote($node_cache_name).", 
    node_cache_data      = ".$an->data->{sys}{use_db_fh}->quote($node_cache_data).", 
    node_cache_note      = ".$an->data->{sys}{use_db_fh}->quote($node_cache_note).", 
    modified_date        = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    node_cache_uuid      = ".$an->data->{sys}{use_db_fh}->quote($node_cache_uuid)." 
";
				$query =~ s/'NULL'/NULL/g;
				$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
					name1 => "query", value1 => $query, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	return($node_cache_uuid);
}

# This updates (or inserts) a record in the 'notifications' table.
sub insert_or_update_notifications
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "insert_or_update_notifications" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $notify_uuid     = $parameter->{notify_uuid}     ? $parameter->{notify_uuid}     : "";
	my $notify_name     = $parameter->{notify_name}     ? $parameter->{notify_name}     : "";
	my $notify_target   = $parameter->{notify_target}   ? $parameter->{notify_target}   : "";
	my $notify_language = $parameter->{notify_language} ? $parameter->{notify_language} : "";
	my $notify_level    = $parameter->{notify_level}    ? $parameter->{notify_level}    : "";
	my $notify_units    = $parameter->{notify_units}    ? $parameter->{notify_units}    : "";
	my $notify_note     = $parameter->{notify_note}     ? $parameter->{notify_note}     : "NULL";
	if (not $notify_target)
	{
		# Throw an error and exit.
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0088", code => 88, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	# If we don't have a UUID, see if we can find one for the given notify server name.
	if (not $notify_uuid)
	{
		my $query = "
SELECT 
    notify_uuid 
FROM 
    notifications 
WHERE 
    notify_target = ".$an->data->{sys}{use_db_fh}->quote($notify_target)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$notify_uuid = $row->[0];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "notify_uuid", value1 => $notify_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	# If I still don't have an notify_uuid, we're INSERT'ing .
	if (not $notify_uuid)
	{
		# INSERT
		   $notify_uuid = $an->Get->uuid();
		my $query      = "
INSERT INTO 
    notifications 
(
    notify_uuid, 
    notify_name, 
    notify_target, 
    notify_language, 
    notify_level, 
    notify_units, 
    notify_note, 
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($notify_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($notify_name).", 
    ".$an->data->{sys}{use_db_fh}->quote($notify_target).", 
    ".$an->data->{sys}{use_db_fh}->quote($notify_language).", 
    ".$an->data->{sys}{use_db_fh}->quote($notify_level).", 
    ".$an->data->{sys}{use_db_fh}->quote($notify_units).", 
    ".$an->data->{sys}{use_db_fh}->quote($notify_note).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Query the rest of the values and see if anything changed.
		my $query = "
SELECT 
    notify_name, 
    notify_target, 
    notify_language, 
    notify_level, 
    notify_units, 
    notify_note 
FROM 
    notifications 
WHERE 
    notify_uuid = ".$an->data->{sys}{use_db_fh}->quote($notify_uuid)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			my $old_notify_name     = $row->[0];
			my $old_notify_target   = $row->[1];
			my $old_notify_language = $row->[2];
			my $old_notify_level    = $row->[3];
			my $old_notify_units    = $row->[4];
			my $old_notify_note     = $row->[5] ? $row->[5] : "NULL";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0006", message_variables => {
				name1 => "old_notify_name",     value1 => $old_notify_name, 
				name2 => "old_notify_target",   value2 => $old_notify_target, 
				name3 => "old_notify_language", value3 => $old_notify_language, 
				name4 => "old_notify_level",    value4 => $old_notify_level, 
				name5 => "old_notify_units",    value5 => $old_notify_units, 
				name6 => "old_notify_note",     value6 => $old_notify_note, 
			}, file => $THIS_FILE, line => __LINE__});
			
			# Anything change?
			if (($old_notify_name     ne $notify_name)     or 
			    ($old_notify_target   ne $notify_target)   or 
			    ($old_notify_language ne $notify_language) or 
			    ($old_notify_level    ne $notify_level)    or 
			    ($old_notify_units    ne $notify_units)    or 
			    ($old_notify_note     ne $notify_note))
			{
				# Something changed, save.
				my $query = "
UPDATE 
    notifications 
SET 
    notify_name     = ".$an->data->{sys}{use_db_fh}->quote($notify_name).", 
    notify_target   = ".$an->data->{sys}{use_db_fh}->quote($notify_target).", 
    notify_language = ".$an->data->{sys}{use_db_fh}->quote($notify_language).", 
    notify_level    = ".$an->data->{sys}{use_db_fh}->quote($notify_level).", 
    notify_units    = ".$an->data->{sys}{use_db_fh}->quote($notify_units).", 
    notify_note     = ".$an->data->{sys}{use_db_fh}->quote($notify_note).", 
    modified_date   = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    notify_uuid     = ".$an->data->{sys}{use_db_fh}->quote($notify_uuid)." 
";
				$query =~ s/'NULL'/NULL/g;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "query", value1 => $query, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	return($notify_uuid);
}

# This updates (or inserts) a record in the 'owners' table.
sub insert_or_update_owners
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "insert_or_update_owners" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $owner_uuid = $parameter->{owner_uuid} ? $parameter->{owner_uuid} : "";
	my $owner_name = $parameter->{owner_name} ? $parameter->{owner_name} : "";
	my $owner_note = $parameter->{owner_note} ? $parameter->{owner_note} : "NULL";
	if (not $owner_name)
	{
		# Throw an error and exit.
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0078", code => 78, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	# If we don't have a UUID, see if we can find one for the given owner server name.
	if (not $owner_uuid)
	{
		my $query = "
SELECT 
    owner_uuid 
FROM 
    owners 
WHERE 
    owner_name = ".$an->data->{sys}{use_db_fh}->quote($owner_name)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$owner_uuid = $row->[0];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "owner_uuid", value1 => $owner_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	# If I still don't have an owner_uuid, we're INSERT'ing .
	if (not $owner_uuid)
	{
		# INSERT
		   $owner_uuid = $an->Get->uuid();
		my $query      = "
INSERT INTO 
    owners 
(
    owner_uuid, 
    owner_name, 
    owner_note, 
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($owner_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($owner_name).", 
    ".$an->data->{sys}{use_db_fh}->quote($owner_note).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Query the rest of the values and see if anything changed.
		my $query = "
SELECT 
    owner_name, 
    owner_note 
FROM 
    owners 
WHERE 
    owner_uuid = ".$an->data->{sys}{use_db_fh}->quote($owner_uuid)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			my $old_owner_name = defined $row->[0] ? $row->[0] : "";
			my $old_owner_note = defined $row->[1] ? $row->[1] : "";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "old_owner_name", value1 => $old_owner_name, 
				name2 => "old_owner_note", value2 => $old_owner_note, 
			}, file => $THIS_FILE, line => __LINE__});
			
			# Anything change?
			if (($old_owner_name ne $owner_name) or 
			    ($old_owner_note ne $owner_note))
			{
				# Something changed, save.
				my $query = "
UPDATE 
    owners 
SET 
    owner_name    = ".$an->data->{sys}{use_db_fh}->quote($owner_name).", 
    owner_note    = ".$an->data->{sys}{use_db_fh}->quote($owner_note).", 
    modified_date = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    owner_uuid    = ".$an->data->{sys}{use_db_fh}->quote($owner_uuid)." 
";
				$query =~ s/'NULL'/NULL/g;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "query", value1 => $query, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	return($owner_uuid);
}

# This updates (or inserts) a record in the 'recipients' table.
sub insert_or_update_recipients
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "insert_or_update_recipients" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $recipient_uuid         = $parameter->{recipient_uuid}         ? $parameter->{recipient_uuid}         : "";
	my $recipient_anvil_uuid   = $parameter->{recipient_anvil_uuid}   ? $parameter->{recipient_anvil_uuid}   : "";
	my $recipient_notify_uuid  = $parameter->{recipient_notify_uuid}  ? $parameter->{recipient_notify_uuid}  : "";
	my $recipient_notify_level = $parameter->{recipient_notify_level} ? $parameter->{recipient_notify_level} : "NULL";
	my $recipient_note         = $parameter->{recipient_note}         ? $parameter->{recipient_note}         : "NULL";
	if ((not $recipient_anvil_uuid) or (not $recipient_notify_uuid))
	{
		# Throw an error and exit.
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0091", code => 91, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	# If we don't have a UUID, see if we can find one for the given recipient server name.
	if (not $recipient_uuid)
	{
		my $query = "
SELECT 
    recipient_uuid 
FROM 
    recipients 
WHERE 
    recipient_anvil_uuid = ".$an->data->{sys}{use_db_fh}->quote($recipient_anvil_uuid)." 
AND 
    recipient_notify_uuid = ".$an->data->{sys}{use_db_fh}->quote($recipient_notify_uuid)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$recipient_uuid = $row->[0];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "recipient_uuid", value1 => $recipient_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	# If I still don't have an recipient_uuid, we're INSERT'ing .
	if (not $recipient_uuid)
	{
		# INSERT
		   $recipient_uuid = $an->Get->uuid();
		my $query          = "
INSERT INTO 
    recipients 
(
    recipient_uuid, 
    recipient_anvil_uuid, 
    recipient_notify_uuid, 
    recipient_notify_level, 
    recipient_note, 
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($recipient_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($recipient_anvil_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($recipient_notify_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($recipient_notify_level).", 
    ".$an->data->{sys}{use_db_fh}->quote($recipient_note).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Query the rest of the values and see if anything changed.
		my $query = "
SELECT 
    recipient_anvil_uuid, 
    recipient_notify_uuid, 
    recipient_notify_level, 
    recipient_note 
FROM 
    recipients 
WHERE 
    recipient_uuid = ".$an->data->{sys}{use_db_fh}->quote($recipient_uuid)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			my $old_recipient_anvil_uuid   = $row->[0];
			my $old_recipient_notify_uuid  = $row->[1];
			my $old_recipient_notify_level = $row->[2] ? $row->[2] : "NULL";
			my $old_recipient_note         = $row->[3] ? $row->[3] : "NULL";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0004", message_variables => {
				name1 => "old_recipient_anvil_uuid",   value1 => $old_recipient_anvil_uuid, 
				name2 => "old_recipient_notify_uuid",  value2 => $old_recipient_notify_uuid, 
				name3 => "old_recipient_notify_level", value3 => $old_recipient_notify_level, 
				name4 => "old_recipient_note",         value4 => $old_recipient_note, 
			}, file => $THIS_FILE, line => __LINE__});
			
			# Anything change?
			if (($old_recipient_anvil_uuid   ne $recipient_anvil_uuid)   or 
			    ($old_recipient_notify_uuid  ne $recipient_notify_uuid)  or 
			    ($old_recipient_notify_level ne $recipient_notify_level) or 
			    ($old_recipient_note         ne $recipient_note))
			{
				# Something changed, save.
				my $query = "
UPDATE 
    recipients 
SET 
    recipient_anvil_uuid   = ".$an->data->{sys}{use_db_fh}->quote($recipient_anvil_uuid).", 
    recipient_notify_uuid  = ".$an->data->{sys}{use_db_fh}->quote($recipient_notify_uuid).",  
    recipient_notify_level = ".$an->data->{sys}{use_db_fh}->quote($recipient_notify_level).", 
    recipient_note         = ".$an->data->{sys}{use_db_fh}->quote($recipient_note).", 
    modified_date          = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    recipient_uuid         = ".$an->data->{sys}{use_db_fh}->quote($recipient_uuid)." 
";
				$query =~ s/'NULL'/NULL/g;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "query", value1 => $query, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	return($recipient_uuid);
}

# This updates (or inserts) a record in the 'servers' table. This is a little different from the other 
# similar methods in that a user can request that only the definition be updated.
sub insert_or_update_servers
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 2, title_key => "tools_log_0001", title_variables => { function => "insert_or_update_servers" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $server_uuid                     = $parameter->{server_uuid}                     ? $parameter->{server_uuid}                     : "";
	my $server_anvil_uuid               = $parameter->{server_anvil_uuid}               ? $parameter->{server_anvil_uuid}               : "";
	my $server_name                     = $parameter->{server_name}                     ? $parameter->{server_name}                     : "";
	my $server_stop_reason              = $parameter->{server_stop_reason}              ? $parameter->{server_stop_reason}              : "";
	my $server_start_after              = $parameter->{server_start_after}              ? $parameter->{server_start_after}              : "NULL";
	my $server_start_delay              = $parameter->{server_start_delay}              ? $parameter->{server_start_delay}              : 0;
	my $server_note                     = $parameter->{server_note}                     ? $parameter->{server_note}                     : "";
	my $server_definition               = $parameter->{server_definition}               ? $parameter->{server_definition}               : "";
	my $server_host                     = $parameter->{server_host}                     ? $parameter->{server_host}                     : "";
	my $server_state                    = $parameter->{server_state}                    ? $parameter->{server_state}                    : "";
	my $server_migration_type           = $parameter->{server_migration_type}           ? $parameter->{server_migration_type}           : "";
	my $server_pre_migration_script     = $parameter->{server_pre_migration_script}     ? $parameter->{server_pre_migration_script}     : "";
	my $server_pre_migration_arguments  = $parameter->{server_pre_migration_arguments}  ? $parameter->{server_pre_migration_arguments}  : "";
	my $server_post_migration_script    = $parameter->{server_post_migration_script}    ? $parameter->{server_post_migration_script}    : "";
	my $server_post_migration_arguments = $parameter->{server_post_migration_arguments} ? $parameter->{server_post_migration_arguments} : "";
	my $just_definition                 = $parameter->{just_definition}                 ? $parameter->{just_definition}                 : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0016", message_variables => {
		name1  => "server_uuid",                     value1  => $server_uuid, 
		name2  => "server_anvil_uuid",               value2  => $server_anvil_uuid, 
		name3  => "server_name",                     value3  => $server_name, 
		name4  => "server_stop_reason",              value4  => $server_stop_reason, 
		name5  => "server_start_after",              value5  => $server_start_after, 
		name6  => "server_start_delay",              value6  => $server_start_delay, 
		name7  => "server_note",                     value7  => $server_note, 
		name8  => "server_definition",               value8  => $server_definition, 
		name9  => "server_host",                     value9  => $server_host, 
		name10 => "server_state",                    value10 => $server_state, 
		name11 => "server_migration_type",           value11 => $server_migration_type, 
		name12 => "server_pre_migration_script",     value12 => $server_pre_migration_script, 
		name13 => "server_pre_migration_arguments",  value13 => $server_pre_migration_arguments, 
		name14 => "server_post_migration_script",    value14 => $server_post_migration_script, 
		name15 => "server_post_migration_arguments", value15 => $server_post_migration_arguments, 
		name16 => "just_definition",                 value16 => $just_definition, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# Make sure I have the essentials
	if ((not $server_name) && (not $server_uuid))
	{
		# Throw an error and exit.
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0181", code => 181, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	if (not $server_definition)
	{
		# Throw an error and exit.
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0183", code => 183, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	# If we don't have a UUID, see if we can find one for the given SMTP server name.
	if (not $server_uuid)
	{
		my $query = "
SELECT 
    server_uuid 
FROM 
    server 
WHERE 
    server_name       = ".$an->data->{sys}{use_db_fh}->quote($server_name)." 
AND 
    server_anvil_uuid = ".$an->data->{sys}{use_db_fh}->quote($server_anvil_uuid)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$server_uuid = $row->[0] ? $row->[0] : "";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "server_uuid", value1 => $server_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	# If I don't have a migration time, use the default.
	if (not $server_migration_type)
	{
		$server_migration_type = $an->data->{sys}{'default'}{migration_type} =~ /cold/i ? "cold" : "live";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "server_migration_type", value1 => $server_migration_type, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	### NOTE: For now, this generates an alert to replicate the now-deleted 
	###       'Striker->_update_server_definition_in_db()' method.
	# If 'just_definition' is set, make sure we have a valid server UUID now. 
	if ($just_definition)
	{
		if (not $server_uuid)
		{
			# Error out.
			$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0184", code => 184, file => $THIS_FILE, line => __LINE__});
			return("");
		}
		
		# OK, now see if the definition file changed.
		my $query = "
SELECT 
    server_definition 
FROM 
    servers 
WHERE 
    server_uuid = ".$an->data->{sys}{use_db_fh}->quote($server_uuid)."
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query
		}, file => $THIS_FILE, line => __LINE__});
		
		# Do the query against the source DB and loop through the results.
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "results", value1 => $results
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			my $old_server_definition = defined $row->[0] ? $row->[0] : "";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "old_server_definition", value1 => $old_server_definition, 
			}, file => $THIS_FILE, line => __LINE__});
			
			if ($old_server_definition eq $server_definition)
			{
				# No change.
				$an->Log->entry({log_level => 2, message_key => "message_0065", file => $THIS_FILE, line => __LINE__});
			}
			else
			{
				# Update.
				my $query = "
UPDATE 
    servers 
SET 
    server_definition = ".$an->data->{sys}{use_db_fh}->quote($server_definition).", 
    modified_date     = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    server_uuid       = ".$an->data->{sys}{use_db_fh}->quote($server_uuid)." 
";
				$query =~ s/'NULL'/NULL/g;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "query", value1 => $query, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
				
				# This will happen whenever the virsh ID changes, disks are inserted/ejected,
				# etc. So it is a notice-level event. It won't be sent until one of the nodes
				# scan though.
				$an->Alert->register_alert({
					alert_level		=>	"notice", 
					alert_agent_name	=>	$THIS_FILE,
					alert_title_key		=>	"an_alert_title_0003",
					alert_message_key	=>	"scan_server_message_0007",
					alert_message_variables	=>	{
						server			=>	$server_name, 
						new			=>	$server_definition,
						diff			=>	diff \$old_server_definition, \$server_definition, { STYLE => 'Unified' },
					},
				});
			}
		}
		
		# Return now.
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "server_uuid", value1 => $server_uuid, 
		}, file => $THIS_FILE, line => __LINE__});
		return($server_uuid);
	}
	
	# If I am still alive, I need to make sure we have the server_anvil_uuid.
	if (not $server_anvil_uuid)
	{
		# Throw an error and exit.
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0182", code => 182, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	# If I still don't have an server_uuid, we're INSERT'ing .
	if (not $server_uuid)
	{
		# INSERT
		   $server_uuid = $an->Get->uuid();
		my $query     = "
INSERT INTO 
    servers 
(
    server_uuid, 
    server_anvil_uuid, 
    server_name, 
    server_stop_reason, 
    server_start_after, 
    server_start_delay, 
    server_note, 
    server_definition, 
    server_host, 
    server_state, 
    server_migration_type, 
    server_pre_migration_script, 
    server_pre_migration_arguments, 
    server_post_migration_script, 
    server_post_migration_arguments, 
    modified_date
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($server_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($server_anvil_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($server_name).", 
    ".$an->data->{sys}{use_db_fh}->quote($server_stop_reason).", 
    ".$an->data->{sys}{use_db_fh}->quote($server_start_after).", 
    ".$an->data->{sys}{use_db_fh}->quote($server_start_delay).", 
    ".$an->data->{sys}{use_db_fh}->quote($server_note).", 
    ".$an->data->{sys}{use_db_fh}->quote($server_definition).", 
    ".$an->data->{sys}{use_db_fh}->quote($server_host).", 
    ".$an->data->{sys}{use_db_fh}->quote($server_state).", 
    ".$an->data->{sys}{use_db_fh}->quote($server_migration_type).", 
    ".$an->data->{sys}{use_db_fh}->quote($server_pre_migration_script).", 
    ".$an->data->{sys}{use_db_fh}->quote($server_pre_migration_arguments).", 
    ".$an->data->{sys}{use_db_fh}->quote($server_post_migration_script).", 
    ".$an->data->{sys}{use_db_fh}->quote($server_post_migration_arguments).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Query the rest of the values and see if anything changed.
		my $query = "
SELECT 
    server_anvil_uuid, 
    server_name, 
    server_stop_reason, 
    server_start_after, 
    server_start_delay, 
    server_note, 
    server_definition, 
    server_host, 
    server_state, 
    server_migration_type, 
    server_pre_migration_script, 
    server_pre_migration_arguments, 
    server_post_migration_script, 
    server_post_migration_arguments, 
FROM 
    servers 
WHERE 
    server_uuid = ".$an->data->{sys}{use_db_fh}->quote($server_uuid)."
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query
		}, file => $THIS_FILE, line => __LINE__});
		
		# Do the query against the source DB and loop through the results.
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "results", value1 => $results
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			my $old_server_anvil_uuid               =         $row->[0];
			my $old_server_name                     =         $row->[1];
			my $old_server_stop_reason              = defined $row->[2]  ? $row->[2]  : "";
			my $old_server_start_after              = defined $row->[3]  ? $row->[3]  : "NULL";
			my $old_server_start_delay              = defined $row->[4]  ? $row->[4]  : "0";
			my $old_server_note                     = defined $row->[5]  ? $row->[5]  : "";
			my $old_server_definition               = defined $row->[6]  ? $row->[6]  : "";
			my $old_server_host                     = defined $row->[7]  ? $row->[7]  : "";
			my $old_server_state                    = defined $row->[8]  ? $row->[8]  : "";
			my $old_server_migration_type           = defined $row->[9]  ? $row->[9]  : "";
			my $old_server_pre_migration_script     = defined $row->[10] ? $row->[10] : "";
			my $old_server_pre_migration_arguments  = defined $row->[11] ? $row->[11] : "";
			my $old_server_post_migration_script    = defined $row->[12] ? $row->[12] : "";
			my $old_server_post_migration_arguments = defined $row->[13] ? $row->[13] : "";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0014", message_variables => {
				name1  => "old_server_anvil_uuid",               value1  => $old_server_anvil_uuid, 
				name2  => "old_server_name",                     value2  => $old_server_name, 
				name3  => "old_server_stop_reason",              value3  => $old_server_stop_reason, 
				name4  => "old_server_start_after",              value4  => $old_server_start_after, 
				name5  => "old_server_start_delay",              value5  => $old_server_start_delay, 
				name6  => "old_server_note",                     value6  => $old_server_note, 
				name7  => "old_server_definition",               value7  => $old_server_definition, 
				name8  => "old_server_host",                     value8  => $old_server_host, 
				name9  => "old_server_state",                    value9  => $old_server_state, 
				name10 => "old_server_migration_type",           value10 => $old_server_migration_type,
				name11 => "old_server_pre_migration_script",     value11 => $old_server_pre_migration_script,
				name12 => "old_server_pre_migration_arguments",  value12 => $old_server_pre_migration_arguments,
				name13 => "old_server_post_migration_script",    value13 => $old_server_post_migration_script,
				name14 => "old_server_post_migration_arguments", value14 => $old_server_post_migration_arguments,
			}, file => $THIS_FILE, line => __LINE__});
			
			# Anything change?
			if (($old_server_anvil_uuid               ne $server_anvil_uuid)              or 
			    ($old_server_name                     ne $server_name)                    or 
			    ($old_server_stop_reason              ne $server_stop_reason)             or 
			    ($old_server_start_after              ne $server_start_after)             or 
			    ($old_server_start_delay              ne $server_start_delay)             or 
			    ($old_server_note                     ne $server_note)                    or 
			    ($old_server_definition               ne $server_definition)              or 
			    ($old_server_host                     ne $server_host)                    or 
			    ($old_server_state                    ne $server_state)                   or 
			    ($old_server_migration_type           ne $server_migration_type)          or 
			    ($old_server_pre_migration_script     ne $server_pre_migration_script)    or 
			    ($old_server_pre_migration_arguments  ne $server_pre_migration_arguments) or 
			    ($old_server_post_migration_script    ne $server_post_migration_script)   or 
			    ($old_server_post_migration_arguments ne $server_post_migration_arguments))
			{
				# Something changed, save.
				my $query = "
UPDATE 
    server 
SET 
    server_anvil_uuid               = ".$an->data->{sys}{use_db_fh}->quote($server_anvil_uuid).", 
    server_name                     = ".$an->data->{sys}{use_db_fh}->quote($server_name).", 
    server_stop_reason              = ".$an->data->{sys}{use_db_fh}->quote($server_stop_reason).", 
    server_start_after              = ".$an->data->{sys}{use_db_fh}->quote($server_start_after).", 
    server_start_delay              = ".$an->data->{sys}{use_db_fh}->quote($server_start_delay).", 
    server_note                     = ".$an->data->{sys}{use_db_fh}->quote($server_note).", 
    server_definition               = ".$an->data->{sys}{use_db_fh}->quote($server_definition).", 
    server_host                     = ".$an->data->{sys}{use_db_fh}->quote($server_host).", 
    server_state                    = ".$an->data->{sys}{use_db_fh}->quote($server_state).", 
    server_migration_type           = ".$an->data->{sys}{use_db_fh}->quote($server_migration_type).", 
    server_pre_migration_script     = ".$an->data->{sys}{use_db_fh}->quote($server_pre_migration_script).", 
    server_pre_migration_arguments  = ".$an->data->{sys}{use_db_fh}->quote($server_pre_migration_arguments).", 
    server_post_migration_script    = ".$an->data->{sys}{use_db_fh}->quote($server_post_migration_script).", 
    server_post_migration_arguments = ".$an->data->{sys}{use_db_fh}->quote($server_post_migration_arguments).", 
    modified_date                   = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    server_uuid                     = ".$an->data->{sys}{use_db_fh}->quote($server_uuid)." 
";
				$query =~ s/'NULL'/NULL/g;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "query", value1 => $query, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	return($server_uuid);
}

# This updates (or inserts) a record in the 'states' table.
sub insert_or_update_states
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "insert_or_update_states" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $state_uuid      = $parameter->{state_uuid}      ? $parameter->{state_uuid}      : "";
	my $state_name      = $parameter->{state_name}      ? $parameter->{state_name}      : "";
	my $state_host_uuid = $parameter->{state_host_uuid} ? $parameter->{state_host_uuid} : $an->data->{sys}{host_uuid};
	my $state_note      = $parameter->{state_note}      ? $parameter->{state_note}      : "NULL";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0004", message_variables => {
		name1 => "state_uuid",      value1 => $state_uuid, 
		name2 => "state_name",      value2 => $state_name, 
		name3 => "state_host_uuid", value3 => $state_host_uuid, 
		name4 => "state_note",      value4 => $state_note, 
	}, file => $THIS_FILE, line => __LINE__});
	if (not $state_name)
	{
		# Throw an error and exit.
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0186", code => 186, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	if (not $state_host_uuid)
	{
		# Throw an error and exit.
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0187", code => 187, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	# If we don't have a UUID, see if we can find one for the given state server name.
	if (not $state_uuid)
	{
		my $query = "
SELECT 
    state_uuid 
FROM 
    states 
WHERE 
    state_name      = ".$an->data->{sys}{use_db_fh}->quote($state_name)." 
AND 
    state_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($state_host_uuid)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$state_uuid = $row->[0];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "state_uuid", value1 => $state_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	# If I still don't have an state_uuid, we're INSERT'ing .
	if (not $state_uuid)
	{
		# It's possible that this is called before the host is recorded in the database. So to be
		# safe, we'll return without doing anything if there is no host_uuid in the database.
		my $hosts = $an->ScanCore->get_hosts();
		my $found = 0;
		foreach my $hash_ref (@{$hosts})
		{
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "hash_ref->{host_uuid}", value1 => $hash_ref->{host_uuid}, 
				name2 => "sys::host_uuid",        value2 => $an->data->{sys}{host_uuid}, 
			}, file => $THIS_FILE, line => __LINE__});
			if ($hash_ref->{host_uuid} eq $an->data->{sys}{host_uuid})
			{
				$found = 1;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "found", value1 => $found, 
				}, file => $THIS_FILE, line => __LINE__});
			}
		}
		if (not $found)
		{
			# We're out.
			return(0);
		}
		
		# INSERT
		   $state_uuid = $an->Get->uuid();
		my $query      = "
INSERT INTO 
    states 
(
    state_uuid, 
    state_name,
    state_host_uuid, 
    state_note, 
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($state_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($state_name).", 
    ".$an->data->{sys}{use_db_fh}->quote($state_host_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($state_note).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Query the rest of the values and see if anything changed.
		my $query = "
SELECT 
    state_name,
    state_host_uuid, 
    state_note 
FROM 
    states 
WHERE 
    state_uuid = ".$an->data->{sys}{use_db_fh}->quote($state_uuid)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			my $old_state_name         = $row->[0];
			my $old_state_host_uuid    = $row->[1];
			my $old_state_note         = $row->[2] ? $row->[2] : "NULL";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
				name1 => "old_state_name",      value1 => $old_state_name, 
				name2 => "old_state_host_uuid", value2 => $old_state_host_uuid, 
				name3 => "old_state_note",      value3 => $old_state_note, 
			}, file => $THIS_FILE, line => __LINE__});
			
			# Anything change?
			if (($old_state_name      ne $state_name)      or 
			    ($old_state_host_uuid ne $state_host_uuid) or 
			    ($old_state_note      ne $state_note))
			{
				# Something changed, save.
				my $query = "
UPDATE 
    states 
SET 
    state_name       = ".$an->data->{sys}{use_db_fh}->quote($state_name).", 
    state_host_uuid  = ".$an->data->{sys}{use_db_fh}->quote($state_host_uuid).",  
    state_note       = ".$an->data->{sys}{use_db_fh}->quote($state_note).", 
    modified_date    = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    state_uuid       = ".$an->data->{sys}{use_db_fh}->quote($state_uuid)." 
";
				$query =~ s/'NULL'/NULL/g;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "query", value1 => $query, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	return($state_uuid);
}

# This updates (or inserts) a record in the 'smtp' table.
sub insert_or_update_smtp
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "insert_or_update_smtp" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $smtp_uuid           = $parameter->{smtp_uuid}           ? $parameter->{smtp_uuid}           : "";
	my $smtp_server         = $parameter->{smtp_server}         ? $parameter->{smtp_server}         : "";
	my $smtp_port           = $parameter->{smtp_port}           ? $parameter->{smtp_port}           : "";
	my $smtp_alt_server     = $parameter->{smtp_alt_server}     ? $parameter->{smtp_alt_server}     : "";
	my $smtp_alt_port       = $parameter->{smtp_alt_port}       ? $parameter->{smtp_alt_port}       : "";
	my $smtp_username       = $parameter->{smtp_username}       ? $parameter->{smtp_username}       : "";
	my $smtp_password       = $parameter->{smtp_password}       ? $parameter->{smtp_password}       : "";
	my $smtp_security       = $parameter->{smtp_security}       ? $parameter->{smtp_security}       : "";
	my $smtp_authentication = $parameter->{smtp_authentication} ? $parameter->{smtp_authentication} : "";
	my $smtp_helo_domain    = $parameter->{smtp_helo_domain}    ? $parameter->{smtp_helo_domain}    : "";
	my $smtp_note           = $parameter->{smtp_note}           ? $parameter->{smtp_note}           : "";
	if (not $smtp_server)
	{
		# Throw an error and exit.
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0077", code => 77, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	# If we don't have a UUID, see if we can find one for the given SMTP server name.
	if (not $smtp_uuid)
	{
		my $query = "
SELECT 
    smtp_uuid 
FROM 
    smtp 
WHERE 
    smtp_server = ".$an->data->{sys}{use_db_fh}->quote($smtp_server)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$smtp_uuid = $row->[0];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "smtp_uuid", value1 => $smtp_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	# If I still don't have an smtp_uuid, we're INSERT'ing .
	if (not $smtp_uuid)
	{
		# INSERT
		   $smtp_uuid = $an->Get->uuid();
		my $query     = "
INSERT INTO 
    smtp 
(
    smtp_uuid, 
    smtp_server, 
    smtp_port, 
    smtp_username, 
    smtp_password, 
    smtp_security, 
    smtp_authentication, 
    smtp_helo_domain, 
    smtp_note, 
    smtp_alt_server, 
    smtp_alt_port, 
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($smtp_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($smtp_server).", 
    ".$an->data->{sys}{use_db_fh}->quote($smtp_port).", 
    ".$an->data->{sys}{use_db_fh}->quote($smtp_username).", 
    ".$an->data->{sys}{use_db_fh}->quote($smtp_password).", 
    ".$an->data->{sys}{use_db_fh}->quote($smtp_security).", 
    ".$an->data->{sys}{use_db_fh}->quote($smtp_authentication).", 
    ".$an->data->{sys}{use_db_fh}->quote($smtp_helo_domain).", 
    ".$an->data->{sys}{use_db_fh}->quote($smtp_note).", 
    ".$an->data->{sys}{use_db_fh}->quote($smtp_alt_server).", 
    ".$an->data->{sys}{use_db_fh}->quote($smtp_alt_port).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Query the rest of the values and see if anything changed.
		my $query = "
SELECT 
    smtp_server, 
    smtp_port, 
    smtp_username, 
    smtp_password, 
    smtp_security, 
    smtp_authentication, 
    smtp_helo_domain, 
    smtp_alt_server, 
    smtp_alt_port, 
    smtp_note  
FROM 
    smtp 
WHERE 
    smtp_uuid = ".$an->data->{sys}{use_db_fh}->quote($smtp_uuid)." 
;";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			my $old_smtp_server         = $row->[0];
			my $old_smtp_port           = $row->[1] ? $row->[1] : "";
			my $old_smtp_username       = $row->[2] ? $row->[2] : "";
			my $old_smtp_password       = $row->[3] ? $row->[3] : "";
			my $old_smtp_security       = $row->[4];
			my $old_smtp_authentication = $row->[5];
			my $old_smtp_helo_domain    = $row->[6] ? $row->[6] : "";
			my $old_smtp_alt_server     = $row->[7] ? $row->[7] : "NULL";
			my $old_smtp_alt_port       = $row->[8] ? $row->[8] : "NULL";
			my $old_smtp_note           = $row->[9] ? $row->[9] : "NULL";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0010", message_variables => {
				name1  => "old_smtp_server",         value1  => $old_smtp_server, 
				name2  => "old_smtp_port",           value2  => $old_smtp_port, 
				name3  => "old_smtp_username",       value3  => $old_smtp_username, 
				name4  => "old_smtp_password",       value4  => $old_smtp_password, 
				name5  => "old_smtp_security",       value5  => $old_smtp_security, 
				name6  => "old_smtp_authentication", value6  => $old_smtp_authentication, 
				name7  => "old_smtp_helo_domain",    value7  => $old_smtp_helo_domain, 
				name8  => "old_smtp_note",           value8  => $old_smtp_note, 
				name9  => "old_smtp_alt_server",     value9  => $old_smtp_alt_server, 
				name10 => "old_smtp_alt_port",       value10 => $old_smtp_alt_port, 
			}, file => $THIS_FILE, line => __LINE__});
			
			# Anything change?
			if (($old_smtp_server         ne $smtp_server)         or 
			    ($old_smtp_port           ne $smtp_port)           or 
			    ($old_smtp_username       ne $smtp_username)       or 
			    ($old_smtp_password       ne $smtp_password)       or 
			    ($old_smtp_security       ne $smtp_security)       or 
			    ($old_smtp_authentication ne $smtp_authentication) or 
			    ($old_smtp_helo_domain    ne $smtp_helo_domain)    or
			    ($old_smtp_note           ne $smtp_note)           or
			    ($old_smtp_alt_server     ne $smtp_alt_server)     or
			    ($old_smtp_alt_port       ne $smtp_alt_port))
			{
				# Something changed, save.
				my $query = "
UPDATE 
    smtp 
SET 
    smtp_server         = ".$an->data->{sys}{use_db_fh}->quote($smtp_server).", 
    smtp_port           = ".$an->data->{sys}{use_db_fh}->quote($smtp_port).", 
    smtp_username       = ".$an->data->{sys}{use_db_fh}->quote($smtp_username).", 
    smtp_password       = ".$an->data->{sys}{use_db_fh}->quote($smtp_password).", 
    smtp_security       = ".$an->data->{sys}{use_db_fh}->quote($smtp_security).", 
    smtp_authentication = ".$an->data->{sys}{use_db_fh}->quote($smtp_authentication).", 
    smtp_helo_domain    = ".$an->data->{sys}{use_db_fh}->quote($smtp_helo_domain).", 
    smtp_note           = ".$an->data->{sys}{use_db_fh}->quote($smtp_note).", 
    smtp_alt_server     = ".$an->data->{sys}{use_db_fh}->quote($smtp_alt_server).", 
    smtp_alt_port       = ".$an->data->{sys}{use_db_fh}->quote($smtp_alt_port).", 
    modified_date       = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    smtp_uuid           = ".$an->data->{sys}{use_db_fh}->quote($smtp_uuid)." 
";
				$query =~ s/'NULL'/NULL/g;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "query", value1 => $query, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	return($smtp_uuid);
}

### NOTE: Unlike the other methods of this type, this method can be told to update the 'variable_value' only.
###       This is so because the section, description and default columns rarely ever change. If this is set
###       and the variable name is new, an INSERT will be done the same as if it weren't set, with the unset
###       columns set to NULL.
# This updates (or inserts) a record in the 'variables' table.
sub insert_or_update_variables
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "insert_or_update_variables" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $variable_uuid         = defined $parameter->{variable_uuid}         ? $parameter->{variable_uuid}         : "";
	my $variable_name         = defined $parameter->{variable_name}         ? $parameter->{variable_name}         : "";
	my $variable_value        = defined $parameter->{variable_value}        ? $parameter->{variable_value}        : "NULL";
	my $variable_default      = defined $parameter->{variable_default}      ? $parameter->{variable_default}      : "NULL";
	my $variable_description  = defined $parameter->{variable_description}  ? $parameter->{variable_description}  : "NULL";
	my $variable_section      = defined $parameter->{variable_section}      ? $parameter->{variable_section}      : "NULL";
	my $variable_source_uuid  = defined $parameter->{variable_source_uuid}  ? $parameter->{variable_source_uuid}  : "NULL";
	my $variable_source_table = defined $parameter->{variable_source_table} ? $parameter->{variable_source_table} : "NULL";
	my $update_value_only     = defined $parameter->{update_value_only}     ? $parameter->{update_value_only}     : 1;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0009", message_variables => {
		name1 => "variable_uuid",         value1 => $variable_uuid, 
		name2 => "variable_name",         value2 => $variable_name, 
		name3 => "variable_value",        value3 => $variable_value, 
		name4 => "variable_default",      value4 => $variable_default, 
		name5 => "variable_description",  value5 => $variable_description, 
		name6 => "variable_section",      value6 => $variable_section, 
		name7 => "variable_source_uuid",  value7 => $variable_source_uuid, 
		name8 => "variable_source_table", value8 => $variable_source_table, 
		name9 => "update_value_only",     value9 => $update_value_only, 
	}, file => $THIS_FILE, line => __LINE__});
	if ((not $variable_name) && (not $variable_uuid))
	{
		# Throw an error and exit.
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0164", code => 164, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	# If we have a variable UUID but not a name, read the variable name. If we don't have a UUID, see if
	# we can find one for the given variable name.
	if (($an->Validate->is_uuid({uuid => $variable_uuid})) && (not $variable_name))
	{
		my $query = "
SELECT 
    variable_name 
FROM 
    variables 
WHERE 
    variable_uuid = ".$an->data->{sys}{use_db_fh}->quote($variable_uuid);
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$variable_name = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
		$variable_name = "" if not defined $variable_name;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "variable_name", value1 => $variable_name, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	if (($variable_name) && (not $variable_uuid))
	{
		my $query = "
SELECT 
    variable_uuid 
FROM 
    variables 
WHERE 
    variable_name = ".$an->data->{sys}{use_db_fh}->quote($variable_name);
		if (($variable_source_uuid ne "NULL") && ($variable_source_table ne "NULL"))
		{
			$query .= "
AND 
    variable_source_uuid  = ".$an->data->{sys}{use_db_fh}->quote($variable_source_uuid)." 
AND 
    variable_source_table = ".$an->data->{sys}{use_db_fh}->quote($variable_source_table)." 
";
		}
		$query .= ";";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			$variable_uuid = $row->[0];
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "variable_uuid", value1 => $variable_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	# If I still don't have an variable_uuid, we're INSERT'ing .
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "variable_uuid", value1 => $variable_uuid, 
	}, file => $THIS_FILE, line => __LINE__});
	if (not $variable_uuid)
	{
		# INSERT
		   $variable_uuid = $an->Get->uuid();
		my $query         = "
INSERT INTO 
    variables 
(
    variable_uuid, 
    variable_name, 
    variable_value, 
    variable_default, 
    variable_description, 
    variable_section, 
    variable_source_uuid, 
    variable_source_table, 
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($variable_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($variable_name).", 
    ".$an->data->{sys}{use_db_fh}->quote($variable_value).", 
    ".$an->data->{sys}{use_db_fh}->quote($variable_default).", 
    ".$an->data->{sys}{use_db_fh}->quote($variable_description).", 
    ".$an->data->{sys}{use_db_fh}->quote($variable_section).", 
    ".$an->data->{sys}{use_db_fh}->quote($variable_source_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($variable_source_table).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Query only the value
		if ($update_value_only)
		{
			my $query = "
SELECT 
    variable_value 
FROM 
    variables 
WHERE 
    variable_uuid = ".$an->data->{sys}{use_db_fh}->quote($variable_uuid);
			if (($variable_source_uuid ne "NULL") && ($variable_source_table ne "NULL"))
			{
				$query .= "
AND 
    variable_source_uuid  = ".$an->data->{sys}{use_db_fh}->quote($variable_source_uuid)." 
AND 
    variable_source_table = ".$an->data->{sys}{use_db_fh}->quote($variable_source_table)." 
";
			}
			$query .= ";";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "query", value1 => $query, 
			}, file => $THIS_FILE, line => __LINE__});
			
			my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
			my $count   = @{$results};
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "results", value1 => $results, 
				name2 => "count",   value2 => $count
			}, file => $THIS_FILE, line => __LINE__});
			foreach my $row (@{$results})
			{
				my $old_variable_value = defined $row->[0] ? $row->[0] : "";
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "old_variable_value", value1 => $old_variable_value, 
				}, file => $THIS_FILE, line => __LINE__});
				
				# Anything change?
				if ($old_variable_value ne $variable_value)
				{
					# Variable changed, save.
					my $query = "
UPDATE 
    variables 
SET 
    variable_value = ".$an->data->{sys}{use_db_fh}->quote($variable_value).", 
    modified_date  = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    variable_uuid  = ".$an->data->{sys}{use_db_fh}->quote($variable_uuid);
					if (($variable_source_uuid ne "NULL") && ($variable_source_table ne "NULL"))
					{
						$query .= "
AND 
    variable_source_uuid  = ".$an->data->{sys}{use_db_fh}->quote($variable_source_uuid)." 
AND 
    variable_source_table = ".$an->data->{sys}{use_db_fh}->quote($variable_source_table)." 
";
					}
					$query .= ";";
					$query =~ s/'NULL'/NULL/g;
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "query", value1 => $query, 
					}, file => $THIS_FILE, line => __LINE__});
					$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
				}
			}
		}
		else
		{
			# Query the rest of the values and see if anything changed.
			my $query = "
SELECT 
    variable_name, 
    variable_value, 
    variable_default, 
    variable_description, 
    variable_section 
FROM 
    variables 
WHERE 
    variable_uuid = ".$an->data->{sys}{use_db_fh}->quote($variable_uuid)." 
;";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "query", value1 => $query, 
			}, file => $THIS_FILE, line => __LINE__});
			
			my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
			my $count   = @{$results};
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "results", value1 => $results, 
				name2 => "count",   value2 => $count
			}, file => $THIS_FILE, line => __LINE__});
			foreach my $row (@{$results})
			{
				my $old_variable_name        = $row->[0];
				my $old_variable_value       = $row->[1] ? $row->[1] : "NULL";
				my $old_variable_default     = $row->[2] ? $row->[2] : "NULL";
				my $old_variable_description = $row->[3] ? $row->[3] : "NULL";
				my $old_variable_section     = $row->[4] ? $row->[4] : "NULL";
				$an->Log->entry({log_level => 3, message_key => "an_variables_0005", message_variables => {
					name1 => "old_variable_name",        value1 => $old_variable_name, 
					name2 => "old_variable_value",       value2 => $old_variable_value, 
					name3 => "old_variable_default",     value3 => $old_variable_default, 
					name4 => "old_variable_description", value4 => $old_variable_description, 
					name5 => "old_variable_section",     value5 => $old_variable_section, 
				}, file => $THIS_FILE, line => __LINE__});
				
				# Anything change?
				if (($old_variable_name        ne $variable_name)        or 
				    ($old_variable_value       ne $variable_value)       or 
				    ($old_variable_default     ne $variable_default)     or 
				    ($old_variable_description ne $variable_description) or 
				    ($old_variable_section     ne $variable_section))
				{
					# Something changed, save.
					my $query = "
UPDATE 
    variables 
SET 
    variable_name        = ".$an->data->{sys}{use_db_fh}->quote($variable_name).", 
    variable_value       = ".$an->data->{sys}{use_db_fh}->quote($variable_value).", 
    variable_default     = ".$an->data->{sys}{use_db_fh}->quote($variable_default).", 
    variable_description = ".$an->data->{sys}{use_db_fh}->quote($variable_description).", 
    variable_section     = ".$an->data->{sys}{use_db_fh}->quote($variable_section).", 
    modified_date        = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    variable_uuid        = ".$an->data->{sys}{use_db_fh}->quote($variable_uuid)." 
";
					$query =~ s/'NULL'/NULL/g;
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "query", value1 => $query, 
					}, file => $THIS_FILE, line => __LINE__});
					$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
				}
			}
		}
	}
	
	return($variable_uuid);
}

# Read or set/update the lock file timestamp.
sub lock_file
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "lock_file" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $do = $parameter->{'do'} ? $parameter->{'do'} : "get";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "do", value1 => $do, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $lock_time = "";
	if ($do eq "set")
	{
		my $shell_call = $an->data->{path}{scancore_lock};
		   $lock_time  = time;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "shell_call", value1 => $shell_call, 
			name2 => "lock_time",  value2 => $lock_time, 
		}, file => $THIS_FILE, line => __LINE__});
		open (my $file_handle, ">$shell_call") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0015", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
		print $file_handle "$lock_time\n";
		close $file_handle;
	}
	else
	{
		# Read the lock file's time stamp, if the file exists.
		if (-e $an->data->{path}{scancore_lock})
		{
			my $shell_call = $an->data->{path}{scancore_lock};
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "shell_call", value1 => $shell_call, 
			}, file => $THIS_FILE, line => __LINE__});
			open (my $file_handle, "<$shell_call") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0016", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
			while(<$file_handle>)
			{
				chomp;
				my $line = $_;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "line", value1 => $line, 
				}, file => $THIS_FILE, line => __LINE__});
				if ($line =~ /^\d+$/)
				{
					$lock_time = $line;
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "lock_time", value1 => $lock_time, 
					}, file => $THIS_FILE, line => __LINE__});
					last;
				}
			}
			close $file_handle;
		}
	}
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "lock_time", value1 => $lock_time, 
	}, file => $THIS_FILE, line => __LINE__});
	return($lock_time);
}

# This uses the data from 'get_anvils()', 'get_nodes()' and 'get_owners()' and stores the data in 
# '$an->data->{anvils}{<uuid>}{<values>}' as used in striker.
sub parse_anvil_data
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "parse_anvil_data" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $include_deleted = $parameter->{include_deleted} ? $parameter->{include_deleted} : 0;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "include_deleted", value1 => $include_deleted, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $anvil_data = $an->ScanCore->get_anvils({include_deleted => $include_deleted});
	my $host_data  = $an->ScanCore->get_hosts({include_deleted => $include_deleted});
	my $node_data  = $an->ScanCore->get_nodes({include_deleted => $include_deleted});
	my $owner_data = $an->ScanCore->get_owners({include_deleted => $include_deleted});
	my $smtp_data  = $an->ScanCore->get_smtp({include_deleted => $include_deleted});
	$an->Log->entry({log_level => 3, message_key => "an_variables_0005", message_variables => {
		name1 => "anvil_data", value1 => $anvil_data, 
		name2 => "host_data",  value2 => $host_data, 
		name3 => "node_data",  value3 => $node_data, 
		name4 => "owner_data", value4 => $owner_data, 
		name5 => "smtp_data",  value5 => $smtp_data, 
	}, file => $THIS_FILE, line => __LINE__});
	
	foreach my $hash_ref (@{$host_data})
	{
		# Get the host UUID
		my $host_uuid = $hash_ref->{host_uuid};
		
		$an->data->{db}{hosts}{$host_uuid}{name}           = $hash_ref->{host_name};
		$an->data->{db}{hosts}{$host_uuid}{type}           = $hash_ref->{host_type};
		$an->data->{db}{hosts}{$host_uuid}{health}         = $hash_ref->{host_health} ? $hash_ref->{host_health} : 0;
		$an->data->{db}{hosts}{$host_uuid}{emergency_stop} = $hash_ref->{host_emergency_stop};
		$an->data->{db}{hosts}{$host_uuid}{stop_reason}    = $hash_ref->{host_stop_reason};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0005", message_variables => {
			name1 => "db::hosts::${host_uuid}::name",           value1 => $an->data->{db}{hosts}{$host_uuid}{name}, 
			name2 => "db::hosts::${host_uuid}::type",           value2 => $an->data->{db}{hosts}{$host_uuid}{type}, 
			name3 => "db::hosts::${host_uuid}::health",         value3 => $an->data->{db}{hosts}{$host_uuid}{health}, 
			name4 => "db::hosts::${host_uuid}::emergency_stop", value4 => $an->data->{db}{hosts}{$host_uuid}{emergency_stop}, 
			name5 => "db::hosts::${host_uuid}::stop_reason",    value5 => $an->data->{db}{hosts}{$host_uuid}{stop_reason}, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	foreach my $hash_ref (@{$node_data})
	{
		# Get the node UUID.
		my $node_uuid = $hash_ref->{node_uuid};
		my $host_uuid = $hash_ref->{node_host_uuid};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "node_uuid", value1 => $node_uuid, 
			name2 => "host_uuid", value2 => $host_uuid, 
		}, file => $THIS_FILE, line => __LINE__});
		
		# Store the data
		$an->data->{db}{nodes}{$node_uuid}{anvil_uuid}  = $hash_ref->{node_anvil_uuid};
		$an->data->{db}{nodes}{$node_uuid}{remote_ip}   = $hash_ref->{node_remote_ip};
		$an->data->{db}{nodes}{$node_uuid}{remote_port} = $hash_ref->{node_remote_port};
		$an->data->{db}{nodes}{$node_uuid}{note}        = $hash_ref->{node_note};
		$an->data->{db}{nodes}{$node_uuid}{bcn_ip}      = $hash_ref->{node_bcn};
		$an->data->{db}{nodes}{$node_uuid}{sn_ip}       = $hash_ref->{node_sn};
		$an->data->{db}{nodes}{$node_uuid}{ifn_ip}      = $hash_ref->{node_ifn};
		$an->data->{db}{nodes}{$node_uuid}{host_uuid}   = $host_uuid;
		$an->data->{db}{nodes}{$node_uuid}{password}    = $hash_ref->{node_password};
		
		# Push in the host data
		$an->data->{db}{nodes}{$node_uuid}{name}           = $an->data->{db}{hosts}{$host_uuid}{name};
		$an->data->{db}{nodes}{$node_uuid}{type}           = $an->data->{db}{hosts}{$host_uuid}{type};
		$an->data->{db}{nodes}{$node_uuid}{health}         = $an->data->{db}{hosts}{$host_uuid}{health};
		$an->data->{db}{nodes}{$node_uuid}{emergency_stop} = $an->data->{db}{hosts}{$host_uuid}{emergency_stop};
		$an->data->{db}{nodes}{$node_uuid}{stop_reason}    = $an->data->{db}{hosts}{$host_uuid}{stop_reason};
		
		$an->Log->entry({log_level => 3, message_key => "an_variables_0013", message_variables => {
			name1  => "db::nodes::${node_uuid}::anvil_uuid",     value1  => $an->data->{db}{nodes}{$node_uuid}{anvil_uuid}, 
			name2  => "db::nodes::${node_uuid}::remote_ip",      value2  => $an->data->{db}{nodes}{$node_uuid}{remote_ip}, 
			name3  => "db::nodes::${node_uuid}::remote_port",    value3  => $an->data->{db}{nodes}{$node_uuid}{remote_port}, 
			name4  => "db::nodes::${node_uuid}::note",           value4  => $an->data->{db}{nodes}{$node_uuid}{note}, 
			name5  => "db::nodes::${node_uuid}::bcn_ip",         value5  => $an->data->{db}{nodes}{$node_uuid}{bcn_ip}, 
			name6  => "db::nodes::${node_uuid}::sn_ip",          value6  => $an->data->{db}{nodes}{$node_uuid}{sn_ip}, 
			name7  => "db::nodes::${node_uuid}::ifn_ip",         value7  => $an->data->{db}{nodes}{$node_uuid}{ifn_ip}, 
			name8  => "db::nodes::${node_uuid}::host_uuid",      value8  => $an->data->{db}{nodes}{$node_uuid}{host_uuid}, 
			name9  => "db::nodes::${node_uuid}::name",           value9  => $an->data->{db}{nodes}{$node_uuid}{name}, 
			name10 => "db::nodes::${node_uuid}::type",           value10 => $an->data->{db}{nodes}{$node_uuid}{type}, 
			name11 => "db::nodes::${node_uuid}::health",         value11 => $an->data->{db}{nodes}{$node_uuid}{health}, 
			name12 => "db::nodes::${node_uuid}::emergency_stop", value12 => $an->data->{db}{nodes}{$node_uuid}{emergency_stop}, 
			name13 => "db::nodes::${node_uuid}::stop_reason",    value13 => $an->data->{db}{nodes}{$node_uuid}{stop_reason}, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
			name1 => "db::nodes::${node_uuid}::password", value1 => $an->data->{db}{nodes}{$node_uuid}{password}, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	foreach my $hash_ref (@{$owner_data})
	{
		# Get the owner UUID
		my $owner_uuid = $hash_ref->{owner_uuid};
		
		# Store the data
		$an->data->{db}{owners}{$owner_uuid}{name} = $hash_ref->{owner_name};
		$an->data->{db}{owners}{$owner_uuid}{note} = $hash_ref->{owner_note};
		
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "db::owners::${owner_uuid}::name", value1 => $an->data->{db}{owners}{$owner_uuid}{name}, 
			name2 => "db::owners::${owner_uuid}::note", value2 => $an->data->{db}{owners}{$owner_uuid}{note}, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	foreach my $hash_ref (@{$smtp_data})
	{
		# Get the SMTP UUID
		my $smtp_uuid = $hash_ref->{smtp_uuid};
		
		# Store the data
		$an->data->{db}{smtp}{$smtp_uuid}{server}         = $hash_ref->{smtp_server};
		$an->data->{db}{smtp}{$smtp_uuid}{port}           = $hash_ref->{smtp_port};
		$an->data->{db}{smtp}{$smtp_uuid}{alt_server}     = $hash_ref->{smtp_alt_server};
		$an->data->{db}{smtp}{$smtp_uuid}{alt_port}       = $hash_ref->{smtp_alt_port};
		$an->data->{db}{smtp}{$smtp_uuid}{username}       = $hash_ref->{smtp_username};
		$an->data->{db}{smtp}{$smtp_uuid}{security}       = $hash_ref->{smtp_security};
		$an->data->{db}{smtp}{$smtp_uuid}{authentication} = $hash_ref->{smtp_authentication};
		$an->data->{db}{smtp}{$smtp_uuid}{helo_domain}    = $hash_ref->{smtp_helo_domain};
		$an->data->{db}{smtp}{$smtp_uuid}{password}       = $hash_ref->{smtp_password};
		
		$an->Log->entry({log_level => 3, message_key => "an_variables_0008", message_variables => {
			name1 => "db::smtp::${smtp_uuid}::server",         value1 => $an->data->{db}{smtp}{$smtp_uuid}{server}, 
			name2 => "db::smtp::${smtp_uuid}::port",           value2 => $an->data->{db}{smtp}{$smtp_uuid}{port}, 
			name3 => "db::smtp::${smtp_uuid}::alt_server",     value3 => $an->data->{db}{smtp}{$smtp_uuid}{alt_server}, 
			name4 => "db::smtp::${smtp_uuid}::alt_port",       value4 => $an->data->{db}{smtp}{$smtp_uuid}{alt_port}, 
			name5 => "db::smtp::${smtp_uuid}::username",       value5 => $an->data->{db}{smtp}{$smtp_uuid}{username}, 
			name6 => "db::smtp::${smtp_uuid}::security",       value6 => $an->data->{db}{smtp}{$smtp_uuid}{security}, 
			name7 => "db::smtp::${smtp_uuid}::authentication", value7 => $an->data->{db}{smtp}{$smtp_uuid}{authentication}, 
			name8 => "db::smtp::${smtp_uuid}::helo_domain",    value8 => $an->data->{db}{smtp}{$smtp_uuid}{helo_domain}, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
			name1 => "db::smtp::${smtp_uuid}::password", value1 => $an->data->{db}{smtp}{$smtp_uuid}{password}, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	# If no 'cgi::anvil_uuid' has been set and if only one anvil is defined, we will auto-select it.
	my $anvil_count = @{$anvil_data};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "anvil_count", value1 => $anvil_count, 
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $hash_ref (@{$anvil_data})
	{
		# Get the Anvil! UUID and associates UUIDs.
		my $anvil_uuid       = $hash_ref->{anvil_uuid};
		my $anvil_name       = $hash_ref->{anvil_name};
		my $anvil_owner_uuid = $hash_ref->{anvil_owner_uuid};
		my $anvil_smtp_uuid  = defined $hash_ref->{anvil_smtp_uuid} ? $hash_ref->{anvil_smtp_uuid} : "";
		
		### NOTE: This is set before we read the CGI variables. So we'll mark this as having been set
		###       here so that, if the CGI variable was set, we'll override this.
		if ($anvil_count == 1)
		{
			$an->data->{cgi}{anvil_uuid}     = $anvil_uuid;
			$an->data->{sys}{anvil_uuid_set} = 1;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "cgi::anvil_uuid",     value1 => $an->data->{cgi}{anvil_uuid}, 
				name2 => "sys::anvil_uuid_set", value2 => $an->data->{sys}{anvil_uuid_set}, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		
		# Store the data
		$an->data->{anvils}{$anvil_uuid}{name}        = $hash_ref->{anvil_name};
		$an->data->{anvils}{$anvil_uuid}{description} = $hash_ref->{anvil_description};
		$an->data->{anvils}{$anvil_uuid}{note}        = $hash_ref->{anvil_note};
		$an->data->{anvils}{$anvil_uuid}{password}    = $hash_ref->{anvil_password};
		
		$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
			name1 => "anvils::${anvil_uuid}::name",        value1 => $an->data->{anvils}{$anvil_uuid}{name}, 
			name2 => "anvils::${anvil_uuid}::description", value2 => $an->data->{anvils}{$anvil_uuid}{description}, 
			name3 => "anvils::${anvil_uuid}::note",        value3 => $an->data->{anvils}{$anvil_uuid}{note}, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
			name1 => "anvils::${anvil_uuid}::password", value1 => $an->data->{anvils}{$anvil_uuid}{password}, 
		}, file => $THIS_FILE, line => __LINE__});
		
		# This will be used later to display Anvil! systems to users in a sorted list.
		$an->data->{sorted}{anvils}{$anvil_name}{uuid} = $anvil_uuid;
		
		# Find the nodes associated with this Anvil!
		my $nodes = [];
		foreach my $node_uuid (keys %{$an->data->{db}{nodes}})
		{
			# Is this node related to this Anvil! system?
			my $node_anvil_uuid = $an->data->{db}{nodes}{$node_uuid}{anvil_uuid};
			$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
				name1 => "node_uuid",       value1 => $node_uuid, 
				name2 => "node_anvil_uuid", value2 => $node_anvil_uuid, 
				name3 => "anvil_uuid",      value3 => $anvil_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
			
			if ($node_anvil_uuid eq $anvil_uuid)
			{
				my $node_name   = $an->data->{db}{nodes}{$node_uuid}{name};
				my $node_string = "$node_name,$node_uuid";
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "node_string", value1 => $node_string, 
				}, file => $THIS_FILE, line => __LINE__});
				
				push @{$nodes}, $node_string;
			}
		}
		# Sort the nodes by their name and pull out their UUID.
		my $processed_node1 = 0;
		foreach my $node (sort {$a cmp $b} @{$nodes})
		{
			my ($node_name, $node_uuid) = ($node =~ /^(.*?),(.*)$/);
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "node_name", value1 => $node_name, 
				name2 => "node_uuid", value2 => $node_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
			my $node_key = "node1";
			if ($processed_node1)
			{
				$node_key = "node2";
			}
			else
			{
				$processed_node1 = 1;
			}
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "node_key", value1 => $node_key, 
			}, file => $THIS_FILE, line => __LINE__});
			
			# Store this so that we can later access the data as 'node1' or 'node2'
			$an->data->{db}{nodes}{$node_uuid}{node_key} = $node_key;
			$an->data->{anvils}{$anvil_uuid}{$node_key}  = {
				uuid           => $node_uuid,
				name           => $an->data->{db}{nodes}{$node_uuid}{name}, 
				remote_ip      => $an->data->{db}{nodes}{$node_uuid}{remote_ip}, 
				remote_port    => $an->data->{db}{nodes}{$node_uuid}{remote_port}, 
				note           => $an->data->{db}{nodes}{$node_uuid}{note}, 
				bcn_ip         => $an->data->{db}{nodes}{$node_uuid}{bcn_ip}, 
				sn_ip          => $an->data->{db}{nodes}{$node_uuid}{sn_ip}, 
				ifn_ip         => $an->data->{db}{nodes}{$node_uuid}{ifn_ip}, 
				type           => $an->data->{db}{nodes}{$node_uuid}{type}, 
				health         => $an->data->{db}{nodes}{$node_uuid}{health}, 
				emergency_stop => $an->data->{db}{nodes}{$node_uuid}{emergency_stop}, 
				stop_reason    => $an->data->{db}{nodes}{$node_uuid}{stop_reason}, 
				use_ip         => "",        # This will be set to the IP/name we successfully connect to the node with.
				use_port       => 22,        # This will switch to the remote_port if we use the remote_ip to access.
				online         => 0,         # This will be set to '1' if we successfully access the node
				power          => "unknown", # This will be set to 'on' or 'off' when we access it or based on the 'power check command' output
				host_uuid      => $an->data->{db}{nodes}{$node_uuid}{host_uuid}, 
				password       => $an->data->{db}{nodes}{$node_uuid}{password} ? $an->data->{db}{nodes}{$node_uuid}{password} : $an->data->{anvils}{$anvil_uuid}{password}, 
			};
			$an->Log->entry({log_level => 3, message_key => "an_variables_0017", message_variables => {
				name1  => "anvils::${anvil_uuid}::${node_key}::uuid",           value1  => $an->data->{anvils}{$anvil_uuid}{$node_key}{uuid}, 
				name2  => "anvils::${anvil_uuid}::${node_key}::name",           value2  => $an->data->{anvils}{$anvil_uuid}{$node_key}{name}, 
				name3  => "anvils::${anvil_uuid}::${node_key}::remote_ip",      value3  => $an->data->{anvils}{$anvil_uuid}{$node_key}{remote_ip}, 
				name4  => "anvils::${anvil_uuid}::${node_key}::remote_port",    value4  => $an->data->{anvils}{$anvil_uuid}{$node_key}{remote_port}, 
				name5  => "anvils::${anvil_uuid}::${node_key}::note",           value5  => $an->data->{anvils}{$anvil_uuid}{$node_key}{note}, 
				name6  => "anvils::${anvil_uuid}::${node_key}::bcn_ip",         value6  => $an->data->{anvils}{$anvil_uuid}{$node_key}{bcn_ip}, 
				name7  => "anvils::${anvil_uuid}::${node_key}::sn_ip",          value7  => $an->data->{anvils}{$anvil_uuid}{$node_key}{sn_ip}, 
				name8  => "anvils::${anvil_uuid}::${node_key}::ifn_ip",         value8  => $an->data->{anvils}{$anvil_uuid}{$node_key}{ifn_ip}, 
				name9  => "anvils::${anvil_uuid}::${node_key}::type",           value9  => $an->data->{anvils}{$anvil_uuid}{$node_key}{type}, 
				name10 => "anvils::${anvil_uuid}::${node_key}::health",         value10 => $an->data->{anvils}{$anvil_uuid}{$node_key}{health}, 
				name11 => "anvils::${anvil_uuid}::${node_key}::emergency_stop", value11 => $an->data->{anvils}{$anvil_uuid}{$node_key}{emergency_stop}, 
				name12 => "anvils::${anvil_uuid}::${node_key}::stop_reason",    value12 => $an->data->{anvils}{$anvil_uuid}{$node_key}{stop_reason}, 
				name13 => "anvils::${anvil_uuid}::${node_key}::use_ip",         value13 => $an->data->{anvils}{$anvil_uuid}{$node_key}{use_ip}, 
				name14 => "anvils::${anvil_uuid}::${node_key}::use_port",       value14 => $an->data->{anvils}{$anvil_uuid}{$node_key}{use_port}, 
				name15 => "anvils::${anvil_uuid}::${node_key}::online",         value15 => $an->data->{anvils}{$anvil_uuid}{$node_key}{online}, 
				name16 => "anvils::${anvil_uuid}::${node_key}::power",          value16 => $an->data->{anvils}{$anvil_uuid}{$node_key}{power}, 
				name17 => "anvils::${anvil_uuid}::${node_key}::host_uuid",      value17 => $an->data->{anvils}{$anvil_uuid}{$node_key}{host_uuid}, 
			}, file => $THIS_FILE, line => __LINE__});
			$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
				name1 => "anvils::${anvil_uuid}::${node_key}::password", value1 => $an->data->{anvils}{$anvil_uuid}{$node_key}{password}, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		
		# Store the owner data.
		foreach my $owner_uuid (keys %{$an->data->{db}{owners}})
		{
			if ($anvil_owner_uuid eq $owner_uuid)
			{
				$an->data->{anvils}{$anvil_uuid}{owner}{name} = $an->data->{db}{owners}{$owner_uuid}{name};
				$an->data->{anvils}{$anvil_uuid}{owner}{note} = $an->data->{db}{owners}{$owner_uuid}{note};
				
				$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
					name1 => "anvils::${anvil_uuid}::owner::name", value1 => $an->data->{anvils}{$anvil_uuid}{owner}{name}, 
					name2 => "anvils::${anvil_uuid}::owner::note", value2 => $an->data->{anvils}{$anvil_uuid}{owner}{note}, 
				}, file => $THIS_FILE, line => __LINE__});
			}
		}
		
		# Store the SMTP mail server info.
		foreach my $smtp_uuid (keys %{$an->data->{db}{smtp}})
		{
			if ($anvil_smtp_uuid eq $smtp_uuid)
			{
				$an->data->{anvils}{$anvil_uuid}{smtp}{server}         = $an->data->{db}{smtp}{$smtp_uuid}{server};
				$an->data->{anvils}{$anvil_uuid}{smtp}{port}           = $an->data->{db}{smtp}{$smtp_uuid}{port};
				$an->data->{anvils}{$anvil_uuid}{smtp}{alt_server}     = $an->data->{db}{smtp}{$smtp_uuid}{alt_server};
				$an->data->{anvils}{$anvil_uuid}{smtp}{alt_port}       = $an->data->{db}{smtp}{$smtp_uuid}{alt_port};
				$an->data->{anvils}{$anvil_uuid}{smtp}{username}       = $an->data->{db}{smtp}{$smtp_uuid}{username};
				$an->data->{anvils}{$anvil_uuid}{smtp}{security}       = $an->data->{db}{smtp}{$smtp_uuid}{security};
				$an->data->{anvils}{$anvil_uuid}{smtp}{authentication} = $an->data->{db}{smtp}{$smtp_uuid}{authentication};
				$an->data->{anvils}{$anvil_uuid}{smtp}{helo_domain}    = $an->data->{db}{smtp}{$smtp_uuid}{helo_domain};
				$an->data->{anvils}{$anvil_uuid}{smtp}{password}       = $an->data->{db}{smtp}{$smtp_uuid}{password};
				$an->Log->entry({log_level => 3, message_key => "an_variables_0008", message_variables => {
					name1 => "anvils::${anvil_uuid}::smtp::server",         value1 => $an->data->{anvils}{$anvil_uuid}{smtp}{server}, 
					name2 => "anvils::${anvil_uuid}::smtp::port",           value2 => $an->data->{anvils}{$anvil_uuid}{smtp}{port}, 
					name3 => "anvils::${anvil_uuid}::smtp::alt_server",     value3 => $an->data->{anvils}{$anvil_uuid}{smtp}{alt_server}, 
					name4 => "anvils::${anvil_uuid}::smtp::alt_port",       value4 => $an->data->{anvils}{$anvil_uuid}{smtp}{alt_port}, 
					name5 => "anvils::${anvil_uuid}::smtp::username",       value5 => $an->data->{anvils}{$anvil_uuid}{smtp}{username}, 
					name6 => "anvils::${anvil_uuid}::smtp::security",       value6 => $an->data->{anvils}{$anvil_uuid}{smtp}{security}, 
					name7 => "anvils::${anvil_uuid}::smtp::authentication", value7 => $an->data->{anvils}{$anvil_uuid}{smtp}{authentication}, 
					name8 => "anvils::${anvil_uuid}::smtp::helo_domain",    value8 => $an->data->{anvils}{$anvil_uuid}{smtp}{helo_domain}, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
					name1 => "anvils::${anvil_uuid}::smtp::password", value1 => $an->data->{anvils}{$anvil_uuid}{smtp}{password}, 
				}, file => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	return(0);
}

# This parses an Install Manifest
sub parse_install_manifest
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "parse_install_manifest" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	### TODO: Support getting a UUID
	if (not $parameter->{uuid})
	{
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0093", code => 93, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	my $manifest_data = "";
	my $return        = $an->ScanCore->get_manifests();
	foreach my $hash_ref (@{$return})
	{
		if ($parameter->{uuid} eq $hash_ref->{manifest_uuid})
		{
			$manifest_data = $hash_ref->{manifest_data};
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "manifest_data", value1 => $manifest_data,
			}, file => $THIS_FILE, line => __LINE__});
			last;
		}
	}
	
	if (not $manifest_data)
	{
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0094", message_variables => { uuid => $parameter->{uuid} }, code => 94, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	my $uuid = $parameter->{uuid};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "uuid", value1 => $uuid,
	}, file => $THIS_FILE, line => __LINE__});
	
	# TODO: Verify the XML is sane (xmlint?)
	my $xml  = XML::Simple->new();
	my $data = $xml->XMLin($manifest_data, KeyAttr => {node => 'name'}, ForceArray => 1);
	
	# Nodes.
	foreach my $node (keys %{$data->{node}})
	{
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "node", value1 => $node,
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $a (keys %{$data->{node}{$node}})
		{
			if ($a eq "interfaces")
			{
				foreach my $b (keys %{$data->{node}{$node}{interfaces}->[0]})
				{
					foreach my $c (@{$data->{node}{$node}{interfaces}->[0]->{$b}})
					{
						my $name = $c->{name} ? $c->{name} : "";
						my $mac  = $c->{mac}  ? $c->{mac}  : "";
						$an->data->{install_manifest}{$uuid}{node}{$node}{interface}{$name}{mac} = "";
						if (($mac) && ($mac =~ /^([0-9A-F]{2}[:-]){5}([0-9A-F]{2})$/i))
						{
							$an->data->{install_manifest}{$uuid}{node}{$node}{interface}{$name}{mac} = $mac;
						}
						elsif ($mac)
						{
							# Malformed MAC
							$an->Log->entry({log_level => 3, message_key => "tools_log_0027", message_variables => {
								uuid => $uuid, 
								node => $node, 
								name => $name, 
								mac  => $mac, 
							}, file => $THIS_FILE, line => __LINE__});
						}
					}
				}
			}
			elsif ($a eq "network")
			{
				$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
					name1 => "a",                                 value1 => $a,
					name2 => "data->node::${node}::network->[0]", value2 => $data->{node}{$node}{network}->[0],
				}, file => $THIS_FILE, line => __LINE__});
				foreach my $network (keys %{$data->{node}{$node}{network}->[0]})
				{
					my $ip = $data->{node}{$node}{network}->[0]->{$network}->[0]->{ip};
					$an->data->{install_manifest}{$uuid}{node}{$node}{network}{$network}{ip} = $ip ? $ip : "";
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "install_manifest::${uuid}::node::${node}::network::${network}::ip", value1 => $an->data->{install_manifest}{$uuid}{node}{$node}{network}{$network}{ip},
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			elsif ($a eq "pdu")
			{
				foreach my $b (@{$data->{node}{$node}{pdu}->[0]->{on}})
				{
					my $reference       = $b->{reference};
					my $name            = $b->{name};
					my $port            = $b->{port};
					my $user            = $b->{user};
					my $password        = $b->{password};
					my $password_script = $b->{password_script};
					
					$an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$reference}{name}            = $name            ? $name            : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$reference}{port}            = $port            ? $port            : ""; 
					$an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$reference}{user}            = $user            ? $user            : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$reference}{password}        = $password        ? $password        : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$reference}{password_script} = $password_script ? $password_script : "";
					$an->Log->entry({log_level => 3, message_key => "an_variables_0004", message_variables => {
						name1 => "install_manifest::${uuid}::node::${node}::pdu::${reference}::name",            value1 => $an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$reference}{name},
						name2 => "install_manifest::${uuid}::node::${node}::pdu::${reference}::port",            value2 => $an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$reference}{port},
						name3 => "install_manifest::${uuid}::node::${node}::pdu::${reference}::user",            value3 => $an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$reference}{user},
						name4 => "install_manifest::${uuid}::node::${node}::pdu::${reference}::password_script", value4 => $an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$reference}{password_script},
					}, file => $THIS_FILE, line => __LINE__});
					$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
						name1 => "install_manifest::${uuid}::node::${node}::pdu::${reference}::password", value1 => $an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$reference}{password},
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			elsif ($a eq "kvm")
			{
				foreach my $b (@{$data->{node}{$node}{kvm}->[0]->{on}})
				{
					my $reference       = $b->{reference};
					my $name            = $b->{name};
					my $port            = $b->{port};
					my $user            = $b->{user};
					my $password        = $b->{password};
					my $password_script = $b->{password_script};
					
					$an->data->{install_manifest}{$uuid}{node}{$node}{kvm}{$reference}{name}            = $name            ? $name            : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{kvm}{$reference}{port}            = $port            ? $port            : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{kvm}{$reference}{user}            = $user            ? $user            : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{kvm}{$reference}{password}        = $password        ? $password        : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{kvm}{$reference}{password_script} = $password_script ? $password_script : "";
					$an->Log->entry({log_level => 3, message_key => "an_variables_0004", message_variables => {
						name1 => "install_manifest::${uuid}::node::${node}::kvm::${reference}::name",            value1 => $an->data->{install_manifest}{$uuid}{node}{$node}{kvm}{$reference}{name},
						name2 => "install_manifest::${uuid}::node::${node}::kvm::${reference}::port",            value2 => $an->data->{install_manifest}{$uuid}{node}{$node}{kvm}{$reference}{port},
						name3 => "install_manifest::${uuid}::node::${node}::kvm::${reference}::user",            value3 => $an->data->{install_manifest}{$uuid}{node}{$node}{kvm}{$reference}{user},
						name4 => "install_manifest::${uuid}::node::${node}::kvm::${reference}::password_script", value4 => $an->data->{install_manifest}{$uuid}{node}{$node}{kvm}{$reference}{password_script},
					}, file => $THIS_FILE, line => __LINE__});
					$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
						name1 => "install_manifest::${uuid}::node::${node}::kvm::${reference}::password", value1 => $an->data->{install_manifest}{$uuid}{node}{$node}{kvm}{$reference}{password},
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			elsif ($a eq "ipmi")
			{
				foreach my $b (@{$data->{node}{$node}{ipmi}->[0]->{on}})
				{
					$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
						name1 => "b",    value1 => $b,
						name2 => "node", value2 => $node,
					}, file => $THIS_FILE, line => __LINE__});
					foreach my $key (keys %{$b})
					{
						$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
							name1 => "b",       value1 => $b,
							name2 => "node",    value2 => $node,
							name3 => "b->$key", value3 => $b->{$key}, 
						}, file => $THIS_FILE, line => __LINE__});
					}
					my $reference       =         $b->{reference};
					my $name            =         $b->{name};
					my $ip              =         $b->{ip};
					my $gateway         =         $b->{gateway};
					my $netmask         =         $b->{netmask};
					my $user            =         $b->{user};
					my $lanplus         = defined $b->{lanplus} ? $b->{lanplus} : "";
					my $privlvl         = defined $b->{privlvl} ? $b->{privlvl} : "";
					my $password        =         $b->{password};
					my $password_script =         $b->{password_script};
					
					# If the password is more than 16 characters long, truncate it so 
					# that nodes with IPMI v1.5 don't spazz out.
					$an->Log->entry({log_level => 4, message_key => "an_variables_0002", message_variables => {
						name1 => "password", value1 => $password,
						name2 => "length",   value2 => length($password),
					}, file => $THIS_FILE, line => __LINE__});
					if (length($password) > 16)
					{
						$password = substr($password, 0, 16);
						$an->Log->entry({log_level => 4, message_key => "an_variables_0002", message_variables => {
							name1 => "password", value1 => $password,
							name2 => "length",   value2 => length($password),
						}, file => $THIS_FILE, line => __LINE__});
					}
					
					$an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{name}            = $name            ? $name            : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{ip}              = $ip              ? $ip              : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{gateway}         = $gateway         ? $gateway         : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{netmask}         = $netmask         ? $netmask         : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{user}            = $user            ? $user            : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{lanplus}         = $lanplus         ? $lanplus         : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{privlvl}         = $privlvl         ? $privlvl         : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{password}        = $password        ? $password        : "";
					$an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{password_script} = $password_script ? $password_script : "";
					$an->Log->entry({log_level => 3, message_key => "an_variables_0008", message_variables => {
						name1 => "install_manifest::${uuid}::node::${node}::ipmi::${reference}::name",            value1 => $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{name},
						name2 => "install_manifest::${uuid}::node::${node}::ipmi::${reference}::ip",              value2 => $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{ip},
						name3 => "install_manifest::${uuid}::node::${node}::ipmi::${reference}::netmask",         value3 => $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{netmask}, 
						name4 => "install_manifest::${uuid}::node::${node}::ipmi::${reference}::gateway",         value4 => $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{gateway},
						name5 => "install_manifest::${uuid}::node::${node}::ipmi::${reference}::user",            value5 => $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{user},
						name6 => "install_manifest::${uuid}::node::${node}::ipmi::${reference}::lanplus",         value6 => $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{lanplus},
						name7 => "install_manifest::${uuid}::node::${node}::ipmi::${reference}::privlvl",         value7 => $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{privlvl},
						name8 => "install_manifest::${uuid}::node::${node}::ipmi::${reference}::password_script", value8 => $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{password_script},
					}, file => $THIS_FILE, line => __LINE__});
					$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
						name1 => "install_manifest::${uuid}::node::${node}::ipmi::${reference}::password", value1 => $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{password},
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			elsif ($a eq "uuid")
			{
				my $node_uuid = $data->{node}{$node}{uuid};
				$an->data->{install_manifest}{$uuid}{node}{$node}{uuid} = $node_uuid ? $node_uuid : "";
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "install_manifest::${uuid}::node::${node}::uuid", value1 => $an->data->{install_manifest}{$uuid}{node}{$node}{uuid},
				}, file => $THIS_FILE, line => __LINE__});
			}
			else
			{
				# What's this?
				$an->Log->entry({log_level => 3, message_key => "tools_log_0028", message_variables => {
					node    => $node, 
					uuid    => $uuid, 
					element => $b, 
				}, file => $THIS_FILE, line => __LINE__});
				foreach my $b (@{$data->{node}{$node}{$a}})
				{
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "data->node::${node}::${a}->[${b}]", value1 => $data->{node}{$node}{$a}->[$b],
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
		}
	}
	
	# The common variables
	foreach my $a (@{$data->{common}})
	{
		foreach my $b (keys %{$a})
		{
			# Pull out and record the 'anvil'
			if ($b eq "anvil")
			{
				# Only ever one entry in the array reference, so we can safely dereference 
				# immediately.
				my $prefix           = $a->{$b}->[0]->{prefix};
				my $domain           = $a->{$b}->[0]->{domain};
				my $sequence         = $a->{$b}->[0]->{sequence};
				my $password         = $a->{$b}->[0]->{password};
				my $striker_user     = $a->{$b}->[0]->{striker_user};
				my $striker_database = $a->{$b}->[0]->{striker_database};
				$an->data->{install_manifest}{$uuid}{common}{anvil}{prefix}           = $prefix           ? $prefix           : "";
				$an->data->{install_manifest}{$uuid}{common}{anvil}{domain}           = $domain           ? $domain           : "";
				$an->data->{install_manifest}{$uuid}{common}{anvil}{sequence}         = $sequence         ? $sequence         : "";
				$an->data->{install_manifest}{$uuid}{common}{anvil}{password}         = $password         ? $password         : "";
				$an->data->{install_manifest}{$uuid}{common}{anvil}{striker_user}     = $striker_user     ? $striker_user     : "";
				$an->data->{install_manifest}{$uuid}{common}{anvil}{striker_database} = $striker_database ? $striker_database : "";
				$an->Log->entry({log_level => 3, message_key => "an_variables_0005", message_variables => {
					name1 => "install_manifest::${uuid}::common::anvil::prefix",           value1 => $an->data->{install_manifest}{$uuid}{common}{anvil}{prefix},
					name2 => "install_manifest::${uuid}::common::anvil::domain",           value2 => $an->data->{install_manifest}{$uuid}{common}{anvil}{domain},
					name3 => "install_manifest::${uuid}::common::anvil::sequence",         value3 => $an->data->{install_manifest}{$uuid}{common}{anvil}{sequence},
					name4 => "install_manifest::${uuid}::common::anvil::striker_user",     value4 => $an->data->{install_manifest}{$uuid}{common}{anvil}{striker_user},
					name5 => "install_manifest::${uuid}::common::anvil::striker_database", value5 => $an->data->{install_manifest}{$uuid}{common}{anvil}{striker_database},
				}, file => $THIS_FILE, line => __LINE__});
				$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
					name1 => "install_manifest::${uuid}::common::anvil::password", value1 => $an->data->{install_manifest}{$uuid}{common}{anvil}{password},
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($b eq "cluster")
			{
				# Cluster Name
				my $name = $a->{$b}->[0]->{name};
				$an->data->{install_manifest}{$uuid}{common}{cluster}{name} = $name ? $name : "";
				
				# Fencing stuff
				my $post_join_delay = $a->{$b}->[0]->{fence}->[0]->{post_join_delay};
				my $order           = $a->{$b}->[0]->{fence}->[0]->{order};
				my $delay           = $a->{$b}->[0]->{fence}->[0]->{delay};
				my $delay_node      = $a->{$b}->[0]->{fence}->[0]->{delay_node};
				$an->data->{install_manifest}{$uuid}{common}{cluster}{fence}{post_join_delay} = $post_join_delay ? $post_join_delay : "";
				$an->data->{install_manifest}{$uuid}{common}{cluster}{fence}{order}           = $order           ? $order           : "";
				$an->data->{install_manifest}{$uuid}{common}{cluster}{fence}{delay}           = $delay           ? $delay           : "";
				$an->data->{install_manifest}{$uuid}{common}{cluster}{fence}{delay_node}      = $delay_node      ? $delay_node      : "";
				$an->Log->entry({log_level => 3, message_key => "an_variables_0004", message_variables => {
					name1 => "install_manifest::${uuid}::common::cluster::fence::post_join_delay", value1 => $an->data->{install_manifest}{$uuid}{common}{cluster}{fence}{post_join_delay},
					name2 => "install_manifest::${uuid}::common::cluster::fence::order",           value2 => $an->data->{install_manifest}{$uuid}{common}{cluster}{fence}{order},
					name3 => "install_manifest::${uuid}::common::cluster::fence::delay",           value3 => $an->data->{install_manifest}{$uuid}{common}{cluster}{fence}{delay},
					name4 => "install_manifest::${uuid}::common::cluster::fence::delay_node",      value4 => $an->data->{install_manifest}{$uuid}{common}{cluster}{fence}{delay_node},
				}, file => $THIS_FILE, line => __LINE__});
			}
			### This is currently not used, may not have a use-case in the future.
			elsif ($b eq "file")
			{
				foreach my $c (@{$a->{$b}})
				{
					my $name    = $c->{name};
					my $mode    = $c->{mode};
					my $owner   = $c->{owner};
					my $group   = $c->{group};
					my $content = $c->{content};
					
					$an->data->{install_manifest}{$uuid}{common}{file}{$name}{mode}    = $mode    ? $mode    : "";
					$an->data->{install_manifest}{$uuid}{common}{file}{$name}{owner}   = $owner   ? $owner   : "";
					$an->data->{install_manifest}{$uuid}{common}{file}{$name}{group}   = $group   ? $group   : "";
					$an->data->{install_manifest}{$uuid}{common}{file}{$name}{content} = $content ? $content : "";
					$an->Log->entry({log_level => 3, message_key => "an_variables_0004", message_variables => {
						name1 => "install_manifest::${uuid}::common::file::${name}::mode",    value1 => $an->data->{install_manifest}{$uuid}{common}{file}{$name}{mode},
						name2 => "install_manifest::${uuid}::common::file::${name}::owner",   value2 => $an->data->{install_manifest}{$uuid}{common}{file}{$name}{owner},
						name3 => "install_manifest::${uuid}::common::file::${name}::group",   value3 => $an->data->{install_manifest}{$uuid}{common}{file}{$name}{group},
						name4 => "install_manifest::${uuid}::common::file::${name}::content", value4 => $an->data->{install_manifest}{$uuid}{common}{file}{$name}{content},
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			elsif ($b eq "iptables")
			{
				my $ports = $a->{$b}->[0]->{vnc}->[0]->{ports};
				$an->data->{install_manifest}{$uuid}{common}{cluster}{iptables}{vnc_ports} = $ports ? $ports : 100;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "install_manifest::${uuid}::common::cluster::iptables::vnc_ports", value1 => $an->data->{install_manifest}{$uuid}{common}{cluster}{iptables}{vnc_ports},
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($b eq "servers")
			{
				my $use_spice_graphics = $a->{$b}->[0]->{provision}->[0]->{use_spice_graphics};
				$an->data->{install_manifest}{$uuid}{common}{cluster}{servers}{provision}{use_spice_graphics} = $use_spice_graphics ? $use_spice_graphics : "0";
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "install_manifest::${uuid}::common::cluster::servers::provision::use_spice_graphics", value1 => $an->data->{install_manifest}{$uuid}{common}{cluster}{servers}{provision}{use_spice_graphics},
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($b eq "tools")
			{
				# Used to control which Anvil! tools are used and how to use them.
				my $anvil_safe_start   = $a->{$b}->[0]->{'use'}->[0]->{'anvil-safe-start'};
				my $anvil_kick_apc_ups = $a->{$b}->[0]->{'use'}->[0]->{'anvil-kick-apc-ups'};
				my $scancore           = $a->{$b}->[0]->{'use'}->[0]->{scancore};
				$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
					name1 => "anvil-safe-start",   value1 => $anvil_safe_start,
					name2 => "anvil-kick-apc-ups", value2 => $anvil_kick_apc_ups,
					name3 => "scancore",           value3 => $scancore,
				}, file => $THIS_FILE, line => __LINE__});
				
				# Make sure we're using digits.
				$anvil_safe_start   =~ s/true/1/i;
				$anvil_safe_start   =~ s/yes/1/i;
				$anvil_safe_start   =~ s/false/0/i;
				$anvil_safe_start   =~ s/no/0/i;
				
				$anvil_kick_apc_ups =~ s/true/1/i;  
				$anvil_kick_apc_ups =~ s/yes/1/i;
				$anvil_kick_apc_ups =~ s/false/0/i; 
				$anvil_kick_apc_ups =~ s/no/0/i;
				
				$an->data->{install_manifest}{$uuid}{common}{cluster}{tools}{'use'}{'anvil-safe-start'}   = defined $anvil_safe_start   ? $anvil_safe_start   : $an->data->{sys}{install_manifest}{'default'}{'use_anvil-safe-start'};
				$an->data->{install_manifest}{$uuid}{common}{cluster}{tools}{'use'}{'anvil-kick-apc-ups'} = defined $anvil_kick_apc_ups ? $anvil_kick_apc_ups : $an->data->{sys}{install_manifest}{'default'}{'use_anvil-kick-apc-ups'};
				$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
					name1 => "install_manifest::${uuid}::common::cluster::tools::use::anvil-safe-start",   value1 => $an->data->{install_manifest}{$uuid}{common}{cluster}{tools}{'use'}{'anvil-safe-start'},
					name2 => "install_manifest::${uuid}::common::cluster::tools::use::anvil-kick-apc-ups", value2 => $an->data->{install_manifest}{$uuid}{common}{cluster}{tools}{'use'}{'anvil-kick-apc-ups'},
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($b eq "media_library")
			{
				my $size  = $a->{$b}->[0]->{size};
				my $units = $a->{$b}->[0]->{units};
				$an->data->{install_manifest}{$uuid}{common}{media_library}{size}  = $size  ? $size  : "";
				$an->data->{install_manifest}{$uuid}{common}{media_library}{units} = $units ? $units : "";
				$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
					name1 => "install_manifest::${uuid}::common::media_library::size",  value1 => $an->data->{install_manifest}{$uuid}{common}{media_library}{size}, 
					name2 => "install_manifest::${uuid}::common::media_library::units", value2 => $an->data->{install_manifest}{$uuid}{common}{media_library}{units}, 
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($b eq "repository")
			{
				my $urls = $a->{$b}->[0]->{urls};
				$an->data->{install_manifest}{$uuid}{common}{anvil}{repositories} = $urls ? $urls : "";
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "install_manifest::${uuid}::common::anvil::repositories",  value1 => $an->data->{install_manifest}{$uuid}{common}{anvil}{repositories}, 
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($b eq "networks")
			{
				foreach my $c (keys %{$a->{$b}->[0]})
				{
					if ($c eq "bonding")
					{
						foreach my $d (keys %{$a->{$b}->[0]->{$c}->[0]})
						{
							if ($d eq "opts")
							{
								# Global bonding options.
								my $options = $a->{$b}->[0]->{$c}->[0]->{opts};
								$an->data->{install_manifest}{$uuid}{common}{network}{bond}{options} = $options ? $options : "";
								$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
									name1 => "Common bonding options", value1 => $an->data->{install_manifest}{$uuid}{common}{network}{bonds}{options},
								}, file => $THIS_FILE, line => __LINE__});
							}
							else
							{
								# Named network.
								my $name      = $a->{$b}->[0]->{$c}->[0]->{$d}->[0]->{name};
								my $primary   = $a->{$b}->[0]->{$c}->[0]->{$d}->[0]->{primary};
								my $secondary = $a->{$b}->[0]->{$c}->[0]->{$d}->[0]->{secondary};
								$an->data->{install_manifest}{$uuid}{common}{network}{bond}{name}{$name}{primary}   = $primary   ? $primary   : "";
								$an->data->{install_manifest}{$uuid}{common}{network}{bond}{name}{$name}{secondary} = $secondary ? $secondary : "";
								$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
									name1 => "Bond",      value1 => $name,
									name2 => "Primary",   value2 => $an->data->{install_manifest}{$uuid}{common}{network}{bond}{name}{$name}{primary},
									name3 => "Secondary", value3 => $an->data->{install_manifest}{$uuid}{common}{network}{bond}{name}{$name}{secondary},
								}, file => $THIS_FILE, line => __LINE__});
							}
						}
					}
					elsif ($c eq "bridges")
					{
						foreach my $d (@{$a->{$b}->[0]->{$c}->[0]->{bridge}})
						{
							my $name = $d->{name};
							my $on   = $d->{on};
							$an->data->{install_manifest}{$uuid}{common}{network}{bridge}{$name}{on} = $on ? $on : "";
							$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
								name1 => "install_manifest::${uuid}::common::network::bridge::${name}::on", value1 => $an->data->{install_manifest}{$uuid}{common}{network}{bridge}{$name}{on},
							}, file => $THIS_FILE, line => __LINE__});
						}
					}
					elsif ($c eq "mtu")
					{
						#<mtu size=\"".$an->data->{cgi}{anvil_mtu_size}."\" />
						my $size = $a->{$b}->[0]->{$c}->[0]->{size};
						$an->data->{install_manifest}{$uuid}{common}{network}{mtu}{size} = $size ? $size : 1500;
						$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
							name1 => "install_manifest::${uuid}::common::network::mtu::size", value1 => $an->data->{install_manifest}{$uuid}{common}{network}{mtu}{size},
						}, file => $THIS_FILE, line => __LINE__});
					}
					else
					{
						my $netblock     = $a->{$b}->[0]->{$c}->[0]->{netblock};
						my $netmask      = $a->{$b}->[0]->{$c}->[0]->{netmask};
						my $gateway      = $a->{$b}->[0]->{$c}->[0]->{gateway};
						my $defroute     = $a->{$b}->[0]->{$c}->[0]->{defroute};
						my $dns1         = $a->{$b}->[0]->{$c}->[0]->{dns1};
						my $dns2         = $a->{$b}->[0]->{$c}->[0]->{dns2};
						my $ntp1         = $a->{$b}->[0]->{$c}->[0]->{ntp1};
						my $ntp2         = $a->{$b}->[0]->{$c}->[0]->{ntp2};
						my $ethtool_opts = $a->{$b}->[0]->{$c}->[0]->{ethtool_opts};
						
						my $netblock_key     = "${c}_network";
						my $netmask_key      = "${c}_subnet";
						my $gateway_key      = "${c}_gateway";
						my $defroute_key     = "${c}_defroute";
						my $ethtool_opts_key = "${c}_ethtool_opts";
						$an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{netblock}     = defined $netblock     ? $netblock     : $an->data->{sys}{install_manifest}{'default'}{$netblock_key};
						$an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{netmask}      = defined $netmask      ? $netmask      : $an->data->{sys}{install_manifest}{'default'}{$netmask_key};
						$an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{gateway}      = defined $gateway      ? $gateway      : $an->data->{sys}{install_manifest}{'default'}{$gateway_key};
						$an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{defroute}     = defined $defroute     ? $defroute     : $an->data->{sys}{install_manifest}{'default'}{$defroute_key};
						$an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{dns1}         = defined $dns1         ? $dns1         : "";
						$an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{dns2}         = defined $dns2         ? $dns2         : "";
						$an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{ntp1}         = defined $ntp1         ? $ntp1         : "";
						$an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{ntp2}         = defined $ntp2         ? $ntp2         : "";
						$an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{ethtool_opts} = defined $ethtool_opts ? $ethtool_opts : $an->data->{sys}{install_manifest}{'default'}{$ethtool_opts_key};
						$an->Log->entry({log_level => 3, message_key => "an_variables_0009", message_variables => {
							name1 => "install_manifest::${uuid}::common::network::name::${c}::netblock",     value1 => $an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{netblock},
							name2 => "install_manifest::${uuid}::common::network::name::${c}::netmask",      value2 => $an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{netmask},
							name3 => "install_manifest::${uuid}::common::network::name::${c}::gateway",      value3 => $an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{gateway},
							name4 => "install_manifest::${uuid}::common::network::name::${c}::defroute",     value4 => $an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{defroute},
							name5 => "install_manifest::${uuid}::common::network::name::${c}::dns1",         value5 => $an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{dns1},
							name6 => "install_manifest::${uuid}::common::network::name::${c}::dns2",         value6 => $an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{dns2},
							name7 => "install_manifest::${uuid}::common::network::name::${c}::ntp1",         value7 => $an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{ntp1},
							name8 => "install_manifest::${uuid}::common::network::name::${c}::ntp2",         value8 => $an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{ntp2},
							name9 => "install_manifest::${uuid}::common::network::name::${c}::ethtool_opts", value9 => $an->data->{install_manifest}{$uuid}{common}{network}{name}{$c}{ethtool_opts},
						}, file => $THIS_FILE, line => __LINE__});
					}
				}
			}
			elsif ($b eq "drbd")
			{
				foreach my $c (keys %{$a->{$b}->[0]})
				{
					if ($c eq "disk")
					{
						my $disk_barrier  = $a->{$b}->[0]->{$c}->[0]->{'disk-barrier'};
						my $disk_flushes  = $a->{$b}->[0]->{$c}->[0]->{'disk-flushes'};
						my $md_flushes    = $a->{$b}->[0]->{$c}->[0]->{'md-flushes'};
						my $c_plan_ahead  = $a->{$b}->[0]->{$c}->[0]->{'c-plan-ahead'};
						my $c_max_rate    = $a->{$b}->[0]->{$c}->[0]->{'c-max-rate'};
						my $c_min_rate    = $a->{$b}->[0]->{$c}->[0]->{'c-min-rate'};
						my $c_fill_target = $a->{$b}->[0]->{$c}->[0]->{'c-fill-target'};
						
						$an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'disk-barrier'}  = defined $disk_barrier  ? $disk_barrier  : "";
						$an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'disk-flushes'}  = defined $disk_flushes  ? $disk_flushes  : "";
						$an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'md-flushes'}    = defined $md_flushes    ? $md_flushes    : "";
						$an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-plan-ahead'}  = defined $c_plan_ahead  ? $c_plan_ahead  : "";
						$an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-max-rate'}    = defined $c_max_rate    ? $c_max_rate    : "";
						$an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-min-rate'}    = defined $c_min_rate    ? $c_min_rate    : "";
						$an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-fill-target'} = defined $c_fill_target ? $c_fill_target : "";
						$an->Log->entry({log_level => 3, message_key => "an_variables_0007", message_variables => {
							name1 => "install_manifest::${uuid}::common::drbd::disk::disk-barrier",  value1 => $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'disk-barrier'},
							name2 => "install_manifest::${uuid}::common::drbd::disk::disk-flushes",  value2 => $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'disk-flushes'},
							name3 => "install_manifest::${uuid}::common::drbd::disk::md-flushes",    value3 => $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'md-flushes'},
							name4 => "install_manifest::${uuid}::common::drbd::disk::c-plan-ahead",  value4 => $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-plan-ahead'},
							name5 => "install_manifest::${uuid}::common::drbd::disk::c-max-rate",    value5 => $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-max-rate'},
							name6 => "install_manifest::${uuid}::common::drbd::disk::c-min-rate",    value6 => $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-min-rate'},
							name7 => "install_manifest::${uuid}::common::drbd::disk::c-fill-target", value7 => $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-fill-target'},
						}, file => $THIS_FILE, line => __LINE__});
					}
					elsif ($c eq "options")
					{
						my $cpu_mask = $a->{$b}->[0]->{$c}->[0]->{'cpu-mask'};
						$an->data->{install_manifest}{$uuid}{common}{drbd}{options}{'cpu-mask'} = defined $cpu_mask ? $cpu_mask : "";
						$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
							name1 => "install_manifest::${uuid}::common::drbd::options::cpu-mask", value1 => $an->data->{install_manifest}{$uuid}{common}{drbd}{options}{'cpu-mask'},
						}, file => $THIS_FILE, line => __LINE__});
					}
					elsif ($c eq "net")
					{
						my $max_buffers = $a->{$b}->[0]->{$c}->[0]->{'max-buffers'};
						my $sndbuf_size = $a->{$b}->[0]->{$c}->[0]->{'sndbuf-size'};
						my $rcvbuf_size = $a->{$b}->[0]->{$c}->[0]->{'rcvbuf-size'};
						$an->data->{install_manifest}{$uuid}{common}{drbd}{net}{'max-buffers'} = defined $max_buffers ? $max_buffers : "";
						$an->data->{install_manifest}{$uuid}{common}{drbd}{net}{'sndbuf-size'} = defined $sndbuf_size ? $sndbuf_size : "";
						$an->data->{install_manifest}{$uuid}{common}{drbd}{net}{'rcvbuf-size'} = defined $rcvbuf_size ? $rcvbuf_size : "";
						$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
							name1 => "install_manifest::${uuid}::common::drbd::net::max-buffers", value1 => $an->data->{install_manifest}{$uuid}{common}{drbd}{net}{'max-buffers'},
							name2 => "install_manifest::${uuid}::common::drbd::net::sndbuf-size", value2 => $an->data->{install_manifest}{$uuid}{common}{drbd}{net}{'sndbuf-size'},
							name3 => "install_manifest::${uuid}::common::drbd::net::rcvbuf-size", value3 => $an->data->{install_manifest}{$uuid}{common}{drbd}{net}{'rcvbuf-size'},
						}, file => $THIS_FILE, line => __LINE__});
					}
				}
			}
			elsif ($b eq "pdu")
			{
				foreach my $c (@{$a->{$b}->[0]->{pdu}})
				{
					my $reference       = $c->{reference};
					my $name            = $c->{name};
					my $ip              = $c->{ip};
					my $user            = $c->{user};
					my $password        = $c->{password};
					my $password_script = $c->{password_script};
					my $agent           = $c->{agent};
					
					$an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{name}            = $name            ? $name            : "";
					$an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{ip}              = $ip              ? $ip              : "";
					$an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{user}            = $user            ? $user            : "";
					$an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{password}        = $password        ? $password        : "";
					$an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{password_script} = $password_script ? $password_script : "";
					$an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{agent}           = $agent           ? $agent           : $an->data->{sys}{install_manifest}{pdu_agent};
					$an->Log->entry({log_level => 4, message_key => "an_variables_0005", message_variables => {
						name1 => "install_manifest::${uuid}::common::pdu::${reference}::name",            value1 => $an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{name},
						name2 => "install_manifest::${uuid}::common::pdu::${reference}::ip",              value2 => $an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{ip},
						name3 => "install_manifest::${uuid}::common::pdu::${reference}::user",            value3 => $an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{user},
						name4 => "install_manifest::${uuid}::common::pdu::${reference}::password_script", value4 => $an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{password_script},
						name5 => "install_manifest::${uuid}::common::pdu::${reference}::agent",           value5 => $an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{agent},
					}, file => $THIS_FILE, line => __LINE__});
					$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
						name1 => "install_manifest::${uuid}::common::pdu::${reference}::password", value1 => $an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{password},
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			elsif ($b eq "kvm")
			{
				foreach my $c (@{$a->{$b}->[0]->{kvm}})
				{
					my $reference       = $c->{reference};
					my $name            = $c->{name};
					my $ip              = $c->{ip};
					my $user            = $c->{user};
					my $password        = $c->{password};
					my $password_script = $c->{password_script};
					my $agent           = $c->{agent};
					
					$an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{name}            = $name            ? $name            : "";
					$an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{ip}              = $ip              ? $ip              : "";
					$an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{user}            = $user            ? $user            : "";
					$an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{password}        = $password        ? $password        : "";
					$an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{password_script} = $password_script ? $password_script : "";
					$an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{agent}           = $agent           ? $agent           : "fence_virsh";
					$an->Log->entry({log_level => 4, message_key => "an_variables_0005", message_variables => {
						name1 => "install_manifest::${uuid}::common::kvm::${reference}::name",            value1 => $an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{name},
						name2 => "install_manifest::${uuid}::common::kvm::${reference}::ip",              value2 => $an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{ip},
						name3 => "install_manifest::${uuid}::common::kvm::${reference}::user",            value3 => $an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{user},
						name4 => "install_manifest::${uuid}::common::kvm::${reference}::password_script", value4 => $an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{password_script},
						name5 => "install_manifest::${uuid}::common::kvm::${reference}::agent",           value5 => $an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{agent},
					}, file => $THIS_FILE, line => __LINE__});
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "install_manifest::${uuid}::common::kvm::${reference}::password", value1 => $an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{password},
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			elsif ($b eq "ipmi")
			{
				foreach my $c (@{$a->{$b}->[0]->{ipmi}})
				{
					my $reference       =         $c->{reference};
					my $name            =         $c->{name};
					my $ip              =         $c->{ip};
					my $netmask         =         $c->{netmask};
					my $gateway         =         $c->{gateway};
					my $user            =         $c->{user};
					my $password        =         $c->{password};
					my $password_script =         $c->{password_script};
					my $agent           =         $c->{agent};
					my $lanplus         = defined $c->{lanplus} ? $c->{lanplus} : "";
					my $privlvl         = defined $c->{privlvl} ? $c->{privlvl} : "";
					
					$an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{name}            = $name            ? $name            : "";
					$an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{ip}              = $ip              ? $ip              : "";
					$an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{netmask}         = $netmask         ? $netmask         : "";
					$an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{gateway}         = $gateway         ? $gateway         : "";
					$an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{user}            = $user            ? $user            : "";
					$an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{lanplus}         = $lanplus         ? $lanplus         : "";
					$an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{privlvl}         = $privlvl         ? $privlvl         : "";
					$an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{password}        = $password        ? $password        : "";
					$an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{password_script} = $password_script ? $password_script : "";
					$an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{agent}           = $agent           ? $agent           : "fence_ipmilan";
					$an->Log->entry({log_level => 3, message_key => "an_variables_0010", message_variables => {
						name1  => "install_manifest::${uuid}::common::ipmi::${reference}::name",             value1  => $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{name},
						name2  => "install_manifest::${uuid}::common::ipmi::${reference}::ip",               value2  => $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{ip},
						name3  => "install_manifest::${uuid}::common::ipmi::${reference}::netmask",          value3  => $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{netmask},
						name4  => "install_manifest::${uuid}::common::ipmi::${reference}::gateway",          value4  => $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{gateway},
						name5  => "install_manifest::${uuid}::common::ipmi::${reference}::user",             value5  => $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{user},
						name6  => "install_manifest::${uuid}::common::ipmi::${reference}::lanplus",          value6  => $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{lanplus},
						name7  => "install_manifest::${uuid}::common::ipmi::${reference}::privlvl",          value7  => $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{privlvl},
						name8  => "install_manifest::${uuid}::common::ipmi::${reference}::password_script",  value8  => $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{password_script},
						name9  => "install_manifest::${uuid}::common::ipmi::${reference}::agent",            value9  => $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{agent},
						name10 => "length(install_manifest::${uuid}::common::ipmi::${reference}::password)", value10 => length($an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{password}),
					}, file => $THIS_FILE, line => __LINE__});
					$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
						name1 => "install_manifest::${uuid}::common::ipmi::${reference}::password", value1 => $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{password},
					}, file => $THIS_FILE, line => __LINE__});
					
					# If the password is more than 16 characters long, truncate it so 
					# that nodes with IPMI v1.5 don't spazz out.
					if (length($an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{password}) > 16)
					{
						$an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{password} = substr($an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{password}, 0, 16);
						$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
							name1 => "length(install_manifest::${uuid}::common::ipmi::${reference}::password)", value1 => length($an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{password}),
						}, file => $THIS_FILE, line => __LINE__});
						$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
							name1 => "install_manifest::${uuid}::common::ipmi::${reference}::password", value1 => $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{password},
						}, file => $THIS_FILE, line => __LINE__});
					}
				}
			}
			elsif ($b eq "ssh")
			{
				my $keysize = $a->{$b}->[0]->{keysize};
				$an->data->{install_manifest}{$uuid}{common}{ssh}{keysize} = $keysize ? $keysize : "";
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "install_manifest::${uuid}::common::ssh::keysize", value1 => $an->data->{install_manifest}{$uuid}{common}{ssh}{keysize},
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($b eq "storage_pool_1")
			{
				my $size  = $a->{$b}->[0]->{size};
				my $units = $a->{$b}->[0]->{units};
				$an->data->{install_manifest}{$uuid}{common}{storage_pool}{1}{size}  = $size  ? $size  : "";
				$an->data->{install_manifest}{$uuid}{common}{storage_pool}{1}{units} = $units ? $units : "";
				$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
					name1 => "install_manifest::${uuid}::common::storage_pool::1::size",  value1 => $an->data->{install_manifest}{$uuid}{common}{storage_pool}{1}{size},
					name2 => "install_manifest::${uuid}::common::storage_pool::1::units", value2 => $an->data->{install_manifest}{$uuid}{common}{storage_pool}{1}{units},
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($b eq "striker")
			{
				foreach my $c (@{$a->{$b}->[0]->{striker}})
				{
					my $name     = $c->{name};
					my $bcn_ip   = $c->{bcn_ip};
					my $ifn_ip   = $c->{ifn_ip};
					my $password = $c->{password};
					my $user     = $c->{user};
					my $database = $c->{database};
					
					$an->data->{install_manifest}{$uuid}{common}{striker}{name}{$name}{bcn_ip}   = $bcn_ip   ? $bcn_ip   : "";
					$an->data->{install_manifest}{$uuid}{common}{striker}{name}{$name}{ifn_ip}   = $ifn_ip   ? $ifn_ip   : "";
					$an->data->{install_manifest}{$uuid}{common}{striker}{name}{$name}{password} = $password ? $password : "";
					$an->data->{install_manifest}{$uuid}{common}{striker}{name}{$name}{user}     = $user     ? $user     : "";
					$an->data->{install_manifest}{$uuid}{common}{striker}{name}{$name}{database} = $database ? $database : "";
					$an->Log->entry({log_level => 3, message_key => "an_variables_0004", message_variables => {
						name1 => "install_manifest::${uuid}::common::striker::name::${name}::bcn_ip",   value1 => $an->data->{install_manifest}{$uuid}{common}{striker}{name}{$name}{bcn_ip},
						name2 => "install_manifest::${uuid}::common::striker::name::${name}::ifn_ip",   value2 => $an->data->{install_manifest}{$uuid}{common}{striker}{name}{$name}{ifn_ip},
						name3 => "install_manifest::${uuid}::common::striker::name::${name}::user",     value3 => $an->data->{install_manifest}{$uuid}{common}{striker}{name}{$name}{user},
						name4 => "install_manifest::${uuid}::common::striker::name::${name}::database", value4 => $an->data->{install_manifest}{$uuid}{common}{striker}{name}{$name}{database},
					}, file => $THIS_FILE, line => __LINE__});
					$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
						name1 => "install_manifest::${uuid}::common::striker::name::${name}::password", value1 => $an->data->{install_manifest}{$uuid}{common}{striker}{name}{$name}{password},
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			elsif ($b eq "switch")
			{
				foreach my $c (@{$a->{$b}->[0]->{switch}})
				{
					my $name = $c->{name};
					my $ip   = $c->{ip};
					$an->data->{install_manifest}{$uuid}{common}{switch}{$name}{ip} = $ip ? $ip : "";
					$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
						name1 => "Switch", value1 => $name,
						name2 => "IP",     value2 => $an->data->{install_manifest}{$uuid}{common}{switch}{$name}{ip},
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			elsif ($b eq "update")
			{
				my $os = $a->{$b}->[0]->{os};
				$an->data->{install_manifest}{$uuid}{common}{update}{os} = $os ? $os : "";
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "install_manifest::${uuid}::common::update::os", value1 => $an->data->{install_manifest}{$uuid}{common}{update}{os},
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($b eq "ups")
			{
				foreach my $c (@{$a->{$b}->[0]->{ups}})
				{
					my $name = $c->{name};
					my $ip   = $c->{ip};
					my $type = $c->{type};
					my $port = $c->{port};
					$an->data->{install_manifest}{$uuid}{common}{ups}{$name}{ip}   = $ip   ? $ip   : "";
					$an->data->{install_manifest}{$uuid}{common}{ups}{$name}{type} = $type ? $type : "";
					$an->data->{install_manifest}{$uuid}{common}{ups}{$name}{port} = $port ? $port : "";
					$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
						name1 => "install_manifest::${uuid}::common::ups::${name}::ip",   value1 => $an->data->{install_manifest}{$uuid}{common}{ups}{$name}{ip},
						name2 => "install_manifest::${uuid}::common::ups::${name}::type", value2 => $an->data->{install_manifest}{$uuid}{common}{ups}{$name}{type},
						name3 => "install_manifest::${uuid}::common::ups::${name}::port", value3 => $an->data->{install_manifest}{$uuid}{common}{ups}{$name}{port},
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			elsif ($b eq "pts")
			{
				foreach my $c (@{$a->{$b}->[0]->{pts}})
				{
					my $name = $c->{name};
					my $ip   = $c->{ip};
					my $type = $c->{type};
					my $port = $c->{port};
					$an->data->{install_manifest}{$uuid}{common}{pts}{$name}{ip}   = $ip   ? $ip   : "";
					$an->data->{install_manifest}{$uuid}{common}{pts}{$name}{type} = $type ? $type : "";
					$an->data->{install_manifest}{$uuid}{common}{pts}{$name}{port} = $port ? $port : "";
					$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
						name1 => "install_manifest::${uuid}::common::pts::${name}::ip",   value1 => $an->data->{install_manifest}{$uuid}{common}{pts}{$name}{ip},
						name2 => "install_manifest::${uuid}::common::pts::${name}::type", value2 => $an->data->{install_manifest}{$uuid}{common}{pts}{$name}{type},
						name3 => "install_manifest::${uuid}::common::pts::${name}::port", value3 => $an->data->{install_manifest}{$uuid}{common}{pts}{$name}{port},
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			else
			{
				# Extra element.
				$an->Log->entry({log_level => 3, message_key => "tools_log_0029", message_variables => {
					uuid    => $uuid, 
					element => $b, 
					value   => $a->{$b}, 
				}, file => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	# Load the common variables.
	$an->data->{cgi}{anvil_prefix}       = $an->data->{install_manifest}{$uuid}{common}{anvil}{prefix};
	$an->data->{cgi}{anvil_domain}       = $an->data->{install_manifest}{$uuid}{common}{anvil}{domain};
	$an->data->{cgi}{anvil_sequence}     = $an->data->{install_manifest}{$uuid}{common}{anvil}{sequence};
	$an->data->{cgi}{anvil_password}     = $an->data->{install_manifest}{$uuid}{common}{anvil}{password}         ? $an->data->{install_manifest}{$uuid}{common}{anvil}{password}         : $an->data->{sys}{install_manifest}{'default'}{password};
	$an->data->{cgi}{anvil_repositories} = $an->data->{install_manifest}{$uuid}{common}{anvil}{repositories};
	$an->data->{cgi}{anvil_ssh_keysize}  = $an->data->{install_manifest}{$uuid}{common}{ssh}{keysize}            ? $an->data->{install_manifest}{$uuid}{common}{ssh}{keysize}            : $an->data->{sys}{install_manifest}{'default'}{ssh_keysize};
	$an->data->{cgi}{anvil_mtu_size}     = $an->data->{install_manifest}{$uuid}{common}{network}{mtu}{size}      ? $an->data->{install_manifest}{$uuid}{common}{network}{mtu}{size}      : $an->data->{sys}{install_manifest}{'default'}{mtu_size};
	$an->data->{cgi}{striker_user}       = $an->data->{install_manifest}{$uuid}{common}{anvil}{striker_user}     ? $an->data->{install_manifest}{$uuid}{common}{anvil}{striker_user}     : $an->data->{sys}{install_manifest}{'default'}{striker_user};
	$an->data->{cgi}{striker_database}   = $an->data->{install_manifest}{$uuid}{common}{anvil}{striker_database} ? $an->data->{install_manifest}{$uuid}{common}{anvil}{striker_database} : $an->data->{sys}{install_manifest}{'default'}{striker_database};
	$an->Log->entry({log_level => 4, message_key => "an_variables_0006", message_variables => {
		name1 => "cgi::anvil_prefix",       value1 => $an->data->{cgi}{anvil_prefix},
		name2 => "cgi::anvil_domain",       value2 => $an->data->{cgi}{anvil_domain},
		name3 => "cgi::anvil_sequence",     value3 => $an->data->{cgi}{anvil_sequence},
		name4 => "cgi::anvil_repositories", value4 => $an->data->{cgi}{anvil_repositories},
		name5 => "cgi::anvil_ssh_keysize",  value5 => $an->data->{cgi}{anvil_ssh_keysize},
		name6 => "cgi::striker_database",   value6 => $an->data->{cgi}{striker_database},
	}, file => $THIS_FILE, line => __LINE__});
	$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
		name1 => "cgi::anvil_password", value1 => $an->data->{cgi}{anvil_password},
	}, file => $THIS_FILE, line => __LINE__});
	
	# Media Library values
	$an->data->{cgi}{anvil_media_library_size} = $an->data->{install_manifest}{$uuid}{common}{media_library}{size};
	$an->data->{cgi}{anvil_media_library_unit} = $an->data->{install_manifest}{$uuid}{common}{media_library}{units};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "cgi::anvil_media_library_size", value1 => $an->data->{cgi}{anvil_media_library_size},
		name2 => "cgi::anvil_media_library_unit", value2 => $an->data->{cgi}{anvil_media_library_unit},
	}, file => $THIS_FILE, line => __LINE__});
	
	# Networks
	$an->data->{cgi}{anvil_bcn_ethtool_opts} = $an->data->{install_manifest}{$uuid}{common}{network}{name}{bcn}{ethtool_opts};
	$an->data->{cgi}{anvil_bcn_network}      = $an->data->{install_manifest}{$uuid}{common}{network}{name}{bcn}{netblock};
	$an->data->{cgi}{anvil_bcn_subnet}       = $an->data->{install_manifest}{$uuid}{common}{network}{name}{bcn}{netmask};
	$an->data->{cgi}{anvil_sn_ethtool_opts}  = $an->data->{install_manifest}{$uuid}{common}{network}{name}{sn}{ethtool_opts};
	$an->data->{cgi}{anvil_sn_network}       = $an->data->{install_manifest}{$uuid}{common}{network}{name}{sn}{netblock};
	$an->data->{cgi}{anvil_sn_subnet}        = $an->data->{install_manifest}{$uuid}{common}{network}{name}{sn}{netmask};
	$an->data->{cgi}{anvil_ifn_ethtool_opts} = $an->data->{install_manifest}{$uuid}{common}{network}{name}{ifn}{ethtool_opts};
	$an->data->{cgi}{anvil_ifn_network}      = $an->data->{install_manifest}{$uuid}{common}{network}{name}{ifn}{netblock};
	$an->data->{cgi}{anvil_ifn_subnet}       = $an->data->{install_manifest}{$uuid}{common}{network}{name}{ifn}{netmask};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0009", message_variables => {
		name1 => "cgi::anvil_bcn_ethtool_opts", value1 => $an->data->{cgi}{anvil_bcn_ethtool_opts},
		name2 => "cgi::anvil_bcn_network",      value2 => $an->data->{cgi}{anvil_bcn_network},
		name3 => "cgi::anvil_bcn_subnet",       value3 => $an->data->{cgi}{anvil_bcn_subnet},
		name4 => "cgi::anvil_sn_ethtool_opts",  value4 => $an->data->{cgi}{anvil_sn_ethtool_opts},
		name5 => "cgi::anvil_sn_network",       value5 => $an->data->{cgi}{anvil_sn_network},
		name6 => "cgi::anvil_sn_subnet",        value6 => $an->data->{cgi}{anvil_sn_subnet},
		name7 => "cgi::anvil_ifn_ethtool_opts", value7 => $an->data->{cgi}{anvil_ifn_ethtool_opts},
		name8 => "cgi::anvil_ifn_network",      value8 => $an->data->{cgi}{anvil_ifn_network},
		name9 => "cgi::anvil_ifn_subnet",       value9 => $an->data->{cgi}{anvil_ifn_subnet},
	}, file => $THIS_FILE, line => __LINE__});
	
	# iptables
	$an->data->{cgi}{anvil_open_vnc_ports} = $an->data->{install_manifest}{$uuid}{common}{cluster}{iptables}{vnc_ports};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "cgi::anvil_open_vnc_ports", value1 => $an->data->{cgi}{anvil_open_vnc_ports},
	}, file => $THIS_FILE, line => __LINE__});
	
	# Storage Pool 1
	$an->data->{cgi}{anvil_storage_pool1_size} = $an->data->{install_manifest}{$uuid}{common}{storage_pool}{1}{size};
	$an->data->{cgi}{anvil_storage_pool1_unit} = $an->data->{install_manifest}{$uuid}{common}{storage_pool}{1}{units};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "cgi::anvil_storage_pool1_size", value1 => $an->data->{cgi}{anvil_storage_pool1_size},
		name2 => "cgi::anvil_storage_pool1_unit", value2 => $an->data->{cgi}{anvil_storage_pool1_unit},
	}, file => $THIS_FILE, line => __LINE__});
	
	# Tools
	$an->data->{sys}{install_manifest}{'use_anvil-safe-start'}   = defined $an->data->{install_manifest}{$uuid}{common}{cluster}{tools}{'use'}{'anvil-safe-start'}   ? $an->data->{install_manifest}{$uuid}{common}{cluster}{tools}{'use'}{'anvil-safe-start'}   : $an->data->{sys}{install_manifest}{'default'}{'use_anvil-safe-start'};
	$an->data->{sys}{install_manifest}{'use_anvil-kick-apc-ups'} = defined $an->data->{install_manifest}{$uuid}{common}{cluster}{tools}{'use'}{'anvil-kick-apc-ups'} ? $an->data->{install_manifest}{$uuid}{common}{cluster}{tools}{'use'}{'anvil-kick-apc-ups'} : $an->data->{sys}{install_manifest}{'default'}{'use_anvil-kick-apc-ups'};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "sys::install_manifest::use_anvil-safe-start",   value1 => $an->data->{sys}{install_manifest}{'use_anvil-safe-start'},
		name2 => "sys::install_manifest::use_anvil-kick-apc-ups", value2 => $an->data->{sys}{install_manifest}{'use_anvil-kick-apc-ups'},
	}, file => $THIS_FILE, line => __LINE__});
	
	# Shared Variables
	$an->data->{cgi}{anvil_name}        = $an->data->{install_manifest}{$uuid}{common}{cluster}{name};
	$an->data->{cgi}{anvil_ifn_gateway} = $an->data->{install_manifest}{$uuid}{common}{network}{name}{ifn}{gateway};
	$an->data->{cgi}{anvil_dns1}        = $an->data->{install_manifest}{$uuid}{common}{network}{name}{ifn}{dns1};
	$an->data->{cgi}{anvil_dns2}        = $an->data->{install_manifest}{$uuid}{common}{network}{name}{ifn}{dns2};
	$an->data->{cgi}{anvil_ntp1}        = $an->data->{install_manifest}{$uuid}{common}{network}{name}{ifn}{ntp1};
	$an->data->{cgi}{anvil_ntp2}        = $an->data->{install_manifest}{$uuid}{common}{network}{name}{ifn}{ntp2};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0006", message_variables => {
		name1 => "cgi::anvil_name",        value1 => $an->data->{cgi}{anvil_name},
		name2 => "cgi::anvil_ifn_gateway", value2 => $an->data->{cgi}{anvil_ifn_gateway},
		name3 => "cgi::anvil_dns1",        value3 => $an->data->{cgi}{anvil_dns1},
		name4 => "cgi::anvil_dns2",        value4 => $an->data->{cgi}{anvil_dns2},
		name5 => "cgi::anvil_ntp1",        value5 => $an->data->{cgi}{anvil_ntp1},
		name6 => "cgi::anvil_ntp2",        value6 => $an->data->{cgi}{anvil_ntp2},
	}, file => $THIS_FILE, line => __LINE__});
	
	# DRBD variables
	$an->data->{cgi}{'anvil_drbd_disk_disk-barrier'}  = defined $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'disk-barrier'}  ? $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'disk-barrier'}  : $an->data->{sys}{install_manifest}{'default'}{'anvil_drbd_disk_disk-barrier'};
	$an->data->{cgi}{'anvil_drbd_disk_disk-flushes'}  = defined $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'disk-flushes'}  ? $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'disk-flushes'}  : $an->data->{sys}{install_manifest}{'default'}{'anvil_drbd_disk_disk-flushes'};
	$an->data->{cgi}{'anvil_drbd_disk_md-flushes'}    = defined $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'md-flushes'}    ? $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'md-flushes'}    : $an->data->{sys}{install_manifest}{'default'}{'anvil_drbd_disk_md-flushes'};
	$an->data->{cgi}{'anvil_drbd_disk_c-plan-ahead'}  = defined $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-plan-ahead'}  ? $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-plan-ahead'}  : $an->data->{sys}{install_manifest}{'default'}{'anvil_drbd_disk_c-plan-ahead'};
	$an->data->{cgi}{'anvil_drbd_disk_c-max-rate'}    = defined $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-max-rate'}    ? $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-max-rate'}    : $an->data->{sys}{install_manifest}{'default'}{'anvil_drbd_disk_c-max-rate'};
	$an->data->{cgi}{'anvil_drbd_disk_c-min-rate'}    = defined $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-min-rate'}    ? $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-min-rate'}    : $an->data->{sys}{install_manifest}{'default'}{'anvil_drbd_disk_c-min-rate'};
	$an->data->{cgi}{'anvil_drbd_disk_c-fill-target'} = defined $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-fill-target'} ? $an->data->{install_manifest}{$uuid}{common}{drbd}{disk}{'c-fill-target'} : $an->data->{sys}{install_manifest}{'default'}{'anvil_drbd_disk_c-fill-target'};
	$an->data->{cgi}{'anvil_drbd_options_cpu-mask'}   = defined $an->data->{install_manifest}{$uuid}{common}{drbd}{options}{'cpu-mask'}   ? $an->data->{install_manifest}{$uuid}{common}{drbd}{options}{'cpu-mask'}   : $an->data->{sys}{install_manifest}{'default'}{'anvil_drbd_options_cpu-mask'};
	$an->data->{cgi}{'anvil_drbd_net_max-buffers'}    = defined $an->data->{install_manifest}{$uuid}{common}{drbd}{net}{'max-buffers'}    ? $an->data->{install_manifest}{$uuid}{common}{drbd}{net}{'max-buffers'}    : $an->data->{sys}{install_manifest}{'default'}{'anvil_drbd_net_max-buffers'};
	$an->data->{cgi}{'anvil_drbd_net_sndbuf-size'}    = defined $an->data->{install_manifest}{$uuid}{common}{drbd}{net}{'sndbuf-size'}    ? $an->data->{install_manifest}{$uuid}{common}{drbd}{net}{'sndbuf-size'}    : $an->data->{sys}{install_manifest}{'default'}{'anvil_drbd_net_sndbuf-size'};
	$an->data->{cgi}{'anvil_drbd_net_rcvbuf-size'}    = defined $an->data->{install_manifest}{$uuid}{common}{drbd}{net}{'rcvbuf-size'}    ? $an->data->{install_manifest}{$uuid}{common}{drbd}{net}{'rcvbuf-size'}    : $an->data->{sys}{install_manifest}{'default'}{'anvil_drbd_net_rcvbuf-size'};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0011", message_variables => {
		name1  => "cgi::anvil_drbd_disk_disk-barrier",  value1  => $an->data->{cgi}{'anvil_drbd_disk_disk-barrier'},
		name2  => "cgi::anvil_drbd_disk_disk-flushes",  value2  => $an->data->{cgi}{'anvil_drbd_disk_disk-flushes'},
		name3  => "cgi::anvil_drbd_disk_md-flushes",    value3  => $an->data->{cgi}{'anvil_drbd_disk_md-flushes'},
		name4  => "cgi::anvil_drbd_disk_c-plan-ahead",  value4  => $an->data->{cgi}{'anvil_drbd_disk_c-plan-ahead'},
		name5  => "cgi::anvil_drbd_disk_c-max-rate",    value5  => $an->data->{cgi}{'anvil_drbd_disk_c-max-rate'},
		name6  => "cgi::anvil_drbd_disk_c-min-rate",    value6  => $an->data->{cgi}{'anvil_drbd_disk_c-min-rate'},
		name7  => "cgi::anvil_drbd_disk_c-fill-target", value7  => $an->data->{cgi}{'anvil_drbd_disk_c-fill-target'},
		name8  => "cgi::anvil_drbd_options_cpu-mask",   value8  => $an->data->{cgi}{'anvil_drbd_options_cpu-mask'},
		name9  => "cgi::anvil_drbd_net_max-buffers",    value9  => $an->data->{cgi}{'anvil_drbd_net_max-buffers'},
		name10 => "cgi::anvil_drbd_net_sndbuf-size",    value10 => $an->data->{cgi}{'anvil_drbd_net_sndbuf-size'},
		name11 => "cgi::anvil_drbd_net_rcvbuf-size",    value11 => $an->data->{cgi}{'anvil_drbd_net_rcvbuf-size'},
	}, file => $THIS_FILE, line => __LINE__});
	
	### Foundation Pack
	# Switches
	my $i = 1;
	foreach my $switch (sort {$a cmp $b} keys %{$an->data->{install_manifest}{$uuid}{common}{switch}})
	{
		my $name_key = "anvil_switch".$i."_name";
		my $ip_key   = "anvil_switch".$i."_ip";
		$an->data->{cgi}{$name_key} = $switch;
		$an->data->{cgi}{$ip_key}   = $an->data->{install_manifest}{$uuid}{common}{switch}{$switch}{ip};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
			name1 => "switch",           value1 => $switch,
			name2 => "cgi::${name_key}", value2 => $an->data->{cgi}{$name_key},
			name3 => "cgi::${ip_key}",   value3 => $an->data->{cgi}{$ip_key},
		}, file => $THIS_FILE, line => __LINE__});
		$i++;
	}
	# PDUs
	$i = 1;
	foreach my $reference (sort {$a cmp $b} keys %{$an->data->{install_manifest}{$uuid}{common}{pdu}})
	{
		my $name_key = "anvil_pdu".$i."_name";
		my $ip_key   = "anvil_pdu".$i."_ip";
		my $name     = $an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{name};
		my $ip       = $an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{ip};
		$an->data->{cgi}{$name_key} = $name ? $name : "";
		$an->data->{cgi}{$ip_key}   = $ip   ? $ip   : "";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
			name1 => "reference",        value1 => $reference,
			name2 => "cgi::${name_key}", value2 => $an->data->{cgi}{$name_key},
			name3 => "cgi::${ip_key}",   value3 => $an->data->{cgi}{$ip_key},
		}, file => $THIS_FILE, line => __LINE__});
		$i++;
	}
	# UPSes
	$i = 1;
	foreach my $ups (sort {$a cmp $b} keys %{$an->data->{install_manifest}{$uuid}{common}{ups}})
	{
		my $name_key = "anvil_ups".$i."_name";
		my $ip_key   = "anvil_ups".$i."_ip";
		$an->data->{cgi}{$name_key} = $ups;
		$an->data->{cgi}{$ip_key}   = $an->data->{install_manifest}{$uuid}{common}{ups}{$ups}{ip};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
			name1 => "ups",              value1 => $ups,
			name2 => "cgi::${name_key}", value2 => $an->data->{cgi}{$name_key},
			name3 => "cgi::${ip_key}",   value3 => $an->data->{cgi}{$ip_key},
		}, file => $THIS_FILE, line => __LINE__});
		$i++;
	}
	# Striker Dashboards
	$i = 1;
	foreach my $striker (sort {$a cmp $b} keys %{$an->data->{install_manifest}{$uuid}{common}{striker}{name}})
	{
		my $name_key     =  "anvil_striker".$i."_name";
		my $bcn_ip_key   =  "anvil_striker".$i."_bcn_ip";
		my $ifn_ip_key   =  "anvil_striker".$i."_ifn_ip";
		my $user_key     =  "anvil_striker".$i."_user";
		my $password_key =  "anvil_striker".$i."_password";
		my $database_key =  "anvil_striker".$i."_database";
		$an->data->{cgi}{$name_key}     = $striker;
		$an->data->{cgi}{$bcn_ip_key}   = $an->data->{install_manifest}{$uuid}{common}{striker}{name}{$striker}{bcn_ip};
		$an->data->{cgi}{$ifn_ip_key}   = $an->data->{install_manifest}{$uuid}{common}{striker}{name}{$striker}{ifn_ip};
		$an->data->{cgi}{$user_key}     = $an->data->{install_manifest}{$uuid}{common}{striker}{name}{$striker}{user}     ? $an->data->{install_manifest}{$uuid}{common}{striker}{name}{$striker}{user}     : $an->data->{cgi}{striker_user};
		$an->data->{cgi}{$password_key} = $an->data->{install_manifest}{$uuid}{common}{striker}{name}{$striker}{password} ? $an->data->{install_manifest}{$uuid}{common}{striker}{name}{$striker}{password} : $an->data->{cgi}{anvil_password};
		$an->data->{cgi}{$database_key} = $an->data->{install_manifest}{$uuid}{common}{striker}{name}{$striker}{database} ? $an->data->{install_manifest}{$uuid}{common}{striker}{name}{$striker}{database} : $an->data->{cgi}{striker_database};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0005", message_variables => {
			name1 => "cgi::$name_key",     value1 => $an->data->{cgi}{$name_key},
			name2 => "cgi::$bcn_ip_key",   value2 => $an->data->{cgi}{$bcn_ip_key},
			name3 => "cgi::$ifn_ip_key",   value3 => $an->data->{cgi}{$ifn_ip_key},
			name4 => "cgi::$user_key",     value4 => $an->data->{cgi}{$user_key},
			name5 => "cgi::$database_key", value5 => $an->data->{cgi}{$database_key},
		}, file => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
			name1 => "cgi::$password_key", value1 => $an->data->{cgi}{$password_key},
		}, file => $THIS_FILE, line => __LINE__});
		$i++;
	}
	
	### Now the Nodes.
	$i = 1;
	foreach my $node (sort {$a cmp $b} keys %{$an->data->{install_manifest}{$uuid}{node}})
	{
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "i",    value1 => $i,
			name2 => "node", value2 => $node,
		}, file => $THIS_FILE, line => __LINE__});
		my $name_key          = "anvil_node".$i."_name";
		my $bcn_ip_key        = "anvil_node".$i."_bcn_ip";
		my $bcn_link1_mac_key = "anvil_node".$i."_bcn_link1_mac";
		my $bcn_link2_mac_key = "anvil_node".$i."_bcn_link2_mac";
		my $sn_ip_key         = "anvil_node".$i."_sn_ip";
		my $sn_link1_mac_key  = "anvil_node".$i."_sn_link1_mac";
		my $sn_link2_mac_key  = "anvil_node".$i."_sn_link2_mac";
		my $ifn_ip_key        = "anvil_node".$i."_ifn_ip";
		my $ifn_link1_mac_key = "anvil_node".$i."_ifn_link1_mac";
		my $ifn_link2_mac_key = "anvil_node".$i."_ifn_link2_mac";
		my $uuid_key          = "anvil_node".$i."_uuid";
		my $ipmi_ip_key       = "anvil_node".$i."_ipmi_ip";
		my $ipmi_netmask_key  = "anvil_node".$i."_ipmi_netmask",
		my $ipmi_gateway_key  = "anvil_node".$i."_ipmi_gateway",
		my $ipmi_password_key = "anvil_node".$i."_ipmi_password",
		my $ipmi_user_key     = "anvil_node".$i."_ipmi_user",
		my $ipmi_lanplus_key  = "anvil_node".$i."_ipmi_lanplus",
		my $ipmi_privlvl_key  = "anvil_node".$i."_ipmi_privlvl",
		my $pdu1_key          = "anvil_node".$i."_pdu1_outlet";
		my $pdu2_key          = "anvil_node".$i."_pdu2_outlet";
		my $pdu3_key          = "anvil_node".$i."_pdu3_outlet";
		my $pdu4_key          = "anvil_node".$i."_pdu4_outlet";
		my $default_ipmi_pw   =  $an->data->{cgi}{anvil_password};
		
		# Find the IPMI, PDU and KVM reference names
		my $ipmi_reference = "";
		my $pdu1_reference = "";
		my $pdu2_reference = "";
		my $pdu3_reference = "";
		my $pdu4_reference = "";
		my $kvm_reference  = "";
		foreach my $reference (sort {$a cmp $b} keys %{$an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}})
		{
			# There should only be one entry
			$ipmi_reference = $reference;
		}
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "ipmi_reference", value1 => $ipmi_reference,
		}, file => $THIS_FILE, line => __LINE__});
		
		my $j = 1;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "j",                                             value1 => $j,
			name2 => "install_manifest::${uuid}::node::${node}::pdu", value2 => $an->data->{install_manifest}{$uuid}{node}{$node}{pdu},
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $reference (sort {$a cmp $b} keys %{$an->data->{install_manifest}{$uuid}{node}{$node}{pdu}})
		{
			# There should be two or four PDUs
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "j",         value1 => $j,
				name2 => "reference", value2 => $reference,
			}, file => $THIS_FILE, line => __LINE__});
			if ($j == 1)
			{
				$pdu1_reference = $reference;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "pdu1_reference", value1 => $pdu1_reference,
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($j == 2)
			{
				$pdu2_reference = $reference;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "pdu2_reference", value1 => $pdu2_reference,
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($j == 3)
			{
				$pdu3_reference = $reference;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "pdu3_reference", value1 => $pdu3_reference,
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($j == 4)
			{
				$pdu4_reference = $reference;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "pdu4_reference", value1 => $pdu4_reference,
				}, file => $THIS_FILE, line => __LINE__});
			}
			$j++;
		}
		$an->Log->entry({log_level => 3, message_key => "an_variables_0004", message_variables => {
			name1 => "pdu1_reference", value1 => $pdu1_reference,
			name2 => "pdu2_reference", value2 => $pdu2_reference,
			name3 => "pdu3_reference", value3 => $pdu3_reference,
			name4 => "pdu4_reference", value4 => $pdu4_reference,
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $reference (sort {$a cmp $b} keys %{$an->data->{install_manifest}{$uuid}{node}{$node}{kvm}})
		{
			# There should only be one entry
			$kvm_reference = $reference;
		}
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "kvm_reference", value1 => $kvm_reference,
		}, file => $THIS_FILE, line => __LINE__});
		
		$an->data->{cgi}{$name_key}          = $node;
		$an->data->{cgi}{$bcn_ip_key}        = $an->data->{install_manifest}{$uuid}{node}{$node}{network}{bcn}{ip};
		$an->data->{cgi}{$sn_ip_key}         = $an->data->{install_manifest}{$uuid}{node}{$node}{network}{sn}{ip};
		$an->data->{cgi}{$ifn_ip_key}        = $an->data->{install_manifest}{$uuid}{node}{$node}{network}{ifn}{ip};
		
		$an->data->{cgi}{$ipmi_ip_key}       = $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{ip};
		$an->data->{cgi}{$ipmi_netmask_key}  = $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{netmask}  ? $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{netmask}  : $an->data->{cgi}{anvil_bcn_subnet};
		$an->data->{cgi}{$ipmi_gateway_key}  = $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{gateway}  ? $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{gateway}  : "";
		$an->data->{cgi}{$ipmi_password_key} = $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{password} ? $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{password} : $default_ipmi_pw;
		$an->data->{cgi}{$ipmi_user_key}     = $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{user}     ? $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{user}     : "admin";
		$an->data->{cgi}{$ipmi_lanplus_key}  = $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{lanplus}  ? $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{lanplus}  : "";
		$an->data->{cgi}{$ipmi_privlvl_key}  = $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{privlvl}  ? $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{privlvl}  : "USER";
		$an->data->{cgi}{$pdu1_key}          = $an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$pdu1_reference}{port};
		$an->data->{cgi}{$pdu2_key}          = $an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$pdu2_reference}{port};
		$an->data->{cgi}{$pdu3_key}          = $an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$pdu3_reference}{port};
		$an->data->{cgi}{$pdu4_key}          = $an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$pdu4_reference}{port};
		$an->data->{cgi}{$uuid_key}          = $an->data->{install_manifest}{$uuid}{node}{$node}{uuid}                            ? $an->data->{install_manifest}{$uuid}{node}{$node}{uuid}                            : "";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0015", message_variables => {
			name1  => "cgi::$name_key",          value1  => $an->data->{cgi}{$name_key},
			name2  => "cgi::$bcn_ip_key",        value2  => $an->data->{cgi}{$bcn_ip_key},
			name3  => "cgi::$ipmi_ip_key",       value3  => $an->data->{cgi}{$ipmi_ip_key},
			name4  => "cgi::$ipmi_netmask_key",  value4  => $an->data->{cgi}{$ipmi_netmask_key},
			name5  => "cgi::$ipmi_gateway_key",  value5  => $an->data->{cgi}{$ipmi_gateway_key},
			name6  => "cgi::$ipmi_user_key",     value6  => $an->data->{cgi}{$ipmi_user_key},
			name7  => "cgi::$ipmi_lanplus_key",  value7  => $an->data->{cgi}{$ipmi_lanplus_key},
			name8  => "cgi::$ipmi_privlvl_key",  value8  => $an->data->{cgi}{$ipmi_privlvl_key},
			name9  => "cgi::$sn_ip_key",         value9  => $an->data->{cgi}{$sn_ip_key},
			name10 => "cgi::$ifn_ip_key",        value10 => $an->data->{cgi}{$ifn_ip_key},
			name11 => "cgi::$pdu1_key",          value11 => $an->data->{cgi}{$pdu1_key},
			name12 => "cgi::$pdu2_key",          value12 => $an->data->{cgi}{$pdu2_key},
			name13 => "cgi::$pdu3_key",          value13 => $an->data->{cgi}{$pdu3_key},
			name14 => "cgi::$pdu4_key",          value14 => $an->data->{cgi}{$pdu4_key},
			name15 => "cgi::$uuid_key",          value15 => $an->data->{cgi}{$uuid_key},
		}, file => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
			name1 => "cgi::$ipmi_password_key", value1 => $an->data->{cgi}{$ipmi_password_key},
		}, file => $THIS_FILE, line => __LINE__});
		
		# IPMI is, by default, tempremental about passwords. If the manifest doesn't specify the 
		# password to use, we'll copy the cluster password but then strip out special characters and 
		# shorten it to 16 characters or less.
		$an->data->{cgi}{$ipmi_password_key} =~ s/ //g;
		$an->data->{cgi}{$ipmi_password_key} =~ s/!//g;
		if (length($an->data->{cgi}{$ipmi_password_key}) > 16)
		{
			$an->data->{cgi}{$ipmi_password_key} = substr($an->data->{cgi}{$ipmi_password_key}, 0, 16);
		}
		
		# Make sure the password matches later when we generate the cluster.conf file.
		$an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{password} = $an->data->{cgi}{$ipmi_password_key};
		$an->Log->entry({log_level => 4, message_key => "an_variables_0002", message_variables => {
			name1 => "cgi::$ipmi_password_key",                                                     value1 => $an->data->{cgi}{$ipmi_password_key},
			name2 => "install_manifest::${uuid}::node::${node}::ipmi::${ipmi_reference}::password", value2 => $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$ipmi_reference}{password},
		}, file => $THIS_FILE, line => __LINE__});
		
		# If the user remapped their network, we don't want to undo the results.
		if (not $an->data->{cgi}{perform_install})
		{
			$an->data->{cgi}{$bcn_link1_mac_key} = $an->data->{install_manifest}{$uuid}{node}{$node}{interface}{bcn_link1}{mac};
			$an->data->{cgi}{$bcn_link2_mac_key} = $an->data->{install_manifest}{$uuid}{node}{$node}{interface}{bcn_link2}{mac};
			$an->data->{cgi}{$sn_link1_mac_key}  = $an->data->{install_manifest}{$uuid}{node}{$node}{interface}{sn_link1}{mac};
			$an->data->{cgi}{$sn_link2_mac_key}  = $an->data->{install_manifest}{$uuid}{node}{$node}{interface}{sn_link2}{mac};
			$an->data->{cgi}{$ifn_link1_mac_key} = $an->data->{install_manifest}{$uuid}{node}{$node}{interface}{ifn_link1}{mac};
			$an->data->{cgi}{$ifn_link2_mac_key} = $an->data->{install_manifest}{$uuid}{node}{$node}{interface}{ifn_link2}{mac};
			$an->Log->entry({log_level => 3, message_key => "an_variables_0006", message_variables => {
				name1 => "cgi::$bcn_link1_mac_key", value1 => $an->data->{cgi}{$bcn_link1_mac_key},
				name2 => "cgi::$bcn_link2_mac_key", value2 => $an->data->{cgi}{$bcn_link2_mac_key},
				name3 => "cgi::$sn_link1_mac_key",  value3 => $an->data->{cgi}{$sn_link1_mac_key},
				name4 => "cgi::$sn_link2_mac_key",  value4 => $an->data->{cgi}{$sn_link2_mac_key},
				name5 => "cgi::$ifn_link1_mac_key", value5 => $an->data->{cgi}{$ifn_link1_mac_key},
				name6 => "cgi::$ifn_link2_mac_key", value6 => $an->data->{cgi}{$ifn_link2_mac_key},
			}, file => $THIS_FILE, line => __LINE__});
		}
		$i++;
	}
	
	### Now to build the fence strings.
	my $fence_order                        = $an->data->{install_manifest}{$uuid}{common}{cluster}{fence}{order};
	   $an->data->{cgi}{anvil_fence_order} = $fence_order;
	
	# Nodes
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "cgi::anvil_node1_name", value1 => $an->data->{cgi}{anvil_node1_name},
		name2 => "cgi::anvil_node2_name", value2 => $an->data->{cgi}{anvil_node2_name},
	}, file => $THIS_FILE, line => __LINE__});
	my $node1_name = $an->data->{cgi}{anvil_node1_name};
	my $node2_name = $an->data->{cgi}{anvil_node2_name};
	my $delay_set  = 0;
	my $delay_node = $an->data->{install_manifest}{$uuid}{common}{cluster}{fence}{delay_node};
	my $delay_time = $an->data->{install_manifest}{$uuid}{common}{cluster}{fence}{delay};
	foreach my $node ($an->data->{cgi}{anvil_node1_name}, $an->data->{cgi}{anvil_node2_name})
	{
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "node", value1 => $node,
		}, file => $THIS_FILE, line => __LINE__});
		my $i = 1;
		foreach my $method (split/,/, $fence_order)
		{
			if ($method eq "kvm")
			{
				# Only ever one, but...
				my $j = 1;
				foreach my $reference (sort {$a cmp $b} keys %{$an->data->{install_manifest}{$uuid}{node}{$node}{kvm}})
				{
					my $port            = $an->data->{install_manifest}{$uuid}{node}{$node}{kvm}{$reference}{port};
					my $user            = $an->data->{install_manifest}{$uuid}{node}{$node}{kvm}{$reference}{user};
					my $password        = $an->data->{install_manifest}{$uuid}{node}{$node}{kvm}{$reference}{password};
					my $password_script = $an->data->{install_manifest}{$uuid}{node}{$node}{kvm}{$reference}{password_script};
					
					# Build the string.
					my $string =  "<device name=\"$reference\"";
						$string .= " port=\"$port\""  if $port;
						$string .= " login=\"$user\"" if $user;
					# One or the other, not both.
					if ($password)
					{
						$string .= " passwd=\"$password\"";
					}
					elsif ($password_script)
					{
						$string .= " passwd_script=\"$password_script\"";
					}
					if (($node eq $delay_node) && (not $delay_set))
					{
						$string    .= " delay=\"$delay_time\"";
						$delay_set =  1;
					}
					$string .= " action=\"reboot\" />";
					$string =~ s/\s+/ /g;
					$an->data->{fence}{node}{$node}{order}{$i}{method}{$method}{device}{$j}{string} = $string;
					$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
						name1 => "fence::node::${node}::order::${i}::method::${method}::device::${j}::string", value1 => $an->data->{fence}{node}{$node}{order}{$i}{method}{$method}{device}{$j}{string},
					}, file => $THIS_FILE, line => __LINE__});
					$j++;
				}
			}
			elsif ($method eq "ipmi")
			{
				# Only ever one, but...
				my $j = 1;
				foreach my $reference (sort {$a cmp $b} keys %{$an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}})
				{
					my $name            = $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{name};
					my $ip              = $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{ip};
					my $user            = $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{user};
					my $lanplus         = $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{lanplus};
					my $privlvl         = $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{privlvl};
					my $password        = $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{password};
					my $password_script = $an->data->{install_manifest}{$uuid}{node}{$node}{ipmi}{$reference}{password_script};
					$an->Log->entry({log_level => 3, message_key => "an_variables_0006", message_variables => {
						name1 => "name",            value1 => $name,
						name2 => "ip",              value2 => $ip,
						name3 => "user",            value3 => $user,
						name4 => "lanplus",         value4 => $lanplus,
						name5 => "privlvl",         value5 => $privlvl,
						name6 => "password_script", value6 => $password_script,
					}, file => $THIS_FILE, line => __LINE__});
					$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
						name1 => "password", value1 => $password,
					}, file => $THIS_FILE, line => __LINE__});
					if ((not $name) && ($ip))
					{
						$name = $ip;
					}
					# Build the string
					my $string =  "<device name=\"$reference\"";
					   $string .= " ipaddr=\"$name\"" if $name;
					   $string .= " login=\"$user\""  if $user;
					if (($lanplus eq "true") or ($lanplus eq "1"))
					{
						# Add lanplus and privlvl
						$string .= " lanplus=\"1\" privlvl=\"$privlvl\"";
					}
					# One or the other, not both.
					if ($password)
					{
						$string .= " passwd=\"$password\"";
					}
					elsif ($password_script)
					{
						$string .= " passwd_script=\"$password_script\"";
					}
					if (($node eq $delay_node) && (not $delay_set))
					{
						$string    .= " delay=\"$delay_time\"";
						$delay_set =  1;
					}
					$string .= " action=\"reboot\" />";
					$string =~ s/\s+/ /g;
					$an->data->{fence}{node}{$node}{order}{$i}{method}{$method}{device}{$j}{string} = $string;
					
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "fence::node::${node}::order::${i}::method::${method}::device::${j}::string", value1 => $an->data->{fence}{node}{$node}{order}{$i}{method}{$method}{device}{$j}{string},
					}, file => $THIS_FILE, line => __LINE__});
					$j++;
				}
			}
			elsif ($method eq "pdu")
			{
				# Here we can have > 1.
				my $j = 1;
				foreach my $reference (sort {$a cmp $b} keys %{$an->data->{install_manifest}{$uuid}{node}{$node}{pdu}})
				{
					my $port            = $an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$reference}{port};
					my $user            = $an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$reference}{user};
					my $password        = $an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$reference}{password};
					my $password_script = $an->data->{install_manifest}{$uuid}{node}{$node}{pdu}{$reference}{password_script};
					
					# If there is no port, skip.
					next if not $port;
					
					# Build the string
					my $string = "<device name=\"$reference\" ";
						$string .= " port=\"$port\""  if $port;
						$string .= " login=\"$user\"" if $user;
					# One or the other, not both.
					if ($password)
					{
						$string .= " passwd=\"$password\"";
					}
					elsif ($password_script)
					{
						$string .= " passwd_script=\"$password_script\"";
					}
					if (($node eq $delay_node) && (not $delay_set))
					{
						$string    .= " delay=\"$delay_time\"";
						$delay_set =  1;
					}
					$string .= " action=\"reboot\" />";
					$string =~ s/\s+/ /g;
					$an->data->{fence}{node}{$node}{order}{$i}{method}{$method}{device}{$j}{string} = $string;
					$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
						name1 => "fence::node::${node}::order::${i}::method::${method}::device::${j}::string", value1 => $an->data->{fence}{node}{$node}{order}{$i}{method}{$method}{device}{$j}{string},
					}, file => $THIS_FILE, line => __LINE__});
					$j++;
				}
			}
			$i++;
		}
	}
	
	# Devices
	foreach my $device (split/,/, $fence_order)
	{
		if ($device eq "kvm")
		{
			foreach my $reference (sort {$a cmp $b} keys %{$an->data->{install_manifest}{$uuid}{common}{kvm}})
			{
				my $name            = $an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{name};
				my $ip              = $an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{ip};
				my $user            = $an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{user};
				my $password        = $an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{password};
				my $password_script = $an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{password_script};
				my $agent           = $an->data->{install_manifest}{$uuid}{common}{kvm}{$reference}{agent};
				if ((not $name) && ($ip))
				{
					$name = $ip;
				}
				
				# Build the string
				my $string =  "<fencedevice name=\"$reference\" agent=\"$agent\"";
					$string .= " ipaddr=\"$name\"" if $name;
					$string .= " login=\"$user\""  if $user;
				# One or the other, not both.
				if ($password)
				{
					$string .= " passwd=\"$password\"";
				}
				elsif ($password_script)
				{
					$string .= " passwd_script=\"$password_script\"";
				}
				$string .= " />";
				$string =~ s/\s+/ /g;
				$an->data->{fence}{device}{$device}{name}{$reference}{string} = $string;
				$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
					name1 => "fence::device::${device}::name::${reference}::string", value1 => $an->data->{fence}{device}{$device}{name}{$reference}{string},
				}, file => $THIS_FILE, line => __LINE__});
			}
		}
		if ($device eq "ipmi")
		{
			foreach my $reference (sort {$a cmp $b} keys %{$an->data->{install_manifest}{$uuid}{common}{ipmi}})
			{
				my $name            = $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{name};
				my $ip              = $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{ip};
				my $user            = $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{user};
				my $password        = $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{password};
				my $password_script = $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{password_script};
				my $agent           = $an->data->{install_manifest}{$uuid}{common}{ipmi}{$reference}{agent};
				if ((not $name) && ($ip))
				{
					$name = $ip;
				}
					
				# Build the string
				my $string =  "<fencedevice name=\"$reference\" agent=\"$agent\"";
					$string .= " ipaddr=\"$name\"" if $name;
					$string .= " login=\"$user\""  if $user;
				if ($password)
				{
					$string .= " passwd=\"$password\"";
				}
				elsif ($password_script)
				{
					$string .= " passwd_script=\"$password_script\"";
				}
				$string .= " />";
				$string =~ s/\s+/ /g;
				$an->data->{fence}{device}{$device}{name}{$reference}{string} = $string;
				$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
					name1 => "fence::device::${device}::name::${reference}::string", value1 => $an->data->{fence}{device}{$device}{name}{$reference}{string},
				}, file => $THIS_FILE, line => __LINE__});
			}
		}
		if ($device eq "pdu")
		{
			foreach my $reference (sort {$a cmp $b} keys %{$an->data->{install_manifest}{$uuid}{common}{pdu}})
			{
				my $name            = $an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{name};
				my $ip              = $an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{ip};
				my $user            = $an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{user};
				my $password        = $an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{password};
				my $password_script = $an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{password_script};
				my $agent           = $an->data->{install_manifest}{$uuid}{common}{pdu}{$reference}{agent};
				if ((not $name) && ($ip))
				{
					$name = $ip;
				}
					
				# Build the string
				my $string =  "<fencedevice name=\"$reference\" agent=\"$agent\" ";
					$string .= " ipaddr=\"$name\"" if $name;
					$string .= " login=\"$user\""  if $user;
				if ($password)
				{	
					$string .= "passwd=\"$password\"";
				}
				elsif ($password_script)
				{
					$string .= "passwd_script=\"$password_script\"";
				}
				$string .= " />";
				$string =~ s/\s+/ /g;
				$an->data->{fence}{device}{$device}{name}{$reference}{string} = $string;
				$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
					name1 => "fence::device::${device}::name::${reference}::string", value1 => $an->data->{fence}{device}{$device}{name}{$reference}{string},
				}, file => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	# Some system stuff.
	$an->data->{sys}{post_join_delay} = $an->data->{install_manifest}{$uuid}{common}{cluster}{fence}{post_join_delay};
	$an->data->{sys}{update_os}       = $an->data->{install_manifest}{$uuid}{common}{update}{os};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "sys::post_join_delay", value1 => $an->data->{sys}{post_join_delay},
		name2 => "sys::update_os",       value2 => $an->data->{sys}{update_os},
	}, file => $THIS_FILE, line => __LINE__});
	if ((lc($an->data->{install_manifest}{$uuid}{common}{update}{os}) eq "false") || (lc($an->data->{install_manifest}{$uuid}{common}{update}{os}) eq "no"))
	{
		$an->data->{sys}{update_os} = 0;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "sys::update_os", value1 => $an->data->{sys}{update_os},
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	return(0);
}

# This reads a cache type for the given target for the requesting host and returns the data, if found.
sub read_cache
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "read_cache" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $target = $parameter->{target} ? $parameter->{target} : "";
	my $type   = $parameter->{type}   ? $parameter->{type}   : "";
	my $source = $parameter->{source} ? $parameter->{source} : $an->data->{sys}{host_uuid};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
		name1 => "target", value1 => $target, 
		name2 => "type",   value2 => $type, 
		name3 => "source", value3 => $source, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $query = "
SELECT 
    node_cache_data 
FROM 
    nodes_cache 
WHERE 
    node_cache_name      = ".$an->data->{sys}{use_db_fh}->quote($type)."
AND 
    node_cache_node_uuid = ".$an->data->{sys}{use_db_fh}->quote($target)."
AND 
    node_cache_data IS DISTINCT FROM 'DELETED'";
    
	if ($source eq "any")
	{
		$query .= "
LIMIT 1
;";
	}
	else
	{
		$query .= "
AND 
    node_cache_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($source)."
;";
	}
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query, 
	}, file => $THIS_FILE, line => __LINE__});
	my $data = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
	   $data = "" if not defined $data;
	
	### WARNING: This can expose passwords. Only change the log level to actively debug.
	$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
		name1 => "data", value1 => $data, 
	}, file => $THIS_FILE, line => __LINE__});
	return($data);
}

# This reads a variable
sub read_variable
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "read_variable" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $variable_uuid         = $parameter->{variable_uuid}         ? $parameter->{variable_uuid}         : "";
	my $variable_name         = $parameter->{variable_name}         ? $parameter->{variable_name}         : "";
	my $variable_source_uuid  = $parameter->{variable_source_uuid}  ? $parameter->{variable_source_uuid}  : "NULL";
	my $variable_source_table = $parameter->{variable_source_table} ? $parameter->{variable_source_table} : "NULL";
	my $id                    = $parameter->{id}                    ? $parameter->{id}                    : $an->data->{sys}{read_db_id};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0004", message_variables => {
		name1 => "variable_uuid",         value1 => $variable_uuid, 
		name2 => "variable_name",         value2 => $variable_name, 
		name3 => "variable_source_uuid",  value3 => $variable_source_uuid, 
		name4 => "variable_source_table", value4 => $variable_source_table, 
	}, file => $THIS_FILE, line => __LINE__});
	
	if (not $variable_name)
	{
		# Throw an error and exit.
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0165", code => 165, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	# If we don't have a UUID, see if we can find one for the given SMTP server name.
	my $query = "
SELECT 
    variable_value, 
    variable_uuid, 
    round(extract(epoch from modified_date)) 
FROM 
    variables 
WHERE ";
	if ($variable_uuid)
	{
		$query .= "
    variable_uuid = ".$an->data->{sys}{use_db_fh}->quote($variable_uuid);
	}
	else
	{
		$query .= "
    variable_name         = ".$an->data->{sys}{use_db_fh}->quote($variable_name);
		if (($variable_source_uuid ne "NULL") && ($variable_source_table ne "NULL"))
		{
			$query .= "
AND 
    variable_source_uuid  = ".$an->data->{sys}{use_db_fh}->quote($variable_source_uuid)." 
AND 
    variable_source_table = ".$an->data->{sys}{use_db_fh}->quote($variable_source_table)." 
";
		}
	}
	$query .= ";";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $variable_value = "";
	my $modified_date  = "";
	my $results        = $an->DB->do_db_query({id => $id, query => $query, source => $THIS_FILE, line => __LINE__});
	my $count          = @{$results};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		$variable_value = defined $row->[0] ? $row->[0] : "";
		$variable_uuid  =         $row->[1];
		$modified_date  =         $row->[2];
		$an->Log->entry({log_level => 3, message_key => "an_variables_0004", message_variables => {
			name1 => "variable_name",  value1 => $variable_name, 
			name2 => "variable_value", value2 => $variable_value, 
			name3 => "variable_uuid",  value3 => $variable_uuid, 
			name4 => "modified_date",  value4 => $modified_date, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	return($variable_value, $variable_uuid, $modified_date);
}

# This generates an Install Manifest and records it in the 'manifests' table.
sub save_install_manifest
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "save_install_manifest" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	# If 'raw' is set, just straight update the manifest_data.
	my $xml;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "cgi::raw",           value1 => $an->data->{cgi}{raw}, 
		name2 => "cgi::manifest_data", value2 => $an->data->{cgi}{manifest_data}, 
	}, file => $THIS_FILE, line => __LINE__});
	if (($an->data->{cgi}{raw}) && ($an->data->{cgi}{manifest_data}))
	{
		$xml = $an->data->{cgi}{manifest_data};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "xml", value1 => $xml, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Break up hostsnames
		my ($node1_short_name)    = ($an->data->{cgi}{anvil_node1_name}    =~ /^(.*?)\./);
		my ($node2_short_name)    = ($an->data->{cgi}{anvil_node2_name}    =~ /^(.*?)\./);
		my ($switch1_short_name)  = ($an->data->{cgi}{anvil_switch1_name}  =~ /^(.*?)\./);
		my ($switch2_short_name)  = ($an->data->{cgi}{anvil_switch2_name}  =~ /^(.*?)\./);
		my ($pdu1_short_name)     = ($an->data->{cgi}{anvil_pdu1_name}     =~ /^(.*?)\./);
		my ($pdu2_short_name)     = ($an->data->{cgi}{anvil_pdu2_name}     =~ /^(.*?)\./);
		my ($pdu3_short_name)     = ($an->data->{cgi}{anvil_pdu3_name}     =~ /^(.*?)\./);
		my ($pdu4_short_name)     = ($an->data->{cgi}{anvil_pdu4_name}     =~ /^(.*?)\./);
		my ($ups1_short_name)     = ($an->data->{cgi}{anvil_ups1_name}     =~ /^(.*?)\./);
		my ($ups2_short_name)     = ($an->data->{cgi}{anvil_ups2_name}     =~ /^(.*?)\./);
		my ($striker1_short_name) = ($an->data->{cgi}{anvil_striker1_name} =~ /^(.*?)\./);
		my ($striker2_short_name) = ($an->data->{cgi}{anvil_striker1_name} =~ /^(.*?)\./);
		my ($now_date, $now_time) = $an->Get->date_and_time();
		my $date                  = "$now_date, $now_time";
		
		# Not yet supported but will be later.
		$an->data->{cgi}{anvil_node1_ipmi_password} = $an->data->{cgi}{anvil_node1_ipmi_password} ? $an->data->{cgi}{anvil_node1_ipmi_password} : $an->data->{cgi}{anvil_password};
		$an->data->{cgi}{anvil_node1_ipmi_user}     = $an->data->{cgi}{anvil_node1_ipmi_user}     ? $an->data->{cgi}{anvil_node1_ipmi_user}     : "admin";
		$an->data->{cgi}{anvil_node1_ipmi_lanplus}  = $an->data->{cgi}{anvil_node1_ipmi_lanplus}  ? $an->data->{cgi}{anvil_node1_ipmi_lanplus}  : "false";
		$an->data->{cgi}{anvil_node1_ipmi_privlvl}  = $an->data->{cgi}{anvil_node1_ipmi_privlvl}  ? $an->data->{cgi}{anvil_node1_ipmi_privlvl}  : "USER";
		$an->data->{cgi}{anvil_node2_ipmi_password} = $an->data->{cgi}{anvil_node2_ipmi_password} ? $an->data->{cgi}{anvil_node2_ipmi_password} : $an->data->{cgi}{anvil_password};
		$an->data->{cgi}{anvil_node2_ipmi_user}     = $an->data->{cgi}{anvil_node2_ipmi_user}     ? $an->data->{cgi}{anvil_node2_ipmi_user}     : "admin";
		$an->data->{cgi}{anvil_node2_ipmi_lanplus}  = $an->data->{cgi}{anvil_node2_ipmi_lanplus}  ? $an->data->{cgi}{anvil_node2_ipmi_lanplus}  : "false";
		$an->data->{cgi}{anvil_node2_ipmi_privlvl}  = $an->data->{cgi}{anvil_node2_ipmi_privlvl}  ? $an->data->{cgi}{anvil_node2_ipmi_privlvl}  : "USER";
		
		# Generate UUIDs if needed.
		$an->data->{cgi}{anvil_node1_uuid}          = $an->Get->uuid() if not $an->data->{cgi}{anvil_node1_uuid};
		$an->data->{cgi}{anvil_node2_uuid}          = $an->Get->uuid() if not $an->data->{cgi}{anvil_node2_uuid};
		
		### TODO: This isn't set for some reason, fix
		$an->data->{cgi}{anvil_open_vnc_ports} = $an->data->{sys}{install_manifest}{'default'}{open_vnc_ports} if not $an->data->{cgi}{anvil_open_vnc_ports};
		
		# Set the MTU.
		$an->data->{cgi}{anvil_mtu_size} = $an->data->{sys}{install_manifest}{'default'}{mtu_size} if not $an->data->{cgi}{anvil_mtu_size};
		
		# Use the subnet mask of the IPMI devices by comparing their IP to that
		# of the BCN and IFN, and use the netmask of the matching network.
		my $node1_ipmi_netmask = $an->Get->netmask_from_ip({ip => $an->data->{cgi}{anvil_node1_ipmi_ip}});
		my $node2_ipmi_netmask = $an->Get->netmask_from_ip({ip => $an->data->{cgi}{anvil_node2_ipmi_ip}});
		
		### Setup the DRBD lines.
		$an->Log->entry({log_level => 3, message_key => "an_variables_0011", message_variables => {
			name1  => "cgi::anvil_drbd_disk_disk-barrier",  value1  => $an->data->{cgi}{'anvil_drbd_disk_disk-barrier'},
			name2  => "cgi::anvil_drbd_disk_disk-flushes",  value2  => $an->data->{cgi}{'anvil_drbd_disk_disk-flushes'},
			name3  => "cgi::anvil_drbd_disk_md-flushes",    value3  => $an->data->{cgi}{'anvil_drbd_disk_md-flushes'},
			name4  => "cgi::anvil_drbd_disk_c-plan-ahead",  value4  => $an->data->{cgi}{'anvil_drbd_disk_c-plan-ahead'},
			name5  => "cgi::anvil_drbd_disk_c-max-rate",    value5  => $an->data->{cgi}{'anvil_drbd_disk_c-max-rate'},
			name6  => "cgi::anvil_drbd_disk_c-min-rate",    value6  => $an->data->{cgi}{'anvil_drbd_disk_c-min-rate'},
			name7  => "cgi::anvil_drbd_disk_c-fill-target", value7  => $an->data->{cgi}{'anvil_drbd_disk_c-fill-target'},
			name8  => "cgi::anvil_drbd_options_cpu-mask",   value8  => $an->data->{cgi}{'anvil_drbd_options_cpu-mask'},
			name9  => "cgi::anvil_drbd_net_max-buffers",    value9  => $an->data->{cgi}{'anvil_drbd_net_max-buffers'},
			name10 => "cgi::anvil_drbd_net_sndbuf-size",    value10 => $an->data->{cgi}{'anvil_drbd_net_sndbuf-size'},
			name11 => "cgi::anvil_drbd_net_rcvbuf-size",    value11 => $an->data->{cgi}{'anvil_drbd_net_rcvbuf-size'},
		}, file => $THIS_FILE, line => __LINE__});
		
		### TODO: Should we check/override bad c-* entries?
		
		# Standardize
		$an->data->{cgi}{'anvil_drbd_disk_disk-barrier'} =  lc($an->data->{cgi}{'anvil_drbd_disk_disk-barrier'});
		$an->data->{cgi}{'anvil_drbd_disk_disk-barrier'} =~ s/no/false/;
		$an->data->{cgi}{'anvil_drbd_disk_disk-barrier'} =~ s/0/false/;
		$an->data->{cgi}{'anvil_drbd_disk_disk-flushes'} =  lc($an->data->{cgi}{'anvil_drbd_disk_disk-flushes'});
		$an->data->{cgi}{'anvil_drbd_disk_disk-flushes'} =~ s/no/false/;
		$an->data->{cgi}{'anvil_drbd_disk_disk-flushes'} =~ s/0/false/;
		$an->data->{cgi}{'anvil_drbd_disk_md-flushes'}   =  lc($an->data->{cgi}{'anvil_drbd_disk_md-flushes'});
		$an->data->{cgi}{'anvil_drbd_disk_md-flushes'}   =~ s/no/false/;
		$an->data->{cgi}{'anvil_drbd_disk_md-flushes'}   =~ s/0/false/;
		
		# Convert
		$an->data->{cgi}{'anvil_drbd_disk_disk-barrier'} = $an->data->{cgi}{'anvil_drbd_disk_disk-barrier'} eq "false" ? "no" : "yes";
		$an->data->{cgi}{'anvil_drbd_disk_disk-flushes'} = $an->data->{cgi}{'anvil_drbd_disk_disk-flushes'} eq "false" ? "no" : "yes";
		$an->data->{cgi}{'anvil_drbd_disk_md-flushes'}   = $an->data->{cgi}{'anvil_drbd_disk_md-flushes'}   eq "false" ? "no" : "yes";
		$an->data->{cgi}{'anvil_drbd_options_cpu-mask'}  = defined $an->data->{cgi}{'anvil_drbd_options_cpu-mask'}   ? $an->data->{cgi}{'anvil_drbd_options_cpu-mask'} : "";
		$an->data->{cgi}{'anvil_drbd_net_max-buffers'}   = $an->data->{cgi}{'anvil_drbd_net_max-buffers'} =~ /^\d+$/ ? $an->data->{cgi}{'anvil_drbd_net_max-buffers'}  : "";
		$an->data->{cgi}{'anvil_drbd_net_sndbuf-size'}   = $an->data->{cgi}{'anvil_drbd_net_sndbuf-size'}            ? $an->data->{cgi}{'anvil_drbd_net_sndbuf-size'}  : "";
		$an->data->{cgi}{'anvil_drbd_net_rcvbuf-size'}   = $an->data->{cgi}{'anvil_drbd_net_rcvbuf-size'}            ? $an->data->{cgi}{'anvil_drbd_net_rcvbuf-size'}  : "";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0007", message_variables => {
			name1 => "cgi::anvil_drbd_disk_disk-barrier", value1 => $an->data->{cgi}{'anvil_drbd_disk_disk-barrier'},
			name2 => "cgi::anvil_drbd_disk_disk-flushes", value2 => $an->data->{cgi}{'anvil_drbd_disk_disk-flushes'},
			name3 => "cgi::anvil_drbd_disk_md-flushes",   value3 => $an->data->{cgi}{'anvil_drbd_disk_md-flushes'},
			name4 => "cgi::anvil_drbd_options_cpu-mask",  value4 => $an->data->{cgi}{'anvil_drbd_options_cpu-mask'},
			name5 => "cgi::anvil_drbd_net_max-buffers",   value5 => $an->data->{cgi}{'anvil_drbd_net_max-buffers'},
			name6 => "cgi::anvil_drbd_net_sndbuf-size",   value6 => $an->data->{cgi}{'anvil_drbd_net_sndbuf-size'},
			name7 => "cgi::anvil_drbd_net_rcvbuf-size",   value7 => $an->data->{cgi}{'anvil_drbd_net_rcvbuf-size'},
		}, file => $THIS_FILE, line => __LINE__});
		
		### TODO: Get the node and dashboard UUIDs if not yet set.
		
		### KVM-based fencing is supported but not documented. Sample entries
		### are here for those who might ask for it when building test Anvil!
		### systems later.
		# Many things are currently static but might be made configurable later.
		$xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>

<!--
Generated on:    ".$date."
Striker Version: ".$an->data->{sys}{version}."
-->

<config>
	<node name=\"".$an->data->{cgi}{anvil_node1_name}."\" uuid=\"".$an->data->{cgi}{anvil_node1_uuid}."\">
		<network>
			<bcn ip=\"".$an->data->{cgi}{anvil_node1_bcn_ip}."\" />
			<sn ip=\"".$an->data->{cgi}{anvil_node1_sn_ip}."\" />
			<ifn ip=\"".$an->data->{cgi}{anvil_node1_ifn_ip}."\" />
		</network>
		<ipmi>
			<on reference=\"ipmi_n01\" ip=\"".$an->data->{cgi}{anvil_node1_ipmi_ip}."\" netmask=\"$node1_ipmi_netmask\" user=\"".$an->data->{cgi}{anvil_node1_ipmi_user}."\" password=\"".$an->data->{cgi}{anvil_node1_ipmi_password}."\" gateway=\"\" lanplus=\"".$an->data->{cgi}{anvil_node1_ipmi_lanplus}."\" privlvl=\"".$an->data->{cgi}{anvil_node1_ipmi_privlvl}."\" />
		</ipmi>
		<pdu>
			<on reference=\"pdu01\" port=\"".$an->data->{cgi}{anvil_node1_pdu1_outlet}."\" />
			<on reference=\"pdu02\" port=\"".$an->data->{cgi}{anvil_node1_pdu2_outlet}."\" />
			<on reference=\"pdu03\" port=\"".$an->data->{cgi}{anvil_node1_pdu3_outlet}."\" />
			<on reference=\"pdu04\" port=\"".$an->data->{cgi}{anvil_node1_pdu4_outlet}."\" />
		</pdu>
		<kvm>
			<!-- port == virsh name of VM -->
			<on reference=\"kvm_host\" port=\"\" />
		</kvm>
		<interfaces>
			<interface name=\"bcn_link1\" mac=\"".$an->data->{cgi}{anvil_node1_bcn_link1_mac}."\" />
			<interface name=\"bcn_link2\" mac=\"".$an->data->{cgi}{anvil_node1_bcn_link2_mac}."\" />
			<interface name=\"sn_link1\" mac=\"".$an->data->{cgi}{anvil_node1_sn_link1_mac}."\" />
			<interface name=\"sn_link2\" mac=\"".$an->data->{cgi}{anvil_node1_sn_link2_mac}."\" />
			<interface name=\"ifn_link1\" mac=\"".$an->data->{cgi}{anvil_node1_ifn_link1_mac}."\" />
			<interface name=\"ifn_link2\" mac=\"".$an->data->{cgi}{anvil_node1_ifn_link2_mac}."\" />
		</interfaces>
	</node>
	<node name=\"".$an->data->{cgi}{anvil_node2_name}."\" uuid=\"".$an->data->{cgi}{anvil_node2_uuid}."\">
		<network>
			<bcn ip=\"".$an->data->{cgi}{anvil_node2_bcn_ip}."\" />
			<sn ip=\"".$an->data->{cgi}{anvil_node2_sn_ip}."\" />
			<ifn ip=\"".$an->data->{cgi}{anvil_node2_ifn_ip}."\" />
		</network>
		<ipmi>
			<on reference=\"ipmi_n02\" ip=\"".$an->data->{cgi}{anvil_node2_ipmi_ip}."\" netmask=\"$node2_ipmi_netmask\" user=\"".$an->data->{cgi}{anvil_node2_ipmi_user}."\" password=\"".$an->data->{cgi}{anvil_node2_ipmi_password}."\" gateway=\"\" lanplus=\"".$an->data->{cgi}{anvil_node2_ipmi_lanplus}."\" privlvl=\"".$an->data->{cgi}{anvil_node2_ipmi_privlvl}."\" />
		</ipmi>
		<pdu>
			<on reference=\"pdu01\" port=\"".$an->data->{cgi}{anvil_node2_pdu1_outlet}."\" />
			<on reference=\"pdu02\" port=\"".$an->data->{cgi}{anvil_node2_pdu2_outlet}."\" />
			<on reference=\"pdu03\" port=\"".$an->data->{cgi}{anvil_node2_pdu3_outlet}."\" />
			<on reference=\"pdu04\" port=\"".$an->data->{cgi}{anvil_node2_pdu4_outlet}."\" />
		</pdu>
		<kvm>
			<on reference=\"kvm_host\" port=\"\" />
		</kvm>
		<interfaces>
			<interface name=\"bcn_link1\" mac=\"".$an->data->{cgi}{anvil_node2_bcn_link1_mac}."\" />
			<interface name=\"bcn_link2\" mac=\"".$an->data->{cgi}{anvil_node2_bcn_link2_mac}."\" />
			<interface name=\"sn_link1\" mac=\"".$an->data->{cgi}{anvil_node2_sn_link1_mac}."\" />
			<interface name=\"sn_link2\" mac=\"".$an->data->{cgi}{anvil_node2_sn_link2_mac}."\" />
			<interface name=\"ifn_link1\" mac=\"".$an->data->{cgi}{anvil_node2_ifn_link1_mac}."\" />
			<interface name=\"ifn_link2\" mac=\"".$an->data->{cgi}{anvil_node2_ifn_link2_mac}."\" />
		</interfaces>
	</node>
	<common>
		<networks>
			<bcn netblock=\"".$an->data->{cgi}{anvil_bcn_network}."\" netmask=\"".$an->data->{cgi}{anvil_bcn_subnet}."\" gateway=\"\" defroute=\"no\" ethtool_opts=\"".$an->data->{cgi}{anvil_bcn_ethtool_opts}."\" />
			<sn netblock=\"".$an->data->{cgi}{anvil_sn_network}."\" netmask=\"".$an->data->{cgi}{anvil_sn_subnet}."\" gateway=\"\" defroute=\"no\" ethtool_opts=\"".$an->data->{cgi}{anvil_sn_ethtool_opts}."\" />
			<ifn netblock=\"".$an->data->{cgi}{anvil_ifn_network}."\" netmask=\"".$an->data->{cgi}{anvil_ifn_subnet}."\" gateway=\"".$an->data->{cgi}{anvil_ifn_gateway}."\" dns1=\"".$an->data->{cgi}{anvil_dns1}."\" dns2=\"".$an->data->{cgi}{anvil_dns2}."\" ntp1=\"".$an->data->{cgi}{anvil_ntp1}."\" ntp2=\"".$an->data->{cgi}{anvil_ntp2}."\" defroute=\"yes\" ethtool_opts=\"".$an->data->{cgi}{anvil_ifn_ethtool_opts}."\" />
			<bonding opts=\"mode=1 miimon=100 use_carrier=1 updelay=120000 downdelay=0\">
				<bcn name=\"bcn_bond1\" primary=\"bcn_link1\" secondary=\"bcn_link2\" />
				<sn name=\"sn_bond1\" primary=\"sn_link1\" secondary=\"sn_link2\" />
				<ifn name=\"ifn_bond1\" primary=\"ifn_link1\" secondary=\"ifn_link2\" />
			</bonding>
			<bridges>
				<bridge name=\"ifn_bridge1\" on=\"ifn\" />
			</bridges>
			<mtu size=\"".$an->data->{cgi}{anvil_mtu_size}."\" />
		</networks>
		<repository urls=\"".$an->data->{cgi}{anvil_repositories}."\" />
		<media_library size=\"".$an->data->{cgi}{anvil_media_library_size}."\" units=\"".$an->data->{cgi}{anvil_media_library_unit}."\" />
		<storage_pool_1 size=\"".$an->data->{cgi}{anvil_storage_pool1_size}."\" units=\"".$an->data->{cgi}{anvil_storage_pool1_unit}."\" />
		<anvil prefix=\"".$an->data->{cgi}{anvil_prefix}."\" sequence=\"".$an->data->{cgi}{anvil_sequence}."\" domain=\"".$an->data->{cgi}{anvil_domain}."\" password=\"".$an->data->{cgi}{anvil_password}."\" striker_user=\"".$an->data->{cgi}{striker_user}."\" striker_database=\"".$an->data->{cgi}{striker_database}."\" />
		<ssh keysize=\"8191\" />
		<cluster name=\"".$an->data->{cgi}{anvil_name}."\">
			<!-- Set the order to 'kvm' if building on KVM-backed VMs. Also set each node's 'port=' above and '<kvm>' element attributes below. -->
			<fence order=\"ipmi,pdu\" post_join_delay=\"90\" delay=\"15\" delay_node=\"".$an->data->{cgi}{anvil_node1_name}."\" />
		</cluster>
		<drbd>
			<disk disk-barrier=\"".$an->data->{cgi}{'anvil_drbd_disk_disk-barrier'}."\" disk-flushes=\"".$an->data->{cgi}{'anvil_drbd_disk_disk-flushes'}."\" md-flushes=\"".$an->data->{cgi}{'anvil_drbd_disk_md-flushes'}."\" c-plan-ahead=\"".$an->data->{cgi}{'anvil_drbd_disk_c-plan-ahead'}."\" c-max-rate=\"".$an->data->{cgi}{'anvil_drbd_disk_c-max-rate'}."\" c-min-rate=\"".$an->data->{cgi}{'anvil_drbd_disk_c-min-rate'}."\" c-fill-target=\"".$an->data->{cgi}{'anvil_drbd_disk_c-fill-target'}."\" />
			<options cpu-mask=\"".$an->data->{cgi}{'anvil_drbd_options_cpu-mask'}."\" />
			<net max-buffers=\"".$an->data->{cgi}{'anvil_drbd_net_max-buffers'}."\" sndbuf-size=\"".$an->data->{cgi}{'anvil_drbd_net_sndbuf-size'}."\" rcvbuf-size=\"".$an->data->{cgi}{'anvil_drbd_net_rcvbuf-size'}."\" />
		</drbd>
		<switch>
			<switch name=\"".$an->data->{cgi}{anvil_switch1_name}."\" ip=\"".$an->data->{cgi}{anvil_switch1_ip}."\" />
";

		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "cgi::anvil_switch2_name", value1 => $an->data->{cgi}{anvil_switch2_name},
		}, file => $THIS_FILE, line => __LINE__});
		if (($an->data->{cgi}{anvil_switch2_name}) && ($an->data->{cgi}{anvil_switch2_name} ne "--"))
		{
			$xml .= "\t\t\t<switch name=\"".$an->data->{cgi}{anvil_switch2_name}."\" ip=\"".$an->data->{cgi}{anvil_switch2_ip}."\" />";
		}
		$xml .= "
		</switch>
		<ups>
			<ups name=\"".$an->data->{cgi}{anvil_ups1_name}."\" type=\"apc\" port=\"3551\" ip=\"".$an->data->{cgi}{anvil_ups1_ip}."\" />
			<ups name=\"".$an->data->{cgi}{anvil_ups2_name}."\" type=\"apc\" port=\"3552\" ip=\"".$an->data->{cgi}{anvil_ups2_ip}."\" />
		</ups>
		<pdu>";
		# PDU 1 and 2 always exist.
		my $pdu1_agent = $an->data->{cgi}{anvil_pdu1_agent} ? $an->data->{cgi}{anvil_pdu1_agent} : $an->data->{sys}{install_manifest}{anvil_pdu_agent};
		$xml .= "
			<pdu reference=\"pdu01\" name=\"".$an->data->{cgi}{anvil_pdu1_name}."\" ip=\"".$an->data->{cgi}{anvil_pdu1_ip}."\" agent=\"$pdu1_agent\" />";
		my $pdu2_agent = $an->data->{cgi}{anvil_pdu2_agent} ? $an->data->{cgi}{anvil_pdu2_agent} : $an->data->{sys}{install_manifest}{anvil_pdu_agent};
		$xml .= "
			<pdu reference=\"pdu02\" name=\"".$an->data->{cgi}{anvil_pdu2_name}."\" ip=\"".$an->data->{cgi}{anvil_pdu2_ip}."\" agent=\"$pdu2_agent\" />";
		if ($an->data->{cgi}{anvil_pdu3_name})
		{
			my $pdu3_agent = $an->data->{cgi}{anvil_pdu3_agent} ? $an->data->{cgi}{anvil_pdu3_agent} : $an->data->{sys}{install_manifest}{anvil_pdu_agent};
			$xml .= "
			<pdu reference=\"pdu03\" name=\"".$an->data->{cgi}{anvil_pdu3_name}."\" ip=\"".$an->data->{cgi}{anvil_pdu3_ip}."\" agent=\"$pdu3_agent\" />";
		}
		if ($an->data->{cgi}{anvil_pdu4_name})
		{
			my $pdu4_agent = $an->data->{cgi}{anvil_pdu4_agent} ? $an->data->{cgi}{anvil_pdu4_agent} : $an->data->{sys}{install_manifest}{anvil_pdu_agent};
			$xml .= "
			<pdu reference=\"pdu04\" name=\"".$an->data->{cgi}{anvil_pdu4_name}."\" ip=\"".$an->data->{cgi}{anvil_pdu4_ip}."\" agent=\"$pdu4_agent\" />";
		}
		
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "sys::install_manifest::use_anvil-kick-apc-ups", value1 => $an->data->{sys}{install_manifest}{'use_anvil-kick-apc-ups'},
			name2 => "sys::install_manifest::use_anvil-safe-start",   value2 => $an->data->{sys}{install_manifest}{'use_anvil-safe-start'},
		}, file => $THIS_FILE, line => __LINE__});
		my $say_use_anvil_kick_apc_ups = $an->data->{sys}{install_manifest}{'use_anvil-kick-apc-ups'} ? "true" : "false";
		my $say_use_anvil_safe_start   = $an->data->{sys}{install_manifest}{'use_anvil-safe-start'}   ? "true" : "false";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "say_use_anvil_kick_apc_ups", value1 => $say_use_anvil_kick_apc_ups,
			name2 => "say_use_anvil-safe-start",   value2 => $say_use_anvil_safe_start,
		}, file => $THIS_FILE, line => __LINE__});
		
		$xml .= "
		</pdu>
		<ipmi>
			<ipmi reference=\"ipmi_n01\" agent=\"fence_ipmilan\" />
			<ipmi reference=\"ipmi_n02\" agent=\"fence_ipmilan\" />
		</ipmi>
		<kvm>
			<kvm reference=\"kvm_host\" ip=\"192.168.122.1\" user=\"root\" password=\"\" password_script=\"\" agent=\"fence_virsh\" />
		</kvm>
		<striker>
			<striker name=\"".$an->data->{cgi}{anvil_striker1_name}."\" bcn_ip=\"".$an->data->{cgi}{anvil_striker1_bcn_ip}."\" ifn_ip=\"".$an->data->{cgi}{anvil_striker1_ifn_ip}."\" database=\"\" user=\"\" password=\"\" uuid=\"\" />
			<striker name=\"".$an->data->{cgi}{anvil_striker2_name}."\" bcn_ip=\"".$an->data->{cgi}{anvil_striker2_bcn_ip}."\" ifn_ip=\"".$an->data->{cgi}{anvil_striker2_ifn_ip}."\" database=\"\" user=\"\" password=\"\" uuid=\"\" />
		</striker>
		<update os=\"true\" />
		<iptables>
			<vnc ports=\"".$an->data->{cgi}{anvil_open_vnc_ports}."\" />
		</iptables>
		<servers>
			<!-- This isn't used anymore, but this section may be useful for other things in the future, -->
			<!-- <provision use_spice_graphics=\"0\" /> -->
		</servers>
		<tools>
			<use anvil-safe-start=\"$say_use_anvil_safe_start\" anvil-kick-apc-ups=\"$say_use_anvil_kick_apc_ups\" />
		</tools>
	</common>
</config>
		";
	}
	
	# Record it to the database.
	if (not $an->data->{cgi}{manifest_uuid})
	{
		# Insert it.
		   $an->data->{cgi}{manifest_uuid} = $an->Get->uuid();
		my $query = "
INSERT INTO 
    manifests 
(
    manifest_uuid, 
    manifest_data, 
    manifest_note, 
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{cgi}{manifest_uuid}).", 
    ".$an->data->{sys}{use_db_fh}->quote($xml).", 
    NULL, 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Update it
		my $query = "
UPDATE 
    public.manifests 
SET
    manifest_data = ".$an->data->{sys}{use_db_fh}->quote($xml).", 
    modified_date = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
WHERE 
    manifest_uuid = ".$an->data->{sys}{use_db_fh}->quote($an->data->{cgi}{manifest_uuid})." 
;";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query, 
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "cgi::manifest_uuid", value1 => $an->data->{cgi}{manifest_uuid}, 
	}, file => $THIS_FILE, line => __LINE__});
	return($an->data->{cgi}{manifest_uuid});
}

# This reads in the cache for the target and checks or sets the power state of the target UUID, if possible.
sub target_power
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "target_power" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $task   = $parameter->{task}   ? $parameter->{task}   : "status";
	my $target = $parameter->{target} ? $parameter->{target} : "";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "task",   value1 => $task, 
		name2 => "target", value2 => $target, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# This should really be 'fence_target'...
	my $ipmi_target = "";
	my $state       = "unknown";
	if (($task ne "status") && ($task ne "on") && ($task ne "off"))
	{
		# Bad task.
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0111", message_variables => { task => $task }, code => 111, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	if (not $target)
	{
		# No target UUID
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0112", code => 112, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	elsif (not $an->Validate->is_uuid({uuid => $target}))
	{
		# Not a valid UUID.
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0113", message_variables => { target => $target }, code => 113, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	# Check the power state.
	### WARNING: This exposes passwords. Only change the log level to actively debug.
	my $power_check = $an->ScanCore->read_cache({target => $target, type => "power_check"});
	$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
		name1 => "power_check", value1 => $power_check, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# If I don't have a power_check, see if anyone else does.
	if (not $power_check)
	{
		$power_check = $an->ScanCore->read_cache({target => $target, type => "power_check", source => "any"});
		$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
			name1 => "power_check", value1 => $power_check, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	# Now check, if we can.
	$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
		name1 => "power_check", value1 => $power_check, 
	}, file => $THIS_FILE, line => __LINE__});
	if ($power_check)
	{
		# If there are multiple methods, loop through them
		my $methods       = {};
		my $method_number = "";
		my $method_name   = "";
		foreach my $method (split/;/, $power_check)
		{
			### WARNING: This exposes passwords. Only change the log level to actively debug.
			$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
				name1 => "method", value1 => $method, 
			}, file => $THIS_FILE, line => __LINE__});
			
			# I can't trust PDUs because their response is based on outlet states.
			next if $method =~ /fence_apc/;
			next if $method =~ /fence_raritan/;
			
			# I should only have one method left, fence_ipmilan or fence_virsh.
			if ($method =~ /^(\d+):(\w+): (fence_.*)$/)
			{
				$method_number = $1;
				$method_name   = $2;
				$power_check   = $3;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
					name1 => "method_number", value1 => $method_number, 
					name2 => "method_name",   value2 => $method_name, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
					name1 => "power_check", value1 => $power_check, 
				}, file => $THIS_FILE, line => __LINE__});
			}
			
			# Convert the '-a X' to an IP address, if needed.
			$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
				name1 => "power_check", value1 => $power_check,
			}, file => $THIS_FILE, line => __LINE__});
			
			# Only do the IP address conversion if address is set.
			if ($power_check =~ /-a\s/) {
				$ipmi_target = ($power_check =~ /-a\s(.*?)\s/)[0];
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "ipmi_target", value1 => $ipmi_target,
				}, file => $THIS_FILE, line => __LINE__});
				if (not $an->Validate->is_ipv4({ip => $ipmi_target}))
				{
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "ipmi_target", value1 => $ipmi_target,
					}, file => $THIS_FILE, line => __LINE__});
					
					print "$THIS_FILE ".__LINE__."; ipmi_target: [$ipmi_target]\n";
					my $ip = $an->Get->ip({host => $ipmi_target});
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "ip", value1 => $ip,
					}, file => $THIS_FILE, line => __LINE__});
					
					if ($ip)
					{
						$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
							name1 => ">> power_check", value1 => $power_check,
						}, file => $THIS_FILE, line => __LINE__});
						
						$power_check =~ s/$ipmi_target/$ip/;
						$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
							name1 => "<< power_check", value1 => $power_check,
						}, file => $THIS_FILE, line => __LINE__});
					}
				}
			}
			
			$power_check =~ s/#!action!#/$task/;
			$power_check =~ s/^.*fence_/fence_/;
			
			if ($power_check !~ /^\//)
			{
				$power_check = $an->data->{path}{fence_agents}."/".$power_check;
				$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
					name1 => "power_check", value1 => $power_check,
				}, file => $THIS_FILE, line => __LINE__});
			}
			
			my $shell_call = $power_check;
			$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
				name1 => "shell_call", value1 => $shell_call,
			}, file => $THIS_FILE, line => __LINE__});
			open (my $file_handle, "$shell_call 2>&1 |") or $an->Alert->error({title_key => "error_title_0020", message_key => "error_message_0022", message_variables => { shell_call => $shell_call, error => $! }, code => 30, file => $THIS_FILE, line => __LINE__});
			while(<$file_handle>)
			{
				chomp;
				my $line = $_;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "line", value1 => $line,
				}, file => $THIS_FILE, line => __LINE__});
				if ($line =~ / On$/i)
				{
					$state = "on";
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "state", value1 => $state,
					}, file => $THIS_FILE, line => __LINE__});
				}
				if ($line =~ / Off$/i)
				{
					$state = "off";
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "state", value1 => $state,
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			close $file_handle;
			
			# Exit the loop if I got a state.
			last if $state ne "unknown";
		}
	}
	else
	{
		# Couldn't find a power_check comman in the cache.
		$an->Log->entry({log_level => 1, message_key => "warning_message_0017", message_variables => {
			name => $an->data->{sys}{uuid_to_name}{$target},
			uuid => $target,
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	# Set to 'unknown', 'on' or 'off'.
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "ipmi_target", value1 => $ipmi_target,
		name2 => "state",       value2 => $state,
	}, file => $THIS_FILE, line => __LINE__});
	return($state);
}

# This updates the server's stop_reason (if it has changed)
sub update_server_stop_reason
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "update_server_stop_reason" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $server_name = $parameter->{server_name} ? $parameter->{server_name} : "";
	my $stop_reason = $parameter->{stop_reason} ? $parameter->{stop_reason} : "NULL";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
		name1 => "server_name", value1 => $server_name,
		name2 => "stop_reason", value2 => $stop_reason,
	}, file => $THIS_FILE, line => __LINE__});
	
	# Die if I wasn't passed a server name or stop reason.
	if (not $server_name)
	{
		$an->Alert->error({title_key => "tools_title_0003", message_key => "error_message_0158", code => 159, file => $THIS_FILE, line => __LINE__});
		return("");
	}
	
	my $server_data = $an->ScanCore->get_servers();
	foreach my $hash_ref (@{$server_data})
	{
		my $this_server_uuid        = $hash_ref->{server_uuid};
		my $this_server_name        = $hash_ref->{server_name};
		my $this_server_stop_reason = $hash_ref->{server_stop_reason};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
			name1 => "this_server_uuid",        value1 => $this_server_uuid,
			name2 => "this_server_name",        value2 => $this_server_name,
			name3 => "this_server_stop_reason", value3 => $this_server_stop_reason,
		}, file => $THIS_FILE, line => __LINE__});
		
		if ($server_name eq $this_server_name)
		{
			# Found the server. Has the stop_reason changed?
			if ($stop_reason ne $this_server_stop_reason)
			{
				# Yes, update.
				my $query = "
UPDATE 
    servers 
SET 
    server_stop_reason = ".$an->data->{sys}{use_db_fh}->quote($stop_reason).", 
    modified_date      = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    server_uuid        = ".$an->data->{sys}{use_db_fh}->quote($this_server_uuid)." 
";
				$query =~ s/'NULL'/NULL/g;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "query", value1 => $query
				}, file => $THIS_FILE, line => __LINE__});
				$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	return(0);
}

# This pulls the data on the UPSes associated with this node and returns '1' if at least one of the UPSes has
# power, '2' if neither do but the hold-up time of at least one is above minimum, '3' if both are on 
# batteries and below the minimum hold-up time and '4' if both are on batteries and have been long enough to
# trigger load shedding.
sub check_node_power
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	$an->Log->entry({log_level => 2, title_key => "tools_log_0001", title_variables => { function => "check_node_power" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $node_power_ok       = 1;
	my $a_ups_has_input     = 0;
	my $highest_holdup_time = 0;
	my $minimum_ups_runtime = $an->data->{scancore}{minimum_ups_runtime};
	$an->Log->entry({log_level => 2, message_key => "an_variables_0004", message_variables => {
		name1 => "node_power_ok",       value1 => $node_power_ok,
		name2 => "a_ups_has_input",     value2 => $a_ups_has_input,
		name3 => "highest_holdup_time", value3 => $highest_holdup_time,
		name4 => "minimum_ups_runtime", value4 => $minimum_ups_runtime,
	}, file => $THIS_FILE, line => __LINE__});
	
	# First, see if my UPSes have input power. If not:
	# * See which has the longest hold-up time. If one of them is above the minimum hold-up time, set our
	#   health to '2/warning'.
	# * If the power is out to both and we're in warning, check to see if we've been in a warning state
	#   long enough to trigger load shedding. If so, we'll set our health to '4/load shed'.
	# * If the strongest is too low, set our health to '3/critical' and shut down.
	my $query = "
SELECT 
    power_ups_name, 
    power_on_battery, 
    power_seconds_left 
FROM 
    power 
WHERE 
    power_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{host_uuid}).";
";
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
	
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count
	}, file => $THIS_FILE, line => __LINE__});
	
	# If there are no results, then mark power as always OK because #yolo
	my $ups_count = @{$results};
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "ups_count", value1 => $ups_count
	}, file => $THIS_FILE, line => __LINE__});
	if (not $ups_count)
	{
		return(0);
	}
	
	# NOTE: I know I could sort by remaining hold-up time and/or filter by which UPS is on batteries, but
	#       slurping it all in makes it easier to debug with everything in memory.
	my $last_agent = "";
	# One or more records were found.
	foreach my $row (@{$results})
	{
		my $power_ups_name     = $row->[0];
		my $power_on_battery   = $row->[1];
		my $power_seconds_left = $row->[2];
		$an->Log->entry({log_level => 2, message_key => "an_variables_0003", message_variables => {
			name1 => "power_ups_name",     value1 => $power_ups_name,
			name2 => "power_on_battery",   value2 => $power_on_battery,
			name3 => "power_seconds_left", value3 => $power_seconds_left,
		}, file => $THIS_FILE, line => __LINE__});
		
		# Record the highest hold-up time.
		if ($power_seconds_left > $highest_holdup_time)
		{
			$highest_holdup_time = $power_seconds_left;
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "highest_holdup_time", value1 => $highest_holdup_time,
			}, file => $THIS_FILE, line => __LINE__});
		}
		
		# Are we on batteries?
		if ($power_on_battery)
		{
			# Well poop.
			$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
				name1 => "power_seconds_left",  value1 => $power_seconds_left,
				name2 => "highest_holdup_time", value2 => $highest_holdup_time,
			}, file => $THIS_FILE, line => __LINE__});
		}
		else
		{
			# We've got input power, sweeeet.
			$a_ups_has_input = 1;
			$node_power_ok   = 1;
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "node_power_ok", value1 => $node_power_ok,
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	$results = "";
	
	# Now, if no UPS has input power, see if the highest holdup time exceeds the minimum required to 
	# avoid a shut down.
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "a_ups_has_input", value1 => $a_ups_has_input,
	}, file => $THIS_FILE, line => __LINE__});
	if ($a_ups_has_input)
	{
		$node_power_ok = 1;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "node_power_ok", value1 => $node_power_ok,
		}, file => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# No input power from mains...
		$node_power_ok = 2;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0006", message_variables => {
			name1 => "node_power_ok",                    value1 => $node_power_ok,
			name2 => "minimum_ups_runtime",              value2 => $minimum_ups_runtime, 
			name3 => "highest_holdup_time",              value3 => $highest_holdup_time, 
			name4 => "scancore::disable::load_shedding", value4 => $an->data->{scancore}{disable}{load_shedding}, 
			name5 => "sys::anvil::node1::online",        value5 => $an->data->{sys}{anvil}{node1}{online}, 
			name6 => "sys::anvil::node2::online",        value6 => $an->data->{sys}{anvil}{node2}{online}, 
		}, file => $THIS_FILE, line => __LINE__});
		
		# Log the time remaining. I know this might get noisey, but it could be very helpful to an
		# admin watching the logs.
		$an->Log->entry({log_level => 1, message_key => "scancore_warning_0022", message_variables => {
			highest_holdup_time => $highest_holdup_time,
			minimum_ups_runtime => $minimum_ups_runtime,
		}, file => $THIS_FILE, line => __LINE__});
		
		# Are both nodes up?
		my $both_nodes_online = 1;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "both_nodes_online", value1 => $both_nodes_online,
		}, file => $THIS_FILE, line => __LINE__});
		if ((not $an->data->{sys}{anvil}{node1}{online}) or (not $an->data->{sys}{anvil}{node2}{online}))
		{
			# Disable load shedding because our peer is dead.
			$both_nodes_online = 0;
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "both_nodes_online", value1 => $both_nodes_online,
			}, file => $THIS_FILE, line => __LINE__});
		}
		
		if ($minimum_ups_runtime >= $highest_holdup_time)
		{
			# Time to go zzz
			$node_power_ok = 3;
			$an->Log->entry({log_level => 1, message_key => "an_variables_0001", message_variables => {
				name1 => "node_power_ok", value1 => $node_power_ok,
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ((not $an->data->{scancore}{disable}{load_shedding}) && ($both_nodes_online))
		{
			# WARNING: We can't use 'quote' to protect the 'scancore::power::load_shed_delay' 
			#          value so we must check that it is set and purely digits. '0' is OK, it 
			#          just means that we'll shed-load without delay.
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "scancore::power::load_shed_delay", value1 => $an->data->{scancore}{power}{load_shed_delay},
			}, file => $THIS_FILE, line => __LINE__});
			if ($an->data->{scancore}{power}{load_shed_delay} eq "")
			{
				$an->data->{scancore}{power}{load_shed_delay} = 300;
				$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
					name1 => "scancore::power::load_shed_delay", value1 => $an->data->{scancore}{power}{load_shed_delay},
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($an->data->{scancore}{power}{load_shed_delay} =~ /\D/)
			{
				$an->data->{scancore}{power}{load_shed_delay} = 300;
				$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
					name1 => "scancore::power::load_shed_delay", value1 => $an->data->{scancore}{power}{load_shed_delay},
				}, file => $THIS_FILE, line => __LINE__});
			}
			
			# Is it time to load-shed? No results == No.
			my $shed_load = 1;
			my $query     = "
SELECT 
    power_on_battery, 
    modified_date 
FROM 
    history.power 
WHERE 
    power_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{host_uuid})."
AND 
    modified_date > (SELECT current_timestamp - interval '".$an->data->{scancore}{power}{load_shed_delay}." seconds') 
ORDER BY 
    modified_date DESC;
";
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "query", value1 => $query
			}, file => $THIS_FILE, line => __LINE__});
			
			my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
			my $count   = @{$results};
			$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
				name1 => "results", value1 => $results, 
				name2 => "count",   value2 => $count,
			}, file => $THIS_FILE, line => __LINE__});
			### TODO: There should be about 5+ entries (7~9 usually) if things have been running 
			###       normally. It might be worth NOT deciding to shed load unless we've got >5
			###       results... Something to think about and decide on later. For now, we'll not
			###       check the results count.
			if ($count < 1)
			{
				$shed_load = 0;
				$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
					name1 => "shed_load", value1 => $shed_load, 
				}, file => $THIS_FILE, line => __LINE__});
			}
			else
			{
				# We will disable shed load if any of these results show 'power_on_battery' 
				# as 'TRUE'.
				foreach my $row (@{$results})
				{
					# One or more records were found.
					my $power_on_battery = $row->[0]; 
					my $modified_date    = $row->[1]; 
					$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
						name1 => "power_on_battery", value1 => $power_on_battery, 
						name2 => "modified_date",    value2 => $modified_date, 
					}, file => $THIS_FILE, line => __LINE__});
					
					if ($power_on_battery eq "0")
					{
						# Nope.
						$shed_load = 0;
						$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
							name1 => "shed_load", value1 => $shed_load, 
						}, file => $THIS_FILE, line => __LINE__});
					}
				}
			}
			
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "shed_load", value1 => $shed_load, 
			}, file => $THIS_FILE, line => __LINE__});
			if ($shed_load)
			{
				$node_power_ok = 4;
				$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
					name1 => "node_power_ok", value1 => $node_power_ok, 
				}, file => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	# Returns;
	# 1 = At least one of the UPSes has power
	# 2 = Neither do but the hold-up time of at least one is above minimum
	# 3 = Both are on batteries and below the minimum hold-up time 
	# 4 = Both are on batteries and have been long enough to trigger load shedding (and load shedding 
	#     is not disabled)
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "node_power_ok", value1 => $node_power_ok,
	}, file => $THIS_FILE, line => __LINE__});
	return ($node_power_ok);
}

### NOTE: This is only called by nodes.
# This pulls the data on the various temperature sensors. If all are within acceptible ranges, '1' will be 
# returned. If any are in warning or critical state, '2' will be returned. If enough are critical to trigger 
# power-down, '3' will be returned. If enough are in warning and/or critical that, had they all been 
# critical, load shedding would have been triggered, 'sys::node::<node_name>::thermal_load_shed' is set to 
# '1'. If the peer is also set to '1' and both us and the peer have been set for more than 
# 'scancore::temperature::load_shed_delay' seconds, '4' will be returned, triggering a load-shed.
sub check_local_temperature_health
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	$an->Log->entry({log_level => 2, title_key => "tools_log_0001", title_variables => { function => "check_local_temperature_health" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	# 1 == OK, 
	# 2 == Warning, 
	# 3 == Critical (should shut down), 
	# 4 == Warning:load_shed (if peer is also).
	my $node_temperature_ok           = 1;
	my $default_sensor_weight         = $an->data->{scancore}{temperature}{default_sensor_weight} ? $an->data->{scancore}{temperature}{default_sensor_weight} : 1;
	my $shutdown_threshold            = $an->data->{scancore}{temperature}{shutdown_limit}        ? $an->data->{scancore}{temperature}{shutdown_limit}        : 5;
	my $warning_sensor_weight         = 0;
	my $critical_sensor_weight        = 0;
	my $my_thermal_load_shed_variable = "sys::node::".$an->hostname."::thermal_load_shed";
	
	# Read in the temperature values for this machine.
	$an->Log->entry({log_level => 2, message_key => "an_variables_0006", message_variables => {
		name1 => "node_temperature_ok",           value1 => $node_temperature_ok,
		name2 => "default_sensor_weight",         value2 => $default_sensor_weight,
		name3 => "shutdown_threshold",            value3 => $shutdown_threshold,
		name4 => "warning_sensor_weight",         value4 => $warning_sensor_weight,
		name5 => "critical_sensor_weight",        value5 => $critical_sensor_weight,
		name6 => "my_thermal_load_shed_variable", value6 => $my_thermal_load_shed_variable,
	}, file => $THIS_FILE, line => __LINE__});
	
	# Pull in all the thermal sensors for this host.
	my $query = "
SELECT 
    temperature_agent_name, 
    temperature_sensor_name, 
    temperature_state 
FROM 
    temperature 
WHERE 
    temperature_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{host_uuid})." 
AND 
    temperature_sensor_host = ".$an->data->{sys}{use_db_fh}->quote($an->hostname)."
;";
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
	
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "results", value1 => $results
	}, file => $THIS_FILE, line => __LINE__});
	
	# If there are no results, then mark power as always OK because #yolo
	my $sensor_count = @{$results};
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "sensor_count", value1 => $sensor_count
	}, file => $THIS_FILE, line => __LINE__});
	if (not $sensor_count)
	{
		# No sensors are high, we're done.
		my $variable_uuid = $an->ScanCore->insert_or_update_variables({
			variable_name         => $my_thermal_load_shed_variable,
			variable_value        => "0",
			variable_source_uuid  => $an->data->{sys}{host_uuid}, 
			variable_source_table => "hosts", 
			update_value_only     => 1,
		});
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "variable_uuid", value1 => $variable_uuid, 
		}, file => $THIS_FILE, line => __LINE__});
		return($node_temperature_ok);
	}
	
	# One or more records were found.
	foreach my $row (@{$results})
	{
		my $temperature_agent_name  = $row->[0];
		my $temperature_sensor_name = $row->[1];
		my $temperature_state       = $row->[2];
		$an->Log->entry({log_level => 2, message_key => "an_variables_0003", message_variables => {
			name1 => "temperature_agent_name",  value1 => $temperature_agent_name,
			name2 => "temperature_sensor_name", value2 => $temperature_sensor_name,
			name3 => "temperature_state",       value3 => $temperature_state,
		}, file => $THIS_FILE, line => __LINE__});
		
		# If this is a sensor that is 'ok', skip it. Otherwise, we'll set the 'node_temperature_ok' 
		# to '2' (which may get set to '3' after these checks are done.
		next if $temperature_state eq "ok";
		$node_temperature_ok = 2;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "node_temperature_ok", value1 => $node_temperature_ok,
		}, file => $THIS_FILE, line => __LINE__});
		
		# If it is critical, find this sensor's weight and add it to the total.
		my $this_sensor_weight = $default_sensor_weight;
		
		# Get the weight of the sensor.
		$an->Log->entry({log_level => 2, message_key => "an_variables_0004", message_variables => {
			name1 => "this_sensor_weight",                                                        value1 => $this_sensor_weight,
			name2 => "warning_sensor_weight",                                                     value2 => $warning_sensor_weight, 
			name3 => "critical_sensor_weight",                                                    value3 => $critical_sensor_weight, 
			name4 => "${temperature_agent_name}::thresholds::${temperature_sensor_name}::weight", value4 => $an->data->{$temperature_agent_name}{thresholds}{$temperature_sensor_name}{weight},
		}, file => $THIS_FILE, line => __LINE__});
		if ($an->data->{$temperature_agent_name}{thresholds}{$temperature_sensor_name}{weight})
		{
			$this_sensor_weight = $an->data->{$temperature_agent_name}{thresholds}{$temperature_sensor_name}{weight};
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "this_sensor_weight", value1 => $this_sensor_weight,
			}, file => $THIS_FILE, line => __LINE__});
		}
		
		# If we have enough sensors in a warning (or critcial) state to cross the heuristics for 
		# shutdown (had they all been critical), we will set our health to 'warning:load_shed' and
		# return '4'. If our peer is also 'warning:load_shed', then we'll shed load.
		$warning_sensor_weight += $this_sensor_weight;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "warning_sensor_weight", value1 => $warning_sensor_weight,
		}, file => $THIS_FILE, line => __LINE__});
		
		# If the sensor is critical, add it's weight to the critical weight
		if ($temperature_state =~ /critical/)
		{
			$critical_sensor_weight += $this_sensor_weight;
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "critical_sensor_weight", value1 => $critical_sensor_weight,
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	# If we've crossed the critical heauristic, we're dead. Otherwise, check to see if we're high enough
	# to set the 'warning:load_shed'.
	my $evaluate_load_shed = 0;
	$an->Log->entry({log_level => 2, message_key => "an_variables_0003", message_variables => {
		name1 => "warning_sensor_weight",  value1 => $warning_sensor_weight,
		name2 => "critical_sensor_weight", value2 => $critical_sensor_weight,
		name3 => "shutdown_threshold",     value3 => $shutdown_threshold,
	}, file => $THIS_FILE, line => __LINE__});
	if ($critical_sensor_weight > $shutdown_threshold)
	{
		$node_temperature_ok = 3;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "node_temperature_ok", value1 => $node_temperature_ok,
		}, file => $THIS_FILE, line => __LINE__});
	}
	elsif ($warning_sensor_weight > $shutdown_threshold)
	{
		$evaluate_load_shed = 1;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "evaluate_load_shed", value1 => $evaluate_load_shed,
		}, file => $THIS_FILE, line => __LINE__});
		
		# Set the health to 'warning:load_shed'.
		$an->ScanCore->host_state({set => "warning:load_shed"});
	}
	
	# If we recently booted, don't shed load (to give a just-rebooted node time for a human to do 
	# something).
	my $uptime_delay = $an->data->{sys}{load_shed}{uptime_delay};
	my $uptime       = $an->System->get_uptime();
	$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
		name1 => "uptime",       value1 => $uptime,
		name2 => "uptime_delay", value2 => $uptime_delay,
	}, file => $THIS_FILE, line => __LINE__});
	if ($uptime < $uptime_delay)
	{
		$evaluate_load_shed = 0;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "evaluate_load_shed", value1 => $evaluate_load_shed,
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	# Set or clear the load_shed variable. If we need to set, also check the peer and see if we and they 
	# have been in this high-warning state for long enough to trigger a laod shed.
	if ($evaluate_load_shed)
	{
		# Set my value to 1, if not already set.
		my $shed_load     = 1;
		my $variable_uuid = $an->ScanCore->insert_or_update_variables({
			variable_name         => $my_thermal_load_shed_variable,
			variable_value        => "1",
			variable_source_uuid  => $an->data->{sys}{host_uuid}, 
			variable_source_table => "hosts", 
			update_value_only     => 1,
		});
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "variable_uuid", value1 => $variable_uuid, 
		}, file => $THIS_FILE, line => __LINE__});
		
		# Make sure both nodes are online. Otherwise, we'll not load shed anyway and might as well 
		# stop here.
		my $both_nodes_online = 1;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "both_nodes_online", value1 => $both_nodes_online,
		}, file => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
			name1 => "sys::anvil::node1::online", value1 => $an->data->{sys}{anvil}{node1}{online},
			name2 => "sys::anvil::node2::online", value2 => $an->data->{sys}{anvil}{node2}{online},
		}, file => $THIS_FILE, line => __LINE__});
		if ((not $an->data->{sys}{anvil}{node1}{online}) or (not $an->data->{sys}{anvil}{node2}{online}))
		{
			# Disable load shedding because our peer is dead.
			$both_nodes_online  = 0;
			$evaluate_load_shed = 0;
			$shed_load          = 0;
			$an->Log->entry({log_level => 2, message_key => "an_variables_0003", message_variables => {
				name1 => "both_nodes_online",  value1 => $both_nodes_online,
				name2 => "evaluate_load_shed", value2 => $evaluate_load_shed,
				name3 => "shed_load",          value3 => $shed_load,
			}, file => $THIS_FILE, line => __LINE__});
		}
		
		# If both nodes are up and the user has not disabled load shedding, proceed.
		if ((not $an->data->{scancore}{disable}{load_shedding}) && ($both_nodes_online))
		{
			# WARNING: We can't use 'quote' to protect the 'scancore::temperature::load_shed_delay' 
			#          value so we must check that it is set and purely digits. '0' is OK, it 
			#          just means that we'll shed-load without delay.
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "scancore::temperature::load_shed_delay", value1 => $an->data->{scancore}{temperature}{load_shed_delay},
			}, file => $THIS_FILE, line => __LINE__});
			if ($an->data->{scancore}{temperature}{load_shed_delay} eq "")
			{
				$an->data->{scancore}{temperature}{load_shed_delay} = 300;
				$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
					name1 => "scancore::temperature::load_shed_delay", value1 => $an->data->{scancore}{temperature}{load_shed_delay},
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($an->data->{scancore}{temperature}{load_shed_delay} =~ /\D/)
			{
				$an->data->{scancore}{temperature}{load_shed_delay} = 300;
				$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
					name1 => "scancore::temperature::load_shed_delay", value1 => $an->data->{scancore}{temperature}{load_shed_delay},
				}, file => $THIS_FILE, line => __LINE__});
			}
			
			# Now check to see if we and the peer are both in high enough warning long enough to 
			# justify load shedding.
			my $my_host_uuid = $an->data->{sys}{host_uuid};
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "my_host_uuid", value1 => $my_host_uuid,
			}, file => $THIS_FILE, line => __LINE__});
			
			my $peer_host_uuid = "";
			my $peer_host_name = "";
			foreach my $node_key ("node1", "node2")
			{
				$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
					name1 => "sys::anvil::${node_key}::host_uuid", value1 => $an->data->{sys}{anvil}{$node_key}{host_uuid},
					name2 => "sys::host_uuid",                     value2 => $an->data->{sys}{host_uuid},
				}, file => $THIS_FILE, line => __LINE__});
				next if $an->data->{sys}{anvil}{$node_key}{host_uuid} eq $an->data->{sys}{host_uuid};
				
				
				$peer_host_name = $an->data->{sys}{anvil}{$node_key}{name};
				$peer_host_uuid = $an->data->{sys}{anvil}{$node_key}{host_uuid};
				$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
					name1 => "peer_host_name", value1 => $peer_host_name,
					name2 => "peer_host_uuid", value2 => $peer_host_uuid,
				}, file => $THIS_FILE, line => __LINE__});
				last;
			}
			
			# If I didn't find the peer's UUID, I Have a problem and I can not proceed.
			if (not $peer_host_uuid)
			{
				$an->Log->entry({log_level => 0, title_key => "tools_title_0002", message_key => "scancore_warning_0028", file => $THIS_FILE, line => __LINE__});
			}
			else
			{
				my $peer_thermal_load_shed_variable = "sys::node::".$peer_host_name."::thermal_load_shed";
				$an->Log->entry({log_level => 2, message_key => "an_variables_0004", message_variables => {
					name1 => "my_thermal_load_shed_variable",   value1 => $my_thermal_load_shed_variable,
					name2 => "sys::host_uuid",                  value2 => $an->data->{sys}{host_uuid},
					name3 => "peer_thermal_load_shed_variable", value3 => $peer_thermal_load_shed_variable,
					name4 => "peer_host_uuid",                  value4 => $peer_host_uuid,
				}, file => $THIS_FILE, line => __LINE__});
				
				my $my_shed_load   = $an->ScanCore->check_load_shed_variable({
					thermal_load_shed_variable => $my_thermal_load_shed_variable,
					host_uuid => $an->data->{sys}{host_uuid}
				});
				my $peer_shed_load = $an->ScanCore->check_load_shed_variable({
					thermal_load_shed_variable => $peer_thermal_load_shed_variable,
					host_uuid => $peer_host_uuid
				});
				$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
					name1 => "my_shed_load",   value1 => $my_shed_load,
					name2 => "peer_shed_load", value2 => $peer_shed_load,
				}, file => $THIS_FILE, line => __LINE__});
				
				if ((not $my_shed_load) or (not $peer_shed_load))
				{
					$shed_load = 0;
					$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
						name1 => "shed_load", value1 => $shed_load, 
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
		}
		
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "shed_load", value1 => $shed_load, 
		}, file => $THIS_FILE, line => __LINE__});
		if ($shed_load)
		{
			# OK, we're clear for load shed.
			$node_temperature_ok = 4;
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "node_temperature_ok", value1 => $node_temperature_ok,
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	else
	{
		# Clear (if needed)
		my $variable_uuid = $an->ScanCore->insert_or_update_variables({
			variable_name         => $my_thermal_load_shed_variable,
			variable_value        => "0",
			variable_source_uuid  => $an->data->{sys}{host_uuid}, 
			variable_source_table => "hosts", 
			update_value_only     => 1,
		});
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "variable_uuid", value1 => $variable_uuid, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "node_temperature_ok", value1 => $node_temperature_ok,
	}, file => $THIS_FILE, line => __LINE__});
	return($node_temperature_ok);
}

# This takes a variable key and checks to see if there is a record older than 
# 'scancore::temperature::load_shed_delay' and that it is not '0'. It then looks for younger records. If the 
# older record doesn't exist, is a '0' or if any younger records are a '0', this method will return '0' 
# (aborting the load shed).
sub check_load_shed_variable
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	my $thermal_load_shed_variable = $parameter->{thermal_load_shed_variable} ? $parameter->{thermal_load_shed_variable} : "";
	my $host_uuid = $parameter->{host_uuid} ? $parameter->{host_uuid} : "";

	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "check_load_shed_variable" }, message_key => "an_variables_0002", message_variables => { 
		name1 => "thermal_load_shed_variable", value1 => $thermal_load_shed_variable, 
		name2 => "host_uuid",                  value2 => $host_uuid, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $shed_load = 1;
	### NOTE: I need to check two things here; Is there at least one load shed variable older than 
	###       load_shed_delay and, if so, what was it last set to? Second, are there any younger than 
	###       that set to '0'? We need to know that at least one former record existed (could be the one
	###       we set when we just recently went hot) so that we know a singular return value of '1' 
	###       wasn't just set.
	
	# So first; do I have any records older than 'scancore::temperature::load_shed_delay'?
	my $query = "
SELECT 
    variable_value, 
    modified_date, 
    (SELECT floor(extract(epoch from now())) - floor(extract(epoch from modified_date))) 
FROM 
    history.variables 
WHERE 
    variable_name         = ".$an->data->{sys}{use_db_fh}->quote($thermal_load_shed_variable)."
AND 
    variable_source_uuid  = ".$an->data->{sys}{use_db_fh}->quote($host_uuid)."
AND 
    variable_source_table = 'hosts' 
AND 
    floor(extract(epoch from modified_date)) < (SELECT floor(extract(epoch from now())) - ".$an->data->{scancore}{temperature}{load_shed_delay}.")
ORDER BY modified_date DESC 
LIMIT 1;
;";
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1  => "query", value1 => $query, 
	}, file => $THIS_FILE, line => __LINE__});
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count,
	}, file => $THIS_FILE, line => __LINE__});
	if ($count < 1)
	{
		# There are no old load_shed records...
		$shed_load = 0;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "shed_load", value1 => $shed_load, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# There should only be one row...
		foreach my $row (@{$results})
		{
			# Get the most recent old value
			my $therman_load_shed = $row->[0]; 
			my $modified_date     = $row->[1]; 
			my $record_age        = $row->[2];
			$an->Log->entry({log_level => 2, message_key => "an_variables_0003", message_variables => {
				name1 => "therman_load_shed", value1 => $therman_load_shed, 
				name2 => "modified_date",     value2 => $modified_date, 
				name3 => "record_age",        value3 => $record_age, 
			}, file => $THIS_FILE, line => __LINE__});
			if (not $therman_load_shed)
			{
				# The most recent old record is set to not load shed, so it's
				# not the record we just set when we recently went hot.
				$shed_load = 0;
				$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
					name1 => "shed_load", value1 => $shed_load, 
				}, file => $THIS_FILE, line => __LINE__});
			}
			last;
		}
	}
	
	# Check newer records, if I haven't given up already
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "shed_load", value1 => $shed_load, 
	}, file => $THIS_FILE, line => __LINE__});
	if ($shed_load)
	{
		# We will disable shed load if any of these results are '0'.
		my $query = "
SELECT 
    variable_value, 
    modified_date, 
    (SELECT floor(extract(epoch from now())) - floor(extract(epoch from modified_date))) 
FROM 
    history.variables 
WHERE 
    variable_name         = ".$an->data->{sys}{use_db_fh}->quote($thermal_load_shed_variable)." 
AND 
    variable_source_uuid  = ".$an->data->{sys}{use_db_fh}->quote($host_uuid)." 
AND 
    variable_source_table = 'hosts' 
AND 
    floor(extract(epoch from modified_date)) > (SELECT floor(extract(epoch from now())) - ".$an->data->{scancore}{temperature}{load_shed_delay}.") 
ORDER BY modified_date DESC;
;";
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query
		}, file => $THIS_FILE, line => __LINE__});
		
		my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
			name1 => "results", value1 => $results, 
			name2 => "count",   value2 => $count,
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $row (@{$results})
		{
			# One or more records were found.
			my $therman_load_shed = $row->[0]; 
			my $modified_date     = $row->[1]; 
			my $record_age        = $row->[2]; 
			$an->Log->entry({log_level => 2, message_key => "an_variables_0003", message_variables => {
				name1 => "therman_load_shed", value1 => $therman_load_shed, 
				name2 => "modified_date",     value2 => $modified_date, 
				name3 => "record_age",        value3 => $record_age, 
			}, file => $THIS_FILE, line => __LINE__});
			
			if (not $therman_load_shed)
			{
				$shed_load = 0;
				$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
					name1 => "shed_load", value1 => $shed_load, 
				}, file => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "shed_load", value1 => $shed_load, 
	}, file => $THIS_FILE, line => __LINE__});
	return($shed_load);
}

### TODO: If server waffling becomes a problem, we'll want to record when we do a precautionary migration and
###       then, here, check to see when the last precautionary migration happened and NOT migrate again 
###       within some set time.
# This pulls all of the health entries for this node and the peer node, sums them and determines if this node
# is equal in health, sicker or healthier.
sub check_node_health
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	$an->Log->entry({log_level => 2, title_key => "tools_log_0001", title_variables => { function => "check_node_health" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	my $node_health_ok     = 1;
	my $my_health_weight   = 0;
	my $peer_health_weight = 0;
	my $node_name          = $an->hostname;
	my $node_key           = $an->data->{sys}{node_name}{$node_name}{node_key};
	my $peer_key           = $an->data->{sys}{node_name}{$node_name}{peer_node_key};
	my $peer_name          = $an->data->{sys}{anvil}{$peer_key}{name};
	my $node_info          = $an->Get->node_info({node_name => $peer_name});
	my $peer_host_uuid     = $node_info->{host_uuid};
	my $peer_node_uuid     = $an->data->{sys}{anvil}{$peer_key}{uuid};	# This is the node ID
	my $peer_online        = $an->data->{sys}{anvil}{$node_key}{online};
	$an->Log->entry({log_level => 2, message_key => "an_variables_0007", message_variables => {
		name1 => "node_name",      value1 => $node_name, 
		name2 => "node_key",       value2 => $node_key, 
		name3 => "peer_key",       value3 => $peer_key, 
		name4 => "peer_name",      value4 => $peer_name, 
		name5 => "peer_host_uuid", value5 => $peer_host_uuid, 
		name6 => "peer_node_uuid", value6 => $peer_node_uuid, 
		name7 => "peer_online",    value7 => $peer_online, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# If the peer isn't online, there is no sense summing weights.
	if (not $peer_online)
	{
		$node_health_ok = 2;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "node_health_ok", value1 => $node_health_ok, 
		}, file => $THIS_FILE, line => __LINE__});
		return($node_health_ok);
	}
	
	# Read and sum my health weights. The agent and source name is for logging purposes only.
	my $query = "
SELECT 
    health_agent_name, 
    health_source_name, 
    health_source_weight 
FROM 
    health 
WHERE 
    health_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{host_uuid})."
;";
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
		
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "results", value1 => $results
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		my $health_agent_name    = $row->[0]; 
		my $health_source_name   = $row->[1]; 
		my $health_source_weight = $row->[2];
		$an->Log->entry({log_level => 2, message_key => "an_variables_0003", message_variables => {
			name1 => "health_agent_name",    value1 => $health_agent_name, 
			name2 => "health_source_name",   value2 => $health_source_name, 
			name3 => "health_source_weight", value3 => $health_source_weight, 
		}, file => $THIS_FILE, line => __LINE__});
		
		$my_health_weight += $health_source_weight;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "my_health_weight", value1 => $my_health_weight, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	# Read in my peer's health.
	$query = "
SELECT 
    health_agent_name, 
    health_source_name, 
    health_source_weight 
FROM 
    health 
WHERE 
    health_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($peer_host_uuid)."
;";
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query
	}, file => $THIS_FILE, line => __LINE__});
		
	$results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "results", value1 => $results
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		my $health_agent_name    = $row->[0]; 
		my $health_source_name   = $row->[1]; 
		my $health_source_weight = $row->[2];
		$an->Log->entry({log_level => 2, message_key => "an_variables_0003", message_variables => {
			name1 => "health_agent_name",    value1 => $health_agent_name, 
			name2 => "health_source_name",   value2 => $health_source_name, 
			name3 => "health_source_weight", value3 => $health_source_weight, 
		}, file => $THIS_FILE, line => __LINE__});
		
		$peer_health_weight += $health_source_weight;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "peer_health_weight", value1 => $peer_health_weight, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	# If I am healthier, I will check/set 'health_triggered_migration' with the current time stamp. If
	# the health is equal or worse, we will clear this if it was set. If we're healthier, we will return
	# '2' (requesting a migration) once this variable is older than 'scancore::health::migration_delay'.
	my $variable_name  = "health_triggered_migration";
	my ($went_sick_time, $variable_uuid, $modified_date) = $an->ScanCore->read_variable({
			variable_name         => $variable_name,
			variable_source_uuid  => $an->data->{sys}{host_uuid},
			variable_source_table => "hosts",
		});
	$an->Log->entry({log_level => 2, message_key => "an_variables_0005", message_variables => {
		name1 => "variable_name",   value1 => $variable_name, 
		name2 => "sys::host_uuid",  value2 => $an->data->{sys}{host_uuid}, 
		name3 => "went_sick_time",  value3 => $went_sick_time, 
		name4 => "variable_uuid",   value4 => $variable_uuid, 
		name5 => "modified_date",   value5 => $modified_date, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# NOTE: We don't check the readiness of the peer to because 'anvil-migrate-server' has the health 
	#       check logic and will refuse to  migrate if the peer isn't healthy, regardless of what we do 
	#       here (and no, we will NOT use '--force'. We want this behaviour).
	$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
		name1 => "my_health_weight",   value1 => $my_health_weight, 
		name2 => "peer_health_weight", value2 => $peer_health_weight, 
	}, file => $THIS_FILE, line => __LINE__});
	if ($my_health_weight < $peer_health_weight)
	{
		# We're healthier. Before we set '2' though, see how long we've been healthier. We don't 
		# want to migrate until we've been healthier for at least a few minutes.
		my $current_time  = time;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "current_time",  value1 => $current_time, 
		}, file => $THIS_FILE, line => __LINE__});
		if (not $went_sick_time)
		{
			# First time we've gone healthier
			my $variable_uuid = $an->ScanCore->insert_or_update_variables({
				variable_name         => $variable_name,
				variable_value        => $current_time,
				variable_source_uuid  => $an->data->{sys}{host_uuid}, 
				variable_source_table => "hosts", 
				update_value_only     => 1,
			});
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "variable_uuid", value1 => $variable_uuid, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		else
		{
			# Already went sick. How long ago?
			my $migration_delay = $an->data->{scancore}{health}{migration_delay};
			my $migration_time  = $went_sick_time + $migration_delay;
			my $difference      = $migration_time - $current_time;
			$an->Log->entry({log_level => 2, message_key => "an_variables_0003", message_variables => {
				name1 => "migration_delay", value1 => $migration_delay, 
				name2 => "migration_time",  value2 => $migration_time, 
				name3 => "difference",      value3 => $difference, 
			}, file => $THIS_FILE, line => __LINE__});
			
			if ($current_time >=  $migration_time)
			{
				# Time to migrate!
				$node_health_ok = 2;
				$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
					name1 => "node_health_ok", value1 => $node_health_ok, 
				}, file => $THIS_FILE, line => __LINE__});
			}
		}
	}
	elsif ($my_health_weight > $peer_health_weight)
	{
		# We're sicker.
		$node_health_ok = 3;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "node_health_ok", value1 => $node_health_ok, 
		}, file => $THIS_FILE, line => __LINE__});
		
		# If we used to be healthier, clear our 'went_sick_time'.
		if ($went_sick_time)
		{
			# We're the same health but 'health_triggered_migration'is set, so clear it.
			my $variable_uuid = $an->ScanCore->insert_or_update_variables({
				variable_name         => $variable_name,
				variable_value        => "0",
				variable_source_uuid  => $an->data->{sys}{host_uuid}, 
				variable_source_table => "hosts", 
				update_value_only     => 1,
			});
		}
	}
	elsif ($went_sick_time)
	{
		# We're the same health but 'health_triggered_migration'is set, so clear it.
		my $variable_uuid = $an->ScanCore->insert_or_update_variables({
			variable_name         => $variable_name,
			variable_value        => "0",
			variable_source_uuid  => $an->data->{sys}{host_uuid}, 
			variable_source_table => "hosts", 
			update_value_only     => 1,
		});
	}
	
	# Values are:
	# 1 = Both nodes have the same health.
	# 2 = We're healther than our peer (migrate)
	# 3 = We're sicker than our peer (do nothing)
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "node_health_ok", value1 => $node_health_ok, 
	}, file => $THIS_FILE, line => __LINE__});
	return($node_health_ok);
}

### NOTE: This is only called by nodes.
# This finds all servers currently running on the peer and migrates them to this node.
sub migrate_all_servers_to_here
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	$an->Log->entry({log_level => 2, title_key => "tools_log_0001", title_variables => { function => "migrate_all_servers_to_here" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	# If the user has disabled auto-migration, exit now.
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "scancore::disable::preventative_migration", value1 => $an->data->{scancore}{disable}{preventative_migration}, 
	}, file => $THIS_FILE, line => __LINE__});
	if ($an->data->{scancore}{disable}{preventative_migration})
	{
		return(1);
	}
	
	# Who is my peer again?
	my $node_name = $an->hostname;
	my $peer_key  = $an->data->{sys}{node_name}{$node_name}{peer_node_key};
	my $peer_name = $an->data->{sys}{anvil}{$peer_key}{name};
	$an->Log->entry({log_level => 2, message_key => "an_variables_0003", message_variables => {
		name1 => "node_name", value1 => $node_name, 
		name2 => "peer_key",  value2 => $peer_key, 
		name3 => "peer_name", value3 => $peer_name, 
	}, file => $THIS_FILE, line => __LINE__});
	
	### NOTE: We DO NOT migrate directly! We will use 'anvil-migrate-server' because we WANT it to abort
	###       if needed.
	
	# Find the servers running on our peer. We'll call 'clustat' here to be sure we have the most current
	# view of system.
	my $to_migrate = [];
	my $shell_call = $an->data->{path}{clustat};
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "shell_call", value1 => $shell_call, 
	}, file => $THIS_FILE, line => __LINE__});
	open (my $file_handle, $shell_call." 2>&1 |") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0014", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
	while(<$file_handle>)
	{
		chomp;
		my $line =  $_;
		   $line =~ s/\s+/ /g;
		   $line =~ s/^\s+//;
		   $line =~ s/\s+$//;
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "line", value1 => $line, 
		}, file => $THIS_FILE, line => __LINE__});
		
		if ($line =~ /^vm:(.*?) (.*?) (.*)/)
		{
			my $server = $1;
			my $host   = $2;
			my $state  = $3;
			$an->Log->entry({log_level => 2, message_key => "an_variables_0003", message_variables => {
				name1 => "server", value1 => $server, 
				name2 => "host",   value2 => $host, 
				name3 => "state",  value3 => $state, 
			}, file => $THIS_FILE, line => __LINE__});
			
			if (($host eq $peer_name) && ($state eq "started"))
			{
				# Migrate it.
				push @{$to_migrate}, $server;
			}
		}
	}
	close $file_handle;
	
	# Well?
	my $return = 0;
	if (@{$to_migrate} > 0)
	{
		# Tell the user what we're doing.
		$an->Alert->register_alert({
			alert_level		=>	"warning", 
			alert_agent_name	=>	$THIS_FILE,
			alert_title_key		=>	"an_alert_title_0004",
			alert_message_key	=>	"scancore_warning_0001",
			alert_message_variables	=>	{
				host_name		=>	$an->hostname,
				peer_name		=>	$peer_name,
			},
		});
		
		# Send the email
		$an->ScanCore->process_alerts();
		
		# Migrate!
		foreach my $server (sort {$a cmp $b} @{$to_migrate})
		{
			my $shell_call = $an->data->{path}{'anvil-migrate-server'}." --server $server; ".$an->data->{path}{'echo'}." return_code:\$?";
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "shell_call", value1 => $shell_call, 
			}, file => $THIS_FILE, line => __LINE__});
			open (my $file_handle, $shell_call." 2>&1 |") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0014", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
			while(<$file_handle>)
			{
				chomp;
				my $line = $_;
				$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
					name1 => "line", value1 => $line, 
				}, file => $THIS_FILE, line => __LINE__});
				if ($line =~ /return_code:(\d+)$/)
				{
					$return = $1;
					$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
						name1 => "return", value1 => $return,
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			close $file_handle;
		}
		
		# All done
		$an->Alert->register_alert({
			alert_level		=>	"warning", 
			alert_agent_name	=>	$THIS_FILE,
			alert_title_key		=>	"an_alert_title_0006",
			alert_message_key	=>	"scancore_warning_0002",
			alert_message_variables	=>	{
				host_name		=>	$an->hostname,
				peer_name		=>	$peer_name,
			},
		});
	}
	
	### TODO: Update cluster.conf to set this node as the node with the 'delay' (or have scan-clustat 
	###       do it).
	
	return($return);
}

# This tries to log into each node 
sub check_for_dlm_hang
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	my $node = $parameter->{node};

	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "check_for_dlm_hang" }, message_key => "an_variables_0001", message_variables => { 
		name1 => "node", value1 => $node,
	}, file => $THIS_FILE, line => __LINE__});
	
	# We'll only act on nodes that we have the ability to fence.
	my $reboot = 0;
	### NOTE: This exposes the password.
	my $power_check_command = $an->data->{cache}{$node}{info}{power_check_command};
	$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
		name1 => "power_check_command", value1 => $power_check_command, 
	}, file => $THIS_FILE, line => __LINE__});
	if ($power_check_command)
	{
		# First, can we access it?
		my $node_info = $an->Get->node_info({node_name => $node});
		my $target    = $node_info->{use_ip};
		my $port      = $node_info->{use_port};
		my $password  = $node_info->{password};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "target", value1 => $target,
			name2 => "port",   value2 => $port,
		}, file => $THIS_FILE, line => __LINE__});
		$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
			name1 => "password", value1 => $password,
		}, file => $THIS_FILE, line => __LINE__});
		
		my $access = $an->Check->access({
			target		=>	$target,
			port		=>	$port,
			password	=>	$password,
		});
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "access", value1 => $access,
		}, file => $THIS_FILE, line => __LINE__});
		
		if ($access)
		{
			### TODO: Make this a lot more graceful...
			# If we're dashboard 2 (or higher), add time to the timeout to make sure we don't try
			# to kill the node at the exact same time as dashboard 1.
			if ($an->hostname() =~ /2$/)
			{
				$an->data->{scancore}{dashboard}{dlm_hung_timeout} += 10;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "scancore::dashboard::dlm_hung_timeout", value1 => $an->data->{scancore}{dashboard}{dlm_hung_timeout},
				}, file => $THIS_FILE, line => __LINE__});
			}
			if ($an->hostname() =~ /3$/)
			{
				$an->data->{scancore}{dashboard}{dlm_hung_timeout} += 20;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "scancore::dashboard::dlm_hung_timeout", value1 => $an->data->{scancore}{dashboard}{dlm_hung_timeout},
				}, file => $THIS_FILE, line => __LINE__});
			}
			if ($an->hostname() =~ /4$/)
			{
				$an->data->{scancore}{dashboard}{dlm_hung_timeout} += 30;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "scancore::dashboard::dlm_hung_timeout", value1 => $an->data->{scancore}{dashboard}{dlm_hung_timeout},
				}, file => $THIS_FILE, line => __LINE__});
			}
			
			# We can log in, so call 'timeout X ls /shared'
			my $shell_call = "
if [ -e '".$an->data->{path}{shared}." ];
then
    ".$an->data->{path}{timeout}." ".$an->data->{scancore}{dashboard}{dlm_hung_timeout}." ".$an->data->{path}{ls}." ".$an->data->{path}{shared}." || ".$an->data->{path}{echo}." timeout
else
    ".$an->data->{path}{echo}." 'does not exist'
fi
";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "shell_call", value1 => $shell_call,
				name2 => "target",     value2 => $node,
			}, file => $THIS_FILE, line => __LINE__});
			my ($error, $ssh_fh, $return) = $an->Remote->remote_call({
				target		=>	$target,
				port		=>	$port,
				password	=>	$password,
				'close'		=>	1,
				shell_call	=>	$shell_call,
			});
			foreach my $line (@{$return})
			{
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "line", value1 => $line, 
				}, file => $THIS_FILE, line => __LINE__});
				if ($line eq "timeout")
				{
					# No good... fence it
					$reboot = 1;
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "reboot", value1 => $reboot, 
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
		}
	}
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "reboot", value1 => $reboot, 
	}, file => $THIS_FILE, line => __LINE__});
	return($reboot);
}

# This reboots a node (ie: that may be hung)
sub reboot_node
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	my $node_uuid = $parameter->{node_uuid};

	my $query = "
SELECT
	host_uuid,
	host_name,
	node_uuid
FROM
	hosts a,
	nodes b
WHERE
	a.host_uuid = b.node_host_uuid
AND
	a.node_uuid = ".$an->data->{sys}{use_db_fh}->quote($node_uuid)."
;
";
	# There should only be 1 record
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $host_uuid = $results->[0]->[0];
	my $host_name = $results->[0]->[1];

	$an->Log->entry({log_level => 2, title_key => "tools_log_0001", title_variables => { function => "reboot_node" }, message_key => "an_variables_0003", message_variables => { 
		name1 => "host_name", value1 => $host_name, 
		name2 => "host_uuid", value2 => $host_uuid,
		name3 => "node_uuid", value3 => $node_uuid,
	}, file => $THIS_FILE, line => __LINE__});
	
	# This shouldn't be called unless we confirmed the node is off, so no need to check again, just boot.
	my $rebooted = 0;
	my $state    = $an->ScanCore->target_power({
			target => $node_uuid,
			task   => "off",
		});
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "state", value1 => $state, 
	}, file => $THIS_FILE, line => __LINE__});
	
	if ($state eq "off")
	{
		# Shutdown, at least, worked.
		$rebooted = 1;
		$an->Log->entry({log_level => 0, title_key => "tools_title_0002", message_key => "scancore_log_0088", message_variables => {
			node => $host_name,
		}, file => $THIS_FILE, line => __LINE__});
		
		$state = $an->ScanCore->target_power({
				target => $node_uuid,
				task   => "on",
			});
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "state", value1 => $state, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "state", value1 => $state, 
	}, file => $THIS_FILE, line => __LINE__});
	return($state);
}

# This reads in the 'alerts' table and generates the emails/log file entries as needed.
sub process_alerts
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	my $first_run = 0 if not defined $parameter->{first_run};
	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "process_alerts" }, message_key => "tools_log_0003", message_variables => { 
		name1 => "first_run", value1 => $first_run
	}, file => $THIS_FILE, line => __LINE__});
	
	# Get notification target data so that we know what languages to search for keys in.
	my $languages = [];
	my $query     = "SELECT DISTINCT notify_language FROM notifications;";
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	my $count   = @{$results};
	$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
		name1 => "results", value1 => $results, 
		name2 => "count",   value2 => $count,
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		# One or more records were found.
		my $language = $row->[0]; 
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "language", value1 => $language, 
		}, file => $THIS_FILE, line => __LINE__});
		
		push @{$languages}, $language;
	}
	undef $results;
	
	# Read in all pending alerts
	$query = "
SELECT 
    alert_uuid, 
    alert_agent_name, 
    alert_level, 
    alert_title_key, 
    alert_title_variables, 
    alert_message_key, 
    alert_message_variables, 
    alert_header, 
    alert_sort, 
    modified_date
FROM 
    alerts 
WHERE 
    alert_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{host_uuid})." 
ORDER BY 
    alert_agent_name ASC, 
    modified_date ASC, 
    alert_sort ASC 
;";
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "query", value1 => $query, 
	}, file => $THIS_FILE, line => __LINE__});
	
	$results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "results", value1 => $results, 
	}, file => $THIS_FILE, line => __LINE__});
	foreach my $row (@{$results})
	{
		# One or more records were found.
		my $alert_uuid              =         $row->[0]; 
		my $alert_agent_name        =         $row->[1]; 
		my $alert_level             =         $row->[2]; 
		my $alert_title_key         =         $row->[3]; 
		my $alert_title_variables   =         $row->[4]; 
		my $alert_message_key       =         $row->[5]; 
		my $alert_message_variables =         $row->[6]; 
		my $alert_header            =         $row->[7]; 
		my $alert_sort              = defined $row->[8] ? $row->[8] : 9999; 
		my $modified_date           =         $row->[9]; 
		$an->Log->entry({log_level => 2, message_key => "an_variables_0010", message_variables => {
			name1  => "alert_uuid",              value1  => $alert_uuid, 
			name2  => "alert_agent_name",        value2  => $alert_agent_name, 
			name3  => "alert_level",             value3  => $alert_level, 
			name4  => "alert_title_key",         value4  => $alert_title_key, 
			name5  => "alert_title_variables",   value5  => $alert_title_variables, 
			name6  => "alert_message_key",       value6  => $alert_message_key, 
			name7  => "alert_message_variables", value7  => $alert_message_variables, 
			name8  => "alert_header",            value8  => $alert_header, 
			name9  => "alert_sort",              value9  => $alert_sort, 
			name10 => "modified_date",           value10 => $modified_date, 
		}, file => $THIS_FILE, line => __LINE__});
		
		# Check to make sure we have both the $alert_title_key and $alert_message_key. If we're 
		# missing either, we'll send a generic "oh crap" alert and then delete it so that Strings 
		# doesn't error out and block alert emails.
		my $problem = 0;
		foreach my $language (sort {$a cmp $b} @{$languages})
		{
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "language", value1 => $language, 
			}, file => $THIS_FILE, line => __LINE__});
			if ((not $an->data->{strings}{lang}{$language}{key}{$alert_title_key}{content}) or (not $an->data->{strings}{lang}{$language}{key}{$alert_message_key}{content}))
			{
				# Well fuch. Move this over to 'scancore_log_0097'
				$problem = 1;
				
				# Delete this right away so it can't come back if this somehow kills us in 
				# the next couple of steps.
				my $query = "DELETE FROM alerts WHERE alert_uuid = ".$an->data->{sys}{use_db_fh}->quote($alert_uuid).";";
				$an->Log->entry({log_level => 1, message_key => "an_variables_0001", message_variables => {
					name1 => "query", value1 => $query, 
				}, file => $THIS_FILE, line => __LINE__});
				$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
				
				# Substitute out the '!!x!y!!' and '!!x!!!' strings for '_!x!y!_' and 
				# '_!x!!_' to prevent a possible fatal attempt to translate them.
				my $i = 0;
				while ($alert_title_variables =~ /(!!.*?!!)/)
				{
					$i++;
					die "$THIS_FILE ".__LINE__."; Exiting on infinite loop parsing pairs out of: [$alert_title_variables]\n" if $i > 1000;
					$alert_title_variables =~ s/!!(.*?)!!/_!$1!_/g;
				}
				$an->Log->entry({log_level => 1, message_key => "an_variables_0001", message_variables => {
					name1 => "alert_title_variables", value1 => $alert_title_variables, 
				}, file => $THIS_FILE, line => __LINE__});
				
				$i = 0;
				while ($alert_message_variables =~ /(!!.*?!!)/)
				{
					$i++;
					die "$THIS_FILE ".__LINE__."; Exiting on infinite loop parsing pairs out of: [$alert_message_variables]\n" if $i > 1000;
					$alert_message_variables =~ s/!!(.*?)!!/_!$1!_/g;
				}
				$an->Log->entry({log_level => 1, message_key => "an_variables_0001", message_variables => {
					name1 => "alert_message_variables", value1 => $alert_message_variables, 
				}, file => $THIS_FILE, line => __LINE__});
				
				# Sort this at the top.
				$an->data->{db}{alerts}{agent_name}{$THIS_FILE}{alert_sort}{'1'}{alert_uuid}{$alert_uuid} = {
					alert_level             => $alert_level, 
					alert_title_key         => "scancore_title_0003", 
					alert_title_variables   => "", 
					alert_message_key       => "scancore_log_0097", 
					alert_message_variables => "!!alert_agent_name!".$alert_agent_name."!!,!!alert_level!".$alert_level."!!,!!alert_title_key!".$alert_title_key."!!,!!alert_title_variables!".$alert_title_variables."!!,!!alert_message_key!".$alert_message_key."!!,!!alert_message_variables!".$alert_message_variables."!!,!!modified_date!".$modified_date."!!",
					alert_header 		=> 1,
					modified_date           => $modified_date
				};
			}
		}
		next if $problem;
		
		# Store the alert
		$an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid} = {
			alert_level             => $alert_level, 
			alert_title_key         => $alert_title_key, 
			alert_title_variables   => $alert_title_variables, 
			alert_message_key       => $alert_message_key, 
			alert_message_variables => $alert_message_variables,
			alert_header 		=> $alert_header,
			modified_date           => $modified_date
		};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0007", message_variables => {
			name1 => "db::alerts::agent_name::${alert_agent_name}::alert_sort::${alert_sort}::alert_uuid::${alert_uuid}::alert_level",             value1 => $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_level},
			name2 => "db::alerts::agent_name::${alert_agent_name}::alert_sort::${alert_sort}::alert_uuid::${alert_uuid}::alert_title_key",         value2 => $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_title_key},
			name3 => "db::alerts::agent_name::${alert_agent_name}::alert_sort::${alert_sort}::alert_uuid::${alert_uuid}::alert_title_variables",   value3 => $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_title_variables},
			name4 => "db::alerts::agent_name::${alert_agent_name}::alert_sort::${alert_sort}::alert_uuid::${alert_uuid}::alert_message_key",       value4 => $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_message_key},
			name5 => "db::alerts::agent_name::${alert_agent_name}::alert_sort::${alert_sort}::alert_uuid::${alert_uuid}::alert_message_variables", value5 => $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_message_variables},
			name6 => "db::alerts::agent_name::${alert_agent_name}::alert_sort::${alert_sort}::alert_uuid::${alert_uuid}::alert_header",            value6 => $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_header},
			name7 => "db::alerts::agent_name::${alert_agent_name}::alert_sort::${alert_sort}::alert_uuid::${alert_uuid}::modified_date",           value7 => $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{modified_date},
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	# Process alerts, if any.
	if (ref($an->data->{db}{alerts}{agent_name}))
	{
		### Load the latest alert recipient information
		# Email/file notification targets. We'll load them into an easy to access hash.
		my $notifications = $an->ScanCore->get_notifications();
		foreach my $hash_ref (@{$notifications})
		{
			my $notify_uuid     = $hash_ref->{notify_uuid};
			my $notify_name     = $hash_ref->{notify_name};
			my $notify_target   = $hash_ref->{notify_target};
			my $notify_language = $hash_ref->{notify_language};
			my $notify_level    = $hash_ref->{notify_level};
			my $notify_units    = $hash_ref->{notify_units};
			$an->Log->entry({log_level => 2, message_key => "an_variables_0006", message_variables => {
				name1 => "notify_uuid",     value1 => $notify_uuid,
				name2 => "notify_name",     value2 => $notify_name,
				name3 => "notify_target",   value3 => $notify_target,
				name4 => "notify_language", value4 => $notify_language,
				name5 => "notify_level",    value5 => $notify_level,
				name6 => "notify_units",    value6 => $notify_units,
			}, file => $THIS_FILE, line => __LINE__});
			
			$an->data->{notifications}{$notify_uuid}{notify_name}     = $notify_name;
			$an->data->{notifications}{$notify_uuid}{notify_target}   = $notify_target;
			$an->data->{notifications}{$notify_uuid}{notify_language} = $notify_language;
			$an->data->{notifications}{$notify_uuid}{notify_level}    = $notify_level;
			$an->data->{notifications}{$notify_uuid}{notify_units}    = $notify_units;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0005", message_variables => {
				name1 => "notifications::${notify_uuid}::notify_name",     value1 => $an->data->{notifications}{$notify_uuid}{notify_name},
				name2 => "notifications::${notify_uuid}::notify_target",   value2 => $an->data->{notifications}{$notify_uuid}{notify_target},
				name3 => "notifications::${notify_uuid}::notify_language", value3 => $an->data->{notifications}{$notify_uuid}{notify_language},
				name4 => "notifications::${notify_uuid}::notify_level",    value4 => $an->data->{notifications}{$notify_uuid}{notify_level},
				name5 => "notifications::${notify_uuid}::notify_units",    value5 => $an->data->{notifications}{$notify_uuid}{notify_units},
			}, file => $THIS_FILE, line => __LINE__});
		}
		
		# Links notification targets with Anvils (and possible alert level overrides)
		my $recipients = $an->ScanCore->get_recipients();
		
		# Loop through recipients. Any that match this Anvil! will be compared against the recipients
		# requested alert level. If they want this level alert, we'll pull their data from 
		# notifications and email/log.
		my $dashboard_recipients = {};
		foreach my $hash_ref (@{$recipients})
		{
			my $recipient_anvil_uuid   = $hash_ref->{recipient_anvil_uuid};
			my $recipient_notify_uuid  = $hash_ref->{recipient_notify_uuid};
			my $recipient_notify_level = $hash_ref->{recipient_notify_level};
			$an->Log->entry({log_level => 2, message_key => "an_variables_0004", message_variables => {
				name1 => "sys::anvil_uuid",        value1 => $an->data->{sys}{anvil_uuid},
				name2 => "recipient_anvil_uuid",   value2 => $recipient_anvil_uuid,
				name3 => "recipient_notify_uuid",  value3 => $recipient_notify_uuid,
				name4 => "recipient_notify_level", value4 => $recipient_notify_level,
			}, file => $THIS_FILE, line => __LINE__});
			
			# If this is a node and this recipient isn't listening to this Anvil!, skip it.
			next if (($an->Get->what_am_i eq "node") && ($recipient_anvil_uuid ne $an->data->{sys}{anvil_uuid}));
			
			# Get the information for this notification target
			if ($an->data->{notifications}{$recipient_notify_uuid}{notify_name})
			{
				# Match found, proceed.
				my $notify_name     = $an->data->{notifications}{$recipient_notify_uuid}{notify_name};
				my $notify_target   = $an->data->{notifications}{$recipient_notify_uuid}{notify_target};
				my $notify_language = $an->data->{notifications}{$recipient_notify_uuid}{notify_language};
				my $notify_level    = $an->data->{notifications}{$recipient_notify_uuid}{notify_level};
				my $notify_units    = $an->data->{notifications}{$recipient_notify_uuid}{notify_units};
				$an->Log->entry({log_level => 2, message_key => "an_variables_0006", message_variables => {
					name1 => "notify_name",            value1 => $notify_name,
					name2 => "notify_target",          value2 => $notify_target,
					name3 => "notify_language",        value3 => $notify_language,
					name4 => "notify_level",           value4 => $notify_level,
					name5 => "notify_units",           value5 => $notify_units,
					name6 => "recipient_notify_level", value6 => $recipient_notify_level,
				}, file => $THIS_FILE, line => __LINE__});
				
				# If the notification name isn't set, set the default.
				if (not $notify_name)
				{
					$notify_name = "#!string!scancore_message_0003!#";
					$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
						name1 => "notify_name", value1 => $notify_name,
					}, file => $THIS_FILE, line => __LINE__});
				}
				
				# If I am a dashboard, make sure I want to send to this notification target.
				if ($an->Get->what_am_i eq "dashboard")
				{
					my ($proceed, $level) = $an->ScanCore->check_dashboard_target({
						notify_target => $notify_target
					});
					$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
						name1 => "proceed", value1 => $proceed,
						name2 => "level",   value2 => $level,
					}, file => $THIS_FILE, line => __LINE__});
					next if not $proceed;
					
					# In case we see the same recipient twice, skip them.
					next if $dashboard_recipients->{$notify_target};
					
					# Now note that we're processing this target and update the level to
					# the one set in striker.conf.
					$dashboard_recipients->{$notify_target} = 1;
					$recipient_notify_level                 = $level;
					$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
						name1 => "recipient_notify_level", value1 => $recipient_notify_level,
					}, file => $THIS_FILE, line => __LINE__});
				}
				
				# See if this notification target has a custom level for this Anvil!.
				if ($recipient_notify_level)
				{
					$notify_level = $recipient_notify_level;
					$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
						name1 => "notify_level", value1 => $notify_level,
					}, file => $THIS_FILE, line => __LINE__});
				}
				
				# Is this an email recipient?
				if ($an->Validate->is_email({email => $notify_target}))
				{
					# Send an email
					$an->ScanCore->send_email({
						email => $notify_target,
						name => $notify_name,
						user_level => $notify_level,
						language => $notify_language,
						units => $notify_units,
						anvil_uuid => $recipient_anvil_uuid
					});
				}
				else
				{
					# Record to a file.
					$an->ScanCore->record_alert_to_file({
						file => $notify_target,
						name => $notify_name,
						level => $notify_level,
						language => $notify_language,
						units => $notify_units
					});
				}
			}
		}
		
		# All done, delete the public.alerts entries.
		$query = "DELETE FROM alerts WHERE alert_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{host_uuid}).";";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "query", value1 => $query
		}, file => $THIS_FILE, line => __LINE__});
		$an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
		
		# Delete the alerts from memory.
		delete $an->data->{db}{alerts};
		
		# Mark that an alert was sent
		$an->Log->entry({log_level => 3, message_key => "scancore_log_0053", file => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# No alerts
		$an->Log->entry({log_level => 3, message_key => "scancore_log_0052", file => $THIS_FILE, line => __LINE__}) if not $first_run;
	}
	
	return(0);
}

# This takes an email address and returns '1' if it's a manually selected notification target for this 
# striker dashbaord.
sub check_dashboard_target
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	my $notify_target = $parameter->{notify_target};

	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "check_dashboard_target" }, message_key => "an_variables_0001", message_variables => { 
		name1 => "notify_target", value1 => $notify_target, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $proceed = 0;
	my $level   = "warning";
	if (($an->data->{striker}{email}{use_server}) && ($an->data->{striker}{email}{notify}))
	{
		# Yup! Is this recipient in the list?
		foreach my $target (split/,/, $an->data->{striker}{email}{notify})
		{
			$target =~ s/\s+//;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "target", value1 => $target, 
			}, file => $THIS_FILE, line => __LINE__});
			
			my $recipient = $target;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "recipient", value1 => $recipient, 
				name2 => "level",     value2 => $level, 
			}, file => $THIS_FILE, line => __LINE__});
			if ($target =~ /^(.*?):(.*)$/)
			{
				$recipient = $1;
				$level     = $2;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
					name1 => "recipient", value1 => $recipient, 
					name2 => "level",     value2 => $level, 
				}, file => $THIS_FILE, line => __LINE__});
			}
			
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "recipient",     value1 => $recipient, 
				name2 => "notify_target", value2 => $notify_target, 
			}, file => $THIS_FILE, line => __LINE__});
			if ($recipient eq $notify_target)
			{
				$proceed = 1;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "proceed", value1 => $proceed, 
				}, file => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "proceed", value1 => $proceed, 
	}, file => $THIS_FILE, line => __LINE__});
	return($proceed, $level);
}

# This sends any pending alerts to a give recipient, if applicable.
sub send_email
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	my $email = $parameter->{email};
	my $name = $parameter->{name};
	my $user_level = $parameter->{user_level};
	my $language = $parameter->{language};
	my $units = $parameter->{units};
	my $anvil_uuid = $parameter->{anvil_uuid};

	$an->Log->entry({log_level => 2, title_key => "tools_log_0001", title_variables => { function => "send_email" }, message_key => "an_variables_0006", message_variables => { 
		name1 => "email",      value1 => $email, 
		name2 => "name",       value2 => $name, 
		name3 => "user_level", value3 => $user_level, 
		name4 => "language",   value4 => $language, 
		name5 => "units",      value5 => $units, 
		name6 => "anvil_uuid", value6 => $anvil_uuid, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# If I am a dashboard, see if 'striker::email::use_server' exists and is set.
	if ($an->Get->what_am_i eq "dashboard")
	{
		# I am a dashboard. Check to see if we should send an email. If so, we might override the 
		# alert level.
		(my $proceed, $user_level) = $an->ScanCore->check_dashboard_target({
			notify_target => $email
		});
		$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
			name1 => "proceed",    value1 => $proceed,
			name2 => "user_level", value2 => $user_level,
		}, file => $THIS_FILE, line => __LINE__});
		
		if (not $proceed)
		{
			# Nope, return.
			return(0);
		}
	}
	
	# The 'subject' will hold the highest alert seen and be used to generate a proper email subject prior
	# to dispatching the email proper.
	# debug    = 5
	# info     = 4
	# notice   = 3
	# warning  = 2
	# critical = 1
	# ignore   = 0
	my $subject = 5;
	my $body    = "";
	
	# Convert the user's log level to a numeric number for easier comparison.
	$user_level = $an->Alert->convert_level_name_to_number({level => $user_level});
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "user_level", value1 => $user_level, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# Generate the title key.
	my $lowest_level = 5;
	foreach my $alert_agent_name (sort {$a cmp $b} keys %{$an->data->{db}{alerts}{agent_name}})
	{
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "alert_agent_name", value1 => $alert_agent_name, 
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $alert_sort (sort {$a cmp $b} keys %{$an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}})
		{
			$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
				name1 => "alert_sort", value1 => $alert_sort, 
			}, file => $THIS_FILE, line => __LINE__});
			foreach my $alert_uuid (keys %{$an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}})
			{
				$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
					name1 => "alert_uuid", value1 => $alert_uuid, 
				}, file => $THIS_FILE, line => __LINE__});
				
				my $alert_level             = $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_level};
				my $alert_title_key         = $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_title_key};
				my $alert_title_variables   = $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_title_variables};
				my $alert_message_key       = $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_message_key};
				my $alert_message_variables = $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_message_variables};
				my $alert_header            = $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_header};
				$an->Log->entry({log_level => 2, message_key => "an_variables_0006", message_variables => {
					name1 => "alert_level",             value1 => $alert_level, 
					name2 => "alert_title_key",         value2 => $alert_title_key, 
					name3 => "alert_title_variables",   value3 => $alert_title_variables, 
					name4 => "alert_message_key",       value4 => $alert_message_key, 
					name5 => "alert_message_variables", value5 => $alert_message_variables, 
					name6 => "alert_header",            value6 => $alert_header, 
				}, file => $THIS_FILE, line => __LINE__});
				
				$alert_level = $an->Alert->convert_level_name_to_number({level => $alert_level});
				$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
					name1 => "alert_level",  value1 => $alert_level, 
					name2 => "lowest_level", value2 => $lowest_level, 
				}, file => $THIS_FILE, line => __LINE__});
				if ($alert_level < $lowest_level)
				{
					$lowest_level = $alert_level;
					$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
						name1 => "lowest_level", value1 => $lowest_level, 
					}, file => $THIS_FILE, line => __LINE__});
				}
				
				# Record the alert level if it is higher than we saw before.
				$subject = $alert_level if $subject > $alert_level;
				$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
					name1 => "subject", value1 => $subject, 
				}, file => $THIS_FILE, line => __LINE__});
				
				# The conversion of C to F is handled in translate_sensor_{name,value}() functions.
				my $title   = $an->ScanCore->get_string_from_double_bang({
					language => $language,
					key => $alert_title_key,
					variables => $alert_title_variables,
					units => $units
				});
				my $message = $an->ScanCore->get_string_from_double_bang({
					language => $language,
					key => $alert_message_key,
					variables => $alert_message_variables,
					units => $units
				});
				$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
					name1 => "title",   value1 => $title, 
					name2 => "message", value2 => $message, 
				}, file => $THIS_FILE, line => __LINE__});
				
				# If the alert level is equal to or lower than the user level, add it to the message body.
				$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
					name1 => "user_level",  value1 => $user_level, 
					name2 => "alert_level", value2 => $alert_level, 
				}, file => $THIS_FILE, line => __LINE__});
				if ($user_level >= $alert_level)
				{
					if ($alert_header)
					{
						$an->Log->entry({log_level => 2, message_key => "an_variables_0002", message_variables => {
							name1 => "title",   value1 => $title, 
							name2 => "message", value2 => $message, 
						}, file => $THIS_FILE, line => __LINE__});
						$body .= $an->String->get({language => $language, key => "scancore_email_0005", variables => {
								title   => $title,
								message => $message,
							}})."\n\n";
					}
					else
					{
						# No header
						$body .= $an->String->get({language => $language, key => "scancore_email_0006", variables => { message => $message }})."\n";
					}
				}
				else
				{
					# Ignored
					$an->Log->entry({log_level => 3, message_key => "scancore_log_0050", message_variables => {
						user       => "$name <$email>",
						alert_uuid => $alert_uuid, 
						title      => $title,
						message    => $message
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
		}
	}
	
	# If there is no message body, we're done.
	if (not $body)
	{
		return(0);
	}
	
	### NOTE: The "subject" is a bit mis-named, as it is really the highest log level in this message, 
	###       represented as an integer.
	# Get the list of other email recipients.
	$an->Log->entry({log_level => 2, message_key => "an_variables_0003", message_variables => {
		name1 => "email",      value1 => $email, 
		name2 => "subject",    value2 => $subject, 
		name3 => "anvil_uuid", value3 => $anvil_uuid, 
	}, file => $THIS_FILE, line => __LINE__});
	my $other_recipients = $an->Get->other_alert_recipients({
		user       => $email,
		level      => $subject,
		anvil_uuid => $anvil_uuid,
	});
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "other_recipients", value1 => $other_recipients, 
	}, file => $THIS_FILE, line => __LINE__});
	if ($other_recipients)
	{
		my $recipients_message = $an->String->get({language => $language, key => "scancore_email_0007", variables => { recipients => $other_recipients }});
		$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
			name1 => "recipients_message", value1 => $recipients_message, 
		}, file => $THIS_FILE, line => __LINE__});
		
		$body .= $recipients_message."\n";
	}
	
	# Generate the email body.
	my $subject_line = $an->String->get({language => $language, key => "scancore_email_0004", variables => { hostname => $an->hostname }});
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "subject_line", value1 => $subject_line, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $say_subject = $an->String->get({language => $language, key => "scancore_email_0001", variables => {
			level   => "#!string!an_alert_subject_".sprintf("%04d", $lowest_level)."!#",
			subject => $subject_line,
		}});
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "say_subject", value1 => $say_subject, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# The footer is a generic message tell the user not to yell at us for spamming them. (hey, you laugh,
	# but managers will get these emails...)
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "scancore::append_email_footer", value1 => $an->data->{scancore}{append_email_footer}, 
	}, file => $THIS_FILE, line => __LINE__});
	if ($an->data->{scancore}{append_email_footer})
	{
		$body .= $an->String->get({language => $language, key => "scancore_email_0003", variables => { hostname => $an->hostname }});
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "body", value1 => $body, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	# Now assemble the message.
	my $say_to = "$name <$email>";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0004", message_variables => {
		name1 => "sys::anvil::smtp::username", value1 => $an->data->{sys}{anvil}{smtp}{username},
		name2 => "say_to",                     value2 => $say_to, 
		name3 => "say_subject",                value3 => $say_subject,
		name4 => "body",                       value4 => $body,
	}, file => $THIS_FILE, line => __LINE__});
	my $email_body = $an->String->get({language => $language, key => "scancore_email_0002", variables => {
			from     => $an->data->{sys}{anvil}{smtp}{username},
			to       => $say_to,
			subject  => $say_subject,
			reply_to => $other_recipients, 
			body     => $body,
		}});
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "email_body", value1 => $email_body,
	}, file => $THIS_FILE, line => __LINE__});
	
	# First, see if the relay file needs to be updated.
	$an->ScanCore->check_email_configuration();
	
	# Select a known_free email file name.
	my $date_and_time =  $an->Get->date_and_time({split_date_time => 0, no_spaces => 1});
	   $date_and_time =~ s/:/-/g;
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "date_and_time", value1 => $date_and_time,
	}, file => $THIS_FILE, line => __LINE__});
	
	my $email_file = $an->data->{path}{alert_emails}."/$date_and_time.1";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "email_file", value1 => $email_file, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $file_ok = 0;
	until ($file_ok)
	{
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "email_file", value1 => $email_file, 
		}, file => $THIS_FILE, line => __LINE__});
		if (-e $email_file)
		{
			my ($file, $suffix) = ($email_file =~ /^(.*?)\.(\d+)$/);
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "file",   value1 => $file,
				name2 => "suffix", value2 => $suffix,
			}, file => $THIS_FILE, line => __LINE__});
			
			$suffix++;
			$email_file = "$file.$suffix";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "email_file", value1 => $email_file,
			}, file => $THIS_FILE, line => __LINE__});
			   
			# Make sure I'm not sending more than 10/sec...
			if ($suffix > 10)
			{
				# Given the precision of the date coming from pgsql, there must be something
				# wrong.
				$an->Alert->error({title_key => "an_0003", message_key => "scancore_error_0014", message_variables => { file => $email_file }, code => 2, file => $THIS_FILE, line => __LINE__});
			}
		}
		else
		{
			$file_ok = 1;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "file_ok", value1 => $file_ok,
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	# Write out the email file.
	my $shell_call = $email_file;
	$an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
		name1 => "shell_call", value1 => $shell_call, 
	}, file => $THIS_FILE, line => __LINE__});
	open (my $file_handle, ">$shell_call") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0015", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
	print $file_handle $email_body;
	close $file_handle;
	
	# Now send the email.
	$an->Log->entry({log_level => 2, message_key => "scancore_log_0049", message_variables => { file => $email_file }, file => $THIS_FILE, line => __LINE__});
	
	$shell_call = $an->data->{path}{mailx}." -t < $email_file";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "shell_call", value1 => $shell_call, 
	}, file => $THIS_FILE, line => __LINE__});
	open ($file_handle, $shell_call." 2>&1 |") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0014", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
	while(<$file_handle>)
	{
		chomp;
		my $line = $_;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "line", value1 => $line, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	close $file_handle;
	
	return(0);
}

# This records entries from alerts to a file, if applicable.
sub record_alert_to_file
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	my $file = $parameter->{file};
	my $name = $parameter->{name};
	my $level = $parameter->{level};
	my $language = $parameter->{language};
	my $units = $parameter->{units};

	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "record_alert_to_file" }, message_key => "an_variables_0005", message_variables => { 
		name1 => "file",     value1 => $file, 
		name2 => "name",     value2 => $name, 
		name3 => "level",    value3 => $level, 
		name4 => "language", value4 => $language, 
		name5 => "units",    value5 => $units, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $messages = "";
	
	# Prepend the alert file path.
	$file = $an->data->{path}{alert_files}."/$file";
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "file", value1 => $file, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# Convert the user's log level to a numeric number for easier comparison.
	$level = $an->Alert->convert_level_name_to_number({level => $level});
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "level", value1 => $level, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# Loop through all the alerts and prep the relevant ones to be written to the file.
	foreach my $alert_agent_name (sort {$a cmp $b} keys %{$an->data->{db}{alerts}{agent_name}})
	{
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "alert_agent_name", value1 => $alert_agent_name, 
		}, file => $THIS_FILE, line => __LINE__});
		foreach my $alert_sort (sort {$a cmp $b} keys %{$an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}})
		{
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "alert_sort", value1 => $alert_sort, 
			}, file => $THIS_FILE, line => __LINE__});
			foreach my $alert_uuid (keys %{$an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}})
			{
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "alert_uuid", value1 => $alert_uuid, 
				}, file => $THIS_FILE, line => __LINE__});
				
				my $alert_level             = $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_level};
				my $alert_title_key         = $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_title_key};
				my $alert_title_variables   = $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_title_variables};
				my $alert_message_key       = $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_message_key};
				my $alert_message_variables = $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{alert_message_variables};
				my $modified_date           = $an->data->{db}{alerts}{agent_name}{$alert_agent_name}{alert_sort}{$alert_sort}{alert_uuid}{$alert_uuid}{modified_date};
				
				$an->Log->entry({log_level => 3, message_key => "an_variables_0006", message_variables => {
					name1 => "alert_level",             value1 => $alert_level, 
					name2 => "alert_title_key",         value2 => $alert_title_key, 
					name3 => "alert_title_variables",   value3 => $alert_title_variables, 
					name4 => "alert_message_key",       value4 => $alert_message_key, 
					name5 => "alert_message_variables", value5 => $alert_message_variables, 
					name6 => "modified_date",           value6 => $modified_date, 
				}, file => $THIS_FILE, line => __LINE__});
				
				$alert_level = $an->Alert->convert_level_name_to_number({level => $alert_level});
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "alert_level", value1 => $alert_level, 
				}, file => $THIS_FILE, line => __LINE__});
				
				if ($level >= $alert_level)
				{
					my $title    =  $an->ScanCore->get_string_from_double_bang({
						language => $language,
						key => $alert_title_key,
						variables => $alert_title_variables,
						units => $units
					});
					my $message  =  $an->ScanCore->get_string_from_double_bang({
						language => $language,
						key => $alert_message_key,
						variables => $alert_message_variables,
						units => $units
					});
					my $say_date =  $modified_date;
					$say_date =~ s/(\d+-\d+-\d+ \d+:\d+:\d+)\.\d+(.*)$/$1 (GMT$2)/;
					
					my $string = $an->String->get({key => "scancore_log_0033", variables => {
							date			=>	$say_date,
							alert_agent_name	=>	$alert_agent_name,
							title			=>	$title, 
							message			=>	$message, 
						}});
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "string", value1 => $string, 
					}, file => $THIS_FILE, line => __LINE__});
					
					$messages .= "$string\n";
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "messages", value1 => $messages, 
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
		}
	}
	
	$an->Log->entry({log_level => 3, message_key => "scancore_log_0032", message_variables => { file => $file }, file => $THIS_FILE, line => __LINE__});
	
	# Append to the log file.
	my $shell_call = ">>$file";
	open (my $filehandle, "$shell_call") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0015", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
	print $filehandle $messages;
	close $filehandle;
	
	return(0);
}

# This converts the string keys and variables stored in the alerts table (flanked with '!!') to strings. It
# also handles the special 'sensor' data and will convert metric to imperial values as needed.
sub get_string_from_double_bang
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	my $language = $parameter->{language};
	my $key = $parameter->{key};
	my $variables = $parameter->{variables};
	my $units = $parameter->{units};

	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "get_string_from_double_bang" }, message_key => "an_variables_0004", message_variables => { 
		name1 => "language",  value1 => $language, 
		name2 => "key",       value2 => $key,  
		name3 => "variables", value3 => $variables, 
		name4 => "units",     value4 => $units
	}, file => $THIS_FILE, line => __LINE__});
	
	if ($variables)
	{
		my $hash = {};
		my $i    = 0;
		while ($variables =~ /(!!.*?!!)/)
		{
			$i++;
			die "$THIS_FILE ".__LINE__."; Exiting on infinite loop parsing pairs out of: [$variables]\n" if $i > 1000;
			
			my $pair      =  ($variables =~ /(!!.*?!!)/s)[0];
			   $variables =~ s/\Q$pair\E//s;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
				name1 => "i",         value1 => $i, 
				name2 => "pair",      value2 => $pair, 
				name3 => "variables", value3 => $variables, 
			}, file => $THIS_FILE, line => __LINE__});
			next if not $pair;
			
			my $variable = "";
			my $value    = "";
			if ($pair =~ /^!!(.*?)!!!$/s)
			{
				# No value, this is OK.
				($variable) = ($pair =~ /^!!(.*?)!!!$/s);
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "variable", value1 => $variable, 
				}, file => $THIS_FILE, line => __LINE__});
			}
			elsif ($pair =~ /^!!(.*?)!(.*?)!!$/s)
			{
				($variable, $value) = ($pair =~ /^!!(.*?)!(.*?)!!$/s);
				$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
					name1 => "variable", value1 => $variable, 
					name2 => "value",    value2 => $value, 
				}, file => $THIS_FILE, line => __LINE__});
				
				# If the variable matches a key in the language file, translate it.
				if (exists $an->data->{strings}{lang}{$language}{key}{$value}{content})
				{
					# This language has a translation key!
					$value = $an->String->get({key => $value});
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "value", value1 => $value, 
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			die "$THIS_FILE ".__LINE__."; No variable parsed from: [$pair]\n" if not defined $variable;
			
			# If the value is one of the special sensor name or value strings, translate it.
			if ($variable eq "sensor_name") 
			{
				my ($sensor_name, $sensor_units) = ($value =~ /name=(.*?):units=(.*)$/);
				$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
					name1 => "sensor_name",  value1 => $sensor_name, 
					name2 => "sensor_units", value2 => $sensor_units, 
				}, file => $THIS_FILE, line => __LINE__});
				
				$value = $an->ScanCore->translate_sensor_name({
					ipmitool_sensor_name => $sensor_name,
					ipmitool_sensor_units => $sensor_units
				});
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "value", value1 => $value, 
				}, file => $THIS_FILE, line => __LINE__});
			}
			# Catch 'sensor_value', 'new_sensor_value' and 'old_sensor_value'.
			elsif ($variable =~ /sensor_value/)
			{
				my ($sensor_value, $sensor_units) = ($value =~ /value=(.*?):units=(.*)$/);
				$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
					name1 => "sensor_value", value1 => $sensor_value, 
					name2 => "sensor_units", value2 => $sensor_units, 
				}, file => $THIS_FILE, line => __LINE__});
				
				$value = $an->ScanCore->translate_sensor_value({
					ipmitool_value_sensor_value => $sensor_value,
					ipmitool_sensor_units => $sensor_units,
					units => $units
				});
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "value", value1 => $value, 
				}, file => $THIS_FILE, line => __LINE__});
			}
			# This catches any value in the format 'X Y'.
			elsif ($value =~ /(.*?) (.*)$/)
			{
				# NOTE: This will split on *anything* with a space. So it is possible that 
				#       we're NOT looking at a 'value units' pair!
				my $left_hand_side  = $1;
				my $right_hand_side = $2;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
					name1 => "left_hand_side",  value1 => $left_hand_side, 
					name2 => "right_hand_side", value2 => $right_hand_side, 
				}, file => $THIS_FILE, line => __LINE__});
				
				my $returned = $an->ScanCore->translate_units({
					value => $left_hand_side,
					units => $right_hand_side,
					user_units => $units
				});
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "returned", value1 => $returned, 
				}, file => $THIS_FILE, line => __LINE__});
				
				# Only rewrite 'value' if 'returned' has something in it.
				if ($returned)
				{
					$value = $returned;
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "value", value1 => $value, 
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			# This catches certain values that we translate to the requested target's language.
			else
			{
				my $returned = $an->ScanCore->translate_strings({
					string => $value
				});
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "returned", value1 => $returned, 
				}, file => $THIS_FILE, line => __LINE__});
				
				# Only rewrite 'value' if 'returned' has something in it.
				if ($returned)
				{
					$value = $returned;
					$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
						name1 => "value", value1 => $value, 
					}, file => $THIS_FILE, line => __LINE__});
				}
			}
			$hash->{$variable} = $value;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "hash->{$variable}", value1 => $hash->{$variable}, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		$variables = $hash;
	}
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0003", message_variables => {
		name1 => "language",  value1 => $language, 
		name2 => "key",       value2 => $key, 
		name3 => "variables", value3 => $variables, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $string = $an->String->get({
		language  => $language,
		key       => $key,
		variables => $variables, 
	});
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "string", value1 => $string, 
	}, file => $THIS_FILE, line => __LINE__});
	return($string);
}

# This checks the local postfix and mail relay data and updates if needed.
sub check_email_configuration
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "check_email_configuration" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
	
	if ($an->Get->what_am_i eq "dashboard")
	{
		# I am a dashboard. Is 'use_server' set?
		my $proceed = 0;
		if ($an->data->{striker}{email}{use_server})
		{
			# We'll look up the server name to use
			my $smtp_data = $an->ScanCore->get_smtp();
			foreach my $hash_ref (@{$smtp_data})
			{
				if ($hash_ref->{smtp_server} eq $an->data->{striker}{email}{use_server})
				{
					$proceed                                      = 1;
					$an->data->{sys}{anvil}{smtp}{server}         = $hash_ref->{smtp_server};
					$an->data->{sys}{anvil}{smtp}{port}           = $hash_ref->{smtp_port};
					$an->data->{sys}{anvil}{smtp}{alt_server}     = $hash_ref->{smtp_alt_server};
					$an->data->{sys}{anvil}{smtp}{alt_port}       = $hash_ref->{smtp_alt_port};
					$an->data->{sys}{anvil}{smtp}{username}       = $hash_ref->{smtp_username};
					$an->data->{sys}{anvil}{smtp}{password}       = $hash_ref->{smtp_password};
					$an->data->{sys}{anvil}{smtp}{security}       = $hash_ref->{smtp_security};
					$an->data->{sys}{anvil}{smtp}{authentication} = $hash_ref->{smtp_authentication};
					$an->data->{sys}{anvil}{smtp}{helo_domain}    = $hash_ref->{smtp_helo_domain};
					$an->Log->entry({log_level => 3, message_key => "an_variables_0009", message_variables => {
						name1 => "proceed",                          value1 => $proceed, 
						name2 => "sys::anvil::smtp::server",         value2 => $an->data->{sys}{anvil}{smtp}{server}, 
						name3 => "sys::anvil::smtp::port",           value3 => $an->data->{sys}{anvil}{smtp}{port}, 
						name4 => "sys::anvil::smtp::alt_server",     value4 => $an->data->{sys}{anvil}{smtp}{smtp_alt_server}, 
						name5 => "sys::anvil::smtp::alt_port",       value5 => $an->data->{sys}{anvil}{smtp}{alt_port}, 
						name6 => "sys::anvil::smtp::username",       value6 => $an->data->{sys}{anvil}{smtp}{username}, 
						name7 => "sys::anvil::smtp::security",       value7 => $an->data->{sys}{anvil}{smtp}{security}, 
						name8 => "sys::anvil::smtp::authentication", value8 => $an->data->{sys}{anvil}{smtp}{authentication}, 
						name9 => "sys::anvil::smtp::helo_domain",    value9 => $an->data->{sys}{anvil}{smtp}{helo_domain}, 
					}, file => $THIS_FILE, line => __LINE__});
					$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
						name1 => "sys::anvil::smtp::password", value1 => $an->data->{sys}{anvil}{smtp}{password}, 
					}, file => $THIS_FILE, line => __LINE__});
					last;
				}
			}
		}
	}
	
	# These will be set to '1' if either the relay file or main.cf need to be updated.
	my $reconfigure = 0;
	
	# Checking to see of the email relay file needs to be created or updated.
	$an->Log->entry({log_level => 3, message_key => "scancore_log_0034", message_variables => {
		postfix_relay_file => $an->data->{path}{postfix_relay_file}, 
	}, file => $THIS_FILE, line => __LINE__});
	if (-e $an->data->{path}{postfix_relay_file})
	{
		# It exists, reading it.
		$an->Log->entry({log_level => 3, message_key => "scancore_log_0035", file => $THIS_FILE, line => __LINE__});
		my $alt_server_found = 0;
		my $shell_call       = $an->data->{path}{postfix_relay_file};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "shell_call", value1 => $shell_call, 
		}, file => $THIS_FILE, line => __LINE__});
		open (my $file_handle, "<$shell_call") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0016", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
		while(<$file_handle>)
		{
			chomp;
			my $line = $_;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "line", value1 => $line, 
			}, file => $THIS_FILE, line => __LINE__});
			if ($line =~ /^\[(.*?)\]:(\d+)\s(.*?):(.*)$/)
			{
				my $server   = $1;
				my $port     = $2;
				my $username = $3;
				my $password = $4;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0006", message_variables => {
					name1 => "server",                     value1 => $server, 
					name2 => "sys::anvil::smtp::server",   value2 => $an->data->{sys}{anvil}{smtp}{server},
					name3 => "port",                       value3 => $port, 
					name4 => "sys::anvil::smtp::port",     value4 => $an->data->{sys}{anvil}{smtp}{port},
					name5 => "username",                   value5 => $username, 
					name6 => "sys::anvil::smtp::username", value6 => $an->data->{sys}{anvil}{smtp}{username},
				}, file => $THIS_FILE, line => __LINE__});
				$an->Log->entry({log_level => 4, message_key => "an_variables_0002", message_variables => {
					name1 => "password",                  value1 => $password, 
					name2 => "sys::anvil::smtp::password", value2 => $an->data->{sys}{anvil}{smtp}{password},
				}, file => $THIS_FILE, line => __LINE__});
				
				if (($server   ne $an->data->{sys}{anvil}{smtp}{server})   or
				    ($port     ne $an->data->{sys}{anvil}{smtp}{port})     or
				    ($username ne $an->data->{sys}{anvil}{smtp}{username}) or
				    ($password ne $an->data->{sys}{anvil}{smtp}{password}))
				{
					# Changes made
					$an->Log->entry({log_level => 3, message_key => "scancore_log_0036", file => $THIS_FILE, line => __LINE__});
					$reconfigure = 1;
				}
				else
				{
					# No change
					$an->Log->entry({log_level => 3, message_key => "scancore_log_0047", file => $THIS_FILE, line => __LINE__});
				}
			}
			
			# If there was a problem, this file might be blanked. If so, rewrite.
			if ($line eq "[]: :")
			{
				$reconfigure = 1;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "reconfigure", value1 => $reconfigure, 
				}, file => $THIS_FILE, line => __LINE__});
			}
		}
		close $file_handle;
	}
	else
	{
		# Relay file doesn't exist at all, so this might be an upgrade. As such, check that the 
		# programs we need are installed.
		$an->Log->entry({log_level => 3, message_key => "scancore_log_0037", file => $THIS_FILE, line => __LINE__});
		$reconfigure = 1;
	}
	
	# Read in mail.cf now and see if anything there changed. If so. we'll update and write it out
	my $smtp_server         = "";
	my $smtp_port           = "";
	my $smtp_alt_server     = "";
	my $smtp_alt_port       = "";
	# These aren't checked yet
	#my $smtp_security       = "";
	#my $smtp_authentication = "";
	#my $smtp_helo_domain    = "";
	my $postfix_main_cf     = "";
	
	### TODO: Re: issue #80 - Add support for alternate/no security.
	# Read it in
	my $shell_call = $an->data->{path}{postfix_main};
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "shell_call", value1 => $shell_call, 
	}, file => $THIS_FILE, line => __LINE__});
	open (my $file_handle, "<$shell_call") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0016", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
	while(<$file_handle>)
	{
		chomp;
		my $line                =  $_;
		   $postfix_main_cf .= "$line\n";
		
		# Find the old values
		if ($line =~ /^relayhost = \[(.*?)\]:(\d+)/)
		{
			$smtp_server = $1;
			$smtp_port   = $2;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "smtp_server", value1 => $smtp_server, 
				name2 => "smtp_port",   value2 => $smtp_port, 
			}, file => $THIS_FILE, line => __LINE__});
			
		}
		if ($line =~ /^smtp_fallback_relay = \[(.*?)\]:(\d+)/)
		{
			$smtp_alt_server = $1;
			$smtp_alt_port   = $2;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
				name1 => "smtp_alt_server", value1 => $smtp_alt_server, 
				name2 => "smtp_alt_port",   value2 => $smtp_alt_port, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	close $file_handle;
	
	# Something changed?
	$an->Log->entry({log_level => 3, message_key => "an_variables_0008", message_variables => {
		name1 => "smtp_server",                  value1 => $smtp_server, 
		name2 => "sys::anvil::smtp::server",     value2 => $an->data->{sys}{anvil}{smtp}{server},
		name3 => "smtp_port",                    value3 => $smtp_port, 
		name4 => "sys::anvil::smtp::port",       value4 => $an->data->{sys}{anvil}{smtp}{port},
		name5 => "smtp_alt_server",              value5 => $smtp_alt_server, 
		name6 => "sys::anvil::smtp::alt_server", value6 => $an->data->{sys}{anvil}{smtp}{alt_server},
		name7 => "smtp_alt_port",                value7 => $smtp_alt_port, 
		name8 => "sys::anvil::smtp::alt_port",   value8 => $an->data->{sys}{anvil}{smtp}{alt_port},
	}, file => $THIS_FILE, line => __LINE__});
	if (($smtp_server     ne $an->data->{sys}{anvil}{smtp}{server})     or
	    ($smtp_port       ne $an->data->{sys}{anvil}{smtp}{port})       or 
	    ($smtp_alt_server ne $an->data->{sys}{anvil}{smtp}{alt_server}) or
	    ($smtp_alt_port   ne $an->data->{sys}{anvil}{smtp}{alt_port}))
	{
		$reconfigure = 1;
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "reconfigure", value1 => $reconfigure, 
		}, file => $THIS_FILE, line => __LINE__});
	}
	
	# (Re)write the relay file now, if needed.
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "reconfigure", value1 => $reconfigure, 
	}, file => $THIS_FILE, line => __LINE__});
	if ($reconfigure)
	{
		# Write the new relay file.
		$an->Log->entry({log_level => 1, message_key => "scancore_log_0038", message_variables => { postfix_relay_file => $an->data->{path}{postfix_relay_file} }, file => $THIS_FILE, line => __LINE__});
		
		my $shell_call = $an->data->{path}{postfix_relay_file};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "shell_call", value1 => $shell_call, 
		}, file => $THIS_FILE, line => __LINE__});
		
		my $postfix_line = "[".$an->data->{sys}{anvil}{smtp}{server}."]:".$an->data->{sys}{anvil}{smtp}{port}." ".$an->data->{sys}{anvil}{smtp}{username}.":".$an->data->{sys}{anvil}{smtp}{password};
		$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
			name1 => "postfix_line", value1 => $postfix_line,
		}, file => $THIS_FILE, line => __LINE__});
		
		open (my $file_handle, ">$shell_call") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0015", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
		print $file_handle "$postfix_line\n";
		close $file_handle;
		
		# Generate the binary version.
		$an->Log->entry({log_level => 1, message_key => "scancore_log_0039", file => $THIS_FILE, line => __LINE__});
		
		$shell_call = $an->data->{path}{postmap}." ".$an->data->{path}{postfix_relay_file};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "shell_call", value1 => $shell_call, 
		}, file => $THIS_FILE, line => __LINE__});
		open ($file_handle, $shell_call." 2>&1 |") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0014", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
		while(<$file_handle>)
		{
			chomp;
			my $line = $_;
			### This can contain a password, so log level is 4.
			$an->Log->entry({log_level => 4, message_key => "an_variables_0001", message_variables => {
				name1 => "line", value1 => $line, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		close $file_handle;
		
		# If I am writing the file, there is a chance that postfix hasn't been configured yet. So 
		# check it and, if needed, fix it.
		my $backup_file = $an->data->{path}{postfix_main}.".anvil";
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "backup_file", value1 => $backup_file, 
		}, file => $THIS_FILE, line => __LINE__});
		
		if (not -e $backup_file)
		{
			# Backup the original.
			$an->Log->entry({log_level => 3, message_key => "scancore_log_0034", message_variables => {
				source      => $an->data->{path}{postfix_main},
				destination =>  $backup_file,
			}, file => $THIS_FILE, line => __LINE__});
			
			my $shell_call = $an->data->{path}{cp}." --archive --no-clobber --verbose ".$an->data->{path}{postfix_main}." $backup_file";
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "shell_call", value1 => $shell_call, 
			}, file => $THIS_FILE, line => __LINE__});
			open (my $file_handle, $shell_call." 2>&1 |") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0014", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
			while(<$file_handle>)
			{
				chomp;
				my $line = $_;
				$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
					name1 => "line", value1 => $line, 
				}, file => $THIS_FILE, line => __LINE__});
			}
			close $file_handle;
		}
		else
		{
			# Already backed up
			$an->Log->entry({log_level => 3, message_key => "scancore_log_0040", file => $THIS_FILE, line => __LINE__});
		}
		
		# Now update the postfix main.cf file by reading it in and replacing the variables we want to
		# update, then writing it all back out.
		my $postfix_main = "";
		$an->Log->entry({log_level => 3, message_key => "scancore_log_0041", message_variables => { postfix_main => $an->data->{path}{postfix_main} }, file => $THIS_FILE, line => __LINE__});
		
		$shell_call = $an->data->{path}{postfix_main};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "shell_call", value1 => $shell_call, 
		}, file => $THIS_FILE, line => __LINE__});
		open ($file_handle, "<$shell_call") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0016", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
		while(<$file_handle>)
		{
			chomp;
			my $line = $_;
			
			# Avoid duplicates
			next if $line =~ /^relayhost = \[/;
			next if $line =~ /^smtp_use_tls =/;
			next if $line =~ /^smtp_sasl_auth_enable =/;
			next if $line =~ /^smtp_sasl_password_maps =/;
			next if $line =~ /^smtp_sasl_security_options =/;
			next if $line =~ /^smtp_tls_CAfile =/;
			next if $line =~ /^smtp_fallback_relay =/;
			next if $line =~ /^smtp_helo_name =/;
			
			if ($line =~ /#relayhost = \[an.ip.add.ress\]/)
			{
				# Insert the mail relay configuration here.
				$an->Log->entry({log_level => 3, message_key => "scancore_log_0042", file => $THIS_FILE, line => __LINE__});
				
				# TODO: Experiment if I really need to define the mail server and IP both 
				#       here and in the relay file.
				$postfix_main .= "$line\n";
				$postfix_main .= "relayhost = [".$an->data->{sys}{anvil}{smtp}{server}."]:".$an->data->{sys}{anvil}{smtp}{port}."\n";
				if ($an->data->{sys}{anvil}{smtp}{alt_server})
				{
					my $port         =  $an->data->{sys}{anvil}{smtp}{alt_port} ? $an->data->{sys}{anvil}{smtp}{alt_port} : $an->data->{sys}{anvil}{smtp}{port};
					   $postfix_main .= "smtp_fallback_relay = [".$an->data->{sys}{anvil}{smtp}{alt_server}."]:$port\n";
				}
				   $postfix_main .= "smtp_helo_name = ".$an->data->{sys}{anvil}{smtp}{helo_domain}."\n";
				$postfix_main .= "smtp_use_tls = yes\n";
				$postfix_main .= "smtp_sasl_auth_enable = yes\n";
				$postfix_main .= "smtp_sasl_password_maps = hash:".$an->data->{path}{postfix_relay_file}."\n";
				$postfix_main .= "smtp_sasl_security_options =\n";
				$postfix_main .= "smtp_tls_CAfile = /etc/pki/tls/certs/ca-bundle.crt\n";
			}
			else
			{
				$postfix_main .= "$line\n";
			}
		}
		close $file_handle;
		
		# Write out the new version.
		$an->Log->entry({log_level => 3, message_key => "scancore_log_0043", message_variables => { postfix_main => $an->data->{path}{postfix_main} }, file => $THIS_FILE, line => __LINE__});
		
		# Record the config in the main log
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "postfix_main", value1 => $postfix_main, 
		}, file => $THIS_FILE, line => __LINE__});
		
		# Do the actual write...
		$shell_call = $an->data->{path}{postfix_main};
		$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
			name1 => "shell_call", value1 => $shell_call, 
		}, file => $THIS_FILE, line => __LINE__});
		open ($file_handle, ">$shell_call") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0015", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
		print $file_handle $postfix_main;
		close $file_handle;
		
		# Reload postfix
		$an->Log->entry({log_level => 1, message_key => "scancore_log_0044", file => $THIS_FILE, line => __LINE__});
		$shell_call = $an->data->{path}{initd}."/postfix restart";
		open ($file_handle, $shell_call." 2>&1 |") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0014", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
		while(<$file_handle>)
		{
			chomp;
			my $line = $_;
			$line =~ s/\n//g;
			$line =~ s/\r//g;
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "line", value1 => $line, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		close $file_handle;
		sleep 2;
	}
	
	# Make sure the mail alerts directory exists and create it if not.
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "path::alert_emails", value1 => $an->data->{path}{alert_emails}, 
	}, file => $THIS_FILE, line => __LINE__});
	if (-e $an->data->{path}{alert_emails})
	{
		$an->Log->entry({log_level => 3, message_key => "scancore_log_0055", message_variables => { email_directory => $an->data->{path}{alert_emails} }, file => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Need to create it.
		$an->Log->entry({log_level => 2, message_key => "scancore_log_0045", message_variables => { email_directory => $an->data->{path}{alert_emails} }, file => $THIS_FILE, line => __LINE__});
		
		mkdir $an->data->{path}{alert_emails} or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0019", message_variables => {
								directory => $an->data->{path}{alert_emails}, 
								error     => $! 
							}, code => 2, file => $THIS_FILE, line => __LINE__});
		
		# Set the mode
		my $directory_mode = 0775;
		$an->Log->entry({log_level => 3, message_key => "scancore_log_0046", message_variables => { directory_mode => sprintf("%04o", $directory_mode) }, file => $THIS_FILE, line => __LINE__});
		chmod $directory_mode, $an->data->{path}{alert_emails};
	}
	
	return(0);
}

# This translates the string when appropriate.
sub translate_strings
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	my $string = $parameter->{string};

	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "translate_strings" }, message_key => "an_variables_0002", message_variables => { 
		name1 => "string",     value1 => $string, 
		name2 => "lc(string)", value2 => lc($string), 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $return = "";
	if (lc($string) eq "yes")
	{
		$return = $an->String->get({key => "tools_suffix_0047"});
	}
	elsif (lc($string) eq "no")
	{
		$return = $an->String->get({key => "tools_suffix_0048"});
	}
	elsif (lc($string) eq "enabled")
	{
		$return = $an->String->get({key => "tools_suffix_0049"});
	}
	elsif (lc($string) eq "disabled")
	{
		$return = $an->String->get({key => "tools_suffix_0050"});
	}
	elsif (lc($string) eq "on")
	{
		$return = $an->String->get({key => "tools_suffix_0051"});
	}
	elsif (lc($string) eq "off")
	{
		$return = $an->String->get({key => "tools_suffix_0052"});
	}
	### TODO: Add these to the wiki
	elsif (lc($string) eq "optimal")
	{
		$return = $an->String->get({key => "tools_suffix_0053"});
	}
	elsif (lc($string) eq "partially degraded")
	{
		$return = $an->String->get({key => "tools_suffix_0054"});
	}
	elsif (lc($string) eq "degraded")
	{
		$return = $an->String->get({key => "tools_suffix_0055"});
	}
	elsif (lc($string) eq "no pending images")
	{
		$return = $an->String->get({key => "tools_suffix_0056"});
	}
	elsif ((lc($string) eq "auto") or (lc($string) eq "automatic"))
	{
		$return = $an->String->get({key => "tools_suffix_0057"});
	}
	elsif (lc($string) eq "allowed")
	{
		$return = $an->String->get({key => "tools_suffix_0059"});
	}
	elsif (lc($string) eq "not allowed")
	{
		$return = $an->String->get({key => "tools_suffix_0060"});
	}
	elsif (lc($string) eq "present")
	{
		$return = $an->String->get({key => "tools_suffix_0061"});
	}
	elsif (lc($string) eq "absent")
	{
		$return = $an->String->get({key => "tools_suffix_0062"});
	}
	elsif (lc($string) eq "missing")
	{
		$return = $an->String->get({key => "tools_suffix_0067"});
	}
	elsif (lc($string) eq "read ahead")
	{
		$return = $an->String->get({key => "tools_suffix_0063"});
	}
	elsif (lc($string) eq "no read ahead")
	{
		$return = $an->String->get({key => "tools_suffix_0064"});
	}
	elsif ((lc($string) eq "na") or (lc($string) eq "n/a"))
	{
		$return = $an->String->get({key => "tools_suffix_0065"});
	}
	elsif (lc($string) eq "none")
	{
		$return = $an->String->get({key => "tools_suffix_0066"});
	}
	elsif (lc($string) eq "battery is not being charged")
	{
		$return = $an->String->get({key => "tools_suffix_0068"});
	}
	elsif (lc($string) eq "lion")
	{
		$return = $an->String->get({key => "tools_suffix_0071"});
	}
	elsif (lc($string) eq "transparent")
	{
		$return = $an->String->get({key => "tools_suffix_0072"});
	}
	elsif (lc($string) eq "inconsistent")
	{
		$return = $an->String->get({key => "tools_suffix_0075"});
	}
	elsif (lc($string) eq "consistent")
	{
		$return = $an->String->get({key => "tools_suffix_0074"});
	}
	elsif (lc($string) eq "direct io")
	{
		$return = $an->String->get({key => "tools_suffix_0076"});
	}
	elsif (lc($string) eq "hdd")
	{
		$return = $an->String->get({key => "tools_suffix_0077"});
	}
	elsif (lc($string) eq "ssd")
	{
		$return = $an->String->get({key => "tools_suffix_0078"});
	}
	elsif (lc($string) eq "sas")
	{
		$return = $an->String->get({key => "tools_suffix_0079"});
	}
	elsif (lc($string) eq "sata")
	{
		$return = $an->String->get({key => "tools_suffix_0080"});
	}
	elsif (lc($string) eq "rbld")
	{
		$return = $an->String->get({key => "tools_suffix_0081"});
	}
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "return",  value1 => $return, 
	}, file => $THIS_FILE, line => __LINE__});
	return($return);
}

### NOTE: This is called loosely. It is entirely possible that 'units' is NOT valid. Simply return nothing in
###       such cases.
# This looks at the 'unit' and if it is one of the ones described in the ScanCore "Unit Parsing" page, 
# translate it. See: https://alteeve.com/w/ScanCore#Unit_Parsing
sub translate_units
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	my $value = $parameter->{value};
	my $units = $parameter->{units};
	my $user_units = defined $parameter->{user_units} ? $parameter->{user_units} : "metric";

	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "translate_units" }, message_key => "an_variables_0003", message_variables => { 
		name1 => "value",      value1 => $value, 
		name2 => "units",      value2 => $units, 
		name3 => "user_units", value3 => $user_units, 
	}, file => $THIS_FILE, line => __LINE__});
	
	my $return = "";
	
	# This won't modify and values with a space in them.
	if (($value eq "") or ($value =~ /\s/))
	{
		return($return);
	}
	
	if ($units eq "%")
	{
		$return = $value.$an->String->get({key => "tools_suffix_0016"});
	}
	elsif ($units eq "W")
	{
		$return = $value.$an->String->get({key => "tools_suffix_0017"});
	}
	elsif ($units eq "vDC")
	{
		$return = $value.$an->String->get({key => "tools_suffix_0018"});
	}
	elsif ($units eq "vAC")
	{
		$return = $value.$an->String->get({key => "tools_suffix_0019"});
	}
	elsif ($units eq "A")
	{
		$return = $value.$an->String->get({key => "tools_suffix_0020"});
	}
	elsif ($units eq "RPM")
	{
		$return = $value.$an->String->get({key => "tools_suffix_0021"});
	}
	elsif ($units eq "Bps")
	{
		$return = $value.$an->String->get({key => "tools_suffix_0022"});
	}
	elsif ($units eq "Kbps")
	{
		$return = $value.$an->String->get({key => "tools_suffix_0023"});
	}
	elsif ($units eq "Mbps")
	{
		$return = $value.$an->String->get({key => "tools_suffix_0024"});
	}
	elsif ($units eq "Gbps")
	{
		$return = $value.$an->String->get({key => "tools_suffix_0025"});
	}
	elsif ($units eq "Tbps")
	{
		$return = $value.$an->String->get({key => "tools_suffix_0026"});
	}
	elsif (($value =~ /^\d+$/) && ($units eq "Bytes"))
	{
		$return = $an->Readable->bytes_to_hr({'bytes' => $value});
	}
	elsif (($value =~ /^\d+$/) && ($units eq "sec"))
	{
		$return = $an->Readable->time({'time' => $value});
	}
	# Don't confuse this with 'Seconds', which is NOT converted.
	elsif (($value =~ /^\d+$/) && ($units eq "seconds"))
	{
		$return = $an->Readable->time({'time' => $value, suffix => "long"});
	}
	elsif ($units eq "Second")
	{
		$return = $value." ".$an->String->get({key => "tools_suffix_0037"});
	}
	elsif ($units eq "Seconds")
	{
		$return = $value." ".$an->String->get({key => "tools_suffix_0038"});
	}
	elsif ($units eq "Minute")
	{
		$return = $value." ".$an->String->get({key => "tools_suffix_0039"});
	}
	elsif ($units eq "Minutes")
	{
		$return = $value." ".$an->String->get({key => "tools_suffix_0040"});
	}
	elsif ($units eq "Hour")
	{
		$return = $value." ".$an->String->get({key => "tools_suffix_0041"});
	}
	elsif ($units eq "Hours")
	{
		$return = $value." ".$an->String->get({key => "tools_suffix_0042"});
	}
	elsif ($units eq "Day")
	{
		$return = $value." ".$an->String->get({key => "tools_suffix_0043"});
	}
	elsif ($units eq "Days")
	{
		$return = $value." ".$an->String->get({key => "tools_suffix_0044"});
	}
	elsif ($units eq "Week")
	{
		$return = $value." ".$an->String->get({key => "tools_suffix_0045"});
	}
	elsif ($units eq "C")
	{
		# Temperature, convert to the user's desired units.
		if ($user_units eq "metric")
		{
			# Leave as °C
			$return = $value." ".$an->String->get({key => "tools_suffix_0010"});
		}
		else
		{
			# Convert to °F
			$return = $an->Convert->convert_to_fahrenheit({temperature => $value})." ".$an->String->get({key => "tools_suffix_0012"});
		}
	}
	### TODO: Add to wiki
	elsif ($units eq "Sectors")
	{
		$return = $value." ".$an->String->get({key => "tools_suffix_0058"});
	}
	elsif ($units eq "mAh")
	{
		$return = $value.$an->String->get({key => "tools_suffix_0070"});
	}
	elsif ($units eq "mA")
	{
		$return = $value.$an->String->get({key => "tools_suffix_0069"});
	}
	elsif ($units eq "J")
	{
		$return = $value.$an->String->get({key => "tools_suffix_0073"});
	}
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "return",  value1 => $return, 
	}, file => $THIS_FILE, line => __LINE__});
	return($return)
}

# This and translate_sensor_value() are special functions used to translate IPMI sensor data into a user's 
# chosen language and units (metric v. imperial).
sub translate_sensor_name
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	my $ipmitool_sensor_name = $parameter->{ipmitool_sensor_name};
	my $ipmitool_sensor_units = $parameter->{ipmitool_sensor_units};

	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "translate_sensor_name" }, message_key => "an_variables_0002", message_variables => { 
		name1 => "ipmitool_sensor_name",  value1 => $ipmitool_sensor_name, 
		name2 => "ipmitool_sensor_units", value2 => $ipmitool_sensor_units, 
	}, file => $THIS_FILE, line => __LINE__});
	
	if (not defined $ipmitool_sensor_units)
	{
		$an->Log->entry({log_level => 1, message_key => "an_variables_0002", message_variables => {
			name1 => "ipmitool_sensor_name",  value1 => $ipmitool_sensor_name, 
			name2 => "ipmitool_sensor_units", value2 => $ipmitool_sensor_units, 
		}, file => $THIS_FILE, line => __LINE__});
		return($ipmitool_sensor_name)
	}
	
	my $say_sensor_name = $ipmitool_sensor_name;
	
	# Now, if it is a sensor we know, we'll not use the base units but instead five it a proper name. 
	# We'll translate the value after.
	my $say_units = $ipmitool_sensor_units;
	if ($ipmitool_sensor_units eq "C")
	{
		if ($say_sensor_name eq "Ambient")
		{
			$say_units = $an->String->get({key => "scan_ipmitool_sensor_name_0001"});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /CPU(\d+)/)
		{
			my $cpu       = $1;
			   $say_units = $an->String->get({
				key	=>	"scan_ipmitool_sensor_name_0003",
				variables	=>	{
					cpu		=>	$cpu,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /DIMM-(.*)/)
		{
			my $module    = $1;
			   $say_units = $an->String->get({
				key	=>	"scan_ipmitool_sensor_name_0006",
				variables	=>	{
					module		=>	$module,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /Systemboard/)
		{
			$say_units = $an->String->get({key => "scan_ipmitool_sensor_name_0023"});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	elsif ($ipmitool_sensor_units eq "V")
	{
		if ($say_sensor_name =~ /BATT (\d+\.?\d+?)V/)
		{
			my $voltage   = $1;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0002", 
				variables	=>	{
					voltage		=>	$voltage,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /CPU(\d+) (\d+\.?\d+?)V/)
		{
			my $cpu       = $1;
			my $voltage   = $2;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0004", 
				variables	=>	{
					cpu		=>	$cpu,
					voltage		=>	$voltage,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /ICH (\d+\.?\d+?)V/)
		{
			my $voltage   = $1;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0013", 
				variables	=>	{
					voltage		=>	$voltage,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /IOH (\d+\.?\d+?)V AUX/)
		{
			my $voltage   = $1;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0014", 
				variables	=>	{
					voltage		=>	$voltage,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /IOH (\d+\.?\d+?)V/)
		{
			my $voltage   = $1;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0015", 
				variables	=>	{
					voltage		=>	$voltage,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /iRMC (\d+\.?\d+?)V STBY/)
		{
			my $voltage   = $1;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0016", 
				variables	=>	{
					voltage		=>	$voltage,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /LAN (\d+\.?\d+?)V STBY/)
		{
			my $voltage   = $1;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0017", 
				variables	=>	{
					voltage		=>	$voltage,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /MAIN (\d+\.?\d+?)V/)
		{
			my $voltage   = $1;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0018", 
				variables	=>	{
					voltage		=>	$voltage,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /STBY (\d+\.?\d+?)V/)
		{
			my $voltage   = $1;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0022", 
				variables	=>	{
					voltage		=>	$voltage,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	elsif ($ipmitool_sensor_units eq "W")
	{
		if ($say_sensor_name =~ /CPU(\d+) Power/)
		{
			my $cpu       = $1;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0005", 
				variables	=>	{
					cpu		=>	$cpu,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /Fan Power/)
		{
			$say_units = $an->String->get({key => "scan_ipmitool_sensor_name_0010"});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /HDD Power/)
		{
			$say_units = $an->String->get({key => "scan_ipmitool_sensor_name_0011"});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /Memory Power/)
		{
			$say_units = $an->String->get({key => "scan_ipmitool_sensor_name_0019"});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /PSU(\d+) Power/)
		{
			my $psu       = $1;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0020", 
				variables	=>	{
					psu		=>	$psu,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /Total Power/)
		{
			$say_units = $an->String->get({key => "scan_ipmitool_sensor_name_0024"});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	elsif ($ipmitool_sensor_units eq "%")
	{
		if ($say_sensor_name =~ /I2C(\d+) error ratio/)
		{
			my $channel   = $1;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0012", 
				variables	=>	{
					channel		=>	$channel,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /SEL Level/)
		{
			$say_units = $an->String->get({key => "scan_ipmitool_sensor_name_0021"});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	elsif ($ipmitool_sensor_units eq "RPM")
	{
		if ($say_sensor_name =~ /FAN(\d+) PSU(\d+)/)
		{
			my $fan       = $1;
			my $psu       = $2;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0007", 
				variables	=>	{
					psu		=>	$psu,
					fan		=>	$fan,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /FAN(\d+) PSU/)
		{
			my $fan       = $1;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0008", 
				variables	=>	{
					fan		=>	$fan,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
		elsif ($say_sensor_name =~ /FAN(\d+) SYS/)
		{
			my $fan       = $1;
			   $say_units = $an->String->get({
				key		=>	"scan_ipmitool_sensor_name_0009", 
				variables	=>	{
					fan		=>	$fan,
				},
			});
			$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
				name1 => "say_units", value1 => $say_units, 
			}, file => $THIS_FILE, line => __LINE__});
		}
	}
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "say_sensor_name",  value1 => $say_sensor_name, 
	}, file => $THIS_FILE, line => __LINE__});
	return($say_sensor_name)
}

# This and translate_sensor_name() are special functions used to translate 
# PMI sensor data into a user's chosen language and units (metric v. imperial).
sub translate_sensor_value
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

	my $ipmitool_value_sensor_value = $parameter->{ipmitool_value_sensor_value};
	my $ipmitool_sensor_units = $parameter->{ipmitool_sensor_units};
	my $units = $parameter->{units};

	$an->Log->entry({log_level => 3, title_key => "tools_log_0001", title_variables => { function => "translate_sensor_value" }, message_key => "an_variables_0003", message_variables => { 
		name1 => "ipmitool_value_sensor_value", value1 => $ipmitool_value_sensor_value, 
		name2 => "ipmitool_sensor_units",       value2 => $ipmitool_sensor_units, 
		name3 => "units",                       value3 => $units, 
	}, file => $THIS_FILE, line => __LINE__});
	$units = "metric" if not $units;
	
	# Translate the sensor units.
	my $say_units = $ipmitool_sensor_units;
	if ($say_units eq "C")
	{
		if ($units eq "metric")
		{
			# Leave as °C
			$say_units = $an->String->get({key => "tools_suffix_0010"});
		}
		else
		{
			# Convert to °F
			$say_units                   = $an->String->get({key => "tools_suffix_0012"});
			$ipmitool_value_sensor_value = $an->Convert->convert_to_fahrenheit({temperature => $ipmitool_value_sensor_value});
		}
	} # Already °C at this time
	elsif ($say_units eq "%")   { $say_units = $an->String->get({key => "tools_suffix_0016"}); }
	elsif ($say_units eq "W")   { $say_units = $an->String->get({key => "tools_suffix_0017"}); } # watts
	elsif ($say_units eq "V")   { $say_units = $an->String->get({key => "tools_suffix_0018"}); } # vDC is always assumed, may need to update this later.
	elsif ($say_units eq "RPM") { $say_units = $an->String->get({key => "tools_suffix_0021"}); } # rotations per minute.
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "say_units", value1 => $say_units, 
	}, file => $THIS_FILE, line => __LINE__});
	
	# Put them together
	my $say_sensor_value = "$ipmitool_value_sensor_value $say_units";
	
	$an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
		name1 => "say_sensor_value", value1 => $say_sensor_value, 
	}, file => $THIS_FILE, line => __LINE__});
	return($say_sensor_value);
}

#############################################################################################################
# Internal methods                                                                                          #
#############################################################################################################

1;
