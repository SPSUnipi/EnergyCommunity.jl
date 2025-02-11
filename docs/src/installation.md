# Installation guide

This guide explains how to install EnergyCommunity.jl and its dependencies.

## Install Julia

EnergyCommunity.jl is a Julia package. To use it, you need to install Julia. You can download Julia from the [official website](https://julialang.org/downloads/).

## Install EnergyCommunity.jl

To install EnergyCommunity.jl, you can use the Julia package manager. Open Julia and run the following commands:

```julia
julia> import Pkg

julia> Pkg.add("EnergyCommunity")
```

## Install a solver

EnergyCommunity.jl requires an optimization solver to solve the optimization problem. You can use any optimization solver compatible with JuMP.jl. For example, you can use the open-source solver HiGHS. To install HiGHS, run the following command:

```julia
julia> Pkg.add("HiGHS")
```

It is recommended to use a solver capable of Mixed-Integer Linear Programming. You can find a list of solvers compatible with JuMP.jl [here](https://jump.dev/JuMP.jl/latest/installation).

## Install input/output packages

EnergyCommunity.jl also supports input/output featurs, such as saving/loading a model to disk or plotting results. To install the plotting package Plots.jl, run the following command:

```julia
julia> Pkg.add("Plots")
```

To install FileIO.jl that is used to export the model to disk, run the following command:

```julia
julia> Pkg.add("FileIO")
```