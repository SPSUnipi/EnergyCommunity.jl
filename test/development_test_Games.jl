using Revise
using EnergyCommunity
using FileIO
using HiGHS, Plots
using JuMP
using Gurobi
using Games
using TickTock
using Combinatorics


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

OPTIMIZER = optimizer_with_attributes(Gurobi.Optimizer, "OutputFlag"=>0, "Threads"=>10)
OPTIMIZER_MIPGAP = optimizer_with_attributes(Gurobi.Optimizer,
    "OutputFlag"=>1,
    "LogToConsole"=>0,
    "MIPGap"=>0.2,
    # "MIPFocus"=>1,
    "TimeLimit"=>1000,
    "LogFile"=>"C:\\Users\\Davide\\Desktop\\gurobi_varlc.log",
    "Threads"=>10,
    # "NoRelHeurTime"=>10,
    "PoolSolutions"=>100,
    "PoolSearchMode"=>0,
)


# Read data from excel file
ECModel = ModelEC(input_file, EnergyCommunity.GroupCO(), OPTIMIZER)


# test_coalition = ["EC", "user1", "user2", "user3", "user4", "user5"]

# set_user_set!(ECModel, test_coalition)

reset_user_set!(ECModel)
#set_user_set!(ECModel, ["user$id" for id=1:5])

# build_model!(ECModel)
# optimize!(ECModel)

#enum_mode = load("test/enum_mode_datasest.jld2", EnumMode())

#nucleolus_dist_enum, b, model_nuc = nucleolus(enum_mode, OPTIMIZER; raw_outputs=true)  # nucleolus

# NCModel = ModelEC(ECModel, EnergyCommunity.GroupNC())
# build_model!(NCModel)
# optimize!(NCModel)


# ANCModel = ModelEC(ECModel, EnergyCommunity.GroupANC())
# build_model!(ANCModel)
# optimize!(ANCModel)

coal_EC = [EC_CODE; ECModel.user_set]
profit_list = [23064.94534744716, 6825.297230565472, 44921.61629393777, 5175.039574246674, 5055.268214914409, 3487.4191783565184, 4680.009759817722, 66826.60688194631, 6156.843910783279, 4661.382228575006, 56295.61820125032]
test_profit = Dict(
    u=>profit_list[i] for (i, u) in enumerate(coal_EC)  #profit_list[i]
)

# # utility_callback = to_utility_callback_by_subgroup(ECModel, GroupNC(), no_aggregator_group=GroupNC())
# worst_coalition_callback, ecm_copy_worst = to_least_profitable_coalition_callback(
#     ECModel, GroupNC();
#     optimizer=OPTIMIZER_MIPGAP,
#     raw_outputs=true,
#     no_aggregator_group=GroupANC()
# )

# output_data = worst_coalition_callback(test_profit)
# output_data_mod = worst_coalition_callback(test_profit; modify_solver_options=["BestObjStop"=>10000.])


# worst_coalition_callback_relax, ecm_copy_worst_relax = to_least_profitable_coalition_callback(
#     ECModel, GroupNC(); 
#     raw_outputs=true, 
#     optimizer=OPTIMIZER_MIPGAP,
#     no_aggregator_group=GroupANC(), 
#     relax_combinatorial=true
# )

# output_data_relax = worst_coalition_callback_relax(test_profit)


preload_coalitions = Iterators.flatten([combinations([EC_CODE; ECModel.user_set], k) for k = 1:3])

iter_mode = IterMode(ECModel, GroupNC(); no_aggregator_group=GroupNC(), optimizer=OPTIMIZER_MIPGAP, number_of_solutions=0)

tick()
lc_iter, min_surplus, history, model_dist = var_least_core(
    iter_mode, OPTIMIZER;
    lower_bound=0.0,
    atol=1e-4,
    raw_outputs=true,
    preload_coalitions=preload_coalitions,
    best_objective_stop_option="BestObjStop",
)
time_elapsed_iter=tok()


# tick()
# enum_mode = EnumMode(ECModel, GroupNC(); no_aggregator_group=GroupANC())
# time_elapsed_enum=tok()

# save("enum_mode_ANC.jld2", enum_mode)
# enum_mode = load("enum_mode_ANC.jld2", EnumMode())

# lc_enum, value_min_surplus_enum, model_dist_enum = var_least_core(enum_mode, OPTIMIZER; raw_outputs=true)


# tick()
# varcore_dist_iter, min_surplus_varcore_iter, history_varcore_iter, model_dist_varcore_iter = var_in_core(
#     iter_mode,
#     OPTIMIZER;
#     lower_bound=0.0,
#     atol=1e-4,
#     raw_outputs=true,
#     preload_coalitions=preload_coalitions,
# )
# time_elapsed_varcore_iter=tok()
# println("Variance Core - IterMode calculated with elapsed time [min]: $(time_elapsed_varcore_iter/60)")

# ECModel.user_set = collect(keys(ECModel.users_data))

# utility_callback(ECModel.user_set)

# iter_mode = IterMode(ECModel, GroupNC(); no_aggregator_group=GroupNC(), optimizer=OPTIMIZER_MIPGAP)

# coal_EC = [EC_CODE; ECModel.user_set]

# profit_list = [23064.94534744716, 6825.297230565472, 44921.61629393777, 5175.039574246674, 5055.268214914409, 3487.4191783565184, 4680.009759817722, 66826.60688194631, 6156.843910783279, 4661.382228575006, 56295.61820125032]
# test_profit = Dict(
#     u=>0.0 for (i, u) in enumerate(coal_EC)  #profit_list[i]
# )

# least_profitable_coalition_worst, coalition_benefit_worst, min_surplus_worst = worst_coalition_callback(test_profit)

# test_coalition = ["EC", "user1", "user2", "user3"]

# for u in coal_EC
#     fix(ecm_copy.model[:coalition_status][u], ((u in test_coalition) ? 1.0 : 0.0), force=true)
# end

# optimize!(ecm_copy)
# objective_value(ecm_copy)

# ECModel.user_set = setdiff(test_coalition, [EC_CODE])
# build_model!(ECModel)
# optimize!(ECModel)
# objective_value(ECModel)

# ANCModel.user_set = setdiff(test_coalition, [EC_CODE])
# build_model!(ANCModel)
# optimize!(ANCModel)
# objective_value(ANCModel)

# NCModel.user_set = setdiff(test_coalition, [EC_CODE])
# build_model!(NCModel)
# optimize!(NCModel)
# objective_value(NCModel)
# objective_value(ANCModel) - objective_value(NCModel)

# anc_obj_call = to_objective_callback_by_subgroup(ANCModel)

# anc_obj_call(ANCModel.user_set)
# anc_obj_call(test_coalition)

# tick()
# lc_iter = var_least_core(iter_mode, OPTIMIZER; lower_bound=0.0, atol=1e-4, use_start_value=true)
# time_elapsed=tok()


# enum_mode = EnumMode(ECModel, GroupNC(); no_aggregator_group=GroupNC())

# save("enum_mode_NC.jld2", enum_mode)
# enum_mode = load("enum_mode_NC.jld2", EnumMode())

# lc_enum, value_min_surplus, model_dist = var_least_core(enum_mode, OPTIMIZER; raw_outputs=true)

# save("enum_mode.jld2", enum_mode)
#enum_mode = load("enum_mode.jld2", EnumMode())

# test_coal = ["user1", "user2"]

# least_profitable_coalition, coalition_benefit, min_surplus = worst_coalition_callback(test_profit)

# profit_distribution, min_surplus, history = least_core(mode, ECModel.optimizer)

#sh_val = shapley_value(enum_mode)

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