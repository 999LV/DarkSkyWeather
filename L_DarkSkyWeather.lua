_NAME = "DarkSky Weather"
_VERSION = "0.7"
_DESCRIPTION = "DarkSky Weather plugin"
_AUTHOR = "Rene Boer"

--[[

Version 0.1 2016-11-17 - Alpha version for testing
Version 0.2 2016-11-18 - Beta version for first AltUI App Store release
Version 0.3 2016-11-19 - Beta version with:
		automatic location setup by default - thanks @akbooer
		default icon fix - thanks @NikV
		state icons to reflect current weather - icons from icon8.com
Version 0.4 2016-11-26 - a few bug fixes and exposes more DarkSky variables - thanks @MikeYeager
Version 0.5 2019-03-23 - Added WindGust, uvIndex, Visibility
Version 0.7 2019-04-09 - Added Settings tab, Vera UI7 support, optimized request eliminating hourly data.

Original author logread (aka LV999) upto version 0.4.

It is intended to capture and monitor select weather data
provided by DarkSky (formerly Forecast.io) under their general terms and conditions
available on the website https://darksky.net/dev/

It requires an API developer key that must be obtained from the website.

This program is free software: you can redistribute it and/or modify
it under the condition that it is for private or home useage and
this whole comment is reproduced in the source code file.
Commercial utilisation is not authorized without the appropriate
written agreement from "reneboer", contact by PM on http://community.getvera.com/
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
--]]

-- plugin general variables

local https = require("ssl.https")
local json = require("dkjson")

local SID_Weather = "urn:upnp-micasaverde-com:serviceId:Weather1"
local SID_Security = "urn:micasaverde-com:serviceId:SecuritySensor1"
local SID_AltUI = "urn:upnp-org:serviceId:altui1"
local DS_urltemplate = "https://api.darksky.net/forecast/%s/%s,%s?lang=%s&units=%s&exclude=hourly"
local this_device, child_temperature, child_humidity = nil, nil, nil

-- these are the configuration and their default values
local DS = { 
	Key = "",
	Latitude = "",
	Longitude = "",
	Period = 1800,	-- data refresh interval in seconds
	Units = "auto",
	Language = "en", -- default language
	ProviderName = "DarkSky (formerly Forecast.io)", -- added for reference to data source
	ProviderURL = "https://darksky.net/dev/",
	IconsProvider = "Thanks to icons8 at https://icons8.com",
	Documentation = "https://raw.githubusercontent.com/reneboer/DarkSkyWeather/master/documentation/DarkSkyWeather.pdf",
	LogLevel = 1,
	Version = _VERSION
}

local static_Vars = "ProviderName, ProviderURL, IconsProvider, Documentation, Version"

-- this is the table used to map DarkSky output elements with the plugin serviceIds and variables
local VariablesMap = {
	currently_apparentTemperature = {serviceId = SID_Weather, variable = "ApparentTemperature"},
	currently_cloudCover = {serviceId = SID_Weather, variable = "CurrentCloudCover", multiplier = 100},
	currently_dewPoint = {serviceId = SID_Weather, variable = "CurrentDewPoint", decimal = 1},
	currently_humidity = {serviceId = "urn:micasaverde-com:serviceId:HumiditySensor1", variable = "CurrentLevel", multiplier = 100, decimal = 0},
	currently_icon = {serviceId = SID_Weather, variable = "icon"},
	currently_ozone = {serviceId = SID_Weather, variable = "Ozone"},
	currently_uvIndex = {serviceId = SID_Weather, variable = "uvIndex"},
	currently_visibility = {serviceId = SID_Weather, variable = "Visibility"},
	currently_precipIntensity = {serviceId = SID_Weather, variable = "PrecipIntensity"},
	currently_precipProbability = {serviceId = SID_Weather, variable = "PrecipProbability", multiplier = 100},
	currently_precipType = {serviceId = SID_Weather, variable = "PrecipType"},
	currently_pressure = {serviceId = "urn:upnp-org:serviceId:BarometerSensor1", variable = "CurrentPressure", decimal = 0},
	currently_summary = {serviceId = SID_Weather, variable = "CurrentConditions"},
	currently_temperature = {serviceId = "urn:upnp-org:serviceId:TemperatureSensor1", variable = "CurrentTemperature", decimal = 1},
	currently_time = {serviceId = SID_Weather, variable = "LastUpdate"},
	currently_windBearing =  {serviceId = SID_Weather, variable = "WindBearing"},
	currently_windSpeed = {serviceId = SID_Weather, variable = "WindSpeed"},
	currently_windGust = {serviceId = SID_Weather, variable = "WindGust"},
	daily_data_1_pressure = {serviceId = SID_Weather, variable = "TodayPressure", decimal = 0},
	daily_data_1_summary = {serviceId = SID_Weather, variable = "TodayConditions"},
	daily_data_1_temperatureMax = {serviceId = SID_Weather, variable = "TodayHighTemp", decimal = 1},
	daily_data_1_temperatureMin = {serviceId = SID_Weather, variable = "TodayLowTemp", decimal = 1},
	daily_data_2_pressure = {serviceId = SID_Weather, variable = "TomorrowPressure", decimal = 0},
	daily_data_2_summary = {serviceId = SID_Weather, variable = "TomorrowConditions"},
	daily_data_2_temperatureMax = {serviceId = SID_Weather, variable = "TomorrowHighTemp", decimal = 1},
	daily_data_2_temperatureMin = {serviceId = SID_Weather, variable = "TomorrowLowTemp", decimal = 1},
	daily_summary = {serviceId = SID_Weather, variable = "WeekConditions"}
}

