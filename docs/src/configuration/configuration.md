# Configuration

## Introduction

EnergyCommunity.jl uses a structured YAMLbased configuration system to define the properties of:

- the **simulation environment** (time horizon, discount rate, user list),
- the **market environment** (tariffs, peak categories, price signals),
- the **users and their assets** (loads, generators, storage, heat pumps, converters, etc.).

## Obtaining Example Configurations

To locally obtain example configurations, it is possible to obtain `default` sample configuration files by running the following command:

```julia
julia> using EnergyCommunity

julia> create_example_data(".", config_name="default")
```

This code creates a folder named `data` in the current directory with the following files:

- `energy_community_model.yaml`: a sample configuration file for a Energy Community system.
- `market_data.csv`: a csv file with quantities related to the market prices, such as time-varying electricity prices and more.
- `input_resource.csv`: a csv file with data related to the demand by each user and specific renewable production by time step of the simulation.
- `energy_community_model_thermal.yaml`: another sample configuration file for a Energy Community that contains also dispatchable fuel-fired generators.

> To easily view the files, please explore the [default folder online](https://github.com/SPSUnipi/EnergyCommunity.jl/tree/main/src/data/default)


## Overview of the Configuration Structure

A typical EnergyCommunity.jl configuration file contains three top-level sections:

```yaml
general:
  ...

market:
  ...

users:
  ...
```

Each section has a specific purpose:

| Section | Purpose |
|--------|---------|
| **general** | Defines project-wide settings such as number of users, time horizon, discount rate, global profiles, and optional datasets |
| **market** | Defines tariff structures, buy/sell/consumption prices, peak-tariff processing functions, and user-specific market types |
| **users** | Defines the list of users and, for each user, the set of installed or installable assets with their parameters and profiles |

In the following sections, we describe them in detail.


## Customizing time-series through the `profile` field

Many components in *EnergyCommunity.jl* (loads, renewable generators, heat pumps, thermal storage, market tariffs, etc.) require **time-series inputs**.  
These inputs are specified in a `profile` sub-field within each component or market type.

The `profile` mechanism is intentionally **flexible and customizable**, allowing users to provide data in several formats depending on convenience and dataset availability.

EnergyCommunity.jl supports **four modes** for specifying profile values.

### 1. Strings — Reference a Column Name

If the value is a **string**, it is interpreted as the **name of a column** in an external time-series CSV file (for example `market_data.csv` or `input_resource.csv`).

#### Example

```yaml
profile:
  buy_price: buy_price
  sell_price: sell_price
  ren_pu: pv
```

Meaning:
- The value of `buy_price` is read from the "buy_price" column.
- The value of `ren_pu` is read from the "pv" column.
- This is the most common mode when time-series data are already available.

### 2. Float Numbers — Constant Values

If the value is a **number**, it is interpreted as a **constant time series**, meaning the same value applies to every timestep.

#### Example

```yaml
profile:
  COP: 3.0
```

Meaning:
- COP is equal to 3.0 for all timesteps in the simulation horizon.

This option is convenient when:
- a constant performance value is adequate,
- building simplified test cases,
- or when detailed time-series data are unavailable.

### 3. Lists — Inline Time Series

If a **YAML list** is provided, it is interpreted as a **direct time-series vector**.

#### Example

```yaml
profile:
  load: [2.1, 2.3, 2.0, 2.5, 2.6]
```
Meaning:
- At timestep 1, load = 2.1
- At timestep 2, load = 2.3
- ... and so on.

This mode is useful for:
- small demonstration cases,
- manually defined time-series,
- synthetic or placeholder data.

### 4. Dictionaries — Custom Julia Functions

A **dictionary** allows you to specify a custom Julia function that constructs the time series.

This is the most flexible option and is used when the time-series data
cannot be taken directly from a column, or when additional processing is needed.

#### General Structure

```yaml
profile:
  some_quantity:
    function: <function_name>
    inputs:
      - input1
      - input2
```

EnergyCommunity.jl will:
1. Look up the function `<function_name>`.
2. Collect the inputs listed under inputs.
3. Call the function with those inputs.
4. Store the returned vector as the time series for some_quantity.

#### Application to market

This method is widely used in the market section to define complex tariff structures.
For example, the peak tariff `peak_tariff` of each market tariff is associated with each peak category. However, the input csv files are generally indexed by time steps, and so are `peak_tariff` and `peak_categories` columns in the input csv files. To overcome this, the dictionary-based functionality is adopted to apply the custom function `parse_peak_quantity_by_time_vectors` and remap the time series accordingly.

```yaml
peak_tariff:
    function: parse_peak_quantity_by_time_vectors
    inputs: 
    - peak_categories
    - peak_tariff
```
