![CI](https://github.com/SPSUnipi/EnergyCommunity.jl/actions/workflows/CI.yml/badge.svg)
[![Docs dev](https://img.shields.io/badge/docs-latest-blue.svg)](https://spsunipi.github.io/EnergyCommunity.jl/dev/)
[![Docs stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://spsunipi.github.io/EnergyCommunity.jl/stable/)

# EnergyCommunity.jl
Optimization of Energy Communities becomes easy with EnergyCommunity.jl!

The package allows to describe any Energy Community using a readable configuration file using yaml format and a simple execution.
EnergyCommunity.jl then creates a mathematical optimization model using [JuMP.jl](https://jump.dev/JuMP.jl/stable/) and solves it using any optimization solver compatible with JuMP.jl. The JuMP mathematical model is also editable and customized.

See the following example to understand how to use the package.

## Example

The following example describes how to install and execute a simple Energy Community model.

### Installation

```julia
julia> import Pkg

julia> Pkg.add("EnergyCommunity")  # EnergyCommunity package

julia> Pkg.add("JuMP")  # The optimization package

julia> Pkg.add("HiGHS")  # Open-source solver to solve the optimization problem

julia> Pkg.add("Plots")  # Plotting package
```

### Execution

After the installation, you can run a simple example as follows:

```julia
using EnergyCommunity
using HiGHS, Plots, JuMP

# create a sample Energy Community model input files in folder "data"
create_example_data("data")

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
