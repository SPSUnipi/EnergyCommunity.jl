##= Load parameters

input_file = joinpath(@__DIR__, "../data/energy_community_model.yml")  # Input file
parent_dir = "/data/davidef/gitdf/EnergyCommunity.jl/run_cloud"

enum_mode_file = "enum_mode_datasest.jld2"  # file used to store the enumerative results
total_results_file = "total_results_file_poolmode0_poolsearch200_poolsearch200_N12.jld2"  # file to store all major results
latex_output = "latex_output_poolmode0_poolsearch200_poolsearch200_N12.txt"

overwrite_files = true  # when true, output files are overwritten


##= Load imports

using Revise
using EnergyCommunity
using FileIO
using HiGHS, Plots
using JuMP
using Gurobi
using TheoryOfGames
using TickTock
using Combinatorics
using DataFrames
using JLD2
using Latexify, LaTeXStrings
using YAML
using CPLEX

##= Solver settings

# General optimizer

DEFAULT_OPTIMIZER = CPLEX.Optimizer

if (DEFAULT_OPTIMIZER <: CPLEX.Optimizer)
    OPTIMIZER = optimizer_with_attributes(CPLEX.Optimizer, "CPX_PARAM_THREADS"=>10, "CPX_PARAM_PARALLELMODE"=>-1)
else
    OPTIMIZER = optimizer_with_attributes(Gurobi.Optimizer, "OutputFlag"=>0, "Threads"=>10)
end

BESTOBJSTOP_param = ((DEFAULT_OPTIMIZER <: CPLEX.Optimizer) ? "CPXPARAM_MIP_Limits_UpperObjStop" : "BestObjStop")
LOWEROBJSTOP_param = ((DEFAULT_OPTIMIZER <: CPLEX.Optimizer) ? "CPXPARAM_MIP_Limits_LowerObjStop" : "BestBdStop")

##= Energy Community options

NO_AGG_GROUP = GroupNC();  # type of aggregation when the Aggregator does not belong to the coalition.
                            # options: GroupANC() or GroupNC()
BASE_GROUP = GroupNC();     # base type of aggregation (it shall be GroupNC)


##= Load base EC model

# Read data from excel file
ECModel = ModelEC(input_file, EnergyCommunity.GroupCO(), OPTIMIZER)

# Reset the user set to use all stored users (10)
reset_user_set!(ECModel)
# set_user_set!(ECModel, ["user$id" for id=1:8])

"""
Function to create arbitrarily large energy communities
by replicating a sample community
"""
function build_nusers_EC_file(ECModel, n_users)
    user_list = ["$n" for n = 1:n_users]

    general, users, market = explode_data(ECModel)

    general_new = deepcopy(general)
    general_new["user_set"] = user_list

    users_new = Dict(
        "$u"=>deepcopy(users["user$(mod1(u, length(users)))"])
        for u = 1:n_users
    )

    market_new = deepcopy(market)

    data_new = Dict(
        "general"=>general_new,
        "market"=>market_new,
        "users"=>users_new,
    )

    return ModelEC(
        data_new,
        ECModel.group_type,
        ECModel.optimizer,
        user_list
    )
end

"""
Function to ease testing different solver options using defaults
"""
function build_row_options(optimizer=DEFAULT_OPTIMIZER; options...)

    if optimizer <: Gurobi.Optimizer
        default_options = Dict(
            "OutputFlag"=>1,
            "LogToConsole"=>0,
            "MIPGap"=>0.05,
            # "MIPGapAbs"=>0.01,
            # "MIPFocus"=>1,
            "TimeLimit"=>3600,
            "LogFile"=>"gurobi.log",
            "Threads"=>10,
            # "NoRelHeurTime"=>10,
            "PoolSolutions"=>200,
            "PoolSearchMode"=>0,
            # "Crossover"=>0,  # disable crossover
        )
    elseif optimizer <: CPLEX.Optimizer
        default_options = Dict(
            # "CPX_PARAM_EPGAP"=>0.05,
            # "CPX_PARAM_TILIM"=>3600,
            "CPX_PARAM_THREADS"=>15,
            "CPX_PARAM_PARALLELMODE"=>-1,  #-1: opportunistic, 1:deterministic
            # "NoRelHeurTime"=>10,
            "CPX_PARAM_POPULATELIM"=>200,
            "CPX_PARAM_SOLNPOOLINTENSITY"=>2,
            "CPXPARAM_Benders_Strategy"=>-1,
            # "CPXPARAM_Benders_Strategy"=>3,
            # "CPXPARAM_Benders_Strategy"=>1,
            # "CPXPARAM_SOLNPOOLREPLACE"=>1,
            ### "CPXPARAM_SOLNPOOLGAP"=>0.2,
            # "CPXPARAM_SOLNPOOLINTENSITY"=> 1/2(best) (corrisponde a searchmode 0) 4 (corrisponde a 2 searchmode)
            # "Crossover"=>0,  # disable crossover
        )

        #beststopoption in CPLEX: CPXPARAM_MIP_Limits_UpperObjStop
    end

    options_mod = Dict(String(index)=>value for (index, value) in options)

    merged_options = convert(Dict{String, Any}, (merge(default_options, options_mod)))

    return optimizer_with_attributes(optimizer, merged_options...)
