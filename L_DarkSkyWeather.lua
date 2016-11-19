_NAME = "DarkSky Weather"
_VERSION = "0.3"
_DESCRIPTION = "DarkSky Weather plugin"
_AUTHOR = "logread (aka LV999)"

--[[

Version 0.1 2016-11-17 - Alpha version for testing
Version 0.2 2016-11-18 - Beta version for first AltUI App Store release
Version 0.3 2016-11-19 - Beta version with:
        automatic location setup by default - thanks @akbooer
        default icon fix - thanks @NikV
        state icons to reflect current weather - icons from icon8.com 

This plug-in is intended to run under the "openLuup" emulation of a Vera system
It should work on a "real" Vera, but has not been tested in that environment.
It is intended to capture and monitor select weather data
provided by DarkSky (formerly Forecast.io) under their general terms and conditions
available on the website https://darksky.net/dev/

It requires an API developer key that must be obtained from the website.

This program is free software: you can redistribute it and/or modify
it under the condition that it is for private or home useage and
this whole comment is reproduced in the source code file.
Commercial utilisation is not authorized without the appropriate
written agreement from "logread", contact by PM on http://forum.micasaverde.com/
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
--]]

local https = require("ssl.https")
local json = require("dkjson")

local SID_Weather = "urn:upnp-micasaverde-com:serviceId:Weather1"
local SID_AltUI = "urn:upnp-org:serviceId:altui1"
local DS_urltemplate = "https://api.darksky.net/forecast/%s/%s,%s?lang=%s&units=%s"

local DS = {
	Key = "Enter your DarkSky API key here",
	Latitude = "",
  Longitude = "",
	Period = 1800,	-- data refresh interval in seconds
	Units = "auto",
	Language = "en", -- default language
  ProviderName = "DarkSky (formerly Forecast.io)", -- added for reference to data source
	ProviderURL = "https://darksky.net/dev/",
  IconsProvider = "Thanks to icons8 at https://icons8.com",
  Documentation = "https://raw.githubusercontent.com/999LV/DarkSkyWeather/master/documentation/DarkSkyWeather.pdf",
  Version = _VERSION
	}

local VariablesMap = {
	currently_temperature = {serviceId = "urn:upnp-org:serviceId:TemperatureSensor1", variable = "CurrentTemperature", decimal = 1},
	currently_humidity = {serviceId = "urn:micasaverde-com:serviceId:HumiditySensor1", variable = "CurrentLevel", multiplier = 100, decimal = 0},
  currently_time = {serviceId = SID_Weather, variable = "LastUpdate"},
  currently_pressure = {serviceId = "urn:upnp-org:serviceId:BarometerSensor1", variable = "CurrentPressure", decimal = 0},
  currently_dewPoint = {serviceId = SID_Weather, variable = "CurrentDewPoint", decimal = 1},
  currently_summary = {serviceId = SID_Weather, variable = "CurrentConditions"},
  currently_cloudCover = {serviceId = SID_Weather, variable = "CurrentCloudCover", multiplier = 100},
  currently_icon = {serviceId = SID_Weather, variable = "icon"},
  daily_summary = {serviceId = SID_Weather, variable = "WeekConditions"},
  daily_data_1_summary = {serviceId = SID_Weather, variable = "TodayConditions"},
  daily_data_2_summary = {serviceId = SID_Weather, variable = "TomorrowConditions"},
  daily_data_1_temperatureMax = {serviceId = SID_Weather, variable = "TodayHighTemp", decimal = 1},
  daily_data_1_temperatureMin = {serviceId = SID_Weather, variable = "TodayLowTemp", decimal = 1},
  daily_data_1_pressure = {serviceId = SID_Weather, variable = "TodayPressure", decimal = 0},
  daily_data_2_temperatureMax = {serviceId = SID_Weather, variable = "TomorrowHighTemp", decimal = 1},
  daily_data_2_temperatureMin = {serviceId = SID_Weather, variable = "TomorrowLowTemp", decimal = 1},
  daily_data_2_pressure = {serviceId = SID_Weather, variable = "TomorrowPressure", decimal = 0}
	}

-- functions

local function nicelog(message)
	local display = "DarkSky Weather : %s"
	message = message or ""
	if type(message) == "table" then message = table.concat(message) end
	luup.log(string.format(display, message))
--	print(string.format(display, message))
end

 local function setVar (service, name, value, device) -- credit to @akbooer
  device = device or this_device
  local old = luup.variable_get (service, name, device)
  if tostring(value) ~= old then
   luup.variable_set (service, name, value, device)
  end
end

