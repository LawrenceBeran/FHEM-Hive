package HiveRest;
use strict;
use warnings;

use REST::Client;
use JSON;
use Data::Dumper;
use MIME::Base64;


sub new        # constructor, this method makes an object that belongs to class Number
{
    my $class = shift;          # $_[0] contains the class name

    my $self = {};              # the internal structure we'll use to represent
                                # the data in our class is a hash reference
    bless( $self, $class );     # make $self an object of class $class

    $self->{apiVersion} = '6.4.0';

    $self->{client} = REST::Client->new();
    $self->{client}->setHost('https://api-prod.bgchprod.info:443/omnia');

    return $self;        # a constructor always returns an blessed() object
}


sub _getHeaders {
    my $self = shift;
    my $sessionId = shift;

    my $headers = {
             'Content-Type' => 'application/json'
            , 'Accept' => 'application/vnd.alertme.zoo-'.$self->{apiVersion}.'+json'
            , 'X-Omnia-Client' => 'Hive Web Dashboard'
    };

    if (defined($sessionId))
    {
        $headers->{'X-Omnia-Access-Token'} = $sessionId;
    }
    else 
    {
        if (defined($self->{sessionId})) 
        {
            $headers->{'X-Omnia-Access-Token'} = $self->{sessionId};
        }
    }

#    $self->_log(5, Dumper($headers));

    return $headers;
}

sub _log($$)
{
    my ( $self, $loglevel, $text ) = @_;

    main::Log3("Hive", $loglevel, "HiveRest: ".$text);
}

sub connect {
    my $self = shift;
    my $userName = shift;
    my $password = shift;
    my $sessionId = shift;

    if (defined($sessionId)) 
    {
        # Test the provided session to see if it is valid.
        if (!defined($self->_isTokenValid($sessionId)))
        {
            # Session has expired. Create a new session.
            $self->_log(3, "connect: Session has expired. requesting new one.");
            $sessionId = undef;
        }
        else
        {
            $self->_log(3, "connect: Existing session is valid.");
            $self->{sessionId} = $sessionId;
        }
    }
    else
    {
        # No provided session
        $self->_log(3, "connect: First time logon (no previous session).");
    }

    if (!defined($sessionId))
    {
        $sessionId = $self->_login($userName, $password);
        if (defined($self->{sessionId}))
        {
            $self->_log(3, "connect: Session created");
        }
        else
        {
            $self->_log(1, "connect: Failed to logon to Hive to create new session.");
        }
    }

    return $sessionId;
}

#############################
# LOGIN to the Hive REST API
#############################
sub _login {
    my $self = shift;
    my $userName = shift;
    my $password = shift;

    $self->{sessionId} = undef;

    my $sessions = {
                username => $userName
            ,   password => $password


        };

    my $headers = {
             'Content-Type' => 'application/json'
            , 'Accept' => 'application/json'
            , 'X-Omnia-Client' => 'Hive Web Dashboard'
    };

    my $client = REST::Client->new();
    $client->setHost('https://beekeeper.hivehome.com:443/1.0');

    $client->POST('/cognito/login', encode_json($sessions), $headers);

    if (200 != $client->responseCode()) {
        # Failed to connect to API
        $self->_log(1, "Login: ".$client->responseContent());
    } else {
        my $response = from_json($client->responseContent());

        if (defined $response->{user}) {
            $self->{userId}           = $response->{user}{id};
        }
        # Extract the session ID from the response...
        if (defined $response->{token}) {
            $self->{sessionId}        = $response->{token};


        } else {

            # An error has occured
            $self->_log(1, "Login: ".Dumper(from_json($client->responseContent())));
            # TODO: break down the error and only report the detail not the JSON
        }
    }

    # If undef, then failed to connect!
    return $self->{sessionId};
}

#### 
# Takes a JWT in its basic form as the input parameter, seperates the elements into 
# header, claim and signature parts and then decodes the claim into a JSON object.
# Returns: 
#   undef if the claim cannot be extracted from the token
#   the claim in JSON
sub _getTokenClaim {
    my $self = shift;
    my $token = shift;

    my $claimJSON = undef;

    if (defined $token)
    {
        my ($headerBase64, $claimBase64, $signatureBase64) = split(/[.]/, $token);

        if (defined $claimBase64)
        {
            my $claimStr = MIME::Base64::decode_base64url($claimBase64);
            $claimJSON = decode_json($claimStr);
        }
    }
    return $claimJSON;
}

