# Introduction

## What is EnergyCommunity.jl?

EnergyCommunity is a package for the optimal design and dispatch of Energy Communities at different level of aggregation. Provided easy to read configuration files, EnergyCommunity.jl creates a mathematical optimization model using [JuMP.jl](https://jump.dev/JuMP.jl/latest/) and solves it using any optimization solver compatible with JuMP.jl. The JuMP mathematical model is also editable and customized.

EnergyCommunity.jl automatically builds a Mixed-Integer Linear Programming model that represents the optimal dispatch and design of an Energy Community. To see a simple example of the model, see the example section

## Resources for getting started

Please, check out the examples in the example section and the files available in the [example folder](https://github.com/SPSUnipi/EnergyCommunity.jl/tree/main/examples) of the github repository.

To learn more about the Julia framework, please check out [this simple introduction](https://jump.dev/JuMP.jl/latest/tutorials/getting_started/getting_started_with_julia/#Getting-started-with-Julia) or more material in [julialang](https://docs.julialang.org/en/v1/).

For more material on the backbone optimization framework, please refer to documentation of [JuMP.jl](https://jump.dev/JuMP.jl/latest/tutorials/getting_started/introduction/). JuMP is a domain-specific modeling language that allows mathematical optimization embedded in Julia.
