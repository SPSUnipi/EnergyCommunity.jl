# # Plotting
# This example showcase the plotting capabilities native to the EnergyCommunity.jl package. The package allows to create various plots to visualize the results of the energy community optimization problems, such as time series plots of energy production and consumption, as well as sankey diagrams to illustrate the flow of energy within the community. Moreover, by leveraging on additional packages, it is possible to extend the functionalities and perform additional plots.

# ## Initialization of the model

# Import the needed packages
using EnergyCommunity, JuMP
using HiGHS, Plots

# Create a base Energy Community example in the data folder; use the default configuration.
folder = joinpath(@__DIR__, "data")
create_example_data(folder, config_name="default")

# Input file to load the structure of the energy community based on a yaml file.
input_file = joinpath(@__DIR__, "data/energy_community_model.yml");

# Output path of the plots
output_plot_isolated = joinpath(@__DIR__, "./results/Img/plot_user_{:s}_CO.png");

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

# ## Plots of dispatch

# Create plots of the dispatch of resources by user and save them to disk
plot(CO_Model, output_plot_isolated)

# ## Sankey plots

# Plot the sankey plot of resources
plot_sankey(CO_Model)

# ## Plot of business

# plot business plan
business_plan_plot(CO_Model)
