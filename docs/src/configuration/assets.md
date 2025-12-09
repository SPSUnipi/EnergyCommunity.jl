# Asset types

## Scope and overview

Assets represent the physical or logical components that each user may install or operate in the Energy Community.
Each asset is defined by:
- its type (renewable, battery, heat pump, storage, etc.)
- techno-economic parameters (CAPEX, O&M, lifetime)
- operational constraints
- a profile section defining time-series inputs

### Example

```yaml
asset_name:
  PV:
    type: <asset_type>
    ...
    profile:
      ...
```

Below are examples of the most common asset types supported by EnergyCommunity.jl.

## Fixed Electrical Loads

Fixed electrical loads represent non-flexible electricity demand that must be met exactly at each timestep.  
They follow a predefined time-series profile and cannot shift or store energy.

### Example

```yaml
load:
  type: load
  profile:
    load: load_user1     # column name representing the electrical demand profile
```

### Parameters

The full list of parameters for fixed electrical load assets is shown below:

```@eval
using CSV, DataFrames, Latexify
df = CSV.read("../../src/configtables/load_fixed.csv", DataFrame)
mdtable(df, latex=false)
```


## Renewable Assets (PV, Wind, run-of-river, ...)

Renewable generators convert environmental resources into electricity.
Their production depends on a per-unit availability profile (`ren_pu`),
typically taken from a time-series dataset such as PV or wind capacity factors.

```yaml
PV:
  type: renewable
  CAPEX_lin: 1700       # €/kW
  OEM_lin: 30           # €/kW/y
  lifetime_y: 25        # years
  max_capacity: 300     # kW
  profile:
    ren_pu: pv          # name of column with PV availability
```

Renewable assets define:
- capital and operating costs,
- lifetime,
- capacity limit,
- a profile: pointing to time-series production.

### Parameters

The full list of parameters for renewable assets is shown below:

```@eval
using CSV, DataFrames, Latexify
df = CSV.read("../../src/configtables/renewable.csv", DataFrame)
mdtable(df, latex=false)
```


## Battery Energy Storage System (BESS)

Batteries store electrical energy and are characterized by:
- round-trip efficiency,
- minimum/maximum state of charge,
- C-rate limits (charge/discharge),
- link to a converter that manages AC/DC conversion.

### Example: Battery

```yaml
batt:
  type: battery
  CAPEX_lin: 400        # €/kWh
  OEM_lin: 5            # €/kWh/y
  lifetime_y: 15        # years
  eta: 0.92             # round-trip efficiency
  max_SOC: 1.0          # upper SOC limit
  min_SOC: 0.2          # lower SOC limit
  max_capacity: 60      # kW power limit
  max_C_dch: 1.0        # max discharge C-rate
  max_C_ch: 1.0         # max charge C-rate
  corr_asset: conv      # associated converter asset
```

### Parameters

The full list of parameters for battery assets is shown below:

```@eval
using CSV, DataFrames, Latexify
df = CSV.read("../../src/configtables/battery.csv", DataFrame)
mdtable(df, latex=false)
```

## Converter

Converters interface DC storage (batteries) with the AC electrical system.
They enforce power limits, efficiency, and allowable charge/discharge directions.

### Example: Converter

```yaml
conv:
  type: converter
  CAPEX_lin: 200        # €/kW
  OEM_lin: 2            # €/kW/y
  lifetime_y: 10        # years
  eta: 1.0              # electrical efficiency
  max_dch: 1.0          # max discharge fraction
  min_ch: 0.1           # min charge fraction
  max_capacity: 60      # kW power rating
  corr_asset: batt      # linked battery
```

### Parameters

The full list of parameters for converter assets is shown below:

```@eval
using CSV, DataFrames, Latexify
df = CSV.read("../../src/configtables/converter.csv", DataFrame)
mdtable(df, latex=false)
```

## Heat Pump

Heat pumps couple the electrical and thermal sectors.  
They can operate in:
- **heating mode** (COP > 1),
- **cooling mode** (EER > 1),

and their performance depends on external and internal temperature profiles.

### Example: Heat Pump

```yaml
hp:
  type: heat_pump
  CAPEX_lin: 1300       # €/kW (electrical)
  OEM_lin: 15           # €/kW/y
  lifetime_y: 20        # years

  COP_c1: 2.3           # COP at T_c1
  COP_c2: 2.7           # COP at T_c2
  EER_h1: 3.0           # EER at T_h1
  EER_h2: 2.6           # EER at T_h2

  T_c1: 2.0             # reference external temp for COP_c1
  T_c2: 7.0             # reference external temp for COP_c2
  T_h: 55.0             # delivery/condensation temp (heating)
  T_h1: 30.0            # reference external temp for EER_h1
  T_h2: 35.0            # reference external temp for EER_h2
  T_c: 7.0              # evaporator temp (cooling mode)

  delta_T_approach: 5.0 # °C, temp approach margin
  max_capacity: 50      # kW electrical input power

  profile:
    T_int: T_int        # internal temperature time series
    T_ext: T_ext        # external temperature time series
```

