# Configuration

To customize a `EnergyCommunity.jl` model, the main interface to represent a Energy Community system is by editing a configuration file using `yaml` format. For reference, the `default` sample configuration file is provided in the `examples` and easily installable by running the following command:

```julia
julia> using EnergyCommunity

julia> create_example_data(".", config_name="default")
```

This code creates a folder named `data` in the current directory with the following files:

- `energy_community_model.yaml`: a sample configuration file for a Energy Community system.
- `market_data.csv`: a csv file with quantities related to the market prices, such as time-varying electricity prices and more.
- `input_resource.csv`: a csv file with data related to the demand by each user and specific renewable production by time step of the simulation.
- `energy_community_model_thermal.yaml`: another sample configuration file for a Energy Community that contains also dispatchable fuel-fired generators.

To delve and explore the modelling of Energy Communities with `EnergyCommunity.jl`, we will use the `energy_community_model.yaml` file as a reference and better detailed in the following.
