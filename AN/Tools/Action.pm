package AN::Tools::Action;

use strict;
use warnings;
use Data::Dumper;

our $VERSION  = "0.1.001";
my $THIS_FILE = "Action.pm";

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

sub decide
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    if ($parameter->{decision})
    {
        # Set this in striker.conf; 0 or 1
        if ((not $parameter->{external}) && ($an->data->{scancore}{prevent_decision_making}))
        {
            $an->Log->entry({log_level => 0, title_key => "tools_title_0006", message_key => "scancore_log_0099", message_variables => {
                decision_number => $parameter->{decision}
            }, file => $THIS_FILE, line => __LINE__});
        }
        else
        {
            # Get all pending decisions from the decisions table to determine the next order number
            my $query = "
SELECT
    decision_uuid,
    decision_host_uuid,
    decision_order,
    decision_parameters,
    modified_date
FROM
    decisions
WHERE
    decision_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{host_uuid})."
ORDER BY
    decision_order ASC
;
";
            my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
            my $count   = @{$results};
            $an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
                name1 => "results", value1 => $results,
                name2 => "count",   value2 => $count
            }, file => $THIS_FILE, line => __LINE__});

            my $decision_order = $count + 1;

            my $decision_parameters_stringifier = Data::Dumper->new([$parameter]);
            # Remove unnecessary whitespace
            $decision_parameters_stringifier->Indent(0);
            # Remove excess characters that were added during the to_string operation
            my ($decision_parameters) = $decision_parameters_stringifier->Dump =~ m/= (.*);/g;

            $query = "
INSERT INTO
    decisions
(
    decision_uuid,
    decision_host_uuid,
    decision_order,
    decision_parameters,
    modified_date
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($an->Get->uuid()).",
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{host_uuid}).",
    ".$an->data->{sys}{use_db_fh}->quote($decision_order).",
    ".$an->data->{sys}{use_db_fh}->quote($decision_parameters).",
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
            $an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
        }
    }
}

sub act
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    my $query = "
SELECT
    decision_uuid,
    decision_host_uuid,
    decision_order,
    decision_parameters,
    modified_date
FROM
    decisions
WHERE
    decision_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{host_uuid})."
ORDER BY
    decision_order ASC
;
";
    my $results = $an->DB->do_db_query({query => $query, source => $THIS_FILE, line => __LINE__});
    my $count   = @{$results};
    $an->Log->entry({log_level => 3, message_key => "an_variables_0002", message_variables => {
        name1 => "results", value1 => $results, 
        name2 => "count",   value2 => $count
    }, file => $THIS_FILE, line => __LINE__});

    foreach my $row (@{$results})
    {
        my $decision_uuid                   = $row->[0];
        my $decision_host_uuid              = $row->[1];
        my $decision_order                  = $row->[2];
        my $decision_parameters_string      = $row->[3];
        my $modified_date                   = $row->[4];
        $an->Log->entry({log_level => 3, message_key => "an_variables_0005", message_variables => {
            name1 => "decision_uuid",               value1 => $decision_uuid,
            name2 => "decision_host_uuid",          value2 => $decision_host_uuid,
            name3 => "decision_order",              value3 => $decision_order,
            name4 => "decision_parameters_string",  value4 => $decision_parameters_string,
            name5 => "modified_date",               value5 => $modified_date,
        }, file => $THIS_FILE, line => __LINE__});

        # Remove the pending decision entry; it doesn't matter whether the action succeeds or fails
        $query = "
DELETE FROM
    decisions
WHERE
    decision_uuid = ".$an->data->{sys}{use_db_fh}->quote($decision_uuid)."
;
";
        $an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});

        my $decision_parameters_hash = eval $decision_parameters_string;
        $an->Action->execute_decision($decision_parameters_hash);
    }
}

