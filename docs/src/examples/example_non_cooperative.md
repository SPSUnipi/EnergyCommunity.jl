```@meta
EditURL = "<unknown>/docs/src/examples/example_non_cooperative.jl"
```

# Basic example of EnergyCommunity.jl - Non Cooperative model
This example is taken from the article _Optimal sizing of energy communities with fair
revenue sharing and exit clauses: Value, role and business model of aggregators and users_
by Davide Fioriti et al, [url](https://doi.org/10.1016/j.apenergy.2021.117328) but
for a subset of users

The energy community considered in this example consists of 3 users, where:
* all users can install PV system
* only the first user cannot install batteries, whereas the others can
* the third user can install also wind turbines

Import the needed packages

```@example example_non_cooperative
using EnergyCommunity, JuMP
using HiGHS, Plots
```

Input file to load the structure of the energy community based on a yaml file.

```@example example_non_cooperative
input_file = joinpath(@__DIR__, "../data/energy_community_model.yml")  # Input file
```

Output path of the summary and of the plots

```@example example_non_cooperative
output_file_isolated = joinpath(@__DIR__, "../results/output_file_NC.xlsx")
output_plot_isolated = joinpath(@__DIR__, "../results/Img/plot_user_{:s}_NC.png")
```

Define the Non Cooperative model

```@example example_non_cooperative
NC_Model = ModelEC(input_file, EnergyCommunity.GroupNC(), HiGHS.Optimizer)
```

Build the mathematical model

```@example example_non_cooperative
build_model!(NC_Model)
```

Optimize the model

```@example example_non_cooperative
optimize!(NC_Model)
```

Create plots of the results

```@example example_non_cooperative
plot(NC_Model, output_plot_isolated)
```

Print summaries of the results

```@example example_non_cooperative
print_summary(NC_Model)
```

Save summaries

```@example example_non_cooperative
save_summary(NC_Model, output_file_isolated)
```

Plot the sankey plot of resources

```@example example_non_cooperative
plot_sankey(NC_Model)
```

!!! info
    [View this file on Github](<unknown>/docs/src/examples/example_non_cooperative.jl).

---

*This page was generated using [Literate.jl](https://github.com/fredrikekre/Literate.jl).*

