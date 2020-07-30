package main;

use strict;
use warnings;
use Math::Round qw/nearest/;

###############################
# Forward declares




#################################

sub Hive_Initialize($)
{
	my ($hash) = @_;

	Log(5, "Hive_Initialize: enter");


	# Provider

	# Consumer
	$hash->{DefFn}		= "Hive_Define";
	$hash->{SetFn}    	= "Hive_Set";	
	$hash->{ParseFn}	= "Hive_Parse";
	$hash->{Match}		= ".*";
	$hash->{AttrList}	= "IODev " . $readingFnAttributes;

	Log(5, "Hive_Initialize: exit");

	return undef;
}

sub Hive_CheckIODev($)
{
	my $hash = shift;
	return !defined($hash->{IODev}) || ($hash->{IODev}{TYPE} ne "Hive_Hub");
}

sub Hive_Define($$)
{
	my ($hash, $def) = @_;

	Log(5, "Hive_Define: enter");

	my ($name, $type, $hiveType, $id) = split("[ \t][ \t]*", $def);
	$id = lc($id); # nomalise id

	if (exists($modules{Hive}{defptr}{$id})) 
	{
		my $msg = "Hive_Define: Device with id $id is already defined";
		Log(1, "$msg");
		return $msg;
	}

	Log(5, "Hive_Define id $id ");

	$hash->{id} 	= $id;
	$hash->{type}	= $hiveType;
	$hash->{STATE} = 'Disconnected';
	
	$modules{Hive}{defptr}{$id} = $hash;

	# Tell this Hive device to point to its parent Hive_Hub
	AssignIoPort($hash);

	# Need to call Hive_Hub_UpdateNodes....
	($hash->{IODev}{InitNode})->($hash->{IODev}, 1);

	Log(5, "Hive_Define: exit");

	return undef;
}

sub Hive_Undefine($$)
{
	my ($hash,$arg) = @_;

	Log(5, "Hive_Undefine: enter");

	delete($modules{Hive}{defptr}{$hash->{id}});
	
	Log(5, "Hive_Undefine: exit");

	return undef;
}


