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
    StochasticEC <: AbstractEC

Concrete type for an EnergyCommunity stochastic model.

## Attributes

* `data::Dict`: All data
* `gen_data::Dict`: general data
* `market_data::Dict`: market data
* `users_data::Dict`: users data
* `group_type`: aggregation type of model
* `user_set::Vector`: desired user set
* `model::StochasticProgram`: stochastic model
* `optimizer`: optimizer of the JuMP model
* `results::Dict`: results of the model in Dictionary format
* `scenarios::Vector{Scenario_Load_Renewable}`: scenarios used to optimize the model
* `n_scen_s::Int`: number of long-term scenarios
* `n_scen_eps::Int`: number of short-term scenarios
"""
mutable struct StochasticEC <: AbstractEC
    data::Dict  # All data
    gen_data::Dict  # general data
    market_data::Dict  # market data
    users_data::Dict  # users data

    group_type  # aggregation type of model
    user_set::Vector  # desired user set

    model::StochasticProgram  # stochastic model
    deterministic_model :: Model # deterministic equivalent model (JuMP)
    optimizer  # optimizer of the JuMP model

    results::Dict  # results of the model in Dictionary format
    scenarios::Vector{Scenario_Load_Renewable}  # scenarios used to optimize the model
    n_scen_s::Int  # number of long-term scenarios
    n_scen_eps::Int  # number of short-term scenarios
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
    StochasticEC(data::Dict=ZERO_DD, group_type=GroupNC(),
                 optimizer=nothing, user_set::Vector=Vector(),
                 scenarios=[zero(Scenario_Load_Renewable)],
                 n_scen_s::Int=1, n_scen_eps::Int=1)

Constructor for the stochastic EnergyCommunity model.
"""
function StochasticEC(
    data::Dict=ZERO_DD,
    group_type=GroupNC(),
    optimizer=nothing,
    user_set::Vector=Vector(),
    scenarios::Vector{Scenario_Load_Renewable}=[zero(Scenario_Load_Renewable)],
    n_scen_s::Int=1,
    n_scen_eps::Int=1,
)
    check_valid_data_dict(data)
    gen_data, users_data, market_data = explode_data(data)

    if isempty(user_set)
        user_set = user_names(gen_data, users_data)
    end

    model = StochasticProgram(scenarios, Deterministic())
    deterministic_model = Model() # TODO fix function calls in order to manage deterministic equivalent

    results = Dict()

    if isnothing(optimizer)
        println("WARNING: Optimizer of the EnergyCommunity model not specified")
    end

    return StochasticEC(
        data, gen_data, market_data, users_data,
        group_type, user_set,
        model,
        deterministic_model,
        optimizer,
        results, scenarios, n_scen_s, n_scen_eps
    )
end

"""
    StochasticEC(base::ModelEC,
                 scenarios::Vector{Scenario_Load_Renewable}=[zero(Scenario_Load_Renewable)],
                 n_scen_s::Int=1, n_scen_eps::Int=1)

Constructor for the stochastic EnergyCommunity model given an already defined base model.
"""
function StochasticEC(
    base::ModelEC,
    scenarios::Vector{Scenario_Load_Renewable}=[zero(Scenario_Load_Renewable)],
    n_scen_s::Int=1,
    n_scen_eps::Int=1,
)
    # Build stochastic program
    stoch_model = StochasticProgram(scenarios, Deterministic())

    # Costruisci la nuova struct passando tutti i campi di base + quelli stocastici
    return StochasticEC(
        base.data, base.gen_data, base.market_data, base.users_data,
        base.group_type, base.user_set,
        stoch_model, base.optimizer,
        base.results, scenarios, n_scen_s, n_scen_eps
    )
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
    StochasticEC(file_name::AbstractString, group_type, optimizer=nothing,
                scenarios=[zero(Scenario_Load_Renewable)],
                n_scen_s::Int=1, n_scen_eps::Int=1)

Load EnergyCommunity stochastic model from disk

## Arguments

