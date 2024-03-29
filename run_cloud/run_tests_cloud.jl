##= Load parameters

input_file = joinpath(@__DIR__, "../data/energy_community_model.yml")  # Input file
parent_dir = "C:/Users/Davide/Il mio Drive/Universita/Dottorato/git/EnergyCommunity.jl/run_cloud"

enum_mode_file = "enum_mode_datasest.jld2"  # file used to store the enumerative results
total_results_file = "total_results_file_poolmode0_poolsearch200_poolsearch200_N12.jld2"  # file to store all major results
latex_output = "latex_output_poolmode0_poolsearch200_poolsearch200_N12.txt"

overwrite_files = true  # when true, output files are overwritten

EC_size_list_iter = []#[10, 20, 50]  # List of sizes of the EC to test in iter mode
EC_size_list_enum = [3,4] #[5, 10, 20]  # List of sizes of the EC to test in enum mode



##= Load imports

#using Revise
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

##= Solver settings

# General optimizer
OPTIMIZER = optimizer_with_attributes(Gurobi.Optimizer, "OutputFlag"=>0, "Threads"=>10)

# Optimizer for row-generation techniques, used in the IterMode of TheoryOfGames.jl
OPTIMIZER_ROW_GENERATION = optimizer_with_attributes(Gurobi.Optimizer,
    "OutputFlag"=>1,
    "LogToConsole"=>0,
    "MIPGap"=>0.1,
    # "MIPFocus"=>1,
    "TimeLimit"=>1000,
    "LogFile"=>"gurobi_poolmode0_poolsearch200_N12.log",
    "Threads"=>10,
    # "NoRelHeurTime"=>10,
    "PoolSolutions"=>200,
    "PoolSearchMode"=>0,
    # "Crossover"=>0,  # disable crossover
)

##= Energy Community options

NO_AGG_GROUP = GroupANC();  # type of aggregation when the Aggregator does not belong to the coalition.
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


# models of the ec
EC_size_list = unique([EC_size_list_iter; EC_size_list_enum])
EC_dict = Dict(
    EC_s => build_nusers_EC_file(ECModel, EC_s) for EC_s in EC_size_list
)

# run enum models
for EC_enum_s in EC_size_list_enum
    current_EC = EC_dict[EC_enum_s]


    tick()
    enum_mode = EnumMode(current_EC, BASE_GROUP; no_aggregator_group=NO_AGG_GROUP)
    time_elapsed_enum=tok()
    save("$parent_dir/results_paper/enum/file_enum_$EC_enum_s.jld2", enum_mode)

    tick()
    shapley_dist_enum = shapley_value(enum_mode)  # shapley value
    time_elapsed_shapley_enum=tok()

    tick()
    nucleolus_dist_enum, n_iterations_nucleolus_enum, model_nucleolus_enum = nucleolus(enum_mode, OPTIMIZER; raw_outputs=true)  # nucleolus
    time_elapsed_nucleolus_enum=tok()

    tick()
    varcore_dist_enum = var_in_core(enum_mode, OPTIMIZER)  # variance in core
    time_elapsed_varcore_enum=tok()

    tick()
    varleastcore_dist_enum, val_minsurplus_enum, model_dist_enum = var_least_core(
        enum_mode, OPTIMIZER; raw_outputs=true
    )  # variance least core (include raw outputs for comparison purposes)
    time_elapsed_varleastcore_enum=tok();

    # vector of the users
    user_set_agg = [EC_CODE; get_user_set(current_EC)]

    "Auxiliary function to order the output of reward distributions and return them as vectors"
    vectorize_rewards(reward_dist, users_list=user_set_agg) = [reward_dist[u] for u in users_list]

    # dataframe of reward distributions for the enumerative mode
    df_reward_enum = DataFrame(
        user_set=user_set_agg,
        shapley_enum=vectorize_rewards(shapley_dist_enum),
        nucleolus_enum=vectorize_rewards(nucleolus_dist_enum),
        varcore_enum=vectorize_rewards(varcore_dist_enum),
        varleastcore_enum=vectorize_rewards(varleastcore_dist_enum),
    )

    # dataframe of the time requirements
    dict_time_enum = Dict(
        "EnumMode"=>time_elapsed_enum,
        "shapley_enum"=>time_elapsed_shapley_enum+time_elapsed_enum,
        "nucleolus_enum"=>time_elapsed_nucleolus_enum+time_elapsed_enum,
        "varcore_enum"=>time_elapsed_varcore_enum+time_elapsed_enum,
        "varleastcore_enum"=>time_elapsed_varleastcore_enum+time_elapsed_enum,
    )

    jldsave("$parent_dir/results_paper/enum/enum_simulations_results_$EC_enum_s.jld2"; df_reward_enum, dict_time_enum)
end