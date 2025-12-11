# `general` Section

## Scope and overview

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

The example showcase the use of the tool for the simulation of 3 users (`user1`, `user2`, `user3`) over a project lifetime of 20 years, with an initial step of 1 and a final step of 1152. The discount rate is set to 3%. The profiles for time resolution, energy weight, reward price, and peak categories are defined under the `profile` section. Additionally, optional datasets such as `input_resource.csv`, `market_data.csv`, and `flexibility_resource.csv` are specified for inclusion in the simulation.

> **Note:** The `optional_datasets` section contains a list of additional CSV files that can be included in the simulation for enhanced data input. The string entries in all `profile` fields are interpreted as column names from the CSV files listed in the `optional_datasets` field.

## Parameters in `general` Section

```@eval
using CSV, DataFrames, Latexify
df = CSV.read("../../src/configtables/general.csv", DataFrame)
mdtable(coalesce.(df, ""), latex=false, adjustment=:l)
```
