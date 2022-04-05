using Revise
using EnergyCommunity
using FileIO
using HiGHS, Plots
using JuMP
using Gurobi


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
ECModel = ModelEC(input_file, EnergyCommunity.GroupCO(), Gurobi.Optimizer)
build_model!(ECModel)
optimize!(ECModel)

NCModel = ModelEC(input_file, EnergyCommunity.GroupNC(), Gurobi.Optimizer)
build_model!(NCModel)
optimize!(NCModel)


lpc_callback, ecm_model = to_least_profitable_coalition_callback(ECModel)

spread = objective_value(ECModel) - objective_value(NCModel)

test_coal = Dict("EC"=>0.0, "user1"=>spread/2, "user2"=>spread/2, "user3"=>0.0)
#test_coal = Dict("EC"=>0.0, "user1"=>0.0, "user2"=>0.0, "user3"=>0.0)
#test_coal = Dict("EC"=>0.0, "user2"=>spread/2, "user3"=>spread/2)

least_profitable_coalition, coalition_benefit, min_surplus = lpc_callback(test_coal)

# optimize!(ECModel)

# plot(ECModel, output_plot_combined)

# print_summary(ECModel)

# save_summary(ECModel, output_file_combined)

# grid_shares_EC = calculate_grid_import(ECModel)
# energy_shares_EC = calculate_production_shares(ECModel)

# handle_plot, sank_data = plot_sankey(ECModel, plotting=true)

# save("testECsave.jld2", ECModel)

# model2 = load("testECsave.jld2")

# print_summary(model2)

## Model NC

# NC_Model = ModelEC(ECModel, EnergyCommunity.GroupNC(), GLPK.Optimizer)

# build_model!(NC_Model)

# optimize!(NC_Model)

# plot(NC_Model, output_plot_isolated)

# print_summary(NC_Model)

# save_summary(NC_Model, output_file_isolated)


# grid_shares_NC = calculate_grid_shares(NC_Model)
# energy_shares_NC = calculate_production_shares(NC_Model)


# ## Plot sankey diagrams

# # init sets
# agg_id = "Agg"
# user_set_agg = append!([agg_id], user_set)
# user_set_desc = Dict(u => (u == agg_id) ? "Agg" : u for u in user_set_agg)

# plotlyjs() #set plotly backend in Plots

# # calculate energy shares for the users only mode
# init_step = field(gen_data, "init_step")
# final_step = field(gen_data, "final_step")
# time_set = init_step:final_step

# _P_tot_us_noagg = value.(model_user[:P_tot_us])  # power dispatch of users - users mode
# _P_ren_us_noagg = value.(model_user[:P_ren_us])  # Ren production dispatch of users - users mode

# shared_en_us_abs_aggnoagg, shared_en_tot_abs_aggnoagg, shared_cons_us_abs_aggnoagg, shared_cons_tot_abs_aggnoagg,
#     shared_en_frac_abs_aggnoagg, shared_cons_frac_abs_aggnoagg=
#         calculate_shared_energy_abs_agg(users_data, user_set, time_set,
#                 _P_tot_us_noagg, _P_ren_us_noagg)


# # plot sankey diagram users-only

# zeros_DA = JuMP.Containers.DenseAxisArray([0.0 for t in time_set], time_set)

# s_noagg, df_sank_noagg = createSankeyDiagram(
#     _P_tot_us_noagg, zeros_DA, zeros_DA, user_set, user_set_desc)
# display(s_noagg)
# savefig(s_noagg, output_plot_sankey_noagg)

# # calculate energy shares for the EC mode
# _P_tot_us_agg = value.(model[:P_tot_us])  # power dispatch of users - EC mode
# _P_ren_us_agg = value.(model[:P_ren_us])  # Ren production dispatch of users - EC mode

# shared_en_us_abs_agg, shared_en_tot_abs_agg, shared_cons_us_abs_agg, shared_cons_tot_abs_agg,
#     shared_en_frac_abs_agg, shared_cons_frac_abs_agg =
#         calculate_shared_energy_abs_agg(users_data, user_set, time_set,
#                 _P_tot_us_agg, _P_ren_us_agg)


# # plot sankey diagram EC mode

# s_agg, df_sank_agg = createSankeyDiagram(
#     _P_tot_us_agg, shared_cons_frac_abs_agg, shared_en_frac_abs_agg, user_set, user_set_desc)
# display(s_agg)
# savefig(s_agg, output_plot_sankey_agg)