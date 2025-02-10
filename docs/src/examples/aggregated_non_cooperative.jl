# # Aggregated Non-Cooperative Energy Community
# This example is taken from the article _Optimal sizing of energy communities with fair 
# revenue sharing and exit clauses: Value, role and business model of aggregators and users_
# by Davide Fioriti et al, [url](https://doi.org/10.1016/j.apenergy.2021.117328) but
# for a subset of users


# The energy community considered in this example consists of 3 users, where:
# * all users can install PV system
# * only the first user cannot install batteries, whereas the others can
# * the third user can install also wind turbines

# Import the needed packages
using EnergyCommunity, JuMP
using HiGHS, Plots

# Create a base Energy Community example in the data folder; use the default configuration.
folder = joinpath(@__DIR__, "data")
create_example_data(folder, config_name="default")

# Input file to load the structure of the energy community based on a yaml file.
input_file = joinpath(@__DIR__, "data/energy_community_model.yml");

# Output path of the summary and of the plots
output_file_isolated = joinpath(@__DIR__, "./results/output_file_ANC.xlsx");
output_plot_isolated = joinpath(@__DIR__, "./results/Img/plot_user_{:s}_ANC.png");

# define optimizer and options
optimizer = optimizer_with_attributes(HiGHS.Optimizer, "ipm_optimality_tolerance"=>1e-6)

# Define the Non Cooperative model
ANC_Model = ModelEC(input_file, EnergyCommunity.GroupANC(), optimizer)

# Build the mathematical model
build_model!(ANC_Model)

# Optimize the model
optimize!(ANC_Model)

# get objective value
objective_value(ANC_Model)

# Create plots of the results
plot(ANC_Model, output_plot_isolated)

# Print summaries of the results
print_summary(ANC_Model)

# Save summaries
save_summary(ANC_Model, output_file_isolated)

# Plot the sankey plot of resources
plot_sankey(ANC_Model)

# DataFrame of the business plan
business_plan(ANC_Model)

# plot business plan
business_plan_plot(ANC_Model)

# save the model to a jld2 file
save("anc_model.jld2", ANC_Model)

# read the loaded model from the jld2 file
ANC_Model_loaded = load!("anc_model.jld2", ModelEC())

# get the objective value of the loaded model
objective_value(ANC_Model)