* `file_name::AbstractString`: name of the file to load the data
* `group_type`: aggregation type of model
* `optimizer`: optimizer of the JuMP model
* `scenarios::Vector{Scenario_Load_Renewable}`: scenarios used to optimize the model
* `n_scen_s::Int`: number of long-term scenarios
* `n_scen_eps::Int`: number of short-term scenarios
"""
function StochasticEC(file_name::AbstractString,
        group_type,
        optimizer=nothing,
        scenarios::Array{Scenario_Load_Renewable, 1}=[zero(Scenario_Load_Renewable)],
        n_scen_s::Int=1,
        n_scen_eps::Int=1
    )

    data = read_input(file_name)
    user_set = user_names(general(data), users(data))

    StochasticEC(data, group_type, optimizer, user_set, scenarios, n_scen_s, n_scen_eps)
end

"""
    ModelEC(model_copy::ModelEC, group_type=nothing; optimizer=nothing, user_set=nothing)

Copy constructor; it copies the data from `model_copy` and changes the group type, optimizer, and user set if specified.
Uses accessor functions for dynamic dispatch compatibility.

## Arguments

* `model_copy::ModelEC`: model to copy
* `group_type=nothing`: aggregation type of model; default is the same as `model_copy`
* `optimizer=nothing`: optimizer of the JuMP model; default is the same as `model_copy`
* `user_set=nothing`: desired user set; default is the same as `model_copy`
"""
function ModelEC(model_copy::ModelEC, new_group_type=nothing; optimizer=nothing, user_set=nothing)
    gt = isnothing(new_group_type) ? group_type(model_copy) : new_group_type
    opt = isnothing(optimizer) ? deepcopy(optimizer(model_copy)) : optimizer
    us = isnothing(user_set) ? user_set(model_copy) : user_set

    ModelEC(deepcopy(data(model_copy)), gt, opt, deepcopy(us))
end

"""
    StochasticEC(model_copy::StochasticEC, group_type=nothing; optimizer=nothing, user_set=nothing,
                scenarios=nothing, n_scen_s_val=nothing, n_scen_eps_val=nothing)

Copy constructor of stochastic model.

## Arguments

* `model_copy::StochasticEC`: model to copy
* `group_type=nothing`: aggregation type of model; default is the same as `model_copy`
* `optimizer=nothing`: optimizer of the JuMP model; default is the same as `model_copy`
* `user_set=nothing`: desired user set; default is the same as `model_copy`
* `scenarios=nothing`: desired scenarios set; default is the same as `model_copy`
* `n_scen_s_val::Int`: desired number of long-term scenarios; default is the same as `model_copy`
* `n_scen_eps_val::Int`: desired number of short-term scenarios; default is the same as `model_copy`
"""
function StochasticEC(model_copy::StochasticEC, new_group_type=nothing; optimizer=nothing, user_set=nothing, scenarios=nothing, n_scen_s_val=nothing, n_scen_eps_val=nothing)

    # Use accessor functions for all fields
    gt = isnothing(new_group_type) ? group_type(model_copy) : new_group_type
    opt = isnothing(optimizer) ? deepcopy(optimizer(model_copy)) : optimizer
    us = isnothing(user_set) ? user_set(model_copy) : user_set
    scen = isnothing(scenarios) ? scenarios(model_copy) : scenarios
    ns = isnothing(n_scen_s_val) ? n_scen_s(model_copy) : n_scen_s_val
    neps = isnothing(n_scen_eps_val) ? n_scen_eps(model_copy) : n_scen_eps_val

    StochasticEC(
        deepcopy(data(model_copy)), deepcopy(gen_data(model_copy)), deepcopy(market_data(model_copy)), deepcopy(users_data(model_copy)),
        gt, deepcopy(us),
        jump_model(model_copy), opt,
        deepcopy(results(model_copy)), scen, ns, neps
    )
end

#==============================================================================
# COPY WITH MODIFICATIONS - Generic function for both types
==============================================================================#

"""
    copy_with(model::AbstractEC; group_type=nothing, optimizer=nothing,
              user_set=nothing, scenarios=nothing, n_scen_s_val=nothing, n_scen_eps_val=nothing)

Create a copy of the model with optional field modifications.
Dynamic dispatch handles ModelEC vs StochasticEC automatically.
Note: For StochasticEC, the additional parameters are available; for ModelEC they are ignored.