#### 
# Takes a JWT as the input parameter, decodes the claim element and checks the 'exp' element
# against the current date/time.
# Returns: 
#   undef if the token is expired or invalid
#   the expiry date/time epoch if the token is valid.
sub _isTokenValid {
    my $self = shift;
    my $token = shift;

    my $expired = undef;

    my $tokenClaim = $self->_getTokenClaim($token);
    if (defined $tokenClaim)
    {
        if (defined $tokenClaim->{exp})
        {
            my $currentTime = time;
            if ($tokenClaim->{exp} > $currentTime)
            {
                $expired = $tokenClaim->{exp};
            }
        }
    }

    return $expired;
}

################################
# LOGOUT from the Hive REST API
################################
sub logout {
    my $self = shift;

    if ($self->{sessionId})
    {
#        $self->{client}->DELETE('/auth/sessions/' . $self->{sessionId}, $self->_getHeaders());
#        if (200 != $self->{client}->responseCode()) {
#            # Failed to connect to API
#            $self->_log(1, "Logout: ".$self->{client}->responseContent());
#        } else {
#            undef $self->{sessionId};
#        }
    }

    return $self->{sessionId};
}

sub _getNodeType {
    my $self = shift;
    my $node = shift;
    
    my $nodeType = '';
    
    if (defined($node->{nodeType})) {
        # If API version is 6.4 or greater then the nodeType can be found at the route of the node
        $nodeType = $node->{nodeType}
    } elsif (defined($node->{attributes}->{nodeType})) {
        # If the API version is less than 6.4 then the nodeType is under node->{attributes}
        $nodeType = $node->{attributes}->{nodeType}->{reportedValue};
    } else {
        # nodeType is missing, use the nodes name.
        $nodeType = $node->{name};
    }

    return $nodeType;
}

sub detectNodes {
    my $self = shift;

    my @hubs = ();
    
    # Get nodes
    $self->{client}->GET('/nodes', $self->_getHeaders());
    if (200 != $self->{client}->responseCode()) {
        $self->_log(1, "detectNodes: ".$self->{client}->responseContent());

    } else {

        my $node_response = decode_json($self->{client}->responseContent());

#       open(my $fh, ">", "node_response1.json");
#       print($fh $self->{client}->responseContent());
#       close($fh);  

        # Find all Hub nodes and their child thermostats
        foreach my $node (@{$node_response->{nodes}}) {
            if (lc $node->{id} eq lc $node->{parentNodeId}) {
                push @hubs, {id => $node->{id}, thermostats => []};
            }
        }
    
        # Find each child thermostat item of each hub
        foreach my $hub (@hubs) {
            foreach my $node (@{$node_response->{nodes}}) {
                if (lc $hub->{id} eq lc $node->{parentNodeId} && $node->{id} ne $hub->{id} && lc $self->_getNodeType($node) eq lc "http://alertme.com/schema/json/node.class.thermostatui.json#") {

                    # We have found the thermostatui node type. Cache the HubId, the UI Id and the thermostat Id
                    my $thermostat = {
                                name => $node->{name}
                            ,   thermostatId => $node->{relationships}->{boundNodes}[0]->{id}         # This is for the receiver
                            ,   thermostatUIId => $node->{id}                                         # This is for the transmitter/thermostat
                            ,   hubId => $hub->{id}
                            };
                

                    # Find the heating and hot water nodes for the thermostat
                    foreach my $node1 (@{$node_response->{nodes}}) {
                        if (lc $thermostat->{thermostatId} eq lc $node1->{parentNodeId}) {
                            if ($node1->{attributes}->{supportsHotWater}->{reportedValue}) {
                                $thermostat->{hotWaterId} = $node1->{id};
                            } else {
                                $thermostat->{heatingId} = $node1->{id};
                            }
                        }
                    }

                    push @{$hub->{thermostats}}, $thermostat;
                }
            }
        }
    
       
        # Cache the detected details
        undef $self->{hubs};
        $self->{hubs} = \@hubs;

#        $self->_log(5, "detectNodes: ".Dumper($self->{hubs}));
    }
    return @hubs;
}


sub _getReading {
    my $self = shift;
    my $reading = shift;
  
    return {            reportedValue => $reading->{reportedValue}
                ,       displayValue => $reading->{displayValue}
                ,       reportReceivedTime => $reading->{reportReceivedTime}
                ,       reportChangedTime => $reading->{reportChangedTime}
#               ,       reportReceivedTime => strftime('%c', localtime($reading->{reportReceivedTime}/1000))
#               ,       reportChangedTime => strftime('%c', localtime($reading->{reportChangedTime}/1000))
            };  
  
}