sub execute_decision
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    my $decision = defined $parameter->{decision} ? $parameter->{decision} : 0;

    $an->Log->entry({log_level => 3, message_key => "an_variables_0001", message_variables => {
        name1 => "decision", value1 => $decision,
    }, file => $THIS_FILE, line => __LINE__});

    if ($decision == 1)
    {
        # Node action - enter power OK state
        $an->Action->node_action_enter_ok_state($parameter);
        $an->Action->node_log_power_clear();
    }
    elsif ($decision == 2)
    {
        # Node action - enter temperature OK state
        $an->Action->node_action_enter_ok_state($parameter);
        $an->Action->node_log_temperature_clear();
    }
    elsif ($decision == 3)
    {
        # Node action - enter power warning state
        $an->Action->node_action_enter_warning_state($parameter);
        $an->Action->node_log_power_warning();
    }
    elsif ($decision == 4)
    {
        # Node action - enter temperature warning state
        $an->Action->node_action_enter_warning_state($parameter);
        $an->Action->node_log_temperature_warning();
    }
    elsif ($decision == 5)
    {
        $parameter->{host_stop_reason} = "power";
        # Node action - shutdown self
        $an->Action->node_action_shutdown_self($parameter);
        $an->Action->node_log_power_critical();
    }
    elsif ($decision == 6)
    {
        $parameter->{host_stop_reason} = "temperature";
        # Node action - shutdown self
        $an->Action->node_action_shutdown_self($parameter);
        $an->Action->node_log_temperature_critical();
    }
    elsif ($decision == 7)
    {
        $parameter->{load_shed_reason} = "power";
        # Node action - shed load
        $an->Action->node_action_shed_load($parameter);
        $an->Action->node_log_power_warning();
    }
    elsif ($decision == 8)
    {
        $parameter->{load_shed_reason} = "temperature";
        # Node action - shed load
        $an->Action->node_action_shed_load($parameter);
        $an->Action->node_log_temperature_warning();
    }
    elsif ($decision == 9)
    {
        # Node action - migrate (pull) servers
        $an->Action->node_action_migrate_servers($parameter);
    }
    elsif ($decision == 10)
    {
        # Dashboard action - boot node
        $an->Action->dashboard_action_boot_node($parameter);
    }
    elsif ($decision == 11)
    {
        # Dashboard action - reboot node
        $an->Action->dashboard_action_reboot_node($parameter);
    }
}

sub node_action_enter_ok_state
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    # Set the health to 'OK'.
    $an->ScanCore->host_state({set => "ok"});
    
    # If we were previously sick, tell the user that we're OK now.
    my $cleared_node_sick = $an->Alert->check_alert_sent({
        type			=>	"clear",
        alert_sent_by		=>	$THIS_FILE,
        alert_record_locator	=>	$an->hostname,
        alert_name		=>	"node_sick",
        modified_date		=>	$an->data->{sys}{db_timestamp},
    });

    my $cleared_poweroff = $an->Alert->check_alert_sent({
        type			=>	"clear",
        alert_sent_by		=>	$THIS_FILE,
        alert_record_locator	=>	$an->hostname,
        alert_name		=>	"shutdown_should_have_happened",
        modified_date		=>	$an->data->{sys}{db_timestamp},
    });

    my $cleared_load_shed = $an->Alert->check_alert_sent({
        type			=>	"clear",
        alert_sent_by		=>	$THIS_FILE,
        alert_record_locator	=>	$an->hostname,
        alert_name		=>	"load_shed_needed",
        modified_date		=>	$an->data->{sys}{db_timestamp},
    });

    if ($cleared_node_sick)
    {
        # Tell the user that we're OK.
        $an->Alert->register_alert({
            alert_level		=>	"warning", 
            alert_agent_name	=>	$THIS_FILE,
            alert_title_key		=>	"an_alert_title_0006",
            alert_message_key	=>	"scancore_warning_0013",
            alert_message_variables	=>	{
                node			=>	$an->hostname,
            },
        });
        
        # Send the email
        $an->ScanCore->process_alerts();
    }
}

sub node_action_enter_warning_state
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    # Set the health to 'Warning'.
    $an->ScanCore->host_state({set => "warning"});
    
    # Tell the user that we're no longer a migration target.
    my $set = $an->Alert->check_alert_sent({
        type			=>	"warning",
        alert_sent_by		=>	$THIS_FILE,
        alert_record_locator	=>	$an->hostname,
        alert_name		=>	"node_sick",
        modified_date		=>	$an->data->{sys}{db_timestamp},
    });

    if ($set)
    {
        $an->Alert->register_alert({
            alert_level		=>	"warning", 
            alert_agent_name	=>	$THIS_FILE,
            alert_title_key		=>	"an_alert_title_0004",
            alert_message_key	=>	"scancore_warning_0012",
            alert_message_variables	=>	{
                node			=>	$an->hostname,
            },
        });
        
        # Send the email
        $an->ScanCore->process_alerts();
    }
}

sub node_action_shutdown_self
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
    
    my $host_stop_reason = $parameter->{host_stop_reason};
    
    # Set the health to 'Critical'.
    $an->ScanCore->host_state({set => "critical"});
    
    # Update hosts to set host_emergency_stop to TRUE
    my $query = "
UPDATE 
    hosts 
SET 
    host_emergency_stop = TRUE, 
    host_stop_reason    = ".$an->data->{sys}{use_db_fh}->quote($host_stop_reason).", 
    host_health         = 'critical', 
    modified_date       = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