## Examples
```julia
# For ModelEC
new_model = copy_with(model, group_type=GroupCO())

# For StochasticEC
new_model = copy_with(stoch_model, group_type=GroupCO(), n_scen_s_val=10)
```
"""
function copy_with(model::ModelEC; group_type=nothing, optimizer=nothing, user_set=nothing, kwargs...)
    new_group_type = isnothing(group_type) ? group_type(model) : group_type
    new_optimizer = isnothing(optimizer) ? deepcopy(optimizer(model)) : optimizer
    new_user_set = isnothing(user_set) ? user_set(model) : user_set

    ModelEC(deepcopy(data(model)), new_group_type, new_optimizer, deepcopy(new_user_set))
end

function copy_with(model::StochasticEC;
                   group_type=nothing, optimizer=nothing, user_set=nothing,
                   scenarios=nothing, n_scen_s_val=nothing, n_scen_eps_val=nothing)
    new_group_type = isnothing(group_type) ? group_type(model) : group_type
    new_optimizer = isnothing(optimizer) ? deepcopy(optimizer(model)) : optimizer
    new_user_set = isnothing(user_set) ? user_set(model) : user_set
    new_scenarios = isnothing(scenarios) ? scenarios(model) : scenarios
    new_n_scen_s = isnothing(n_scen_s_val) ? n_scen_s(model) : n_scen_s_val
    new_n_scen_eps = isnothing(n_scen_eps_val) ? n_scen_eps(model) : n_scen_eps_val

    StochasticEC(
        deepcopy(data(model)), deepcopy(gen_data(model)), deepcopy(market_data(model)), deepcopy(users_data(model)),
        new_group_type, deepcopy(new_user_set),
        jump_model(model), new_optimizer,
        deepcopy(results(model)), new_scenarios, new_n_scen_s, new_n_scen_eps
    )
end


#==============================================================================
# BASE INTERFACE FUNCTIONS - copy, deepcopy, zero
==============================================================================#

"""
    Base.copy(model::AbstractEC)

Create a shallow copy of the model (dynamic dispatch).
"""
function Base.copy(model::ModelEC)
    ModelEC(data(model), group_type(model), optimizer(model), deepcopy(user_set(model)))
end

function Base.copy(model::StochasticEC)
    StochasticEC(
        data(model), gen_data(model), market_data(model), users_data(model),
        group_type(model), user_set(model),
        jump_model(model), optimizer(model),
        results(model), scenarios(model), n_scen_s(model), n_scen_eps(model)
    )
end

"""
    Base.deepcopy(model::AbstractEC)

Create a deep copy of the model (dynamic dispatch).
"""
function Base.deepcopy(model::ModelEC)
    ModelEC(deepcopy(data(model)), group_type(model), optimizer(model), deepcopy(user_set(model)))
end

function Base.deepcopy(model::StochasticEC)
    StochasticEC(
        deepcopy(data(model)), deepcopy(gen_data(model)), deepcopy(market_data(model)), deepcopy(users_data(model)),
        group_type(model), deepcopy(user_set(model)),
        jump_model(model), optimizer(model),
        deepcopy(results(model)), scenarios(model), n_scen_s(model), n_scen_eps(model)
    )
end

"""
    Base.zero(::Type{<:AbstractEC})
    Base.zero(::AbstractEC)

Return an empty model of the specified type (dynamic dispatch).
"""
Base.zero(::Type{ModelEC}) = ModelEC()
Base.zero(::Type{StochasticEC}) = StochasticEC()
Base.zero(::ModelEC) = ModelEC()
Base.zero(::StochasticEC) = StochasticEC()


"""
    name(model::AbstractEC)

Return the name/description of the model type (dynamic dispatch).
"""
name(::Type{AbstractEC}) = "An Abstract Energy Community Model"
name(::Type{ModelEC}) = "An Energy Community Model"
name(::Type{StochasticEC}) = "An Energy Community Stochastic Model"
name(model::AbstractEC) = name(typeof(model))


"""
    _print_summary(io::IO, model::AbstractEC)

Print a plain-text summary of `model` to `io` using accessor functions (dynamic dispatch).
"""
function _print_summary(io::IO, model::AbstractEC)
    println(io, name(model))
    println(io, "Energy Community problem for a " * name(get_group_type(model)))
    println(io, "User set: " * string(user_set(model)))

    if model isa StochasticEC
        println(io, "Number of scenarios s: " * string(n_scen_s(model)))
        println(io, "Number of scenarios epsilon: " * string(n_scen_eps(model)))
    end

    if isempty(results(model))
        println(io, "Model not optimized")
    else
        println(io, "Solved model")
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