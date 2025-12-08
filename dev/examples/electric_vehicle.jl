# # Electric Vehicle
# This example demonstrates how to model heating and cooling flexibility in a building using EnergyCommunity.jl using the example provided by the tool named "energy_community_model_flexibility".
# The example includes 3 users:
# - User 1: User with a PV system, an electric load and an adjustable load representing the user's recharging station with an electric vehicle with 53kWh battery
# - User 2: User with a PV, battery system and an electric load
# - User 3: User with a PV, wind, battery system
# This example showcase how to load and optimize an energy community model with the flexibility offered by a single electric vehicle.
#
# In particular, the electric vehicle is modeled as an adjustable load with the following quantities retrieved from the file "data/flexibility_resources.csv":
# - energy_exchange: vector of energy exchange towards the recharging station: when positive with value X, it denotes a new EV to be connected with state of charge X; when negative with value -Y, it denotes an EV to be disconnected with state of charge Y
# - max_supply: maximum discharging power of the recharging station, depending on the available EVs; if no power-to-grid is allowed, this value must be 0
# - max_withdrawal: maximum charging power of the recharging station, depending on the available EVs
# - min_energy: minimum state of charge of the recharging station, accounting for all connected EVs
# - max_energy: maximum state of charge of the recharging station, accounting for all connected EVs

# ## Initialization

# Import the needed packages
using EnergyCommunity, JuMP
using HiGHS, Plots

# Create a base Energy Community example in the data folder; use the default configuration.
folder = joinpath(@__DIR__, "data")
create_example_data(folder, config_name="default")

# Input file to load the structure of the energy community based on a yaml file.
input_file = joinpath(@__DIR__, "data/energy_community_model_flexibility.yml");

# Output path of the plots
output_plot_isolated = joinpath(@__DIR__, "./results/Img/plot_user_{:s}_CO.png");

# define optimizer and options
optimizer = optimizer_with_attributes(HiGHS.Optimizer, "ipm_optimality_tolerance"=>1e-6)

# ### Create, build and optimize the model

# Define the Cooperative model
EV_Model = ModelEC(input_file, EnergyCommunity.GroupCO(), optimizer)

# Build the mathematical model
build_model!(EV_Model)

# Optimize the model
optimize!(EV_Model)

# ### Results

# get objective value
objective_value(EV_Model)

# ## Plots of dispatch

# Create plots of the dispatch of resources by user and save them to disk
plot(EV_Model, output_plot_isolated)
