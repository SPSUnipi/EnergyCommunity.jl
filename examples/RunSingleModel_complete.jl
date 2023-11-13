# # Run this script from EnergyCommunity.jl root!!!
# using Pkg
# Pkg.activate("examples")

using EnergyCommunity, JuMP
using HiGHS, Plots
using Gurobi
using Combinatorics
using TheoryOfGames
using DataFrames

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

reset_user_set!(ECModel)

# build CO model
build_model!(ECModel)

# optimize CO model
optimize!(ECModel)

OPTIMIZER_MIPGAP = optimizer_with_attributes(Gurobi.Optimizer,
    "OutputFlag"=>1,
    "LogToConsole"=>0,
    "MIPGap"=>0.01,
    # "MIPFocus"=>1,
    "TimeLimit"=>1000,
    "LogFile"=>"C:\\Users\\Davide\\Desktop\\gurobi_varlc.log",
    "Threads"=>10,
    # "NoRelHeurTime"=>10,
    "PoolSolutions"=>100,
    "PoolSearchMode"=>0,
)

preload_coalitions = collect(Iterators.flatten([combinations([EC_CODE; ECModel.user_set], k) for k = [1, 10]]))

iter_mode = IterMode(ECModel, GroupNC(); no_aggregator_group=GroupNC(), optimizer=OPTIMIZER_MIPGAP, number_of_solutions=0, decompose_ANC=true)

lc_iter_T, min_surplus_T, history_T, model_dist_T = var_least_core(
    iter_mode, OPTIMIZER_MIPGAP;
    lower_bound=0.0,
    atol=1e-4,
    raw_outputs=true,
    preload_coalitions=preload_coalitions,
    best_objective_stop_option="BestObjStop",    
)

# create plots of CO model
plot(ECModel, output_plot_combined)

# print summary
print_summary(ECModel)

# save summary data
save_summary(ECModel, output_file_combined)

# Plot sankey plot of CO model
plot_sankey(ECModel)

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

# calculation of profit distribution

obj_by_user = objective_by_user(NC_Model)

profit_distribution = JuMP.Containers.DenseAxisArray(
    collect([lc_iter_T[k] + obj_by_user[k] for k in keys(lc_iter_T)]),
    collect(keys(lc_iter_T)),
)

financial_terms_to_df = r->DataFrame([:user_set=>axes(r.NPV)[1]; [k=>r[k].data for k in keys(r)]])

rCO = split_financial_terms(ECModel, profit_distribution)
df_CO = financial_terms_to_df(rCO)

sort!(df_CO, :user_set)

rNC = split_financial_terms(NC_Model, obj_by_user)
df_NC = financial_terms_to_df(rNC)

sort!(df_NC, :user_set)

delta = df_CO[!, 2:end] .- df_NC[!, 2:end]

#%% tru

delta
delta[!, :user_set] = df_CO[:, :user_set]




shared_prod = calculate_time_shared_production(ECModel; add_EC=false)
shared_cons = calculate_time_shared_consumption(ECModel; add_EC=false)

pCO = shadow_price.(ECModel.model[:con_us_balance])
pNC = shadow_price.(NC_Model.model[:con_us_balance])
demand_t = normalized_rhs.(ECModel.model[:con_us_balance])

x_ub = upper_bound.(ECModel.model[:x_us])
x_rc = reduced_cost.(ECModel.model[:x_us])

rev_sh_prod = shared_prod .* pCO
rev_sh_cons = shared_cons .* pCO

tt = demand_t .* (pCO .- pNC)

qq = Dict("user$u"=>sum(tt["user$u", :]) for u in 1:10)
q_table = Dict(r["user_set"]=>r["NPV"] for r in eachrow(delta))

qr = Dict(u=>qq[u]/q_table[u] for u in keys(qq))

ui = ["user$u" for u=1:10]
d_tot = DataFrame(
    index = ui,
    cons = [sum(shared_cons[u, :]) for u in ui],
    prod = [sum(shared_prod[u, :]) for u in ui],
    reward = [rCO.REWARD[u] for u in ui],
)

d_mod = transform(d_tot, AsTable(:) => ByRow(x -> (x.reward/(x.cons +0.001), x.reward/(x.prod+0.001))) => [:r_cons, :r_prod])