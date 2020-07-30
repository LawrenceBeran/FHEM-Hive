
package main;

use strict;
use warnings;
use JSON;
use HiveRest;
use Data::Dumper;

###############################
# Forward declares
sub Hive_Hub_GetUpdate($);

sub Hive_Hub_Send(@);




#################################


sub Hive_Hub_Initialize($)
{
	my ($hash) = @_;

	Log(5, "Hive_Hub_Initialize: enter");


	# Provider
	$hash->{Clients}  = ":Hive:";
	my %mc = (
		"1:Hive" => ".*",
	);
	$hash->{MatchList} = \%mc;
	#Consumer
	$hash->{DefFn}    = "Hive_Hub_Define";
	$hash->{UndefFn}  = "Hive_Hub_Undefine";
	
	Log(5, "Hive_Hub_Initialize: exit");
	return undef;	
}

sub Hive_Hub_Define($$)
{
	my ($hash, $def) = @_;

	Log(5, "Hive_Hub_Define: enter");

	my ($name, $type, $username, $password) = split(' ', $def);

	$hash->{STATE} = 'Disconnected';
	$hash->{INTERVAL} = 60;
	$hash->{NAME} = $name;
	$hash->{username} = $username;
	$hash->{password} = $password;

	$modules{HiveBridge}{defptr} = $hash;

	# Interface used by the hubs children to communicate with the physical hub
  	$hash->{Send} = \&Hive_Hub_Send;
	$hash->{InitNode} = \&Hive_Hub_UpdateNodes;
	
	# Create a timer to get object details
	InternalTimer(gettimeofday()+1, "Hive_Hub_GetUpdate", $hash, 0);
	
	Log(5, "Hive_Hub_Define: exit");

	return undef;
}

sub Hive_Hub_Undefine($$)
{
	my ($hash, $def) = @_;

	Log(5, "Hive_Hub_Undefine: enter");


	if (defined($hash->{id})) {
		Log(1, "Hive_Hub_Undefine: $hash->{id}");
	} else {
		Log(1, "Hive_Hub_Undefine: ");
	}

	RemoveInternalTimer($hash);

	# Close the HIVE session 
	my $hiveClient = HiveRest->new();
	$hiveClient->logout();
	$hash->{HIVE}{SessionId} = undef;

	Log(5, "Hive_Hub_Undefine: exit");

	return undef;
}

############################################################################
# This function updates the internal and reading values on the hive objects.
############################################################################