sub Hive_Set($@)
{
	my ($hash,$name,$cmd,@args) = @_;

	Log(5, "Hive_Set: enter");

	return "Invalid IODev" if (Hive_CheckIODev($hash));	
	
	Log(5, "Hive_Set: Name: $name, Cmd: $cmd");

	my $command   = undef;
	my $cmd_state = undef;

	#
	# This call is dependant on $hash->{heatingId}, $hash->{hotWaterId} & $hash->{id} being defined
	# These are internals that only get set during the call to Hive_Hub_UpdateNodes which is called on a timer initialised from Hive_Hub_Define
	#	They need to be set during Hive_Define
	# We need to get a way where these details can be loaded in advance of Hive_Set being called.
	# The devices (thermostat and thermostatUI) have been defined 
	#
	#	Hive seperates the hardware devices like so:
	#		Hub - 
	#		HeatingReceiver - switches
	#		HeatingThermostat - UI, physical controls
	#
	#	But logicaly the heating and hot water functions are seperate
	#
	#	The devices could be seperated into their own logical components
	#		Hive being the physical module (communicates with the Hive API)
	#		HiveHub - logical module (for physical Hub component details, holiday mode etc)
	#		HiveHeatingReceiverHeating - logical module (for heating controls)
	#		HiveHeatingReceiverHotWater - logical module (for hot water controls)
	#		HiveThermostatUI - logical module (for thermostat)	#
	#
	#  It may cause problems with the HeatingReceiver to be split as they may need to share data/responsabilities
	#

	if (lc $cmd eq 'heating') 
	{
		#	Put heating on to manual
		#	SET <name> HEATING <temp>	
			
		#	Put heating on to manual for period (BOOST)
		#	SET <name> HEATING <temp> <period>

		#	Switch heating off
		#	SET <name> HEATING OFF
			
		#	Switch heating to auto
		#	SET <name> HEATING AUTO	
	
		return ($hash->{IODev}{Send})->($hash->{IODev}, $hash->{heatingId}, "heating", @args);
	} 
	elsif (lc $cmd eq 'water') 
	{
		#	Put hot water on to manual
		#	SET <name> WATER ON	
			
		#	Put heating on to manual for period (BOOST)
		#	SET <name> WATER <period>

		#	Switch heating off
		#	SET <name> WATER OFF
			
		#	Switch heating to auto
		#	SET <name> WATER AUTO		
	
		return ($hash->{IODev}{Send})->($hash->{IODev}, $hash->{hotWaterId}, "water", @args);
	} 
	elsif (lc $cmd eq 'frostprotecttemperature') 
	{
		#	set frostprotecttemperature
		#	SET <name> frostprotecttemperature <temp>	

		return ($hash->{IODev}{Send})->($hash->{IODev}, $hash->{hotWaterId}, "frostprotecttemperature", @args);
	} 
	elsif (lc $cmd eq 'holiday') 
	{
		#	set holiday mode
		#	SET <name> holiday <start day> <start month> <start year> <end day> <end month> <end year> <temp>

		#	set holiday mode off
		#	SET <name> holiday off
		
		return ($hash->{IODev}{Send})->($hash->{IODev}, $hash->{id}, "holiday", @args);
	} 
	elsif (lc $cmd eq 'waterprofile') 
	{
		#	SET <name> waterweekprofile [<weekday> <state>,<until>,<state>,<until>,<state>,<until>] [<repeat>]
		# 	Where weekday: Mon, Tue, Wed, Thu, Fri, Sat, Sun
		# 	Where until: eg. 0:00, 18:00, 23:30
		#	Where state: On, Off

		return ($hash->{IODev}{Send})->($hash->{IODev}, $hash->{hotWaterId}, "waterprofile", @args);
	} 
	elsif (lc $cmd eq 'heatingprofile') 
	{
		#	SET <name> heatingweekprofile [<weekday> <temp>,<until>,<temp>,<until>,<temp>,<until>] [<repeat>]
		# 	Where weekday: Mon, Tue, Wed, Thu, Fri, Sat, Sun
		# 	Where until: eg. 8:00, 18:00, 23:30
		#	Where temp: eg. 17.5, 21

		return ($hash->{IODev}{Send})->($hash->{IODev}, $hash->{heatingId}, "heatingprofile", @args);
	} 
	else 
	{
		if (exists($hash->{hotWaterId})) 
		{
			return "unknown argument $cmd choose one of heating water holiday frostprotecttemperature heatingprofile waterprofile";
		} 
		else 
		{
			return "unknown argument $cmd choose one of heating holiday frostprotecttemperature heatingprofile";
		}
	}
	
	Log(5, "Hive_Set: exit");

	return undef;
}

