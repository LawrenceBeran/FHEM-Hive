# FHEM-Hive
A Hive device module for FHEM home automation

Uses Hive API version 6.4.0

Supported hive devices:
- Hub
- Thermostat

Perl dependant components:
- REST::Client
- JSON
- Math::Round
- Data::Dumper (only for logging)


To add HIVE to your FHEM instance:

	define MyHiveHub Hive_Hub <Hive username> <Hive password>

Once successfully connected to Hive it will automatically create the supported devices within your FHEM configuration.


FHEM Functions supported:
 - Heating
```javascript
    SET <name> HEATING <temp>
    SET <name> HEATING <temp> <period>
    SET <name> HEATING OFF
    SET <name> HEATING AUTO
```
      Where <temp> is a float number e.g. 21.5
      Where <period> is an integer in minutes
  - Water
```javascript
    SET <name> WATER ON
    SET <name> HEATING <period>
    SET <name> HEATING OFF
    SET <name> HEATING AUTO
```
      Where <period> is an integer in minutes
  - frostprotecttemperature
```javascript
    SET <name> frostprotecttemperature <temp>
```
      Where <temp> is a float number e.g. 21.5
  - holiday
```javascript
    SET <name> holiday <start day> <start month> <start year> <end day> <end month> <end year> <temp>
    SET <name> holiday off
```
      Where <temp> is a float number e.g. 21.5
  - waterprofile
```javascript 
    SET <name> waterweekprofile [<weekday> <state>,<until>,<state>,<until>,<state>,<until>] [<repeat>]
```
      Where <weekday>: Mon, Tue, Wed, Thu, Fri, Sat, Sun
      Where <until>: eg. 0:00, 18:00, 23:30
      Where <state>: On, Off
  - heatingprofile
```javascript 
    SET <name> heatingweekprofile [<weekday> <temp>,<until>,<temp>,<until>,<temp>,<until>] [<repeat>]
```
      Where <weekday>: Mon, Tue, Wed, Thu, Fri, Sat, Sun
      Where <until>: eg. 8:00, 18:00, 23:30
      Where <temp>: eg. 17.5, 21
  
Has a load of internals for information about the attached devices.

Polls Hive for the following readings.

Thermostat:
  - HeatingState
  - Heating_ActiveHeatCoolMode
  - Heating_ActiveScheduleLock
  - Heating_State
  - HotWaterState
  - HotWater_ActiveHeatCoolMode
  - HotWater_ActiveScheduleLock
  - HotWater_State
  - RSSI
  - TargetTemperature
  - Temperature
  - presence

UI:
  - RSSI
  - batteryLevel
  - batteryState
  - batteryVoltage
  - presence  
 


Note: No FHEM documentation has been provided
