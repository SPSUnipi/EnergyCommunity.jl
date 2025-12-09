# `market` Section

## Scope and overview

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

A tariff is defined by its buying price, selling price, consumption price, peak categories, peak tariff, and peak weight. The `profile` section within each tariff type specifies the relevant parameters. The `peak_tariff` and `peak_weight` fields utilize a function called `parse_peak_quantity_by_time_vectors`, which processes the input vectors based on the defined peak categories.

```@eval
using CSV, DataFrames, Latexify
println(pwd())
df = CSV.read("../../src/configtables/general.csv", DataFrame)
mdtable(df, latex=false)
```