---------------------------------------------------------------------------------------------
-- Utility functions
---------------------------------------------------------------------------------------------
local log
local var

-- API getting and setting variables and attributes from Vera more efficient.
local function varAPI()
	local def_sid, def_dev = '', 0
	
	local function _init(sid,dev)
		def_sid = sid
		def_dev = dev
	end
	
	-- Get variable value
	local function _get(name, sid, device)
		local value = luup.variable_get(sid or def_sid, name, tonumber(device or def_dev))
		return (value or '')
	end

	-- Get variable value as number type
	local function _getnum(name, sid, device)
		local value = luup.variable_get(sid or def_sid, name, tonumber(device or def_dev))
		local num = tonumber(value,10)
		return (num or 0)
	end
	
	-- Set variable value
	local function _set(name, value, sid, device)
		local sid = sid or def_sid
		local device = tonumber(device or def_dev)
		local old = luup.variable_get(sid, name, device)
		if (tostring(value) ~= tostring(old or '')) then 
			luup.variable_set(sid, name, value, device)
		end
	end

	-- create missing variable with default value or return existing
	local function _default(name, default, sid, device)
		local sid = sid or def_sid
		local device = tonumber(device or def_dev)
		local value = luup.variable_get(sid, name, device) 
		if (not value) then
			value = default	or ''
			luup.variable_set(sid, name, value, device)	
		end
		return value
	end
	
	-- Get an attribute value, try to return as number value if applicable
	local function _getattr(name, device)
		local value = luup.attr_get(name, tonumber(device or def_dev))
		local nv = tonumber(value,10)
		return (nv or value)
	end

	-- Set an attribute
	local function _setattr(name, value, device)
		local val = _getattr(name, device)
		if val ~= value then 
			luup.attr_set(name, value, tonumber(device or def_dev))
		end	
	end
	
	return {
		Get = _get,
		Set = _set,
		GetNumber = _getnum,
		Default = _default,
		GetAttribute = _getattr,
		SetAttribute = _setattr,
		Initialize = _init
	}
end

