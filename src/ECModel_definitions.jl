# Definition of aggregator code name
const EC_CODE = "EC"

# Type of grouping: Non Cooperative, Cooperative, Aggregated Non Cooperative
abstract type AbstractGroup end

# Abstract COoperative group
abstract type AbstractGroupCO <: AbstractGroup end
# Abstract Non-Cooperative group
abstract type AbstractGroupNC <: AbstractGroup end
# Abstract Aggregated Non-Cooperative
abstract type AbstractGroupANC <: AbstractGroupNC end

# Concrete structs
struct GroupCO <: AbstractGroupCO end
struct GroupANC <: AbstractGroupANC end
struct GroupNC <: AbstractGroupNC end

GroupAny = [GroupCO(), GroupANC(), GroupNC()]
GroupCONC = [GroupCO(), GroupNC()]

abstract type AbstractEC end

# constant empty dictionary for an empty EnergyCommunity model
const ZERO_DD = Dict("general"=>Dict(), "users"=>Dict(), "market"=>Dict())



"""

Check whether the dictionary data has the needed components
"""
function check_valid_data_dict(raw_dict_data::Dict)
    # check if file contains the data of the ECModel
    for k_val in ["general", "users", "market"]
        if k_val ∉ keys(raw_dict_data)
            throw(ArgumentError("Data dictionary not a valid input for ECModel"))
            return false
        end
    end
    return true
end


"Structure encapsuling the data"
mutable struct ModelEC <: AbstractEC

    data::Dict  # All data
    gen_data::Dict  # general data
    market_data::Dict  # market data
    users_data::Dict  # users data

    group_type  # aggregation type of model
    user_set::Vector  # desired user set

    model::Model  # JuMP model
    optimizer  # optimizer of the JuMP model

    results::Dict  # results of the model in Dictionary format
end



function ModelEC(
    data::Dict=ZERO_DD,
    group_type=GroupNC(),
    optimizer=nothing,
    user_set::Vector=Vector()
)
    check_valid_data_dict(data)
    gen_data, users_data, market_data = explode_data(data)

    if isempty(user_set)
        user_set = user_names(gen_data, users_data)
    end
    model=Model()
    results=Dict()

    if isnothing(optimizer)
        println("WARNING: Optimizer of the EnergyCommunity model not specified")
    end

    ModelEC(data, gen_data, market_data, users_data, group_type, user_set, model, optimizer, results)
end


function ModelEC(;
    data::Dict,
    group_type,
    optimizer=nothing,
    user_set::Vector=Vector()
)

    ModelEC(data, group_type, optimizer, user_set)
end

"""
Load Model from disk

file_name : str
    Filename
"""
function ModelEC(file_name::AbstractString,
        group_type,
        optimizer=nothing
    )
    data = read_input(file_name)

    ModelEC(data=data, group_type=group_type, optimizer=optimizer)
end

"Copy constructor"
function ModelEC(model_copy::ModelEC, group_type, optimizer=nothing)
    if isnothing(optimizer)
        optimizer = deepcopy(model_copy.optimizer)
    end
    ModelEC(deepcopy(model_copy.data), group_type, optimizer, deepcopy(model_copy.user_set))
end

"Copy of ModelEC"
function Base.copy(model_copy::ModelEC)
    ModelEC(model_copy.data, model_copy.group_type, model_copy.optimizer, deepcopy(model_copy.user_set))
end

"Deepcopy of ModelEC"
function Base.deepcopy(model_copy::ModelEC)
    ModelEC(deepcopy(model_copy.data), model_copy.group_type, deepcopy(user_set), model_copy.optimizer)
end

"""Function zero to represent the empty ModelEC"""
function Base.zero(::ModelEC)
    return ModelEC()
end