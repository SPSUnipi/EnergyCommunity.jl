![CI](https://github.com/SPSUnipi/EnergyCommunity.jl/actions/workflows/CI.yml/badge.svg)
[![Docs dev](https://img.shields.io/badge/docs-latest-blue.svg)](https://spsunipi.github.io/EnergyCommunity.jl/dev/)
[![Docs stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://spsunipi.github.io/EnergyCommunity.jl/stable/)

# EnergyCommunity.jl
Optimization of Energy Communities becomes easy with EnergyCommunity.jl!

A simple optimization of the model can be performed with


```julia
using EnergyCommunity, JuMP
using HiGHS, Plots

# define input configuration (available in the package)
input_file = "./data/energy_community_model.yml"

# create the Energy Community model in Cooperation mode GroupCO()
ECModel = ModelEC(input_file, EnergyCommunity.GroupCO(), HiGHS.Optimizer)

# build the model
build_model!(ECModel)

# set parameters
time_lim = 60 * 10 # max time in second
primal_gap = 1e-5 # primal gap (1e-4 = 1%)
n_threads = 16 # number of threads to be used
set_parameters_ECmodel!(ECModel,primal_gap,time_lim,n_threads)

# optimize the model
optimize!(ECModel)

# create some plots
plot(ECModel, output_plot_combined)
```
