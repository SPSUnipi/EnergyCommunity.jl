##= Load parameters

input_file = joinpath(@__DIR__, "../data/energy_community_model.yml")  # Input file
parent_dir = "C:/Users/Davide/git/gitdf/EnergyCommunity.jl/run_cloud"

overwrite_files = true  # when true, output files are overwritten

EC_size_list_enum = [10] #, 20] #[5, 10, 20]  # List of sizes of the EC to test in enum mode



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

##= Solver settings

# General optimizer
OPTIMIZER = optimizer_with_attributes(Gurobi.Optimizer, "OutputFlag"=>0, "Threads"=>10)

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
        data_new,
        ECModel.group_type,
        ECModel.optimizer,
        user_list
    )
end


# models of the ec
EC_dict = Dict(
    EC_s => build_nusers_EC_file(ECModel, EC_s) for EC_s in EC_size_list_enum
)

# run enum models
for EC_enum_s in EC_size_list_enum
    current_EC = EC_dict[EC_enum_s]


    tick()
    enum_mode = EnumMode(current_EC, BASE_GROUP; no_aggregator_group=NO_AGG_GROUP)
    time_elapsed_enum=tok()

    #save enum results
    filepath = "$parent_dir/results_paper/enum/file_enum_$EC_enum_s.jld2"
    mkpath(dirname(filepath))
    save(filepath, enum_mode)

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

    tick()
    incore_dist_enum = in_core(enum_mode, OPTIMIZER)  # in core
    time_elapsed_incore_enum=tok()

    tick()
    leastcore_dist_enum = least_core(enum_mode, OPTIMIZER)  # least core
    time_elapsed_leastcore_enum=tok()

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
        incore_enum=vectorize_rewards(incore_dist_enum),
        leastcore_enum=vectorize_rewards(leastcore_dist_enum),
    )

    # dataframe of the time requirements
    df_time_enum = DataFrame(
        "name"=>"enum_mode",
        "id_run"=>0.0,
        "EC_size"=>EC_enum_s,
        "mode_time"=>time_elapsed_enum,
        "shapley_enum"=>time_elapsed_shapley_enum+time_elapsed_enum,
        "nucleolus_enum"=>time_elapsed_nucleolus_enum+time_elapsed_enum,
        "varcore_enum"=>time_elapsed_varcore_enum+time_elapsed_enum,
        "varleastcore_enum"=>time_elapsed_varleastcore_enum+time_elapsed_enum,
        "incore_enum"=>time_elapsed_incore_enum+time_elapsed_enum,
        "leastcore_enum"=>time_elapsed_leastcore_enum+time_elapsed_enum,
    )
    
    # save results
    filepath = "$parent_dir/results_paper/enum/enum_simulations_results_$EC_enum_s.jld2"
    # create parent directory if missing
    mkpath(dirname(filepath))
    jldsave(filepath; df_reward_enum, df_time_enum)
end