sub
Hive_Hub_UpdateNodes($$)
{
	my ($hash,$fromDefine) = @_;

	Log(5, "Hive_Hub_UpdateNodes: enter");


	my $presence = "ABSENT";

	my $hiveClient = HiveRest->new();
	$hash->{HIVE}{SessionId} = $hiveClient->connect($hash->{username}, $hash->{password}, $hash->{HIVE}{SessionId});
	if (!defined($hash->{HIVE}{SessionId})) 
	{
		Log(1, "Hive_Hub_UpdateNodes: $hash->{username} failed to logon to Hive");
		$hash->{STATE} = 'Disconnected';
	} 
	else 
	{
		Log(5, "Hive_Hub_UpdateNodes: $hash->{username} succesfully connected to Hive");

		$hash->{STATE} = "Connected";

		my $node_response = $hiveClient->getNodes();
		if (!defined($node_response)) {
			Log(1, "Hive_Hub_UpdateNodes: Failed to get Nodes!");
		} else {
			my $hubNode = undef;

			# Find the first Hub node for updating info from.
			foreach my $node (@{$node_response->{nodes}}) {
				if (lc $node->{id} eq lc $node->{parentNodeId}) {
					
					$hubNode = $node;
	
					# If the Hub node isnt already defined,
					if (!defined($hash->{id}) and !exists($modules{Hive_Hub}{defptr}{$node->{id}})) {
						$hash->{id} = $node->{id};
						# NOTE: We could create the other Hive Hubs while we where at it!
						#		But it would be better to create a new object above Hub
						#		and allow that to create all child Hubs.
						#		I am assuming for now that there is only a single Hub
					}
					last;	
				} 
			}
			
			if (!defined($hash->{id})) {
				$hash->{STATE} = 'No hub';
			} else {

				if (defined($hubNode)) {
					$presence = $hubNode->{attributes}->{presence}->{displayValue};

					if (lc $presence ne "absent") {

						# Update the Hub internal values
						$hash->{devicesState} 	= $hubNode->{attributes}->{devicesState}->{displayValue};
						$hash->{kernelVersion} 	= $hubNode->{attributes}->{kernelVersion}->{displayValue};
						$hash->{powerSupply} 	= $hubNode->{attributes}->{powerSupply}->{displayValue};
						$hash->{protocol} 	= $hubNode->{attributes}->{protocol}->{displayValue};
						$hash->{hardwareVersion} = $hubNode->{attributes}->{hardwareVersion}->{displayValue};			
					} else {
						$hash->{STATE} = $presence;
					}
				} 


				# Process this hubs child devices and pass on the details to the child node for updating their details with
				# Dispatch method handled by Hive_Parse function in file 31_Hive.pm
				foreach my $node (@{$node_response->{nodes}}) {
				
					# Verify params
					if (!defined($hash->{id})) {
						Log(1, "Hive_Hub_UpdateNodes: hash->{id} not defined!");
					} elsif (!defined($node->{parentNodeId})) {
						Log(1, "Hive_Hub_UpdateNodes: node->{parentNodeId} not defined!");
					} elsif (lc $hash->{id} eq lc $node->{parentNodeId} && $node->{id} ne $hash->{id} && lc $hiveClient->_getNodeType($node) eq lc "http://alertme.com/schema/json/node.class.thermostatui.json#") {
				
						Log(3, "Hive_Hub_UpdateNodes: processing thermostat: $node->{name}");
					
						my $nodeString = encode_json($node);
						# Send the thermostat UI node details to the node!
						if (!defined($fromDefine) || exists($modules{Hive}{defptr}{$node->{id}})) 
						{
							Dispatch($hash, "$node->{name},thermostatUI,$node->{id},$nodeString", undef);
						}

						my $thermostatId = $node->{relationships}->{boundNodes}[0]->{id};
						
						# Find the thermostat, heating and hot water nodes associated with the thermostatui
						foreach my $node1 (@{$node_response->{nodes}}) 
						{
							if (lc $thermostatId eq lc $node1->{parentNodeId}) 
							{
								$nodeString = encode_json($node1);

								if ($node1->{attributes}->{supportsHotWater}->{reportedValue}) 
								{
									if (!defined($fromDefine) || exists($modules{Hive}{defptr}{$thermostatId})) 
									{
										Dispatch($hash, "$node->{name},thermostat,$thermostatId,$nodeString", undef);
									}
								} else 
								{
									if (!defined($fromDefine) || exists($modules{Hive}{defptr}{$thermostatId})) 
									{
										Dispatch($hash, "$node->{name},thermostat,$thermostatId,$nodeString", undef);
									}
								}
							} elsif (lc $thermostatId eq lc $node1->{id}) {
								# Send the thermostat node details to the node!
								$nodeString = encode_json($node1);
								if (!defined($fromDefine) || exists($modules{Hive}{defptr}{$thermostatId})) 
								{
									Dispatch($hash, "$node->{name},thermostat,$thermostatId,$nodeString", undef);
								}
							}
						}					
					}			
				}
			}
		}

#        if (!$hiveClient->logout()) {
#			Log(3, "Hive_Hub_UpdateNodes: $hash->{username} logged out");
#        } else {
#			Log(1, "Hive_Hub_UpdateNodes: $hash->{username} failed to logged out");
#		}
	}

	readingsBeginUpdate($hash);
	readingsBulkUpdateIfChanged($hash, "presence", uc $presence);
	readingsEndUpdate($hash, 1);				

	Log(5, "Hive_Hub_UpdateNodes: exit");
}

sub 
Hive_Hub_GetUpdate($)
{
	my ($hash) = @_;

	Log(5, "Hive_Hub_GetUpdate: enter");

	Hive_Hub_UpdateNodes($hash, undef);
	
	InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Hive_Hub_GetUpdate", $hash, 0);

	Log(5, "Hive_Hub_GetUpdate: exit");

	return undef;
}