-- API to handle basic logging and debug messaging
local function logAPI()
local def_level = 1
local def_prefix = ''
local def_debug = false
local def_file = false
local max_length = 100
local onOpenLuup = false
local taskHandle = -1

	local function _update(level)
		if level > 100 then
			def_file = true
			def_debug = true
			def_level = 10
		elseif level > 10 then
			def_debug = true
			def_file = false
			def_level = 10
		else
			def_file = false
			def_debug = false
			def_level = level
		end
	end	

	local function _init(prefix, level,onol)
		_update(level)
		def_prefix = prefix
		onOpenLuup = onol
	end	
	
	-- Build loggin string safely up to given lenght. If only one string given, then do not format because of length limitations.
	local function prot_format(ln,str,...)
		local msg = ""
		if arg[1] then 
			_, msg = pcall(string.format, str, unpack(arg))
		else 
			msg = str or "no text"
		end 
		if ln > 0 then
			return msg:sub(1,ln)
		else
			return msg
		end	
	end	
	local function _log(...) 
		if (def_level >= 10) then
			luup.log(def_prefix .. ": " .. prot_format(max_length,...), 50) 
		end	
	end	
	
	local function _info(...) 
		if (def_level >= 8) then
			luup.log(def_prefix .. "_info: " .. prot_format(max_length,...), 8) 
		end	
	end	

	local function _warning(...) 
		if (def_level >= 2) then
			luup.log(def_prefix .. "_warning: " .. prot_format(max_length,...), 2) 
		end	
	end	

	local function _error(...) 
		if (def_level >= 1) then
			luup.log(def_prefix .. "_error: " .. prot_format(max_length,...), 1) 
		end	
	end	

	local function _debug(...)
		if def_debug then
			luup.log(def_prefix .. "_debug: " .. prot_format(-1,...), 50) 
		end	
	end
	
	-- Write to file for detailed analisys
	local function _logfile(...)
		if def_file then
			local fh = io.open("/tmp/log/harmony.log","a")
			local msg = format(...) or "no text"
			fh:write(msg)
			fh:write("\n")
			fh:close()
		end	
	end
	
	local function _devmessage(devID, isError, timeout, ...)
		local message =  prot_format(60,...)
		local status = isError and 2 or 4
		-- Standard device message cannot be erased. Need to do a reload if message w/o timeout need to be removed. Rely on caller to trigger that.
		if onOpenLuup then
			taskHandle = luup.task(message, status, def_prefix, taskHandle)
			if timeout ~= 0 then
				luup.call_delay("logAPI_clearTask", timeout, "", false)
			else
				taskHandle = -1
			end
		else
			luup.device_message(devID, status, message, timeout, def_prefix)
		end	
	end
	
	local function logAPI_clearTask()
		luup.task("", 4, def_prefix, taskHandle)
		taskHandle = -1
	end
	_G.logAPI_clearTask = logAPI_clearTask
	
	
	return {
		Initialize = _init,
		Error = _error,
		Warning = _warning,
		Info = _info,
		Log = _log,
		Debug = _debug,
		Update = _update,
		LogFile = _logfile,
		DeviceMessage = _devmessage
	}
end 

-- processes and parses the DS data into device variables 
local function setvariables(key, value)
	if VariablesMap[key] then
		if VariablesMap[key].pattern then value = string.gsub(value, VariablesMap[key].pattern, "") end
		if VariablesMap[key].multiplier then value = value * VariablesMap[key].multiplier end
		if VariablesMap[key].decimal then value = math.floor(value * 10^VariablesMap[key].decimal + .5) / 10^VariablesMap[key].decimal end
		var.Set(VariablesMap[key].variable, value, VariablesMap[key].serviceId)
		if VariablesMap[key].serviceId == "urn:upnp-org:serviceId:TemperatureSensor1" then -- we update the child device as well
			var.Set(VariablesMap[key].variable, value, VariablesMap[key].serviceId, child_temperature)
		end
		if VariablesMap[key].serviceId == "urn:micasaverde-com:serviceId:HumiditySensor1" then -- we update the child device as well
			var.Set(VariablesMap[key].variable, value, VariablesMap[key].serviceId, child_humidity)
		end
		if tonumber(DS.RainSensor) == 1 then
			-- the option of a virtual rain sensor is on, so we set the rain flags based on the trigger levels
			log.Debug("DEBUG: IntensityTrigger = %d - ProbabilityTrigger = %d", DS.PrecipIntensityTrigger, DS.PrecipProbabilityTrigger) 
			if key == "currently_precipIntensity" and tonumber(value) >= tonumber(DS.PrecipIntensityTrigger)
				then rain_intensity_trigger = tonumber(value) >= tonumber(DS.PrecipIntensityTrigger) 
			elseif key == "currently_precipProbability" and tonumber(value) >= tonumber(DS.PrecipProbabilityTrigger)
				then rain_probability_trigger = tonumber(value) >= tonumber(DS.PrecipProbabilityTrigger) end
			end
	end