WHERE 
    host_uuid           = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{host_uuid}).";";
    $query =~ s/'NULL'/NULL/g;
    $an->Log->entry({log_level => 1, message_key => "an_variables_0001", message_variables => {
        name1 => "query", value1 => $query,
    }, file => $THIS_FILE, line => __LINE__});
    $an->DB->do_db_write({query => $query, source => $THIS_FILE, line => __LINE__});
    
    my $do_shutdown = 1;
    my $message_key = "scancore_error_0015";
    if ((($host_stop_reason eq "power")       && ($an->data->{scancore}{disable}{power_shutdown})) or 
        (($host_stop_reason eq "temperature") && ($an->data->{scancore}{disable}{thermal_shutdown})))
    {
        # Shutdown has been disabled.
        $do_shutdown = 0;
        $message_key = "scancore_error_0016";
        
        # Tell the user what's (not) happening
        if ($host_stop_reason eq "power")
        {
            # Power shutdown disabled.
            $an->Log->entry({log_level => 0, message_key => "scancore_warning_0017", file => $THIS_FILE, line => __LINE__});
        }
        elsif ($host_stop_reason eq "temperature")
        {
            # Thermal shutdown disabled.
            $an->Log->entry({log_level => 0, message_key => "scancore_warning_0018", file => $THIS_FILE, line => __LINE__});
        }
    }
    elsif ($host_stop_reason eq "power")
    {
        # Power shutdown enabled, we're going down.
        $an->Log->entry({log_level => 0, message_key => "scancore_warning_0019", file => $THIS_FILE, line => __LINE__});
    }
    elsif ($host_stop_reason eq "temperature")
    {
        # Thermal shutdown enabled, we're going down
        $an->Log->entry({log_level => 0, message_key => "scancore_warning_0020", file => $THIS_FILE, line => __LINE__});
    }
    # Send our final email.
    $an->Alert->register_alert({
        alert_level		=>	"critical", 
        alert_agent_name	=>	$THIS_FILE,
        alert_title_key		=>	"an_alert_title_0005",
        alert_message_key	=>	$message_key,
        alert_message_variables	=>	{
            node			=>	$an->hostname,
        },
    });
    
    # Send the email
    $an->ScanCore->process_alerts();
    
    if ($do_shutdown)
    {
        # Stop the anvil-kick-apc-ups if it is in use.
        my $stop_kicking = 0;
        my $shell_call   = $an->data->{path}{'anvil-kick-apc-ups'}." --status";
        $an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
            name1 => "shell_call", value1 => $shell_call, 
        }, file => $THIS_FILE, line => __LINE__});
        open (my $file_handle, "$shell_call 2>&1 |") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0014", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
        while(<$file_handle>)
        {
            chomp;
            my $line = $_;
            $an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
                name1 => "line", value1 => $line, 
            }, file => $THIS_FILE, line => __LINE__});
            if ($line =~ /\[enabled\]/)
            {
                $stop_kicking = 1;
                $an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
                    name1 => "stop_kicking", value1 => $stop_kicking, 
                }, file => $THIS_FILE, line => __LINE__});
            }
        }
        close $file_handle;
        if ($stop_kicking)
        {
            my $shell_call = $an->data->{path}{'anvil-kick-apc-ups'}." --cancel";
            $an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
                name1 => "shell_call", value1 => $shell_call, 
            }, file => $THIS_FILE, line => __LINE__});
            open (my $file_handle, "$shell_call 2>&1 |") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0014", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
            while(<$file_handle>)
            {
                chomp;
                my $line = $_;
                $an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
                    name1 => "line", value1 => $line, 
                }, file => $THIS_FILE, line => __LINE__});
            }
            close $file_handle;
        }
        
        # And now die via 'anvil-safe-stop'. We should be dead before this exits. So ya, so 
        # long and thanks for all the fish.
        $shell_call = $an->data->{path}{'anvil-safe-stop'}." --local --suicide";
        $an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
            name1 => "shell_call", value1 => $shell_call, 
        }, file => $THIS_FILE, line => __LINE__});
        open ($file_handle, "$shell_call 2>&1 |") or $an->Alert->error({title_key => "an_0003", message_key => "error_title_0014", message_variables => { shell_call => $shell_call, error => $! }, code => 2, file => $THIS_FILE, line => __LINE__});
        while(<$file_handle>)
        {
            chomp;
            my $line = $_;
            $line =~ s/\n//g;
            $line =~ s/\r//g;
            $an->Log->entry({log_level => 1, message_key => "scancore_warning_0021", message_variables => { line => $line }, file => $THIS_FILE, line => __LINE__});
        }
        close $file_handle;
        
        # Why are we still alive? die already.
        $an->nice_exit({exit_code => 999});
    }
    else
    {
        # We're not going to die, so record that we've warned the user.
        my $cleared = $an->Alert->check_alert_sent({
            type			=>	"warning",
            alert_sent_by		=>	$THIS_FILE,
            alert_record_locator	=>	$an->hostname,
            alert_name		=>	"shutdown_should_have_happened",
            modified_date		=>	$an->data->{sys}{db_timestamp},
        });
    }
}

