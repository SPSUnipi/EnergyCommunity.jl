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