end

-- flattens the DS json raw weather information hierarchy into a single dimension lua table for subsequent parsing.
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

-- call the DarkSky API with our key and location parameters and processes the weather data json if success
local function DS_GetData()
	if DS.Key ~= "" then
		local url = string.format(DS_urltemplate, DS.Key, DS.Latitude, DS.Longitude, DS.Language, DS.Units)
		log.Info("calling DarkSky API with url = %s", url)
		local wdata, retcode = https.request(url)
		local err = (retcode ~=200)
		if err then -- something wrong happpened (website down, wrong key or location)
			wdata = nil -- to do: better error handling ?
			log.Error("DarkSky API call failed with http code = %s", tostring(retcode))
		else
			log.Debug(wdata)
			wdata, err = json.decode(wdata)
			if not (err == 225) then
				extractloop(wdata)
				-- Update display for ALTUI
				var.Set("DisplayLine1", var.Get("CurrentConditions"), SID_AltUI)
				var.Set("DisplayLine2",	"Pressure: " .. var.Get("CurrentPressure", "urn:upnp-org:serviceId:BarometerSensor1"), SID_AltUI)
			else 
				log.Error("DarkSky API json decode error = %s", tostring(err)) 
			end
		end
		return err
	else
		var.Set("DisplayLine1", "Complete settings first.", SID_AltUI)
		log.Error("DarkSky API key is not yet specified.") 
		return 403
	end
end

-- check if device configuration parameters are current
local function check_param_updates()
local tvalue

	for key, value in pairs(DS) do
		tvalue = var.Get(key)
		if string.find(static_Vars, key) and tvalue ~= value then
			-- reset the static device variables to their build-in default in case new version changed these   
			tvalue = ""
		end  
		if tvalue == "" then
			if key == "Latitude" and value == "" then -- new set up, initialize latitude from controller info
				value = var.GetAttribute("latitude", 0)
				DS[key] = value
			end
			if key == "Longitude" and value == "" then -- new set up, initialize longitude from controller info
				value = var.GetAttribute("longitude", 0)
				DS[key] = value
			end
			var.Set(key, value) -- device newly created... need to initialize variables
		elseif tvalue ~= value then 
			DS[key] = tvalue 
		end
	end
end

-- poll DarkSky Weather on a periodic basis
function Weather_delay_callback()
	check_param_updates()
	DS_GetData() -- get DarkSky data
	luup.call_delay ("Weather_delay_callback", DS["Period"])
end

-- creates/initializes and registers the default Temperature & Humidity children devices
-- and the optional virtual rain sensor child device
local function createchildren()
	local children = luup.chdev.start(this_device)
	luup.chdev.append(this_device, children, "DSWT", "DarkSky Temperature",
			"urn:schemas-micasaverde-com:device:TemperatureSensor:1",
			"D_TemperatureSensor1.xml", "", "", true)
	luup.chdev.append(	this_device, children, "DSWH", "DarkSky Humidity",
			"urn:schemas-micasaverde-com:device:HumiditySensor:1",
			"D_HumiditySensor1.xml", "", "", true)
	luup.chdev.sync(this_device, children)
	for devNo, dev in pairs (luup.devices) do -- check if all children exist
		if dev.device_num_parent == this_device then
			if dev.id == "DSWT" then 
				child_temperature = devNo
			elseif dev.id == "DSWH" then 
				child_humidity = devNo 
			end
		end
	end
end

-- Update the log level.
function DS_SetLogLevel(logLevel)
	local level = tonumber(logLevel,10) or 1
	var.Set("LogLevel", level)
	log.Update(level)
end

-- device init sequence, called from the device implementation file
function init(lul_device)
	this_device = lul_device
	log = logAPI()
	var = varAPI()
	var.Initialize(SID_Weather, this_device)
	var.Default("LogLevel", 1)
	log.Initialize(_NAME, var.GetNumber("LogLevel"))
	log.Info("device startup")
	check_param_updates()
	createchildren(this_device)
	Weather_delay_callback()
	log.Info("device started")
	return true, "OK", _NAME
end