sub getHubDetails {
    my $self = shift;
    my $id = shift;
    
    my $readings = undef;

    if (defined($id)) {
        foreach my $hub (@{$self->{hubs}}) {
            if (lc $hub->{id} eq lc $id) {
                $self->{client}->GET('/nodes/' . $hub->{id}, $self->_getHeaders());
                if (200 != $self->{client}->responseCode()) {
                    # Failed to connect to API
                    $self->_log(1, "getHubDetails: ".$self->{client}->responseContent());
                } else {

                    my $node_response = decode_json($self->{client}->responseContent());
                
#                   open(my $fh, ">", "hub_details.json");
#                   print($fh $self->{client}->responseContent());
#                   close($fh); 

		            $readings->{presence} = $self->_getReading($node_response->{nodes}[0]->{attributes}->{presence});
		            if (lc $readings->{presence} ne "ABSENT") {
			            # Readings
                        $readings->{devicesState}           = $self->_getReading($node_response->{nodes}[0]->{attributes}->{devicesState});

                        # Device attributes
                        $readings->{powerSupply}            = $self->_getReading($node_response->{nodes}[0]->{attributes}->{powerSupply});
                        $readings->{protocol}               = $self->_getReading($node_response->{nodes}[0]->{attributes}->{protocol});
                        $readings->{hardwareVersion}        = $self->_getReading($node_response->{nodes}[0]->{attributes}->{hardwareVersion});
                        $readings->{kernelVersion}          = $self->_getReading($node_response->{nodes}[0]->{attributes}->{kernelVersion});
                        $readings->{internalIPAddress}      = $self->_getReading($node_response->{nodes}[0]->{attributes}->{internalIPAddress});
                    }
                }
            }
        }
    }
    return $readings;    
}


sub getThermostatReadings {
    my $self = shift;
    my $id = shift;
    
    my $readings = undef;
    
    if (defined($id)) {
        foreach my $hub (@{$self->{hubs}}) {
            foreach my $thermostat (@{$hub->{thermostats}}) {
                if (lc $thermostat->{thermostatUIId} eq lc $id) {

                    $self->{client}->GET('/nodes/' . $thermostat->{thermostatUIId} . ',' . $thermostat->{heatingId} . ',' . $thermostat->{hotWaterId}, $self->_getHeaders());
                    if (200 != $self->{client}->responseCode()) {
                        # Failed to connect to API
                        $self->_log(1, "getThermostatReadings: ".$self->{client}->responseContent());
                    } else {
                        
                        my $node_response = decode_json($self->{client}->responseContent());

                        # Get the transmitter thermostatui node details
                        $readings->{LQI}                = $self->_getReading($node_response->{nodes}[0]->{attributes}->{LQI});
                        $readings->{batteryVoltage}     = $self->_getReading($node_response->{nodes}[0]->{attributes}->{batteryVoltage});
                        $readings->{RSSI}               = $self->_getReading($node_response->{nodes}[0]->{attributes}->{RSSI});
                        $readings->{batteryState}       = $self->_getReading($node_response->{nodes}[0]->{attributes}->{batteryState});
                        $readings->{presence}           = $self->_getReading($node_response->{nodes}[0]->{attributes}->{presence});
                        $readings->{batteryLevel}       = $self->_getReading($node_response->{nodes}[0]->{attributes}->{batteryLevel});

                        # Get the heating node details
                        $readings->{temperature}        = $self->_getReading($node_response->{nodes}[1]->{attributes}->{temperature});
                        $readings->{targetHeatTemperature} = $self->_getReading($node_response->{nodes}[1]->{attributes}->{targetHeatTemperature});
                        $readings->{stateHeatingRelay}  = $self->_getReading($node_response->{nodes}[1]->{attributes}->{stateHeatingRelay});

                        # Get the hot water node details
                        $readings->{stateHotWaterRelay} = $self->_getReading($node_response->{nodes}[2]->{attributes}->{stateHotWaterRelay});
                    }
                }
            }
        }
    }
    return $readings;
}