end

"""
Function to ease creating history DataFrames
"""
function create_history_dataframe(vect, function_type)
    df_history = select(DataFrame(vect), [:iteration, :benefit_coal, :value_min_surplus, :lower_problem_min_surplus])
    df_history[!, :name] = fill(function_type, nrow(df_history))
    df_history[!, :worst_coal] = [
        (
            isnothing(el.worst_coal_status) ? "" : join(
                [u for u in axes(el.worst_coal_status)[1] if el.worst_coal_status[u] >= 0.5],
                "; ",
                )
        ) for el in vect
    ]
    df_history[!, :profit_distribution] = [
        (
            isnothing(el.current_profit) ? "" : join(
                join(
                    [string(el.current_profit[u]) for u in axes(el.current_profit)[1]],
                    "; ",
                )
            )
        ) for el in vect
    ]
    return df_history
end

# Gurobi
# run_simulations = [
#     (EC_size=3, optimizer=build_row_options(; PoolSearchMode=1, PoolSolutions=10), precoal=[1], bestobjstop=true),
#     (EC_size=4, optimizer=build_row_options(), precoal=[1], bestobjstop=true),
#     # (EC_size=10, optimizer=build_row_options(; PoolSearchMode=1, PoolSolutions=10), precoal=[1], bestobjstop=true),
#     # (EC_size=10, optimizer=build_row_options(; PoolSearchMode=1, PoolSolutions=50), precoal=[1], bestobjstop=true),
#     # (EC_size=10, optimizer=build_row_options(; PoolSearchMode=1, PoolSolutions=200), precoal=[1], bestobjstop=true),
#     # (EC_size=10, optimizer=build_row_options(), precoal=[1, 2], bestobjstop=true),
#     # (EC_size=10, optimizer=build_row_options(), precoal=[1, 2], bestobjstop=false),
#     # (EC_size=10, optimizer=build_row_options(), precoal=[1, 10], bestobjstop=true),
#     # (EC_size=10, optimizer=build_row_options(), precoal=[1, 10], bestobjstop=false),
#     # (EC_size=10, optimizer=build_row_options(), precoal=[1, 2, 3], bestobjstop=false),
#     # (EC_size=10, optimizer=build_row_options(), precoal=[1, 9, 10], bestobjstop=false),
#     # (EC_size=20, optimizer=build_row_options(), precoal=[1, 20], bestobjstop=false),
#     # (EC_size=50, optimizer=build_row_options(), precoal=[1, 50], bestobjstop=false),
#     # (EC_size=100, optimizer=build_row_options(), precoal=[1, 100], bestobjstop=false),
# ]
# ; CPXPARAM_SOLNPOOLINTENSITY=4, CPXPARAM_POPULATELIM=10
el = (EC_size=20, optimizer=build_row_options(), precoal=[1, 20], bestobjstop=false)
# el = (EC_size=50, optimizer=build_row_options(), precoal=[1, 50], bestobjstop=false)

run_simulations = [el]

# models of the ec
EC_size_list = unique([el.EC_size for el in run_simulations])
EC_dict = Dict(
    EC_s => build_nusers_EC_file(ECModel, EC_s) for EC_s in EC_size_list
)

profit_distribution = Dict(zip(
    ["EC"; ["$u" for u=1:el.EC_size]],
    [95425.57425825504, 6370.769720762968, 6035.435544878244, 6915.777722276747, 10828.873074073344, 69419.4423502945, 6309.407506663352, 48820.44738070294, 7973.829198118299, 7600.68647384271, 57749.20927582309, 6370.769720762968, 6035.435544896871, 6915.777722276747, 10828.873074073344, 69419.44235026836, 6309.407506656018, 48397.634268335816, 7034.530092153378, 7600.686473816633, 57749.20927582681, 6370.76972078532, 6035.435544904321, 6915.777722276747, 10828.873074080795, 69419.44235027954, 6309.407506655902, 47976.29732252235, 7662.5085936420755, 7600.686473827809, 57749.20927582309, 6370.76972078532, 6035.435544900596, 6915.777722258121, 9955.10074188112, 69419.44235025346, 5279.653098964773, 48443.60000246402, 7973.82919806242, 0.0, 0.0, 0.0, 0.0, 5509.175805196923, 10828.87307407707, 69419.44235026836, 0.0, 48820.44738069922, 7973.829198114574, 0.0, 55825.23180174455]
))

current_EC = EC_dict[el.EC_size]

println("Launch callback creation")

worst_coalition_callback, ecm_copy = to_least_profitable_coalition_callback(
    current_EC, BASE_GROUP;
    optimizer=el.optimizer,
    raw_outputs=true,
    no_aggregator_group=NO_AGG_GROUP,
    use_notations=false,
    lower_relaxation_stop_option=LOWEROBJSTOP_param,
    best_objective_stop_option=BESTOBJSTOP_param,
    tolerance_lower_relaxation_stop=0.05,
)

println("End callback creation")

set_least_profitable_profit!(ecm_copy, profit_distribution)

println("profit distribution setup")

# write_to_file(ecm_copy.model, "model_test.lp")

optimize!(ecm_copy)
