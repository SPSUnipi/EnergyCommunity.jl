# Customizing time-series through the `profile` field

Many components in *EnergyCommunity.jl* (loads, renewable generators, heat pumps, thermal storage, market tariffs, etc.) require **time-series inputs**.  
These inputs are specified in a `profile` sub-field within each component or market type.

The `profile` mechanism is intentionally **flexible and customizable**, allowing users to provide data in several formats depending on convenience and dataset availability.

EnergyCommunity.jl supports **four modes** for specifying profile values.

## 1. Strings — Reference a Column Name

If the value is a **string**, it is interpreted as the **name of a column** in an external time-series CSV file (for example `market_data.csv` or `input_resource.csv`).

### Example

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

## 2. Float Numbers — Constant Values

If the value is a **number**, it is interpreted as a **constant time series**, meaning the same value applies to every timestep.

### Example

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

## 3. Lists — Inline Time Series

If a **YAML list** is provided, it is interpreted as a **direct time-series vector**.

### Example

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

## 4. Dictionaries — Custom Julia Functions

A **dictionary** allows you to specify a custom Julia function that constructs the time series.

This is the most flexible option and is used when the time-series data
cannot be taken directly from a column, or when additional processing is needed.

### General Structure

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

### Application to market

This method is widely used in the market section to define complex tariff structures.
For example, the peak tariff `peak_tariff` of each market tariff is associated with each peak category. However, the input csv files are generally indexed by time steps, and so are `peak_tariff` and `peak_categories` columns in the input csv files. To overcome this, the dictionary-based functionality is adopted to apply the custom function `parse_peak_quantity_by_time_vectors` and remap the time series accordingly.

```yaml
peak_tariff:
    function: parse_peak_quantity_by_time_vectors
    inputs: 
    - peak_categories
    - peak_tariff
```