sub getThermostatDetails {
    my $self = shift;
    my $id = shift;
    
    my $readings = undef;
    
    if (defined($id)) {
        foreach my $hub (@{$self->{hubs}}) {
            foreach my $thermostat (@{$hub->{thermostats}}) {
                if (lc $thermostat->{thermostatUIId} eq lc $id) {

                    $self->{client}->GET('/nodes/' . $thermostat->{thermostatUIId} . ',' . $thermostat->{thermostatId}, $self->_getHeaders());
                    if (200 != $self->{client}->responseCode()) {
                        # Failed to connect to API
                        $self->_log(1, "getThermostatDetails: ".$self->{client}->responseContent());
                    } else {
                        my $node_response = decode_json($self->{client}->responseContent());

                        # Get the transmitter thermostatui node details
                        $readings->{T_nativeIdentifier}   = $self->_getReading($node_response->{nodes}[0]->{attributes}->{nativeIdentifier});
                        $readings->{T_powerSupply}        = $self->_getReading($node_response->{nodes}[0]->{attributes}->{powerSupply});
                        $readings->{T_manufacturer}       = $self->_getReading($node_response->{nodes}[0]->{attributes}->{manufacturer});
                        $readings->{T_hardwareVersion}    = $self->_getReading($node_response->{nodes}[0]->{attributes}->{hardwareVersion});
                        $readings->{T_model}              = $self->_getReading($node_response->{nodes}[0]->{attributes}->{model});
                        $readings->{T_zoneName}           = $self->_getReading($node_response->{nodes}[0]->{attributes}->{zoneName});
                        $readings->{T_softwareVersion}    = $self->_getReading($node_response->{nodes}[0]->{attributes}->{softwareVersion});

                        # Get the receiver thermostatui node details
                        $readings->{R_nativeIdentifier}   = $self->_getReading($node_response->{nodes}[1]->{attributes}->{nativeIdentifier});
                        $readings->{R_powerSupply}        = $self->_getReading($node_response->{nodes}[1]->{attributes}->{powerSupply});
                        $readings->{R_manufacturer}       = $self->_getReading($node_response->{nodes}[1]->{attributes}->{manufacturer});
                        $readings->{R_hardwareVersion}    = $self->_getReading($node_response->{nodes}[1]->{attributes}->{hardwareVersion});
                        $readings->{R_model}              = $self->_getReading($node_response->{nodes}[1]->{attributes}->{model});
                        $readings->{R_zoneName}           = $self->_getReading($node_response->{nodes}[1]->{attributes}->{zoneName});
                        $readings->{R_softwareVersion}    = $self->_getReading($node_response->{nodes}[1]->{attributes}->{softwareVersion});
                    }
                }
            }
        }
    }
    return $readings;
}


sub getNodes {
    my $self = shift;

    my $node_response = undef;
    
    # Get nodes
    $self->{client}->GET('/nodes', $self->_getHeaders());
    if (200 != $self->{client}->responseCode()) {
        $self->_log(1, "getNodes: ".$self->{client}->responseContent());

    } else {
        my $ok = eval {
            $node_response = decode_json($self->{client}->responseContent());
            1;
        };

        if (!$ok) {
            my $err= $@;
            $self->_log(1, "getNodes: ".$err);
            $self->_log(1, "getNodes: ".$self->{client}->responseContent());
        }
    }
    return $node_response;
}


sub getNodeAttributes {
    my $self = shift;
    my $id = shift;
    
    my $attributes = undef;
    
    if (defined($id)) {
        $self->{client}->GET('/nodes/' . $id, $self->_getHeaders());
        if (200 != $self->{client}->responseCode()) {
            $self->_log(1, "getNodeAttributes: ".$self->{client}->responseCode()." - ".$self->{client}->responseContent());

        } else {
            my $node_response = decode_json($self->{client}->responseContent());

            $attributes = $node_response->{nodes}[0]->{attributes};
        }
    }
    
    return $attributes;
}


sub putNodeAttributes {
    my $self = shift;
    my $id = shift;
    my $attributes = shift;
    my $ret = undef;
	
    if (defined($id)) {
        $self->{client}->PUT('/nodes/' . $id, encode_json($attributes), $self->_getHeaders());
        if (200 != $self->{client}->responseCode()) {
            $self->_log(1, "putNodeAttributes ".$self->{client}->responseCode()." - ".$self->{client}->responseContent());
        } else {
            $self->_log(3, "putNodeAttributes: Success!");
        }
		$ret = $self->{client}->responseCode();
    }
    return $ret;
}


1;