sub Hive_Hub_ltrim { my $s = shift; $s =~ s/^\s+//;       return $s };
sub Hive_Hub_rtrim { my $s = shift; $s =~ s/\s+$//;       return $s };
sub  Hive_Hub_trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };
sub Hive_Hub_validate_time { my $s = shift; if ($s =~ s/^([0-9]|0[0-9]|1[0-9]|2[0-3]):([0-5][0-9])$/sprintf('%02d:%02d',$1,$2)/e) { return $s; } else { return undef; } } 
sub Hive_Hub_is_temp_valid { my $s = shift; if ($s =~ /^\d*\.?[0|5]?$/) { return $s; } else { return undef; } } 
sub Hive_Hub_is_hotwater_temp_valid { my $s = shift; if ($s =~ s/^(ON|OFF|HEAT)$/\U$1/i) { return $s; } else { return undef; } }

sub Hive_Hub_Send(@)
{
	my ($hash, $dst, $cmd, @args) = @_;
	
	Log(5, "Hive_Hub_Send: enter");

	my $ret = undef;

	Log(5, "Hive_Hub_Send: dst - $dst");

	my $hiveClient = HiveRest->new();
	$hash->{HIVE}{SessionId} = $hiveClient->connect($hash->{username}, $hash->{password}, $hash->{HIVE}{SessionId});
	if (!defined($hash->{HIVE}{SessionId}))
	{
		Log(1, "Hive_Hub_Send: $hash->{username} failed to logon to Hive");
		$hash->{STATE} = 'Disconnected';
	} 
	else 
	{
		# auto:
		#	activeScheduleLock - false
		#	activeHeatCoolMode - HEAT
		# manual:
		#	activeScheduleLock - true
		#	activeHeatCoolMode - HEAT
		#	targetHeatTemperature - <temp>
		# off:
		#	activeScheduleLock - false
		#	activeHeatCoolMode - OFF
		#	stateHeatingRelay - OFF 	?
		#	targetHeatTemperature - 1 	?
	
	
		Log(3, "Hive_Hub_Send: $hash->{username} succesfully connected to Hive");

		if (lc $cmd eq 'heating') {
	
			return "missing a value" if (@args == 0);

			Log(3, "Hive_Hub_Send: $cmd $args[0]");
	
			#
			# TODO: Report on heating state: Manual, auto or off (using combination of settings below)
			#
			my $nodeAttributes = {
										nodes => [ 
										{
											attributes => 
											{
												activeScheduleLock =>
												{
													targetValue => JSON::false()
												},											
												activeHeatCoolMode =>
												{
													targetValue => "HEAT"
												},											
											}
										} ],
								 };
							 
		
			if (lc $args[0] eq "auto") {
			
				# Default config above
			
			} elsif (lc $args[0] eq "off") {
			
				$nodeAttributes->{nodes}[0]->{attributes}->{activeScheduleLock}->{targetValue} = JSON::false();
				$nodeAttributes->{nodes}[0]->{attributes}->{activeHeatCoolMode}->{targetValue} = "OFF";
			
			} else {
				# TODO: Validate $args[0] as a number (temperature)
				# 		Should get devices minimum and maximum temperature from device details
				#		and only allow whole or half decimal places
				
				if ($args[0] =~ /^[1-9][0-9](\.[05])?$/) {
				
					if (@args == 1) {
						# manual
						$nodeAttributes->{nodes}[0]->{attributes}->{activeHeatCoolMode}->{targetValue} = "HEAT";
						$nodeAttributes->{nodes}[0]->{attributes}->{activeScheduleLock}->{targetValue} = JSON::true();
					} else {
						# TODO: May want to restrict the mins to 15 second steps
						if ($args[1] =~ /^[1-9][0-9]*$/) {
						
							# BOOST
							$nodeAttributes->{nodes}[0]->{attributes}->{activeHeatCoolMode}->{targetValue} = "BOOST";
							$nodeAttributes->{nodes}[0]->{attributes}->{scheduleLockDuration}->{targetValue} = $args[1];
						} else {
							return "invalid value, must be a time in mins";
						}
					}
					
					$nodeAttributes->{nodes}[0]->{attributes}->{targetHeatTemperature}->{targetValue} = $args[0];
				} else {
					return "invalid value '${args[0]}', must be a temperature value";
				}
			}
								
			$ret = $hiveClient->putNodeAttributes($dst, $nodeAttributes);
			if (!defined($ret))
			{
				Log(3, "Hive_Hub_Send: Failed to set heating: ret not defined");
				$ret = "failed to set heating!";
			} elsif ($ret != 200) 
			{
				Log(3, "Hive_Hub_Send: Failed to set heating: ret $ret");
				$ret = "failed to set heating!";
			} else 
			{
				$ret = undef;
			}
			
		} elsif (lc $cmd eq 'water') {
		
			return "missing a value" if (@args == 0);

	
			#
			# TODO: Report on hotwater state: Manual, auto or off (using combination of settings below)
			#
			my $nodeAttributes = {
										nodes => [ 
										{
											attributes => 
											{
												activeScheduleLock =>
												{
													targetValue => JSON::false()
												},											
												activeHeatCoolMode =>
												{
													targetValue => "HEAT"
												},											
											}
										} ],
								 };
							 
		
			if (lc $args[0] eq "auto") {
			
				# Default config above
			
			} elsif (lc $args[0] eq "off") {
			
				$nodeAttributes->{nodes}[0]->{attributes}->{activeScheduleLock}->{targetValue} = JSON::false();
				$nodeAttributes->{nodes}[0]->{attributes}->{activeHeatCoolMode}->{targetValue} = "OFF";
			
			} elsif (lc $args[0] eq "on") {
				
				# manual
				$nodeAttributes->{nodes}[0]->{attributes}->{activeHeatCoolMode}->{targetValue} = "HEAT";
				$nodeAttributes->{nodes}[0]->{attributes}->{activeScheduleLock}->{targetValue} = JSON::true();
				
			} else {
			
				# TODO: May want to restrict the mins to 15 second steps
				if ($args[0] =~ /^[1-9][0-9]*$/) {
					
					# BOOST
					$nodeAttributes->{nodes}[0]->{attributes}->{activeHeatCoolMode}->{targetValue} = "BOOST";
					$nodeAttributes->{nodes}[0]->{attributes}->{scheduleLockDuration}->{targetValue} = $args[0];
				} else {
					return "invalid value, must be a time in mins";
				}
			}

			$ret = $hiveClient->putNodeAttributes($dst, $nodeAttributes);
			if (!defined($ret) || $ret != 200) {
				$ret = "failed to set hot water!";
			} else {
				$ret = undef;
			}
			
		} elsif (lc $cmd eq 'frostprotecttemperature') {
			# TODO: Validate min max value
			if ($args[0] =~ /^[1-9][0-9]*$/) {
			
				my $nodeAttributes = {
											nodes => [ 
											{
												attributes => 
												{
													frostProtectTemperature =>
													{
														targetValue => $args[0],
													},
												},
											} ],
									 };
									 
				$ret = $hiveClient->putNodeAttributes($dst, $nodeAttributes);
				if (!defined($ret) || $ret != 200) {
					$ret = "failed to set frostprotecttemperature!";
				} else {
					$ret = undef;
				}
				
			} else {
				return "invalid value, must be a valid temperature value";
			}
		
		} elsif (lc $cmd eq 'holiday') {
		
			return "missing a value" if (@args == 0);

			my $nodeAttributes = {
									nodes => [ 
									{
										attributes => 
										{
											holidayMode =>
											{
												targetValue =>
												{
													enabled => JSON::false(),
												},
											},
										},
									} ],
								 };		
			
			
			if (lc $args[0] eq "off" ) {
			
				# Not necessary as its the default
				$nodeAttributes->{nodes}[0]->{attributes}->{holidayMode}->{targetValue}->{enabled} = JSON::false();
				
			} else {

				# TODO: Validate parameters and set
				my $start_time = time() * 1000; 
				my $end_time = $start_time + (1000 * 60 * 60);
				
				$nodeAttributes->{nodes}[0]->{attributes}->{holidayMode}->{targetValue}->{enabled} = JSON::false();
				$nodeAttributes->{nodes}[0]->{attributes}->{holidayMode}->{targetValue}->{startDateTime} = $start_time;
				$nodeAttributes->{nodes}[0]->{attributes}->{holidayMode}->{targetValue}->{startDateTime} = $end_time;
				$nodeAttributes->{nodes}[0]->{attributes}->{holidayMode}->{targetValue}->{targetHeatTemperature} = 15;
				
			}
		
		
			$ret = $hiveClient->putNodeAttributes($dst, $nodeAttributes);
			if (!defined($ret) || $ret != 200) {
				$ret = "failed to set holiday!";
			} else {
				$ret = undef;
			}
			
		} elsif (lc $cmd eq 'heatingprofile') {
		
			Log(3, "Hive_Hub_Send: Heatingprofile Args: @args");
			
			# Get the current weekprofile, min and max temp and number of max number of 
			# schedule points
			my $current_settings = $hiveClient->getNodeAttributes($dst);
			if (!defined($current_settings)) {
				Log(1,"Hive_Hub_Send: Failed to get thermostats current schedule and settings!");
				return "Failed to connect to Hive to get current settings!";
			} else {

				my $max_temp = $current_settings->{maxHeatTemperature}->{reportedValue};
				my $min_temp = $current_settings->{minHeatTemperature}->{reportedValue};

				my $numb_elements = 6;
				if (defined($current_settings->{supportsTransitionsPerDay}->{reportedValue})) {
					$numb_elements = $current_settings->{supportsTransitionsPerDay}->{reportedValue};
				}
				my $max_numb_elements = $numb_elements;

				if (defined($min_temp) and defined($max_temp)) {
					Log(3,"Hive_Hub_Send: Temp range: ".$min_temp."-".$max_temp);
				} else {
					Log(2,"Hive_Hub_Send: Unable to get min and max temperature from hive hub!");
					$min_temp = 5;
					$max_temp = 30;
				}
				Log(3,"Hive_Hub_Send: Elements: ".$max_numb_elements);
			
				my %dayHash = (mon => "monday", tue => "tuesday", wed => "wednesday", thu => "thursday", fri => "friday", sat => "saturday", sun => "sunday");
				my @daysofweek = qw(monday tuesday wednesday thursday friday saturday sunday);
			
				my $weekString = join(" ", @args);

				# Split the string into its component (day) parts 
				my @array = split(/(monday|mon|tuesday|tue|wednesday|wed|thursday|thu|friday|fri|saturday|sat|sunday|sun)/i, Hive_Hub_trim($weekString));

				# Remove the first element, which is blank
				# TODO: Not sure why this requires two shifts to get rid of the first element
				shift(@array);
				
				my $nodeAttributes = {};
				my $valid_string = 1;

				foreach my $day (@daysofweek) {
					for my $i (0 .. $#{ $current_settings->{schedule}->{reportedValue}->{$day} }) {
						$nodeAttributes->{nodes}[0]->{attributes}->{schedule}->{targetValue}->{$day}[$i]->{time} = $current_settings->{schedule}->{reportedValue}->{$day}[$i]->{time};
						$nodeAttributes->{nodes}[0]->{attributes}->{schedule}->{targetValue}->{$day}[$i]->{heatCoolMode} = $current_settings->{schedule}->{reportedValue}->{$day}[$i]->{heatCoolMode};
						$nodeAttributes->{nodes}[0]->{attributes}->{schedule}->{targetValue}->{$day}[$i]->{targetHeatTemperature} = $current_settings->{schedule}->{reportedValue}->{$day}[$i]->{targetHeatTemperature};
					}
				}
								
				for (my $day = 0;$day <= $#array && $valid_string;$day += 2)
				{
					Log(3,"Hive_Hub_Send: Idx: ".$day." of ".$#array);

					# Verify that '$array[$day]' contains a valid day string
					if (!exists($dayHash{lc($array[$day])}))
					{
						Log(1,"Hive_Hub_Send: Invalid day element '".lc($array[$day])."'");
						$valid_string = undef;
					} else {
						Log(3,"Hive_Hub_Send: Day: ".$array[$day]);
						Log(3,"Hive_Hub_Send: Sch: ".Hive_Hub_trim($array[$day+1]));

						my (@temp, @time);

						my $i;
						push @{ $i++ % 2 ? \@time : \@temp }, $_ for split(/,/, Hive_Hub_trim($array[$day+1]));
						# TODO: Verify elements, 
						#       there should be one more temp than time or
						#                the first time must be 00:00 or 0:00
						#       times should be in the format of ([0-9]|0[0-9]|1[0-9]|2[0-3]):[0-5][0-9]
						#       temp should be greater than min temp and less than max temp (defined in object)
						#               in the format /^\d*\.?[0|5]$/
						#       There should only be a certain number of variables in the arrays
						#               The number is defined in the Hive thermostat node

						
						#
						# TODO: Do not allow more than 6 transitions... Do not change the number of transitions
						#		Do not allow less than 6 transitions... Pad missing transitions after the first at 15 min intevals
						#		Same rules apply for water
						
						

						# Add the first time schedule, this is always midnight!
						unshift(@time, '00:00');

						# No temp value, default it to 18.
						if (scalar(@temp) == 0) {
							unshift(@temp, 18);
						}
						
						# Validate the number of elements in the temp array
						if (scalar(@temp) != scalar(@time)) {
							Log(1,"Hive_Hub_Send: The number of temp elements does not match the time elements.");
							$valid_string = undef;
						} else {
							
							# Unreference the existing schedule for the required day.
							undef $nodeAttributes->{nodes}[0]->{attributes}->{schedule}->{targetValue}->{$dayHash{lc($array[$day])}};

							# Cannot add more elements than defined
							if (scalar(@temp) > $max_numb_elements) {
								Log(1, "Hive_Hub_Send: Too many elements: ".scalar(@temp));
								$valid_string = undef;
							} elsif (scalar(@temp) < $max_numb_elements) {
								Log(2, "Hive_Hub_Send: Not enough elements: ".scalar(@temp));
								# If the arrays do not have enough values, pad them out with the last element 
								push @temp, ($temp[-1]) x ($max_numb_elements - @temp);
								push @time, ($time[-1]) x ($max_numb_elements - @time);
								Log(3, "Hive_Hub_Send: Padded to: ".scalar(@temp));
							}

							my $prev_time = '00:00';
							for my $i ( 0 .. $#temp )
							{
								my $time_ = Hive_Hub_validate_time(Hive_Hub_trim($time[$i]));
								my $temp_ = Hive_Hub_is_temp_valid(Hive_Hub_trim($temp[$i]));

								if (!$time_) {
									Log(1,"Hive_Hub_Send: Time '".$time[$i]."' is not valid");
									$valid_string = undef;
								} elsif ($time_ lt $prev_time) {
									Log(1,"Hive_Hub_Send: Time '".$time_."' is earlier than previous time '".$prev_time);
									$valid_string = undef;
								} elsif (!$temp_) {
									Log(1,"Hive_Hub_Send: Temp '".$temp[$i]."' is not valid");
									$valid_string = undef;
								} elsif ($temp_ < $min_temp || $temp_ > $max_temp) {
									Log(1,"Hive_Hub_Send: Temp '".$temp[$i]."' is out of range");
									$valid_string = undef;
								} else {
									# Cache the current time for use in the next iteration
									$prev_time = $time_;

									$nodeAttributes->{nodes}[0]->{attributes}->{schedule}->{targetValue}->{$dayHash{lc($array[$day])}}[$i]->{time} = $time_;
									$nodeAttributes->{nodes}[0]->{attributes}->{schedule}->{targetValue}->{$dayHash{lc($array[$day])}}[$i]->{heatCoolMode} = "HEAT";
									$nodeAttributes->{nodes}[0]->{attributes}->{schedule}->{targetValue}->{$dayHash{lc($array[$day])}}[$i]->{targetHeatTemperature} = $temp_;
								}

								# If string invalid, break out of loop
								if (!$valid_string) {
									last;
								}
							}
						}
					}
				}

				if (defined($valid_string)) {
					if ($max_numb_elements != $numb_elements) {
						$nodeAttributes->{nodes}[0]->{attributes}->{supportsTransitionsPerDay}->{targetValue} = $max_numb_elements;
					}
					
					$ret = $hiveClient->putNodeAttributes($dst, $nodeAttributes);
					if (!defined($ret) || $ret != 200) {
						$ret = "failed to set heating profile!";
					} else {
						$ret = undef;
					}
				} else {
					$ret = "Invalid command string";
				}
			}
			
		} elsif (lc $cmd eq 'waterprofile') {

			Log(3, "Hive_Hub_Send: Waterprofile Args: @args");
			
			# Get the current weekprofile, min and max temp and number of max number of 
			# schedule points
			my $current_settings = $hiveClient->getNodeAttributes($dst);
			if (!defined($current_settings) || length($current_settings) == 0) {
				Log(1,"Hive_Hub_Send: Failed to get thermostats current schedule and settings!");
				return "Failed to connect to Hive to get current settings!";
			} else {

				my $numb_elements = 6;
				if (defined($current_settings->{supportsTransitionsPerDay}->{reportedValue})) {
					$numb_elements = $current_settings->{supportsTransitionsPerDay}->{reportedValue};
				}
				my $max_numb_elements = $numb_elements;

				Log(3,"Hive_Hub_Send: Elements: ".$max_numb_elements);
			
				my %dayHash = (mon => "monday", tue => "tuesday", wed => "wednesday", thu => "thursday", fri => "friday", sat => "saturday", sun => "sunday");
				my @daysofweek = qw(monday tuesday wednesday thursday friday saturday sunday);
			
				my $weekString = join(" ", @args);

				# Split the string into its component (day) parts 
				my @array = split(/(monday|mon|tuesday|tue|wednesday|wed|thursday|thu|friday|fri|saturday|sat|sunday|sun)/i, Hive_Hub_trim($weekString));

				# Remove the first element, which is blank
				# TODO: Not sure why this requires two shifts to get rid of the first element
				shift(@array);
				
				my $nodeAttributes = {};
				my $valid_string = 1;

				foreach my $day (@daysofweek) {
					for my $i (0 .. $#{ $current_settings->{schedule}->{reportedValue}->{$day} }) {
						$nodeAttributes->{nodes}[0]->{attributes}->{schedule}->{targetValue}->{$day}[$i]->{time} = $current_settings->{schedule}->{reportedValue}->{$day}[$i]->{time};
						$nodeAttributes->{nodes}[0]->{attributes}->{schedule}->{targetValue}->{$day}[$i]->{heatCoolMode} = $current_settings->{schedule}->{reportedValue}->{$day}[$i]->{heatCoolMode};
						$nodeAttributes->{nodes}[0]->{attributes}->{schedule}->{targetValue}->{$day}[$i]->{targetHeatTemperature} = $current_settings->{schedule}->{reportedValue}->{$day}[$i]->{targetHeatTemperature};
					}
				}
								
				for (my $day = 0;$day <= $#array && $valid_string;$day += 2)
				{
					Log(3,"Hive_Hub_Send: Idx: ".$day." of ".$#array);

					# Verify that '$array[$day]' contains a valid day string
					if (!exists($dayHash{lc($array[$day])}))
					{
						Log(1,"Hive_Hub_Send: Invalid day element '".lc($array[$day])."'");
						$valid_string = undef;
					} else {
						Log(3,"Hive_Hub_Send: Day: ".$array[$day]);
						Log(3,"Hive_Hub_Send: Sch: ".Hive_Hub_trim($array[$day+1]));

						$array[$day+1] =~ s/ON/HEAT/ig;
						
						my (@temp, @time);

						my $i;
						push @{ $i++ % 2 ? \@time : \@temp }, $_ for split(/,/, Hive_Hub_trim($array[$day+1]));
						# TODO: Verify elements, 
						#       there should be one more temp than time or
						#                the first time must be 00:00 or 0:00
						#       times should be in the format of ([0-9]|0[0-9]|1[0-9]|2[0-3]):[0-5][0-9]
						#       temp should be greater HEAT|ON or OFF
						#       There should only be a certain number of variables in the arrays
						#               The number is defined in the Hive thermostat node


						# Add the first time schedule, this is always midnight!
						unshift(@time, '00:00');

						# No temp value, default it to 18.
						if (scalar(@temp) == 0) {
							unshift(@temp, 18);
						}						
						
						# Validate the number of elements in the temp array
						if (scalar(@temp) != scalar(@time)) {
							Log(1,"Hive_Hub_Send: The number of temp elements does not match the time elements.");
							$valid_string = undef;
						} else {
							
							# Unreference the existing schedule for the required day.
							undef $nodeAttributes->{nodes}[0]->{attributes}->{schedule}->{targetValue}->{$dayHash{lc($array[$day])}};
						
							# Cannot add more elements than defined
							if (scalar(@temp) > $max_numb_elements) {
								Log(1, "Hive_Hub_Send: Too many elements: ".scalar(@temp));
								$valid_string = undef;
							} elsif (scalar(@temp) < $max_numb_elements) {
								Log(3, "Hive_Hub_Send: Not enough elements: ".scalar(@temp));
								# If the arrays do not have enough values, pad them out with the last element 
								push @temp, ($temp[-1]) x ($max_numb_elements - @temp);
								push @time, ($time[-1]) x ($max_numb_elements - @time);
								Log(3, "Hive_Hub_Send: Padded to: ".scalar(@temp));
							}	
							
							my $prev_time = '00:00';
							for my $i ( 0 .. $#temp )
							{
								my $time_ = Hive_Hub_validate_time(Hive_Hub_trim($time[$i]));
								my $temp_ = Hive_Hub_is_hotwater_temp_valid(Hive_Hub_trim($temp[$i]));

								if (!$time_) {
									Log(1,"Hive_Hub_Send: Time '".$time[$i]."' is not valid");
									$valid_string = undef;
								} elsif ($time_ lt $prev_time) {
									Log(1,"Hive_Hub_Send: Time '".$time_."' is earlier than previous time '".$prev_time);
									$valid_string = undef;
								} elsif (!$temp_) {
									Log(1,"Hive_Hub_Send: Temp '".$temp[$i]."' is not valid");
									$valid_string = undef;
								} else {
									# Cache the current time for use in the next iteration
									$prev_time = $time_;
									
									$nodeAttributes->{nodes}[0]->{attributes}->{schedule}->{targetValue}->{$dayHash{lc($array[$day])}}[$i]->{time} = $time_;
									$nodeAttributes->{nodes}[0]->{attributes}->{schedule}->{targetValue}->{$dayHash{lc($array[$day])}}[$i]->{heatCoolMode} = $temp_;
									$nodeAttributes->{nodes}[0]->{attributes}->{schedule}->{targetValue}->{$dayHash{lc($array[$day])}}[$i]->{targetHeatTemperature} = (lc $temp_ eq "heat") ? 99 : 0;
								}

								# If string invalid, break out of loop
								if (!$valid_string) {
									last;
								}
							}
						}
					}
				}

				if (defined($valid_string)) {
					if ($max_numb_elements != $numb_elements) {
						$nodeAttributes->{nodes}[0]->{attributes}->{supportsTransitionsPerDay}->{targetValue} = $max_numb_elements;
					}
					
					$ret = $hiveClient->putNodeAttributes($dst, $nodeAttributes);
					if (!defined($ret) || $ret != 200) {
						$ret = "failed to set hotwater profile!";
					} else {
						$ret = undef;
					}
				} else {
					$ret = "Invalid command string";
				}
			}		
		}
	
		if (defined($ret)) {
			return "command $cmd failed, returned an error $ret";
		}
	
	
#        if (!$hiveClient->logout()) {
#			Log(3, "Hive_Hub_Send: $hash->{username} logged out");
#        } else {
#			Log(1, "Hive_Hub_Send: $hash->{username} failed to logged out");
#		}
	}

	# TODO: signal a refresh of the readings
	#		Not sure when though as 5 seconds isnt enough for them to be updated
	InternalTimer(gettimeofday()+2, "Hive_Hub_UpdateNodes", $hash, 0);
	
	Log(5, "Hive_Hub_Send: exit");


	return undef;
}


1;
