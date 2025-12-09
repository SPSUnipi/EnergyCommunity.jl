# # Heating and Cooling Flexibility
# This example demonstrates how to model heating and cooling flexibility in a building using EnergyCommunity.jl using the example provided by the tool named "energy_community_model_thermal".
# The example includes 3 users:
# - User 1: User with a PV system and an electric load
# - User 2: User with a PV, battery system and an electric load
# - User 3: User with a PV, wind, battery system, as well as a heat pump, boiler, thermal energy storage and thermal Load
# This example showcase how to load and optimize an energy community model with thermal flexibility.

# ## Initialization

# Import the needed packages
using EnergyCommunity, JuMP
using HiGHS, Plots

# Create a base Energy Community example in the data folder; use the default configuration.
folder = joinpath(@__DIR__, "data")
create_example_data(folder, config_name="default")

# Input file to load the structure of the energy community based on a yaml file.
input_file = joinpath(@__DIR__, "data/energy_community_model_thermal.yml");

# Output path of the plots
output_plot_isolated = joinpath(@__DIR__, "./results/Img/plot_user_{:s}_CO.png");

# define optimizer and options
optimizer = optimizer_with_attributes(HiGHS.Optimizer, "ipm_optimality_tolerance"=>1e-6)

# ### Create, build and optimize the model

# Define the Cooperative model
TH_Model = ModelEC(input_file, EnergyCommunity.GroupCO(), optimizer)

# Build the mathematical model
build_model!(TH_Model)

# Optimize the model
optimize!(TH_Model)

# ### Results

# get objective value
objective_value(TH_Model)

# ## Plots of dispatch

# Create plots of the dispatch of resources by user and save them to disk
plot(TH_Model, output_plot_isolated)
