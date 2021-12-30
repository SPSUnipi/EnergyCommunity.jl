# Type of grouping: Non Cooperative, Cooperative, Aggregated Non Cooperative
abstract type GroupType end

struct GroupCO <: GroupType end
struct GroupANC <: GroupType end
struct GroupNC <: GroupType end

GroupAny = [GroupCO(), GroupANC(), GroupNC()]
GroupCONC = [GroupCO(), GroupNC()]

abstract type AbstractEC end


"Structure encapsuling the data"
mutable struct ModelEC <: AbstractEC

    data::Dict  # All data
    gen_data::Dict  # general data
    market_data::Dict  # market data
    users_data::Dict  # users data

    group_type::GroupType  # aggregation type of model
    user_set::Vector  # desired user set

    model::Model  # JuMP model

    results::Dict  # results of the model in Dictionary format 

    ModelEC(
            data=Dict(), gen_data=Dict(), market_data=Dict(), users_data=Dict(),
            group_type=GroupCO,model=Model(), results=Dict()
            ) = new(data, gen_data, market_data, users_data, group_type, model, results)

    ModelEC(;
            data=Dict(), gen_data=Dict(), market_data=Dict(), users_data=Dict(),
            model=Model(), results=Dict()
            ) = new(data, gen_data, market_data, users_data, group_type, model, results)

    function ModelEC(file_name::AbstractString, group_type::GroupType)
        data = read_input(file_name)
        new(data, general(data), market(data), users(data), group_type)
    end

    function ModelEC(model_copy::ModelEC, group_type::GroupType)
        new(model_copy.data, model_copy.gen_data, model_copy.market_data, model_copy.users_data, group_type)
    end
end

"Build the non cooperative (NC) model"
function build_model!(ecmodel::AbstractEC, ::Union{GroupNC, GroupANC}; user_set::Vector = Vector())
    ecmodel.model_NC = build_model_NC(ecmodel.data)
    return ecmodel
end

"Build the cooperative EC (CO) model for a specific subset of user"
function build_model!(ecmodel::AbstractEC, ::GroupCO; user_set::Vector = Vector())
    ecmodel.model_EC = build_model_EC(ecmodel.data, user_set)
    return ecmodel
end

"Build cooperative (CO) and non-cooperative (NC) models for a specific subset of user"
function build_model!(ecmodel::AbstractEC, ec_models::Vector{<:GroupType}=GroupCONC; user_set::Vector = Vector())
    for ec_mod in ec_models
        build_model!(ecmodel, ec_mod, user_set=user_set)
    end
    return ecmodel
end

"Solve the non cooperative (NC) model"
function optimize_model!(ecmodel::AbstractEC, ::Union{GroupNC, GroupANC})
    optimize!(ecmodel.model_NC)
    ecmodel.results_NC = jump_to_dict(ecmodel.model_NC)
    return ecmodel
end

"Solve the cooperative EC (CO) model for a specific subset of user"
function optimize_model!(ecmodel::AbstractEC, ::GroupCO)
    optimize!(ecmodel.model_EC)
    ecmodel.results_EC = jump_to_dict(ecmodel.model_EC)
    return ecmodel
end

"Solve cooperative (CO) and non-cooperative (NC) models for a specific subset of user"
function optimize_model!(ecmodel::AbstractEC, ec_models::Vector{<:GroupType}=GroupCONC)
    for ec_mod in ec_models
        optimize_model!(ecmodel, ec_mod)
    end
    return ecmodel
end

"Function to save the model into a file"
function save_EC(ecmodel::AbstractEC, file_name::AbstractString)
    dict_ec = Dict("data"=> ecmodel.data, "NC"=>ecmodel.results_NC, "EC"=>ecmodel.results_EC)
    save(file_name, dict_ec)
end

"Function to load a saved model from a file"
function load_EC(file_name::AbstractString)
    dict_ec = load(file_name)
    data = dict_ec["data"]
    return ModelEC(data=data, gen_data=general(data), market_data=market(data), users_data=users(data),
                    results_NC=dict_ec["NC"], results_EC=dict_ec["EC"])
end


"Output results for the NC configuration"
function output_results(ecmodel::AbstractEC,
    output_file::AbstractString, output_file_plot::AbstractString,
    ::Union{GroupNC, GroupANC}; user_set::Vector = Vector())
    return output_results_NC(ecmodel.data, ecmodel.results_NC, 
            output_file, output_file_plot, user_set=user_set)
end

"Output results for the EC configuration"
function output_results(ecmodel::AbstractEC,
    output_file::AbstractString, output_file_plot::AbstractString,
    ::GroupCO; user_set::Vector = Vector())
    return output_results_EC(ecmodel.data, ecmodel.results_EC,
            output_file, output_file_plot, ecmodel.results_NC, user_set=user_set)
end