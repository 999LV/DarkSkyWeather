//# sourceURL=J_DarkSkyWeather.js
/* 
	DarkSkyWeather Hub Control UI
	Written by R.Boer. 
	V0.7 9 April 2019
*/
var DarkSkyWeather = (function (api) {

	// Constants. Keep in sync with LUA code.
    var _uuid = '12021512-0000-a0a0-b0b0-c0c030303032';
	var SID_Weather = "urn:upnp-micasaverde-com:serviceId:Weather1";
	var bOnALTUI = false;

	// Forward declaration.
    var myModule = {};

    function _onBeforeCpanelClose(args) {
		showBusy(false);
        //console.log('DarkSkyWeather, handler for before cpanel close');
    }

    function _init() {
        // register to events...
        api.registerEventHandler('on_ui_cpanel_before_close', myModule, 'onBeforeCpanelClose');
		// See if we are on ALTUI
		if (typeof ALTUI_revision=="string") {
			bOnALTUI = true;
		}
    }
	
	// Return HTML for settings tab
	function _Settings() {
		_init();
        try {
			var deviceID = api.getCpanelDeviceId();
			var deviceObj = api.getDeviceObject(deviceID);
			var timeUpd = [{'value':'300','label':'5 minutes'},{'value':'900','label':'15 minutes'},{'value':'1800','label':'30 minutes'},{'value':'3600','label':'1 hour'}];
			var logLevel = [{'value':'1','label':'Error'},{'value':'2','label':'Warning'},{'value':'8','label':'Info'},{'value':'11','label':'Debug'}];
			var unitMap = [{'value':'auto','label':'Auto'},{'value':'si','label':'System International'},{'value':'us','label':'Imperial'},{'value':'ca','label':'Canadian'},{'value':'uk2','label':'British'}];
			var languageMap = [{'value':'ar','label':'Arabic'},{'value':'aa','label':'Azerbaijani'},{'value':'be','label':'Belarusian'},{'value':'bg','label':'Bulgarian'},{'value':'bn','label':'Bengali'},{'value':'bs','label':'Bosnian'},{'value':'ca','label':'Catalan'},{'value':'cs','label':'Czech'},{'value':'da','label':'Danish'},{'value':'nl','label':'Dutch'},{'value':'de','label':'German'},{'value':'el','label':'Greek'},{'value':'en','label':'English'},{'value':'eo','label':'Esperanto'},{'value':'es','label':'Spanish'},{'value':'et','label':'Estonian'},{'value':'fi','label':'Finnish'},{'value':'fr','label':'French'},{'value':'he','label':'Hebrew'},{'value':'hi','label':'Hindi'},{'value':'hr','label':'Croatian'},{'value':'hu','label':'Hungarian'},{'value':'id','label':'Indonesian'},{'value':'is','label':'Icelandic'},{'value':'it','label':'Italian'},{'value':'ja','label':'Japanese'},{'value':'ka','label':'Georgian'},{'value':'kn','label':'Kannada'},{'value':'ko','label':'Korean'},{'value':'kw','label':'Cornish'},{'value':'lv','label':'Latvian'},{'value':'ml','label':'Malayam'},{'value':'mr','label':'Marathi'},{'value':'nb','label':'Norwegian Bokmål'},{'value':'no','label':'Norwegian'},{'value':'pa','label':'Punjabi'},{'value':'pl','label':'Polish'},{'value':'pt','label':'Portuguese'},{'value':'ro','label':'Romanian'},{'value':'ru','label':'Russian'},{'value':'sk','label':'Slovak'},{'value':'sl','label':'Slovenian'},{'value':'sr','label':'Serbian'},{'value':'sv','label':'Swedish'},{'value':'ta','label':'Tamil'},{'value':'te','label':'Telugu'},{'value':'tet','label':'Tetum'},{'value':'tr','label':'Turkish'},{'value':'uk','label':'Ukrainian'},{'value':'ur','label':'Urdu'},{'value':'x-pig-latin','label':'Igpay Atinlay'},{'value':'zh','label':'simplified Chinese'},{'value':'zh-tw','label':'traditional Chinese'}];

			var html = '<div class="deviceCpanelSettingsPage">'+
				'<h3>Device #'+deviceID+'&nbsp;&nbsp;&nbsp;'+api.getDisplayedDeviceName(deviceID)+'</h3>';
			if (deviceObj.disabled === '1' || deviceObj.disabled === 1) {
				html += '<br>Plugin is disabled in Attributes.';
			} else {
				html +=	htmlAddInput(deviceID, 'DarkSky Provider Key', 70, 'Key','UpdateSettingsCB') + 
				htmlAddInput(deviceID, 'Location Latitude', 10, 'Latitude','UpdateSettingsCB')+
				htmlAddInput(deviceID, 'Location Longitude', 10, 'Longitude','UpdateSettingsCB')+
				htmlAddPulldown(deviceID, 'Update Interval', 'Period', timeUpd,'UpdateSettingsCB')+
				htmlAddPulldown(deviceID, 'Language', 'Language', languageMap,'UpdateSettingsCB')+
				htmlAddPulldown(deviceID, 'Units', 'Units', unitMap,'UpdateSettingsCB')+
				htmlAddPulldown(deviceID, 'Log level', 'LogLevel', logLevel, 'UpdateSettingsCB')+
				htmlAddButton(deviceID,'DoReload');
			}
			html += '</div>';
			api.setCpanelContent(html);
        } catch (e) {
            Utils.logError('Error in DarkSkyWeather.Settings(): ' + e);
        }
	}

	// Call back on settings change
	function _UpdateSettingsCB(deviceID,varID) {
		var val = htmlGetElemVal(deviceID, varID);
		switch (varID) {
		case 'LogLevel':
			api.performLuActionOnDevice(deviceID, SID_Weather, 'SetLogLevel',  { actionArguments: { newLogLevel: val }});
			break;
		default:
			varSet(deviceID,varID,val);
		}
	}

	// Add a label and pulldown selection
	function htmlAddPulldown(di, lb, vr, values, cb) {
		try {
			var selVal = varGet(di, vr);
			var onch = (typeof cb != 'undefined') ? ' onchange="DarkSkyWeather.'+cb+'(\''+di+'\',\''+vr+'\');" ' : ' ';
			var html = '<div class="clearfix labelInputContainer">'+
				'<div class="pull-left inputLabel '+((bOnALTUI) ? 'form-control form-control-sm form-control-plaintext' : '')+'" style="width:280px;">'+lb+'</div>'+
				'<div class="pull-left customSelectBoxContainer">'+
				'<select '+onch+'id="dsID_'+vr+di+'" class="customSelectBox '+((bOnALTUI) ? 'form-control form-control-sm' : '')+'" style="width:200px;">';
			for(var i=0;i<values.length;i++){
				html += '<option value="'+values[i].value+'" '+((values[i].value==selVal)?'selected':'')+'>'+values[i].label+'</option>';
			}
			html += '</select>'+
				'</div>'+
				'</div>';
			return html;
		} catch (e) {
			Utils.logError('DarkSkyWeather: htmlAddPulldown(): ' + e);
		}
	}

	// Add a standard input for a plug-in variable.
	function htmlAddInput(di, lb, si, vr, cb, sid, df) {
		var val = (typeof df != 'undefined') ? df : varGet(di,vr,sid);
		var onch = (typeof cb != 'undefined') ? ' onchange="DarkSkyWeather.'+cb+'(\''+di+'\',\''+vr+'\');" ' : ' ';
		var typ = 'type="text"';
		var html = '<div class="clearfix labelInputContainer">'+
					'<div class="pull-left inputLabel '+((bOnALTUI) ? 'form-control form-control-sm form-control-plaintext' : '')+'" style="width:280px;">'+lb+'</div>'+
					'<div class="pull-left">'+
						'<input class="customInput '+((bOnALTUI) ? 'altui-ui-input form-control form-control-sm' : '')+'" '+onch+'style="width:280px;" '+typ+' size="'+si+'" id="dsID_'+vr+di+'" value="'+val+'">'+
					'</div>'+
				   '</div>';
		return html;
	}

	// Update variable in user_data and lu_status
	function varSet(deviceID, varID, varVal, sid) {
		if (typeof(sid) == 'undefined') { sid = SID_Weather; }
		api.setDeviceStateVariablePersistent(deviceID, sid, varID, varVal);
	}
	// Get variable value. When variable is not defined, this new api returns false not null.
	function varGet(deviceID, varID, sid) {
		try {
			if (typeof(sid) == 'undefined') { sid = SID_Weather; }
			var res = api.getDeviceState(deviceID, sid, varID);
			if (res !== false && res !== null && res !== 'null' && typeof(res) !== 'undefined') {
				return res;
			} else {
				return '';
			}	
        } catch (e) {
            return '';
        }
	}

	// Get the value of an HTML input field
	function htmlGetElemVal(di,elID) {
		var res;
		try {
			res=$('#dsID_'+elID+di).val();
		}
		catch (e) {	
			res = '';
		}
		return res;
	}

	// Add a Save Settings button
	function htmlAddButton(di, cb) {
		var html = '<div class="cpanelSaveBtnContainer labelInputContainer clearfix">'+	
			'<input class="vBtn pull-right btn" type="button" value="Reload Luup" onclick="DarkSkyWeather.'+cb+'(\''+di+'\');"></input>'+
			'</div>';
		return html;
	}

	// Show/hide the interface busy indication.
	function showBusy(busy) {
		if (busy === true) {
			try {
				api.ui.showStartupModalLoading(); // version v1.7.437 and up
			} catch (e) {
				myInterface.showStartupModalLoading(); // For ALTUI support.
			}
		} else {
			try {
				api.ui.hideModalLoading(true);
			} catch (e) {
				myInterface.hideModalLoading(true); // For ALTUI support
			}	
		}
	}
	
	// Show message dialog
	function htmlSetMessage(msg,error) {
		try {
			if (error === true) {
				api.ui.showMessagePopupError(msg);
			} else {
				api.ui.showMessagePopup(msg,0);
			}	
		}	
		catch (e) {	
			$("#ham_msg").html(msg+'<br>&nbsp;');
		}	
	}

	// Force luup reload.
	function _DoReload(deviceID) {
		application.sendCommandSaveUserData(true);
		showBusy(true);
		htmlSetMessage("Changes to configuration made.<br>Now wait for reload to complete and then refresh your browser page!",false);
		setTimeout(function() {
			api.performLuActionOnDevice(0, "urn:micasaverde-com:serviceId:HomeAutomationGateway1", "Reload", {});
			showBusy(false);
		}, 4000);	
	}

	// Expose interface functions
    myModule = {
		// Internal for panels
        uuid: _uuid,
        init: _init,
        onBeforeCpanelClose: _onBeforeCpanelClose,
		UpdateSettingsCB: _UpdateSettingsCB,
		DoReload: _DoReload,
		
		// For JSON calls
        Settings: _Settings,
    };
    return myModule;
})(api);