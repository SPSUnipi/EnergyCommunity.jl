# # Non Cooperative Energy Community
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


# Input file to load the structure of the energy community based on a yaml file.
input_file = joinpath(@__DIR__, "../../../data/energy_community_model.yml");

# Output path of the summary and of the plots
output_file_isolated = joinpath(@__DIR__, "../results/output_file_NC.xlsx");
output_plot_isolated = joinpath(@__DIR__, "../results/Img/plot_user_{:s}_NC.png");


# Define the Non Cooperative model
NC_Model = ModelEC(input_file, EnergyCommunity.GroupNC(), HiGHS.Optimizer)

# Build the mathematical model
build_model!(NC_Model)

# Optimize the model
optimize!(NC_Model)

# Create plots of the results
plot(NC_Model, output_plot_isolated)

# Print summaries of the results
print_summary(NC_Model)

# Save summaries
save_summary(NC_Model, output_file_isolated)

# Plot the sankey plot of resources
plot_sankey(NC_Model)

# DataFrame of the business plan
business_plan(NC_Model)

# plot business plan
business_plan_plot(NC_Model)