sub Hive_Parse($$$)
{
	my ($hash, $msg, $device) = @_;
	my ($name, $type, $id, $nodeString) = split(",", $msg, 4);

	Log(5, "Hive_Parse: enter");

	if (!exists($modules{Hive}{defptr}{$id})) 
	{
		Log(1, "Hive_Parse: Hive $type device doesnt exist: $name");
		return "UNDEFINED Hive_${name}_${type} Hive ${type} ${id}";
	}
	
	# Get the hash of the Hive device object
	my $shash = $modules{Hive}{defptr}{$id};

	# Convert the node details back to JSON.
	my $node = decode_json($nodeString);

	if ((lc $type eq lc "thermostatUI" or lc $type eq lc "thermostat")) 
	{
		readingsBeginUpdate($shash);
	
		if (lc $node->{id} eq lc $id) 
		{
			$shash->{name}				= $node->{name};
			$shash->{model}				= $node->{attributes}->{model}->{reportedValue};
			readingsBulkUpdateIfChanged($shash, "presence", $node->{attributes}->{presence}->{reportedValue});

			if (lc $node->{attributes}->{presence}->{reportedValue} ne "absent") {
			
				$shash->{powerSupply}		= $node->{attributes}->{powerSupply}->{reportedValue};
				$shash->{RSSI}				= $node->{attributes}->{RSSI}->{reportedValue};
				$shash->{LQI}				= $node->{attributes}->{LQI}->{reportedValue};
				$shash->{hardwareVersion} 	= $node->{attributes}->{hardwareVersion}->{reportedValue};
				$shash->{softwareVersion} 	= $node->{attributes}->{softwareVersion}->{reportedValue};
				$shash->{lastSeen}			= $node->{attributes}->{lastSeen}->{reportedValue};
			
				$shash->{STATE} 			= 'Connected';

				readingsBulkUpdateIfChanged($shash, "RSSI", $node->{attributes}->{RSSI}->{reportedValue});


				if (lc $shash->{powerSupply} eq 'battery') {
					readingsBulkUpdateIfChanged($shash, "batteryVoltage", $node->{attributes}->{batteryVoltage}->{reportedValue});
					readingsBulkUpdateIfChanged($shash, "batteryLevel", $node->{attributes}->{batteryLevel}->{reportedValue});
					readingsBulkUpdateIfChanged($shash, "batteryState", $node->{attributes}->{batteryState}->{reportedValue});
				}

				if (defined($node->{attributes}->{holidayMode})) {
					if ($node->{attributes}->{holidayMode}->{reportedValue}->{enabled}) {
	
						$shash->{holidayMode_Enabled}			= 'True';
						$shash->{holidayMode_startDateTime}		= $node->{attributes}->{holidayMode}->{reportedValue}->{startDateTime};
						$shash->{holidayMode_endDateTime}		= $node->{attributes}->{holidayMode}->{reportedValue}->{endDateTime};
						$shash->{holidayMode_TargetHeatTemperature}	= $node->{attributes}->{holidayMode}->{reportedValue}->{targetHeatTemperature};

					} else {
						$shash->{holidayMode_Enabled}			= 'False';
						$shash->{holidayMode_startDateTime}		= '';
						$shash->{holidayMode_endDateTime}		= '';
						$shash->{holidayMode_TargetHeatTemperature}	= '';
					}
				}

				if (defined($node->{attributes}->{zoneName})) {
					$shash->{zoneName} 					= $node->{attributes}->{zoneName}->{reportedValue};
				}
			
				if (defined($node->{attributes}->{frostProtectTemperature})) {
					$shash->{frostProtectTemperature} 			= $node->{attributes}->{frostProtectTemperature}->{reportedValue};
				}
			} 
			else 
			{
				# Device absent
			}
			
			readingsEndUpdate($shash, 1);				
		}
		else 
		{
			my @daysofweek = qw(monday tuesday wednesday thursday friday saturday sunday);
			my $node_type = undef;
			
			# The node passed is for either the hot water or heating element of the thermostat 
			if ($node->{attributes}->{supportsHotWater}->{reportedValue}) 
			{
				# Hot water node
				$node_type = "HotWater";

				# Cache the hot water node id
				$shash->{hotWaterId} = $node->{id};
				
				readingsBeginUpdate($shash);

				if (defined($node->{attributes}->{stateHotWaterRelay}->{reportedValue})) {
					readingsBulkUpdateIfChanged($shash, "HotWaterState", $node->{attributes}->{stateHotWaterRelay}->{reportedValue});
				}
				
				foreach my $day (@daysofweek) {
					my @values;
					foreach my $shedule (@{$node->{attributes}->{schedule}->{reportedValue}->{$day}})
					{
						push(@values, $shedule->{time}."-".$shedule->{heatCoolMode});
					}
					$shash->{"${node_type}_WeekProfile_${day}"} = join(' / ', @values);
				}
								
				readingsEndUpdate($shash, 1);
				
			} 
			else 
			{
				# Heating node
				$node_type = "Heating";

				# Cache the heating node id
				$shash->{heatingId} = $node->{id};
				
				readingsBeginUpdate($shash);
			
				$shash->{FrostProtectTemperature}	= $node->{attributes}->{frostProtectTemperature}->{reportedValue};
				$shash->{MinHeatTemperature} 		= $node->{attributes}->{minHeatTemperature}->{reportedValue};
				$shash->{MaxHeatTemperature} 		= $node->{attributes}->{maxHeatTemperature}->{reportedValue};

				if (defined($node->{attributes}->{temperature}->{reportedValue})) {
					readingsBulkUpdateIfChanged($shash, "Temperature", nearest(0.1, $node->{attributes}->{temperature}->{reportedValue}));
				}
				if (defined($node->{attributes}->{stateHeatingRelay}->{reportedValue})) {
					readingsBulkUpdateIfChanged($shash, "HeatingState", $node->{attributes}->{stateHeatingRelay}->{reportedValue});
				}
				
				# Update the TargetTemperature value if it changes, to ensure a clean graph, log its old and new values
				# at the time of change.
				# Also log the TargetTemperature value if it hasnt changed in an hour, again to ensure any charts are 
				# drawn nicely
				my $readingValue = ReadingsVal($shash->{NAME}, 'TargetTemperature', undef);
				if (defined($readingValue) and defined($node->{attributes}->{targetHeatTemperature}->{reportedValue})) {
					if ($readingValue ne $node->{attributes}->{targetHeatTemperature}->{reportedValue}) {
						readingsBulkUpdate($shash, "TargetTemperature", $readingValue);
						readingsBulkUpdate($shash, "TargetTemperature", $node->{attributes}->{targetHeatTemperature}->{reportedValue});
					} else {
						my $readingAge = ReadingsAge($shash->{NAME}, 'TargetTemperature', undef);
						if (defined($readingAge)) {
							if ($readingAge > (60 * 60)) {
								readingsBulkUpdate($shash, "TargetTemperature", $node->{attributes}->{targetHeatTemperature}->{reportedValue});
							}
						}
					}
				} else {
					# If no previous TargetTemperate has been set, log one
					readingsBulkUpdate($shash, "TargetTemperature", $node->{attributes}->{targetHeatTemperature}->{reportedValue});
				}
				
				foreach my $day (@daysofweek) {
					my @values;
					foreach my $shedule (@{$node->{attributes}->{schedule}->{reportedValue}->{$day}})
					{
						push(@values, $shedule->{time}."-".$shedule->{targetHeatTemperature}." °C");
					}
					$shash->{"${node_type}_WeekProfile_${day}"} = join(' / ', @values);
				}				
			
				readingsEndUpdate($shash, 1);
			}
			
			if (defined($node_type)) {
				$shash->{"${node_type}_TransitionsPerDay"} 	= $node->{attributes}->{supportsTransitionsPerDay}->{reportedValue};
				
				readingsBeginUpdate($shash);

				if (defined($node->{attributes}->{activeHeatCoolMode}->{reportedValue})) {
					readingsBulkUpdateIfChanged($shash, "${node_type}_ActiveHeatCoolMode", $node->{attributes}->{activeHeatCoolMode}->{reportedValue});
				}

				if ($node->{attributes}->{activeScheduleLock}->{reportedValue}) {
					readingsBulkUpdateIfChanged($shash, "${node_type}_ActiveScheduleLock", 'True');
					if (defined($node->{attributes}->{scheduleLockDuration}->{targetSetTime})) {
						$shash->{"${node_type}_LockSetTime"}			= localtime($node->{attributes}->{scheduleLockDuration}->{targetSetTime}/1000);
					}
					if (defined($node->{attributes}->{scheduleLockDuration}->{targetExpiryTime})) {
						$shash->{"${node_type}_LockExpiryTime"}			= localtime($node->{attributes}->{scheduleLockDuration}->{targetExpiryTime}/1000);
					}
					$shash->{"${node_type}_LockDuration"}			= $node->{attributes}->{scheduleLockDuration}->{targetValue};
				} else {
					readingsBulkUpdateIfChanged($shash, "${node_type}_ActiveScheduleLock", 'False');
					$shash->{"${node_type}_LockSetTime"}			= '';
					$shash->{"${node_type}_LockExpiryTime"}			= '';
					$shash->{"${node_type}_LockDuration"}			= '';
				}				

				## TODO: Report on heating state:
				# Auto if
				#	activeScheduleLock = false and activeHeatCoolMode = HEAT
				# Manual if
				#	activeScheduleLock = true and activeHeatCoolMode = HEAT
				# off if
				#	activeScheduleLock = false and activeHeatCoolMode = OFF
				#
				if (defined($node->{attributes}->{activeHeatCoolMode}->{reportedValue})) {
					if ($node->{attributes}->{activeHeatCoolMode}->{reportedValue} eq "HEAT") {
						if (!$node->{attributes}->{activeScheduleLock}->{reportedValue}) {
							readingsBulkUpdateIfChanged($shash, "${node_type}_State", 'AUTO');
						} else {
							readingsBulkUpdateIfChanged($shash, "${node_type}_State", 'MANUAL');
						}
					} elsif (	$node->{attributes}->{activeHeatCoolMode}->{reportedValue} eq "OFF"
							and !$node->{attributes}->{activeScheduleLock}->{reportedValue}) {
						readingsBulkUpdateIfChanged($shash, "${node_type}_State", 'OFF');
					}
				}
				readingsEndUpdate($shash, 1);				
			}
		}
		
#		Log(1, "Hive_Parse ($type): $device->{name}");
	}
	
	Log(5, "Hive_Parse: exit");

	return $shash->{NAME};
}





1;
