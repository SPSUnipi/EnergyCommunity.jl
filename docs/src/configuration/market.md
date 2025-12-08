# `market` Section

## Scope and overview of `market` Section

The `market` block defines tariff rules for different user tariff types.

Example:

```yaml
market:
  ...
  non_commercial:
    profile:
      buy_price: buy_price
      sell_price: sell_price
      consumption_price: consumption_price
      peak_categories: peak_categories
      peak_tariff:
        function: parse_peak_quantity_by_time_vectors
        inputs: [peak_categories, peak_tariff]
      peak_weight:
        function: parse_peak_quantity_by_time_vectors
        inputs: [peak_categories, peak_weight]
  ...
```

## Parameters in `general` Section

```@eval
using CSV, DataFrames, Latexify
df = CSV.read("configtables/general.csv", DataFrame)
mdtable(df, latex=false)
```
