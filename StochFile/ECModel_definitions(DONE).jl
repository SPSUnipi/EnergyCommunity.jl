# Definition of aggregator code name
const EC_CODE = "EC"

# Type of grouping: Non Cooperative, Cooperative
abstract type AbstractGroup end

# Abstract COoperative group
abstract type AbstractGroupCO <: AbstractGroup end
# Abstract Non-Cooperative group
abstract type AbstractGroupNC <: AbstractGroup end

# Concrete structs
struct GroupCO <: AbstractGroupCO end
struct GroupNC <: AbstractGroupNC end

GroupCONC = [GroupCO(), GroupNC()]

# definition of the name of the abstract model types
name(::AbstractGroup) = "Abstract Group Model"
name(::AbstractGroupCO) = "Abstract Cooperative Model"
name(::AbstractGroupNC) = "Abstract Non-Cooperative Model"

# definition of the name of the concrete model types
name(::GroupCO) = "Cooperative Model"
name(::GroupNC) = "Non-Cooperative Model"

# new definition of the Base.string function for an abstract model
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

    model::StochasticProgram  # Stochastic model
    deterministic_model::Model # Deterministic equivalent version of model
    optimizer  # optimizer of the JuMP model
    
    scenarios # scenarios used to optimize the model
    n_scen_s::Int # number of scenario s
    n_scen_eps::Int # number of scenario eps

    results::Dict  # results of the model in Dictionary format
end


"""
Constructor of a ModelEC
Inputs
------
data : Dict 
    Data of the EC
group_type : AbstractGroup
    Type of EC
optimizer
    Optimizer of the model
user_set : Vector
    Vector of the users
"""
function ModelEC(
    data::Dict=ZERO_DD,
    group_type=GroupNC(),
    optimizer=nothing,
    user_set::Vector=Vector(),
    scenarios::Array{Scenario_Load_Renewable, 1}=[zero(Scenario_Load_Renewable)],
    n_scen_s::Int=1,
    n_scen_eps::Int=1
    )
    check_valid_data_dict(data)
    gen_data, users_data, market_data = explode_data(data)

    if isempty(user_set)
        user_set = user_names(gen_data, users_data)
    end
    model = StochasticProgram(scenarios, Deterministic())
    results=Dict()

    if isnothing(optimizer)
        deterministic_model = Model()
        println("WARNING: Optimizer of the EnergyCommunity model not specified")
    else
        deterministic_model = direct_model(optimizer())
    end

    ModelEC(data, gen_data, market_data, users_data, group_type, user_set, model, deterministic_model, optimizer, scenarios, n_scen_s, n_scen_eps, results)
end

# function ModelEC(;
#     data::Dict,
#     group_type,
#     optimizer=nothing,
#     user_set::Vector=Vector()
# )

#     ModelEC(data, group_type, optimizer, user_set)
# end

"""
Load Model from disk
file_name : str
    Filename
"""
function ModelEC(file_name::AbstractString,
        group_type,
        optimizer=nothing,
        scenarios::Array{Scenario_Load_Renewable, 1}=[zero(Scenario_Load_Renewable)],
        n_scen_s::Int=1,
        n_scen_eps::Int=1
    )

    data = read_input(file_name)
    gen_data, users_data, market_data = explode_data(data)

    
    user_set = user_names(gen_data, users_data)

    ModelEC(data, group_type, optimizer, user_set, scenarios, n_scen_s, n_scen_eps)
end

"Copy constructor"
function ModelEC(model_copy::ModelEC, group_type=nothing; optimizer=nothing, user_set=nothing, scenarios=nothing, n_scen_s=nothing, n_scen_eps=nothing)
    if isnothing(group_type)
        group_type = model_copy.group_type
    end
    if isnothing(optimizer)
        optimizer = deepcopy(model_copy.optimizer)
    end
    if isnothing(user_set)
        user_set = model_copy.user_set
    end
    if isnothing(scenarios)
        scenarios = model_copy.scenarios
    end
    if isnothing(n_scen_s)
        n_scen_s = model.n_scen_s
    end
    if isnothing(n_scen_eps)
        n_scen_eps = model.n_scen_eps
    end
    ModelEC(deepcopy(model_copy.data), group_type, optimizer, deepcopy(user_set),scenarios,n_scen_s,n_scen_eps)
end

"Copy of ModelEC"
function Base.copy(model_copy::ModelEC)
    ModelEC(model_copy.data, model_copy.group_type, model_copy.optimizer, deepcopy(model_copy.user_set),model_copy.scenarios,model_copy.n_scen_s,model_copy.n_scen_eps)
end

"Deepcopy of ModelEC"
function Base.deepcopy(model_copy::ModelEC)
    ModelEC(deepcopy(model_copy.data), model_copy.group_type, model_copy.optimizer, deepcopy(model_copy.user_set), model_copy.scenarios, model_copy.n_scen_s, model_copy.n_scen_eps)
end

"""Function zero to represent the empty ModelEC"""
function Base.zero(::ModelEC)
    return ModelEC()
end


"""
    name(model::AbstractEC)
Return the name of the model.
"""
name(model::AbstractEC) = "An Abstract Energy Community Stochastic Model"


"""
    name(model::ModelEC)
Return the name of the model.
"""
name(model::ModelEC) = "An Energy Community Stochastic Model"


"""
    _print_summary(io::IO, model::AbstractEC)
Print a plain-text summary of `model` to `io`.
"""
function _print_summary(io::IO, model::AbstractEC)
    println(io, name(model))
    println(io, "Energy Community problem for a " * name(get_group_type(model)))
    println(io, "Number of scenarios s: " * string(model.n_scen_s))
    println(io, "Number of scenarios epsilon: " * string(model.n_scen_eps))
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

function get_group_type(ECModel::AbstractEC)
    ECModel.group_type
end

function is_optimized(ECModel::AbstractEC)
    if isempty(ECModel.results)
        error("Model " * name(ECModel) * " not optimized")
    end
end