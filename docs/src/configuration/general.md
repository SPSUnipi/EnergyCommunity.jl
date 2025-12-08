# `general` Section

## Scope and overview of `general` Section

The `general` block contains meta-information governing the simulation setup, project structure, and global profiles shared across users.

Example:

```yaml
general:
  init_step: 1
  final_step: 1152
  d_rate: 0.03
  project_lifetime: 20
  user_set: [user1, user2, user3]
  profile:
    time_res: time_res
    energy_weight: energy_weight
    reward_price: reward_price
    peak_categories: peak_categories
  optional_datasets:
    - input_resource.csv
    - market_data.csv
    - flexibility_resource.csv
```

## Parameters in `general` Section

```@eval
using CSV, DataFrames, Latexify
df = CSV.read("configtables/general.csv", DataFrame)
mdtable(df, latex=false)
```
