##= Load parameters

input_file = joinpath(@__DIR__, "../data/energy_community_model.yml")  # Input file
save_iter_dir = "/data/davidef/gitdf/EnergyCommunity.jl/run_cloud/results_paper/iter"

enum_mode_file = "enum_mode_datasest.jld2"  # file used to store the enumerative results
total_results_file = "total_results_file_poolmode0_poolsearch200_poolsearch200_N12.jld2"  # file to store all major results
latex_output = "latex_output_poolmode0_poolsearch200_poolsearch200_N12.txt"

overwrite_files = true  # when true, output files are overwritten


##= Load imports

#using Revise
using EnergyCommunity
using FileIO
using HiGHS, Plots
using JuMP
using Gurobi
using Games
using TickTock
using Combinatorics
using DataFrames
using JLD2
using Latexify, LaTeXStrings
using YAML
using CPLEX
using CSV

##= Solver settings

# General optimizer

DEFAULT_OPTIMIZER = CPLEX.Optimizer

if (DEFAULT_OPTIMIZER <: CPLEX.Optimizer)
    OPTIMIZER = optimizer_with_attributes(CPLEX.Optimizer, "CPX_PARAM_THREADS"=>10, "CPX_PARAM_PARALLELMODE"=>-1)
else
    OPTIMIZER = optimizer_with_attributes(Gurobi.Optimizer, "OutputFlag"=>0, "Threads"=>10)
end

BESTOBJSTOP_param = ((DEFAULT_OPTIMIZER <: CPLEX.Optimizer) ? "CPX_PARAM_MIP_Limits_UpperObjStop" : "BestObjStop")

##= Energy Community options

NO_AGG_GROUP = GroupANC();  # type of aggregation when the Aggregator does not belong to the coalition.
                            # options: GroupANC() or GroupNC()
BASE_GROUP = GroupNC();     # base type of aggregation (it shall be GroupNC)