local function AltUIdisplay()
  setVar(SID_AltUI, "DisplayLine1", luup.variable_get(SID_Weather, "CurrentConditions", this_device), this_device)
  setVar(SID_AltUI, "DisplayLine2",
    "Pressure: " .. luup.variable_get("urn:upnp-org:serviceId:BarometerSensor1", "CurrentPressure", this_device),
    this_device)
end

local function setvariables(key, value) -- process the DS data as needed
	if VariablesMap[key] then
		if VariablesMap[key].pattern then value = string.gsub(value, VariablesMap[key].pattern, "") end
    if VariablesMap[key].multiplier then value = value * VariablesMap[key].multiplier end
    if VariablesMap[key].decimal then value = math.floor(value * 10^VariablesMap[key].decimal + .5) / 10^VariablesMap[key].decimal end
    setVar(VariablesMap[key].serviceId, VariablesMap[key].variable, value)
		if VariablesMap[key].serviceId == "urn:upnp-org:serviceId:TemperatureSensor1" then -- we update the child device as well
			setVar(VariablesMap[key].serviceId, VariablesMap[key].variable, value, child_temperature)
		end
		if VariablesMap[key].serviceId == "urn:micasaverde-com:serviceId:HumiditySensor1" then -- we update the child device as well
			setVar(VariablesMap[key].serviceId, VariablesMap[key].variable, value, child_humidity)
		end
--		nicelog({VariablesMap[key].serviceId," - ", VariablesMap[key].variable, " = ", value})
	end
end

local function extractloop(datatable, keystring)
	local tempstr, separator
	keystring = keystring or ""
	for tkey, value in pairs(datatable) do
		if keystring ~= "" then separator = "_" else separator = "" end
		tempstr = table.concat{keystring, separator, tkey}
		if type(value) == "table" then -- one level up in the data hierarchy -> recursive call
			extractloop(value, tempstr)
		else
			setvariables(tempstr, value)
		end
	end
end

local function DS_GetData() -- call the DarkSky API with our key and location parameters and decode/parse the weather data
  local url = string.format(DS_urltemplate, DS.Key, DS.Latitude, DS.Longitude, DS.Language, DS.Units)
	nicelog({"calling DarkSky API with url = ", url})
	local wdata, retcode = https.request(url)
	local err = (retcode ~=200)
	if err then -- something wrong happpened (website down, wrong key or location)
		wdata = nil -- to do: proper error handling
		nicelog({"DarkSky API call failed with http code =  ", tostring(retcode)})
	else
    wdata, err = json.decode(wdata)
		if not (err == 225) then
        extractloop(wdata)
        AltUIdisplay()
    else nicelog({"DarkSky API json decode error = ", tostring(err)}) end
	end
	return err
end

local function check_param_updates() -- check if device parameters are current
local tvalue
	for key, value in pairs(DS) do
		tvalue = luup.variable_get(SID_Weather, key, this_device) or ""
    if key == "Version" and tvalue ~= value then tvalue = "" end -- register we upgraded to a new version 
		if tvalue == "" then
      if key == "Latitude" and value == "" then -- new set up, initialize latitude from controller info
        value = luup.attr_get("latitude", 0)
        DS[key] = value
      end
      if key == "Longitude" and value == "" then -- new set up, initialize longitude from controller info
        value = luup.attr_get("longitude", 0)
        DS[key] = value
      end
      luup.variable_set(SID_Weather, key, value, this_device) -- device newly created... need to initialize variables
		elseif tvalue ~= value then DS[key] = tvalue end
	end
end

function Weather_delay_callback() -- poll Weather Undergound for changes
	check_param_updates()
	DS_GetData() -- get DarkSky data
	luup.call_delay ("Weather_delay_callback", DS["Period"])
end

local function createchildren()
	local children = luup.chdev.start(this_device)
	luup.chdev.append(	this_device, children, "DSWT", "DarkSky Temperature", "urn:schemas-micasaverde-com:device:TemperatureSensor:1",
						"D_TemperatureSensor1.xml", "", "", true)
	luup.chdev.append(	this_device, children, "DSWH", "DarkSky Humidity", "urn:schemas-micasaverde-com:device:HumiditySensor:1",
						"D_HumiditySensor1.xml", "", "", true)
	luup.chdev.sync(this_device, children)
	child_temperature = nil
	child_humidity = nil
	for devNo, dev in pairs (luup.devices) do -- check if both children exist
		if dev.device_num_parent == this_device then
			if dev.id == "DSWT" then child_temperature = devNo
			elseif dev.id == "DSWH" then child_humidity = devNo end
		end
    end
end

function init(lul_device)
	this_device = lul_device
	nicelog("device startup")
	createchildren(this_device)
	Weather_delay_callback()
	nicelog("device started")
	return true, "OK", _NAME
end
