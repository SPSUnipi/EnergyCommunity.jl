# Definition of aggregator code name
const EC_CODE = "EC"

# Type of grouping: Non Cooperative, Cooperative, Aggregated Non Cooperative
"""
    AbstractGroup

Abstract type for the group model; it is the parent of the three types of group models: Cooperative, Non-Cooperative, and Aggregated Non-Cooperative.
"""
abstract type AbstractGroup end

# Abstract COoperative group
abstract type AbstractGroupCO <: AbstractGroup end
# Abstract Non-Cooperative group
abstract type AbstractGroupNC <: AbstractGroup end
# Abstract Aggregated Non-Cooperative
abstract type AbstractGroupANC <: AbstractGroup end

# Concrete structs
"""
    GroupCO <: AbstractGroupCO

Concrete type for the Cooperative group model.
"""
struct GroupCO <: AbstractGroupCO end

"""
    GroupNC <: AbstractGroupNC

Concrete type for the Non-Cooperative group model.
"""
struct GroupNC <: AbstractGroupNC end
    
"""
    GroupANC <: AbstractGroupANC

Concrete type for the Aggregated Non-Cooperative group model.
"""
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


"""
    AbstractEC

Abstract type for an EnergyCommunity model.
"""
abstract type AbstractEC end

# constant empty dictionary for an empty EnergyCommunity model
const ZERO_DD = Dict("general"=>Dict(), "users"=>Dict(), "market"=>Dict())



"""
    check_valid_data_dict(raw_dict_data::Dict)

Check whether the dictionary data has the needed components.
The dictionary must have the keys "general", "users", and "market".
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


"""
    ModelEC <: AbstractEC

Concrete type for an EnergyCommunity model.

## Attributes

* `data::Dict`: All data
* `gen_data::Dict`: general data
* `market_data::Dict`: market data
* `users_data::Dict`: users data
* `group_type`: aggregation type of model
* `user_set::Vector`: desired user set
* `model::Model`: JuMP model
* `optimizer`: optimizer of the JuMP model
* `results::Dict`: results of the model in Dictionary format
"""
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


"""
    ModelEC(data::Dict=ZERO_DD, group_type=GroupNC(), optimizer=nothing, user_set::Vector=Vector())

Constructor of a ModelEC.

## Arguments

* `data::Dict=ZERO_DD`: All data; a dictionary with the keys "general", "users", and "market"
* `group_type`: aggregation type of model
* `optimizer`: optimizer of the JuMP model
* `user_set::Vector`: desired user set
"""
function ModelEC(
    data::Dict=ZERO_DD,
    group_type=GroupNC(),
    optimizer=nothing,
    user_set::Vector=Vector(),
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

"""
    ModelEC(file_name::AbstractString, group_type, optimizer=nothing)

Load EnergyCommunity model from disk

## Arguments

* `file_name::AbstractString`: name of the file to load the data
* `group_type`: aggregation type of model
* `optimizer`: optimizer of the JuMP model
"""
function ModelEC(file_name::AbstractString,
        group_type,
        optimizer=nothing
    )
    data = read_input(file_name)
    user_set = user_names(general(data), users(data))

    ModelEC(data, group_type, optimizer, user_set)
end

"""
    ModelEC(model_copy::ModelEC, group_type=nothing, optimizer=nothing, user_set=nothing)

Copy constructor; it copies the data from `model_copy` and changes the group type, optimizer, and user set if specified.

## Arguments

* `model_copy::ModelEC`: model to copy
* `group_type=nothing`: aggregation type of model; default is the same as `model_copy`
* `optimizer=nothing`: optimizer of the JuMP model; default is the same as `model_copy`
* `user_set=nothing`: desired user set; default is the same as `model_copy`
"""
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

"""
    Base.copy(model_copy::ModelEC)

Create a copy of a ModelEC opject

## Arguments

* `model_copy::ModelEC`: model to copy
"""
function Base.copy(model_copy::ModelEC)
    ModelEC(model_copy.data, model_copy.group_type, model_copy.optimizer, deepcopy(model_copy.user_set))
end

"""
    Base.deepcopy(model_copy::ModelEC)

Create a deepcopy of a ModelEC opject

## Arguments

* `model_copy::ModelEC`: model to copy
"""
function Base.deepcopy(model_copy::ModelEC)
    ModelEC(deepcopy(model_copy.data), model_copy.group_type, model_copy.optimizer, deepcopy(model_copy.user_set))
end

"""
    Base.zero(::ModelEC)

Function zero to represent the empty ModelEC
"""
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