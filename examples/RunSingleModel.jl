# Run this script from EnergyCommunity.jl root!!!
using Pkg
Pkg.activate(".")  # this line requires EnergyCommunity.jl to be the current directory

using EnergyCommunity, JuMP
using HiGHS, Plots


## Parameters

input_file = joinpath(@__DIR__, "../data/energy_community_model.yml")  # Input file

output_file_isolated = joinpath(@__DIR__, "../results/output_file_NC.xlsx")  # Output file - model users alone
output_plot_isolated = joinpath(@__DIR__, "../results/Img/plot_user_{:s}_NC.png")  # Output png file of plot - model users alone

output_file_combined = joinpath(@__DIR__, "../results/output_file_EC.xlsx")  # Output file - model Energy community
output_plot_combined = joinpath(@__DIR__, "../results/Img/plot_user_{:s}_EC.pdf")  # Output png file of plot - model energy community

output_plot_sankey_agg = joinpath(@__DIR__, "../results/Img/sankey_EC.png")  # Output plot of the sankey plot related to the aggregator case
output_plot_sankey_noagg = joinpath(@__DIR__, "../results/Img/sankey_NC.png")  # Output plot of the sankey plot related to the no aggregator case


## Model CO

## Initialization

# Read data from excel file
ECModel = ModelEC(input_file, EnergyCommunity.GroupCO(), HiGHS.Optimizer)

# build CO model
build_model!(ECModel)

# optimize CO model
optimize!(ECModel)

# create plots of CO model
plot(ECModel, output_plot_combined)

# print summary
print_summary(ECModel)

# save summary data
save_summary(ECModel, output_file_combined)

# Plot sankey plot of CO model
plot_sankey(ECModel)

# plot 20 years business plan of CO model
business_plan_plot(ECModel)

## Model NC

# create NonCooperative model
NC_Model = ModelEC(ECModel, EnergyCommunity.GroupNC())

# build NC model
build_model!(NC_Model)

# optimize NC model
optimize!(NC_Model)

# create plots of NC model
plot(NC_Model, output_plot_isolated)

# print summary of NC model
print_summary(NC_Model)

# save summary of NC model
save_summary(NC_Model, output_file_isolated)

# plot Sankey plot of NC model
plot_sankey(NC_Model)

# plot business plan of NC model
#business_plan_plot(NC_Model)