ATOL = 0.1
RTOL = 1e-2

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
    user_list = ["user$n" for n = 1:n_users]

    general, users, market = explode_data(ECModel)

    general_new = deepcopy(general)
    general_new["user_set"] = user_list

    users_new = Dict(
        "user$u"=>deepcopy(users["user$(mod1(u, length(users)))"])
        for u = 1:n_users
    )

    market_new = deepcopy(market)

    data_new = Dict(
        "general"=>general_new,
        "market"=>market_new,
        "users"=>users_new,
    )

    return ModelEC(
        data=data_new,
        group_type=ECModel.group_type,
        optimizer=ECModel.optimizer,
        user_set=user_list
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
            "MIPGap"=>RTOL,
            "MIPGapAbs"=>ATOL,
            # "MIPFocus"=>1,
            "TimeLimit"=>3600*6,
            "LogFile"=>"gurobi.log",
            "Threads"=>10,
            # "NoRelHeurTime"=>10,
            "PoolSolutions"=>200,
            "PoolSearchMode"=>0,
            # "Crossover"=>0,  # disable crossover
        )
    elseif optimizer <: CPLEX.Optimizer
        default_options = Dict(
            "CPX_PARAM_EPGAP"=>RTOL,
            "CPX_PARAM_EPAGAP"=>ATOL,
            "CPX_PARAM_TILIM"=>2*3600,
            "CPX_PARAM_THREADS"=>10,
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

        #beststopoption in CPLEX: CPX_PARAM_MIP_Limits_UpperObjStop
    end

    options_mod = Dict(String(index)=>value for (index, value) in options)

    merged_options = convert(Dict{String, Any}, (merge(default_options, options_mod)))

    return optimizer_with_attributes(optimizer, merged_options...)
end

"""
Function to ease creating history DataFrames
"""
function create_history_dataframe(vect, function_type)
    df_history = select(DataFrame(vect), [:iteration, :elapsed_time, :benefit_coal, :value_min_surplus, :lower_problem_min_surplus])
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

function simulation(EC_size, optimizer, precoal, bestobjstop)
    return (EC_size=EC_size, optimizer=optimizer, precoal=precoal, bestobjstop=bestobjstop)
end

# Callback to set Benders decomposition and increase comp. time if TIME_LIMIT occurs
function callback_solution_time_limit(ecm_copy)
    # reinitialize start value to current solution
    set_start_value.(all_variables(ecm_copy.model), value.(all_variables(ecm_copy.model)))
    # set desired parameters
    JuMP.set_optimizer_attribute(ecm_copy.model, "CPXPARAM_Benders_Strategy", 3)
    JuMP.set_optimizer_attribute(ecm_copy.model, "CPX_PARAM_TILIM", 3600*24)
    # reoptimize the solution
    optimize!(ecm_copy)
end

dict_callback = Dict(JuMP.TIME_LIMIT=>callback_solution_time_limit)

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

# CPLEX
run_simulations = [
    (EC_size=10, optimizer=build_row_options(), precoal=[1], bestobjstop=true),
    (EC_size=10, optimizer=build_row_options(; CPX_PARAM_SOLNPOOLINTENSITY=4, CPX_PARAM_POPULATELIM=10), precoal=[1], bestobjstop=true),
    (EC_size=10, optimizer=build_row_options(; CPX_PARAM_SOLNPOOLINTENSITY=4, CPX_PARAM_POPULATELIM=50), precoal=[1], bestobjstop=true),
    (EC_size=10, optimizer=build_row_options(; CPX_PARAM_SOLNPOOLINTENSITY=4, CPX_PARAM_POPULATELIM=200), precoal=[1], bestobjstop=true),
    (EC_size=10, optimizer=build_row_options(), precoal=[1], bestobjstop=false),
    (EC_size=10, optimizer=build_row_options(), precoal=[1, 2], bestobjstop=false),
    (EC_size=10, optimizer=build_row_options(), precoal=[1, 10], bestobjstop=false),
    (EC_size=10, optimizer=build_row_options(), precoal=[1, 10], bestobjstop=true),
    (EC_size=10, optimizer=build_row_options(; CPXPARAM_Benders_Strategy=3, CPX_PARAM_TILIM=24*3600), precoal=[1, 10], bestobjstop=false),
    (EC_size=10, optimizer=build_row_options(; CPXPARAM_Benders_Strategy=3, CPX_PARAM_TILIM=24*3600), precoal=[1, 10], bestobjstop=true),
    (EC_size=10, optimizer=build_row_options(), precoal=[1, 2, 3], bestobjstop=false),
    (EC_size=10, optimizer=build_row_options(), precoal=[1, 9, 10], bestobjstop=false),
    (EC_size=20, optimizer=build_row_options(), precoal=[1, 20], bestobjstop=false),
    (EC_size=20, optimizer=build_row_options(), precoal=[1, 20], bestobjstop=true),
    (EC_size=20, optimizer=build_row_options(), precoal=[1, 20], bestobjstop=false),
    (EC_size=20, optimizer=build_row_options(; CPXPARAM_Benders_Strategy=3, CPX_PARAM_TILIM=24*3600), precoal=[1, 20], bestobjstop=true),
    (EC_size=20, optimizer=build_row_options(; CPXPARAM_Benders_Strategy=3, CPX_PARAM_TILIM=24*3600), precoal=[1, 20], bestobjstop=false),
    (EC_size=50, optimizer=build_row_options(), precoal=[1, 50], bestobjstop=true),
    (EC_size=100, optimizer=build_row_options(), precoal=[1, 100], bestobjstop=true),
]

# parse run_simulations to store a backup csv file
base_names_named_tuple = unique(vcat([string.(collect(keys(c))) for c in run_simulations]...))
setdiff!(base_names_named_tuple, ["optimizer"])  # drop optimizer
options_named_tuple = unique(vcat([map(x -> x.first.name, c.optimizer.params) for c in run_simulations]...))

"Function to return the value of the desired option_named given a list of parameters params"
function get_value_option(params, option_name, default="")
    id = findfirst(p -> p.first.name == option_name, params)
    isnothing(id) && return default
    return params[id].second
end

df_run_simulations = DataFrame(
    permutedims(hcat([
        [[c[Symbol(bn)] for bn in base_names_named_tuple];
        [get_value_option(c.optimizer.params, on) for on in options_named_tuple]]
        for c in run_simulations
    ]...)),
    [base_names_named_tuple; options_named_tuple],
)

CSV.write("$save_iter_dir/options_backup.csv", df_run_simulations)



# models of the ec
EC_size_list = unique([el.EC_size for el in run_simulations])
EC_dict = Dict(
    EC_s => build_nusers_EC_file(ECModel, EC_s) for EC_s in EC_size_list
)

# (id_run, el) = first(collect(enumerate(run_simulations)))

# Threads.@threads 
for (id_run, el) in collect(enumerate(run_simulations))

    println("------------- ITER ID RUN $id_run --------------")

    current_EC = EC_dict[el.EC_size]

    iter_mode = IterMode(current_EC, BASE_GROUP; no_aggregator_group=NO_AGG_GROUP, optimizer=el.optimizer, callback_solution=dict_callback)

    # include all coalitions having no more than preload_max_size users
    preload_combs_set = el.precoal
    preload_coalitions = collect(Iterators.flatten([combinations([EC_CODE; current_EC.user_set], k) for k = preload_combs_set]))

    # CORE
    tick()
    incore_dist_iter, min_surplus_incore_iter, history_incore_iter, model_dist_incore_iter = in_core(
        iter_mode,
        OPTIMIZER;
        lower_bound=0.0,
        atol=ATOL,
        rtol=RTOL,
        raw_outputs=true,
        preload_coalitions=preload_coalitions,
        best_objective_stop_option=(el.bestobjstop ? BESTOBJSTOP_param : nothing),
        exclude_visited_coalitions=false,
        max_iter=1000,
    )
    time_elapsed_incore_iter=tok()

    println("In Core - IterMode calculated with elapsed time [min]: $(time_elapsed_incore_iter/60)")

    # LEASTCORE
    tick()
    leastcore_dist_iter, min_surplus_leastcore_iter, history_leastcore_iter, model_dist_leastcore_iter = least_core(
        iter_mode,
        OPTIMIZER;
        lower_bound=0.0,
        atol=ATOL,
        rtol=RTOL,
        raw_outputs=true,
        preload_coalitions=preload_coalitions,
        best_objective_stop_option=(el.bestobjstop ? BESTOBJSTOP_param : nothing),
        exclude_visited_coalitions=false,
        max_iter=1000,
    )
    time_elapsed_leastcore_iter=tok()
    println("Least Core - IterMode calculated with elapsed time [min]: $(time_elapsed_leastcore_iter/60)")

    # VARLEASTCORE
    tick()
    varleastcore_dist_iter, min_surplus_varleastcore_iter, history_varleastcore_iter, model_dist_varleastcore_iter = var_least_core(
        iter_mode,
        OPTIMIZER;
        lower_bound=0.0,
        atol=ATOL,
        rtol=RTOL,
        raw_outputs=true,
        preload_coalitions=preload_coalitions,
        best_objective_stop_option=(el.bestobjstop ? BESTOBJSTOP_param : nothing),
        exclude_visited_coalitions=false,
        max_iter=1000,
    )
    time_elapsed_varleastcore_iter=tok()
    println("Variance Least Core - IterMode calculated with elapsed time [min]: $(time_elapsed_varleastcore_iter/60)")


    # VARCORE
    tick()
    varcore_dist_iter, min_surplus_varcore_iter, history_varcore_iter, model_dist_varcore_iter = var_in_core(
        iter_mode,
        OPTIMIZER;
        lower_bound=0.0,
        atol=ATOL,
        rtol=RTOL,
        raw_outputs=true,
        preload_coalitions=preload_coalitions,
        best_objective_stop_option=(el.bestobjstop ? BESTOBJSTOP_param : nothing),
        exclude_visited_coalitions=false,
        max_iter=1000,
    )
    time_elapsed_varcore_iter=tok()
    println("Variance Core - IterMode calculated with elapsed time [min]: $(time_elapsed_varcore_iter/60)")


    # vector of the users
    user_set_agg = [EC_CODE; get_user_set(current_EC)]

    "Auxiliary function to order the output of reward distributions and return them as vectors"
    vectorize_rewards(reward_dist, users_list=user_set_agg) = [reward_dist[u] for u in users_list]

    # dataframe of reward distributions for the enumerative mode
    df_reward_iter = DataFrame(
        user_set=user_set_agg,
        incore_iter=vectorize_rewards(incore_dist_iter),
        leastcore_iter=vectorize_rewards(leastcore_dist_iter),
        varcore_iter=vectorize_rewards(varcore_dist_iter),
        varleastcore_iter=vectorize_rewards(varleastcore_dist_iter),
    )

    # dictionary of the time requirements
    df_time_iter = DataFrame(
        "name"=>"iter_mode",
        "id_run"=>id_run,
        "EC_size"=>el.EC_size,
        "mode_time"=>0.0,
        "incore_iter"=>time_elapsed_incore_iter,
        "leastcore_iter"=>time_elapsed_leastcore_iter,
        "varcore_iter"=>time_elapsed_varcore_iter,
        "varleastcore_iter"=>time_elapsed_varleastcore_iter,
    )

    # dictionary iterations
    df_iterations_iter = DataFrame(
        "name"=>"iter_mode",
        "id_run"=>id_run,
        "EC_size"=>el.EC_size,
        "incore_iter"=>history_incore_iter[end][1],
        "leastcore_iter"=>history_leastcore_iter[end][1],
        "varcore_iter"=>history_varcore_iter[end][1],
        "varleastcore_iter"=>history_varleastcore_iter[end][1],
    )

    # dictionary least core values
    df_surplus_values = DataFrame(
        "name"=>"iter_mode",
        "id_run"=>id_run,
        "EC_size"=>el.EC_size,
        "incore_iter"=>min_surplus_incore_iter,
        "leastcore_iter"=>min_surplus_leastcore_iter,
        "varcore_iter"=>min_surplus_varcore_iter,
        "varleastcore_iter"=>min_surplus_varleastcore_iter,
    )

    df_history_incore = create_history_dataframe(history_incore_iter, "incore_iter")
    df_history_leastcore = create_history_dataframe(history_leastcore_iter, "leastcore_iter")
    df_history_varcore = create_history_dataframe(history_varcore_iter, "varcore_iter")
    df_history_varleastcore = create_history_dataframe(history_varleastcore_iter, "varleastcore_iter")
    df_history = vcat(df_history_incore, df_history_leastcore, df_history_varcore, df_history_varleastcore)

    # # dictionary of history values
    # dict_history = Dict(
    #     "incore_iter"=>history_incore_iter,
    #     "leastcore_iter"=>history_leastcore_iter,
    #     "varcore_iter"=>history_varcore_iter,
    #     "varleastcore_iter"=>history_varleastcore_iter,
    # )
    
    # save results
    filepath = "$save_iter_dir/iter_simulations_results_$id_run.jld2"
    # create parent directory if missing
    mkpath(dirname(filepath))
    jldsave(filepath; df_reward_iter, df_time_iter, df_iterations_iter, df_surplus_values, df_history)
end