### Parameters

The full list of parameters for heat pump assets is shown below:

```@eval
using CSV, DataFrames, Latexify
df = CSV.read("../../src/configtables/heat_pump.csv", DataFrame)
mdtable(df, latex=false)
```

## Thermal Energy Storage (TES)

Thermal storage allows shifting heat production over time.  
It is modeled with:
- energy capacity (based on water volume and heat capacity),
- thermal losses depending on temperature gradients,
- heating and cooling operating temperatures.

### Example: TES Tank

```yaml
tes:
  type: storage
  CAPEX_lin: 1          # €/l
  OEM_lin: 0.005        # €/l/y
  lifetime_y: 35        # years

  eta: 0.9              # storage efficiency
  max_capacity: 50000   # liters
  cp: 0.00116           # kWh/l°C, specific heat capacity
  b_tr_x: 0.5           # thermal exposure factor
  k: 0.0003             # kWh/h°C, heat loss coefficient

  T_ref_heat: 50.0      # °C, reference temperature for heating mode
  T_ref_cool: 10.0      # °C, reference temperature for cooling mode

  profile:
    T_int: T_int        # internal air temperature
    T_ext: T_ext        # external air temperature
```

### Parameters

The full list of parameters for thermal storage assets is shown below:

```@eval
using CSV, DataFrames, Latexify
df = CSV.read("../../src/configtables/thermal_energy_storage.csv", DataFrame)
mdtable(df, latex=false)
```

## Boiler (Fuel-Fired Thermal Generator)

Boilers convert fuel (e.g., methane) into heat.  
Their operation is modeled through:
- thermal efficiency,
- fuel consumption characteristics,
- maximum thermal output,
- optional commitment-related operating costs.

### Example: Boiler

```yaml
boil:
  type: boiler
  CAPEX_lin: 250        # €/kW
  OEM_lin: 10           # €/kW/y
  OEM_com: 0.02         # €/kWh/y, variable O&M from commitment
  lifetime_y: 20        # years

  eta: 0.94             # thermal efficiency
  PCI: 9.97             # kWh/m³, lower heating value of fuel
  fuel_price: 0.2       # €/m³

  max_capacity: 60      # kWth maximum thermal output
```

### Parameters

The full list of parameters for boiler assets is shown below:

```@eval
using CSV, DataFrames, Latexify
df = CSV.read("../../src/configtables/boiler.csv", DataFrame)
mdtable(df, latex=false)
```

## Thermal Loads

Thermal loads represent time-dependent **heating or cooling demand**.
They can be served by:
- heat pumps,
- boilers,
- thermal energy storage (TES).

The operating mode is determined by a profile value:
- **+1 → heating mode**
- **−1 → cooling mode**

### Example: Thermal Load

```yaml
t_load:
  type: t_load
  corr_asset: [hp, boil, tes]   # assets that can satisfy this demand
  profile:
    t_load: t_load_u1_heat_cool # time-series for thermal demand
    mode: mode                  # heating (+1) or cooling (-1)
```

### Parameters

The full list of parameters for thermal load assets is shown below:

```@eval
using CSV, DataFrames, Latexify
df = CSV.read("../../src/configtables/load_thermal.csv", DataFrame)
mdtable(df, latex=false)
```

## Adjustable Electrical Loads

Adjustable loads behave like a small **virtual battery**:
- they can withdraw power from the grid,
- they can feed power back (optional),
- they track an internal "energy" state,
- they must respect min/max energy and power bounds.

They allow modeling:
- EV charging,
- flexible appliances,
- shiftable industrial loads.

### Example: Adjustable Load

```yaml
load_adj:
  type: load_adj

  eta_P: 0.95               # efficiency when supplying (discharging)
  eta_N: 0.95               # efficiency when absorbing (charging)

  profile:
    energy_exchange: load_user1_adj   # exogenous energy variations
    max_supply: max_supply_user1      # max power supplied to grid
    max_withdrawal: max_withdrawal_user1
    min_energy: min_energy_user1      # minimum allowed "energy" state
    max_energy: max_energy_user1      # maximum allowed "energy" state
```

### Parameters

The full list of parameters for adjustable load assets is shown below:

```@eval
using CSV, DataFrames, Latexify
df = CSV.read("../../src/configtables/load_adjustable.csv", DataFrame)
mdtable(df, latex=false)
```

