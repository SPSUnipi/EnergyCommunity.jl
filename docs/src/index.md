# Introduction

## What is EnergyCommunity.jl?

EnergyCommunity is a package for the optimal design and dispatch of Energy Communities at different level of aggregation. Provided easy to read configuration files, EnergyCommunity.jl creates a mathematical optimization model using [JuMP.jl](https://jump.dev/JuMP.jl/latest/) and solves it using any optimization solver compatible with JuMP.jl. The JuMP mathematical model is also editable and customized.

EnergyCommunity.jl automatically builds a Mixed-Integer Linear Programming model that represents the optimal dispatch and design of an Energy Community composed by an arbitrary number of users, as shown in the image.

![Scheme of the Energy Community](./images/schematic.png)

## Features

- Optimal dispatch and design of Energy Communities composed by an arbitrary number of users using Mixed-Integer Linear Programming;
- Multiple types of users: prosumers, consumers, and producers;
- Support for multiple configurations of Energy Communities:
  - Non-Cooperative: no Energy Community is in place as each user optimizes its own costs independently from the others and no shared reward applies;
  - Aggregated-Non-Cooperative (ANC): an Energy Community is in place but users do not cooperate, so each user optimizes its own costs independently from the others and the shared reward applies for the shared energy that naturally flows among users;
  - COoperative (CO): an Energy Community is in place and users cooperate to minimize the overall costs and share the benefits;
- Each user may own different technologies: batteries, electric vehicles, photovoltaic systems, combined heat and power units, thermal storage systems, heat pumps, boilers, and more;
- Estimate fair reward distribution across users with [TheoryOfGames.jl](https://github.com/SPSUnipi/theoryofgames.jl);
- Support to save and load the model to disk;

## Quick start

Optimizing energy communities with EnergyCommunity.jl is straightforward. After installing the package, you can create a configuration file (YAML or JSON format) describing the energy community and its users, and then run the optimization. Here is a simple example using a YAML configuration file:

```julia
using EnergyCommunity
using HiGHS, Plots, JuMP

# create a sample Energy Community model input files in folder "data"
create_example_data("data")

# define input configuration (available in the package)
input_file = "./data/energy_community_model.yml"

# define pattern of plot by user: the "{:s}" will be filled with the name of the user
output_plot_combined = "outputs/Img/plot_user_{:s}_EC.png"

# create the Energy Community model in Cooperation mode GroupCO()
ECModel = ModelEC(input_file, EnergyCommunity.GroupCO(), HiGHS.Optimizer)

# build the model
build_model!(ECModel)

# optimize the model
optimize!(ECModel)

# create some plots
plot(ECModel, output_plot_combined)
```

## Resources for getting started

Please, check out the examples in the example section and the files available in the [example folder](https://github.com/SPSUnipi/EnergyCommunity.jl/tree/main/examples) of the github repository.

To learn more about the Julia framework, please check out [this simple introduction](https://jump.dev/JuMP.jl/latest/tutorials/getting_started/getting_started_with_julia/#Getting-started-with-Julia) or more material in [julialang](https://docs.julialang.org/en/v1/).

For more material on the backbone optimization framework, please refer to documentation of [JuMP.jl](https://jump.dev/JuMP.jl/latest/tutorials/getting_started/introduction/). JuMP is a domain-specific modeling language that allows mathematical optimization embedded in Julia.

## Scientific references

> - D. Fioriti, G. Bigi, A. Frangioni, M. Passacantando and D. Poli, "Fair Least Core: Efficient, Stable and Unique Game-Theoretic Reward Allocation in Energy Communities by Row-Generation," in IEEE Transactions on Energy Markets, Policy and Regulation, vol. 3, no. 2, pp. 170-181, June 2025, [doi: 10.1109/TEMPR.2024.3495237](https://doi.org/10.1109/TEMPR.2024.3495237).
> - D. Fioriti, A. Frangioni, D. Poli, "Optimal sizing of energy communities with fair revenue sharing and exit clauses: Value, role and business model of aggregators and users," in Applied Energy, vol. 299, 2021, 117328,[doi: 10.1016/j.apenergy.2021.117328](https://doi.org/10.1016/j.apenergy.2021.117328)