# Definition of aggregator code name
const EC_CODE = "EC"

# Type of grouping: Non Cooperative, Cooperative, Aggregated Non Cooperative
abstract type AbstractGroup end

# Abstract COoperative group
abstract type AbstractGroupCO <: AbstractGroup end
# Abstract Non-Cooperative group
abstract type AbstractGroupNC <: AbstractGroup end
# Abstract Aggregated Non-Cooperative
abstract type AbstractGroupANC <: AbstractGroup end

# Concrete structs
struct GroupCO <: AbstractGroupCO end
struct GroupNC <: AbstractGroupNC end
struct GroupANC <: AbstractGroupANC end

GroupAny = [GroupCO(), GroupANC(), GroupNC()]
GroupCONC = [GroupCO(), GroupNC()]

# definition of the name of the abstract model types
name(::AbstractGroup) = "Abstract Group Model"
name(::AbstractGroupCO) = "Abstract Cooperative Model"
name(::AbstractGroupNC) = "Abstract Non-Cooperative Model"
name(::AbstractGroupANC) = "Abstract Aggregating-Non-Cooperative Model"

# definition of the name of the concrete model types
name(::GroupCO) = "Cooperative Model"
name(::GroupNC) = "Non-Cooperative Model"
name(::GroupANC) = "Aggregating-Non-Cooperative Model"

function Base.string(GType::AbstractGroup)
    return name(GType)
end



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
    user_set = user_names(general(data), users(data))

    ModelEC(data=data, group_type=group_type, optimizer=optimizer, user_set=user_set)
end

"Copy constructor"
function ModelEC(model_copy::ModelEC, group_type=nothing; optimizer=nothing, user_set=nothing)
    if isnothing(group_type)
        group_type = model_copy.group_type
    end
    if isnothing(optimizer)
        optimizer = deepcopy(model_copy.optimizer)
    end
    if isnothing(user_set)
        user_set = model_copy.user_set
    end
    ModelEC(deepcopy(model_copy.data), group_type, optimizer, deepcopy(user_set))
end

"Copy of ModelEC"
function Base.copy(model_copy::ModelEC)
    ModelEC(model_copy.data, model_copy.group_type, model_copy.optimizer, deepcopy(model_copy.user_set))
end

"Deepcopy of ModelEC"
function Base.deepcopy(model_copy::ModelEC)
    ModelEC(deepcopy(model_copy.data), model_copy.group_type, model_copy.optimizer, deepcopy(model_copy.user_set))
end

"""Function zero to represent the empty ModelEC"""
function Base.zero(::ModelEC)
    return ModelEC()
end


"""
    name(model::AbstractEC)

Return the name of the model.
"""
name(model::AbstractEC) = "An Abstract Energy Community Model"


"""
    name(model::ModelEC)

Return the name of the model.
"""
name(model::ModelEC) = "An Energy Community Model"


"""
    _print_summary(io::IO, model::AbstractEC)

Print a plain-text summary of `model` to `io`.
"""
function _print_summary(io::IO, model::AbstractEC)
    println(io, name(model))
    println(io, "Energy Community problem for a " * name(get_group_type(model)))
    println(io, "User set: " * string(model.user_set))
    if isempty(model.results)
        println("Model not optimized")
    else
        println("Solved model")
    end
    return
end

function Base.summary(io::IO, ECModel::AbstractEC)
    _print_summary(io, ECModel)
end

function Base.print(io::IO, ECModel::AbstractEC)
    _print_summary(io, ECModel)
end

function Base.show(io::IO, ECModel::AbstractEC)
    _print_summary(io, ECModel)
end