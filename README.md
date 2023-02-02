![CI](https://github.com/davide-f/EnergyCommunity.jl/actions/workflows/CI.yml/badge.svg)

# EnergyCommunity.jl
Optimization of Energy Communities becomes easy with EnergyCommunity.jl!

A simple optimization of the model can be performed with APPLE


```julia
using EnergyCommunity, JuMP
using HiGHS, Plots

# define input configuration (available in the package)
input_file = "./data/energy_community_model.yml"

# create the Energy Community model in Cooperation mode GroupCO()
ECModel = ModelEC(input_file, EnergyCommunity.GroupCO(), HiGHS.Optimizer)

# build the model
build_model!(ECModel)

# optimize the model
optimize!(ECModel)

# create some plots
plot(ECModel, output_plot_combined)
```
