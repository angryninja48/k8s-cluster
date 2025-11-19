# EMHASS Setup Validation

## Configuration File Path Resolution

### EMHASS Expected Paths
According to the official EMHASS documentation, the application expects configuration at:
- **JSON format**: `/app/config.json`
- **YAML format**: `/app/config_emhass.yaml`

### Current Setup (Fixed)

#### Secret Configuration
File: `kubernetes/apps/home/emhass/app/externalsecret.yaml`
- Secret key: `config.json`
- Content format: JSON
- Contains: Home Assistant URL, API token, Solcast credentials, location data, deferrable load config

#### Volume Mount
File: `kubernetes/apps/home/emhass/app/helmrelease.yaml`
```yaml
config-secret:
  type: secret
  name: emhass-secret
  globalMounts:
    - path: /app/config.json      # ✅ Matches JSON content format
      subPath: config.json        # ✅ Correct secret key
```

**Status**: ✅ **VALID** - JSON content is mounted to `/app/config.json`

## Configuration Content Validation

### Key Parameters Configured

1. **Home Assistant Connection**
   - `hass_url`: Connected to external HA URL
   - `long_lived_token`: API authentication
   - `time_zone`: Australia/Sydney

2. **Location Data**
   - Latitude, Longitude, Altitude from HA configuration

3. **Solar Forecasting (Solcast)**
   - `solcast_api_key`: ✅ Configured
   - `solcast_rooftop_id`: ✅ Configured
   - `solar_forecast_kwp`: 9.4 kW system

4. **Publishing Configuration**
   - `continual_publish`: true - Auto-publish sensors to HA
   - `method_ts_round`: "first" - Timestamp rounding method

5. **Deferrable Loads Configuration**
   ```json
   "def_load_config": [
     {},  // Load 0: EV charging (basic)
     {    // Load 1: Hot water (thermal)
       "thermal_config": {
         "heating_rate": 2.4,
         "cooling_constant": 0.1,
         "overshoot_temperature": 65.0,
         "start_temperature": 20,
         "desired_temperatures": []
       }
     }
   ]
   ```

## Integration Flow

### 1. Data Sources
- **Solar Forecast**: Solcast API → EMHASS
- **Electricity Pricing**: Amber (via HA sensors) → EMHASS API calls
- **Battery State**: Home Assistant sensors

### 2. EMHASS Optimization
```
Inputs (via REST API):
├── load_cost_forecast (from sensor.teal_close_general_forecast)
├── prod_price_forecast (from sensor.teal_close_feed_in_forecast)
├── soc_init (from sensor.sigen_plant_battery_state_of_charge)
└── operating_hours_of_each_deferrable_load

Optimization Engine:
├── MPC (Model Predictive Control)
├── 48-hour prediction horizon
└── Cost function optimization

Outputs (published to HA):
├── sensor.p_batt (battery power schedule)
├── sensor.p_deferrable0 (EV charging schedule)
└── sensor.p_deferrable1 (hot water heating schedule)
```

### 3. Control Execution
Home Assistant automations react to EMHASS sensor changes:
- Battery: Control `select.sigen_plant_remote_ems_control_mode`
- EV: Control `select.evcc_garage_mode`
- Hot Water: Control `switch.hotwater`

## Identified Entities

### Energy System
- **Solar**: `sensor.solar_power_output`
- **Battery**:
  - SOC: `sensor.sigen_plant_battery_state_of_charge`
  - Power: `sensor.sigen_plant_battery_power`
  - Control: `select.sigen_plant_remote_ems_control_mode`
- **Grid**:
  - Import: `sensor.grid_import_power`
  - Consumption: `sensor.household_power_consumption`

### Pricing (Amber)
- **Current**:
  - General: `sensor.teal_close_general_price`
  - Feed-in: `sensor.teal_close_feed_in_price`
- **Forecast**:
  - General: `sensor.teal_close_general_forecast`
  - Feed-in: `sensor.teal_close_feed_in_forecast`

### Controllable Loads
- **EV Charging**: `select.evcc_garage_mode` (via EVCC)
- **Hot Water**: `switch.hotwater` (relay controlled)
- **Hot Water Temp**: `sensor.hotwater_top_temperature`

## Deployment Steps

1. **Apply Configuration**
   ```bash
   flux reconcile kustomization emhass -n flux-system
   ```

2. **Verify Pod is Running**
   ```bash
   kubectl get pods -n home -l app.kubernetes.io/name=emhass
   kubectl logs -n home -l app.kubernetes.io/name=emhass
   ```

3. **Check Configuration Loaded**
   Look for in logs:
   - ✅ "Config loaded successfully"
   - ❌ "config.json does not exist" (OLD ERROR - now fixed)

4. **Add Home Assistant Configuration**
   Copy contents from `docs/emhass-integration.yaml` to HA configuration.yaml

5. **Restart Home Assistant**
   Reload configuration or restart HA

6. **Verify Sensors Created**
   Check for these entities in HA:
   - `sensor.p_batt`
   - `sensor.p_batt_forecast`
   - `sensor.p_deferrable0`
   - `sensor.p_deferrable1`
   - `sensor.p_grid`
   - `sensor.p_load`

7. **Test Manual Optimization**
   In HA Developer Tools → Services:
   ```yaml
   service: shell_command.emhass_optimize
   ```

## Expected Behavior

### Daily Optimization (5:30 AM)
1. EMHASS fetches Amber forecasts for next 48 hours
2. Gets Solcast solar forecast
3. Reads current battery SOC
4. Calculates optimal:
   - Battery charge/discharge schedule
   - EV charging windows
   - Hot water heating times
5. Publishes schedules as sensors

### Hourly Re-optimization (6 AM - 10 PM)
- Updates based on actual conditions vs forecast
- Adjusts remaining schedule

### Automation Response
- Automations continuously monitor EMHASS sensor values
- Apply control decisions every 30 minutes
- Immediate response to significant changes

## Troubleshooting

### Config Not Found
**Symptom**: "config.json does not exist" in logs
**Solution**: ✅ Fixed - config now mounted at correct path

### No Sensors in HA
**Possible causes**:
1. EMHASS not publishing - check `continual_publish: true`
2. HA not connected - verify `hass_url` and `long_lived_token`
3. Optimization not run yet - manually trigger via shell command

### Optimization Fails
**Check**:
1. Amber forecast sensors exist and have data
2. Solcast integration working
3. Battery SOC sensor accessible
4. Review EMHASS logs for specific errors

## Validation Checklist

- [x] Configuration file format matches mount path (JSON → /app/config.json)
- [x] All required EMHASS parameters present
- [x] Solcast API credentials configured
- [x] Home Assistant connection details present
- [x] Deferrable loads defined (EV + hot water)
- [x] Thermal model configured for hot water
- [x] Continual publishing enabled
- [x] Home Assistant automations created
- [x] Entity IDs mapped correctly
- [ ] Pod deployed and running (awaiting user confirmation)
- [ ] Sensors appearing in Home Assistant (after deployment)
- [ ] Test optimization successful (after deployment)

## Next Actions

1. Deploy the fixed configuration
2. Monitor logs for successful config loading
3. Verify EMHASS sensors appear in HA
4. Run test optimization
5. Monitor first automated optimization cycle
6. Fine-tune parameters based on observed behavior
