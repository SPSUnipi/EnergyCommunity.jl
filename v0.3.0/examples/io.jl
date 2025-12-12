# # Input/Ouput to/from disk
# This example showcase the input/output capabilities of the EnergyCommunity.jl package on writing and reading the model and outputs to/from disk.
# EnergyCommunity.jl supports:
# - Input from yaml files defining the structure of the energy community
# - Output of summaries and plots to files
# - Saving and loading the model to/from jld2 files, so that any intermediate results can be stored and retrieved later on without the need to re-optimize the model.
# In the example below, we consider a Cooperative (CO) energy community optimization problem and showcase the opportunities related to input/output operations; for plotting, see the other example.

# ## Initialization of the model

# Import the needed packages
using EnergyCommunity, JuMP
using HiGHS, FileIO

# Create a base Energy Community example in the data folder; use the default configuration.
folder = joinpath(@__DIR__, "data")
create_example_data(folder, config_name="default")

# Input file to load the structure of the energy community based on a yaml file.
input_file = joinpath(@__DIR__, "data/energy_community_model.yml");

# Output path of the summary
output_file_isolated = joinpath(@__DIR__, "./results/output_file_CO.xlsx");

# define optimizer and options
optimizer = optimizer_with_attributes(HiGHS.Optimizer, "ipm_optimality_tolerance"=>1e-6)

# Define the Non Cooperative model
CO_Model = ModelEC(input_file, EnergyCommunity.GroupCO(), optimizer)

# Build the mathematical model
build_model!(CO_Model)

# Optimize the model
optimize!(CO_Model)

# get objective value
objective_value(CO_Model)

# ## Print and save summaries

# Print summaries of the results
print_summary(CO_Model)

# Save summaries
save_summary(CO_Model, output_file_isolated)

# DataFrame of the business plan
business_plan(CO_Model)

# ## Save the model to disk

# save the model to a jld2 file, to store the whole object
save("co_model.jld2", CO_Model)

# ## Load the model from disk

# read the loaded model from the jld2 file
CO_Model_loaded = load!("co_model.jld2", ModelEC())

# get the objective value of the loaded model
objective_value(CO_Model_loaded)

# compare the objective values of the two models
objective_value(CO_Model) == objective_value(CO_Model_loaded)