sub node_action_shed_load
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    # Default to thermal load shed
    my $message_key = "scancore_warning_0027";
    my $shell_call  = $an->data->{path}{'anvil-safe-stop'}." --shed-load --reason temperature";
    if ($parameter->{load_shed_reason} eq "power")
    {
        # Change to power load shed
        $message_key = "scancore_warning_0026";
        $shell_call  = $an->data->{path}{'anvil-safe-stop'}." --shed-load --reason power_loss";
    }
    
    # Load shed! Tell the user.
    my $set = $an->Alert->check_alert_sent({
        type			=>	"warning",
        alert_sent_by		=>	$THIS_FILE,
        alert_record_locator	=>	$an->hostname,
        alert_name		=>	"load_shed_needed",
        modified_date		=>	$an->data->{sys}{db_timestamp},
    });
    if ($set)
    {
        $an->Alert->register_alert({
            alert_level		=>	"warning", 
            alert_agent_name	=>	$THIS_FILE,
            alert_title_key		=>	"an_alert_title_0004",
            alert_message_key	=>	$message_key,
        });
    }
    
    # Send the email, because we might be about to die.
    $an->ScanCore->process_alerts();
    
    # Now call the load shedding.
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
    }
    close $file_handle;
}

sub node_action_migrate_servers
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    # Migrate all servers to us.
    my $return = $an->ScanCore->migrate_all_servers_to_here();
    $an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
        name1 => "return", value1 => $return, 
    }, file => $THIS_FILE, line => __LINE__});
}

sub node_log_power_critical
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    if (not $an->data->{sys}{reported}{power_is_critical})
    {
        $an->Log->entry({log_level => 1, message_key => "scancore_log_0079", file => $THIS_FILE, line => __LINE__});
        $an->data->{sys}{reported}{power_is_critical} = 1;
        $an->data->{sys}{reported}{power_is_warning}  = 0;
    }
}

sub node_log_power_warning
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    if (not $an->data->{sys}{reported}{power_is_warning})
    {
        $an->Log->entry({log_level => 1, message_key => "scancore_log_0077", file => $THIS_FILE, line => __LINE__});
        $an->data->{sys}{reported}{power_is_critical} = 0;
        $an->data->{sys}{reported}{power_is_warning}  = 1;
    }
}

sub node_log_power_clear
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    if (($an->data->{sys}{reported}{power_is_critical}) or ($an->data->{sys}{reported}{power_is_warning}))
    {
        # Clear
        $an->Log->entry({log_level => 1, message_key => "scancore_log_0081", file => $THIS_FILE, line => __LINE__});
        $an->data->{sys}{reported}{power_is_critical} = 0;
        $an->data->{sys}{reported}{power_is_warning}  = 0;
    }
}

sub node_log_temperature_critical
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    if (not $an->data->{sys}{reported}{temperature_is_critical})
    {
        $an->Log->entry({log_level => 1, message_key => "scancore_log_0080", file => $THIS_FILE, line => __LINE__});
        $an->data->{sys}{reported}{temperature_is_critical} = 1;
        $an->data->{sys}{reported}{temperature_is_warning}  = 0;
    }
}

sub node_log_temperature_warning
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    if (not $an->data->{sys}{reported}{temperature_is_warning})
    {
        $an->Log->entry({log_level => 1, message_key => "scancore_log_0078", file => $THIS_FILE, line => __LINE__});
        $an->data->{sys}{reported}{temperature_is_critical} = 0;
        $an->data->{sys}{reported}{temperature_is_warning}  = 1;
    }
}

sub node_log_temperature_clear
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    if (($an->data->{sys}{reported}{temperature_is_critical}) or ($an->data->{sys}{reported}{temperature_is_warning}))
    {
        # Clear
        $an->Log->entry({log_level => 1, message_key => "scancore_log_0082", file => $THIS_FILE, line => __LINE__});
        $an->data->{sys}{reported}{temperature_is_critical} = 0;
        $an->data->{sys}{reported}{temperature_is_warning}  = 0;
    }
}

sub dashboard_action_boot_node
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    my $node_uuid = $parameter->{node_uuid};

    my $state = $an->ScanCore->target_power({
            target => $node_uuid,
            task   => "on",
        });
    $an->Log->entry({log_level => 2, message_key => "an_variables_0001", message_variables => {
        name1 => "state", value1 => $state, 
    }, file => $THIS_FILE, line => __LINE__});
}

sub dashboard_action_reboot_node
{
    my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;

    my $node_uuid = $parameter->{node_uuid};

    $an->ScanCore->reboot_node({
        node_uuid => $node_uuid
    });
}

#############################################################################################################
# Internal methods                                                                                          #
#############################################################################################################

1;
