"""
    @enum ASSET_TYPE

Enumeration type to specify the type of the assets.
Implemented values:
- LOAD: load type
- T_LOAD: thermal load
- REN: renewable assets
- CONV: battery converters
- THER: thermal generators
- TES: thermal energy storage component
- BATT: battery component
- HP: heat pump
- BOIL: boiler
"""

@enum ASSET_TYPE LOAD=0 T_LOAD=1 REN=2 BATT=3 CONV=4 THER=5 LOAD_ADJ=6 TES=7 HP=8 BOIL=9
ANY = collect(instances(ASSET_TYPE))  # all assets code
GENS = [REN, THER]  # generator codes
LOADS = [LOAD, LOAD_ADJ, T_LOAD]  # load codes
DEVICES = setdiff(ANY, LOADS)  # devices codes

type_codes = Base.Dict(
    "renewable"=>REN,
    "converter"=>CONV,
    "t_load"=>T_LOAD,
    "load"=>LOAD,
    "thermal"=>THER,
    "battery"=>BATT,
    "storage"=>TES,
    "heat_pump"=>HP,
    "boiler"=>BOIL,
    "load_adj"=>LOAD_ADJ,
)

# Get the previous time step, with circular time step
@inline pre(time_step::Int, gen_data::Dict) = if (time_step > field(gen_data, "init_step")) time_step-1 else field(gen_data, "final_step") end
@inline pre(time_step::V, time_set::UnitRange{V}) where{V <: Int} = if (time_step > time_set[1]) time_step-1 else time_set[end] end


"Function to safely get a field of a dictionary with default value"
@inline field_d(d::AbstractDict, field, default=nothing) = (field in keys(d) ? d[field] : default)
@inline field_i(d, field) = field_d(d, field, 0)
@inline field_f(d, field) = field_d(d, field, 0.0)
"Function get field that throws an error if the field is not found"
@inline function field(d::AbstractDict, field, desc=nothing)
    if field in keys(d)
        return d[field]
    else
        msg = isnothing(desc) ? "Field $field not found in dictionary $(keys(d))" : desc
        throw(KeyError(msg))
    end
end

"Function to get the general parameters"
general(d::AbstractDict) = field(d, "general")
"Function to get the users configuration"
users(d::AbstractDict) = field(d, "users")
"Function to get the market configuration"
market(d::AbstractDict) = field(d, "market")
"Function to get the profile dictionary"
profiles(d::AbstractDict) = field_d(d, "profile")
"Auxiliary function to check if the key 'type' is available in the dictionary d, otherwise false"
has_type(d::AbstractDict) = ("type" in keys(d))
has_type(d) = false  # if d is not an abstract dictionary, then return false
"Function to get the components list of a dictionary"
function components(d::AbstractDict)
    return Dict(k=>v for (k,v) in d if has_type(v))
end
"Function to get the components value of a dictionary"
component(d, c_name) = field(components(d), c_name)
"Function to get the components value of a dictionary"
field_component(d, c_name, f_name) = field(component(d, c_name), f_name)
"Function to get the components value of a dictionary, with default value"
field_component(d, c_name, f_name, default) = field_d(component(d, c_name), f_name, default)
"Function to know if a dictionary has a particular component"
has_component(d, c_name, f_name) = haskey(component(d, c_name), f_name)
"Function to get a specific profile"
function profile(d, profile_name)
    profile_block = profiles(d)
    return field(profile_block, profile_name)
end
"Function to get a specific profile"
function profile_component(d, c_name, profile_name)
    profile_block = profiles(component(d, c_name))
    return field(profile_block, profile_name)
end

"Function to get the asset type of a component"
asset_type(d, comp_name) = type_codes[field(component(d, comp_name), "type")]

"Function to get the list of the assets for a user"
function asset_names(d, a_type::ASSET_TYPE)
    comps = components(d)
    return [at for at in keys(comps) 
        if asset_type(comps, at) == a_type]
end

"Function to get the list of the assets for a user"
asset_names(d) = collect(keys(components(d)))

"Function to get the list of the assets for a user in a list of elements"
function asset_names(d, a_types::Vector{ASSET_TYPE})
    comps = components(d)
    return [at for at in keys(comps) 
        if asset_type(comps, at) ∈ a_types]
end

"Function to get the list of the assets for a user in a list of elements except a list of given types"
function asset_names_ex(d, ex::Vector{ASSET_TYPE})
    comps = components(d)
    accepted_types = setdiff(ANY, ex)
    return asset_names(d, accepted_types)
end

"Function to get the list of devices for a user"
device_names(d) = asset_names(d, DEVICES)

"Function to get the list of generators for a user"
generator_names(d) = asset_names(d, GENS)

"Function to check whether an user has any asset"
has_any_asset(d, a_types::Vector{ASSET_TYPE}=DEVICES) = !isempty(asset_names(d, a_types))

"Function to check whether an user has any asset different from the provided ones"
has_any_different_asset(d, ex::Vector{ASSET_TYPE}) = !isempty(asset_names_ex(d, ex))

"Function to check whether an user has an asset type"
has_asset(d, atype::ASSET_TYPE) = !isempty(asset_names(d, atype))

"Function to check whether an user has an asset given its name"
has_asset(d, aname::AbstractString) = aname in keys(d)


"Get the list of users"
function user_names(gen_data, users_data)
    # get the list of users if set
    user_set = field_d(gen_data, "user_set")
    if isnothing(user_set)
        @info "List of users not specified: all users selected"
        user_set = collect(keys(users_data))
    elseif isempty(user_set)
        throw(ErrorException("Input user list is empty"))
    elseif !(user_set isa AbstractVector)
        throw(ErrorException("Input user list is not a vector"))
    end
    return sort!(user_set)
end


"""
Function to parse a string value of a profile to load the corresponding dataframe
"""
function parse_dataprofile(gen_config, data, profile_name, profile_value::AbstractString)
    
    # initial time step
    init_step = gen_config["init_step"]
    # final time step
    final_step = gen_config["final_step"]

    if profile_value in names(data)
        return data[init_step:final_step, profile_value]
    else
        throw(KeyError("Profile name $profile_value not found in available dataframes"))
    end
end

"""
Function to parse a string value of a profile to load the corresponding dataframe
"""
function parse_dataprofile(gen_config, data, profile_name, profile_value::AbstractVector{T}) where T <: Real

    # initial time step
    init_step = gen_config["init_step"]
    @assert init_step isa Integer "Parameter init_step in configuration is not an Int for profile $profile_name"
    # check init_step value
    @assert init_step >= 1 "Parameter init_step shall be non-negative for profile $profile_name"

    # final time step
    final_step = gen_config["final_step"]
    # check final_step type
    @assert final_step isa Integer "Parameter final_step in configuration is not an Int for profile $profile_name"
    # check final_step value
    @assert length(profile_value) >= final_step "Parameter final_step shall be no larger than the length of profile $profile_name"
    
    return profile_value[init_step:final_step]
end

"""
Function to parse a personalized processing to generate the data
When profile_value is a dictionary, then the user is asking a custom processing of data by a function
"""
function parse_dataprofile(gen_config, data, profile_name, profile_value::Dict)

    func_name = field(profile_value, "function")
    inputs = field(profile_value, "inputs")

    # load input data for the function
    input_data = []
    for i_data in inputs
        push!(input_data, parse_dataprofile(gen_config, data, profile_name * " inputs", i_data))
    end

    # prepare the execution of the function
    cmd_expr = Expr(:call, Symbol(func_name), gen_config, data, profile_name, input_data...)
    
    # execute the function
    ret_value = eval(cmd_expr)
    
    return ret_value
end


"""
Function to parse a string value of a profile to load the corresponding dataframe
"""
function parse_dataprofile(gen_config, data, profile_name, profile_value::T) where T <: Real

    n_steps = gen_config["final_step"] - gen_config["init_step"] + 1
    
    return fill(convert(Float64, profile_value), n_steps)
end

"""
Function to throw error for unformatted data
"""
function parse_dataprofile(gen_config, data, profile_name, profile_value::Any)
    @error "Data descriptor for $profile_name not accepted"
end

"""
Function to read the input of the optimization model described as a yaml file
"""
function read_input(file_name::AbstractString)

    # convert file_name to absolute path
    file_name = abspath(file_name)

    # load YAML file
    data = YAML.load_file(file_name)

    gen_data = general(data)

    # optional data by csv files
    opt_data = DataFrame()
    opt_files = field(gen_data, "optional_datasets")
    if !isnothing(opt_files)  # datasets are available
        for f_name in opt_files
            # get absolute path of f_name
            abs_file_name = (isabspath(f_name) ? f_name : joinpath(dirname(file_name), f_name))
            # read dataset and join to the original dataset
            d = CSV.read(abs_file_name, DataFrame)
            if isempty(opt_data)
                opt_data = d
            else
                opt_data = innerjoin(opt_data, d, on = "time")
            end
        end
    end

    # process main fields of the assets to populate the dictionary with all filled data
    market_data = market(data)
    users_data = users(data)

    function change_profile!(d_dict, data_profiles)
        profile_dict = profiles(d_dict)
        if !isnothing(profile_dict) && length(profile_dict) > 0
            for p_name in keys(profile_dict)
                profile_dict[p_name] = parse_dataprofile(gen_data, opt_data, p_name, profile_dict[p_name])
            end
        end
    end

    change_profile!(gen_data,opt_data)

    for c_name in keys(market_data)
        change_profile!(market_data[c_name], opt_data)
    end

    for u_name in keys(users_data)
        comp_dict = components(users_data[u_name])
        if !isnothing(comp_dict)
            for c_name in keys(comp_dict)
                change_profile!(comp_dict[c_name], opt_data)
            end
        end
    end
    
    return data
end

"Return main data elements of the dataset: general parameters, users data and market data"
function explode_data(data)
    return general(data), users(data), market(data)
end

parse_to_float(x::AbstractString) = parse(Float64, x)
parse_to_float(x::Any) = Float64(x)


"Function to parse the peak power categories and tariff"
function parse_peak_quantity_by_time_vectors(gen_config, data, profile_name, peak_categories, peak_tariffs)
    # initialization of output dictionary
    peak_tariffs_by_category = Dict{String, Float64}()

    for (p_cat, t_value) in zip(peak_categories, peak_tariffs)
        if p_cat ∈ keys(peak_tariffs_by_category) &&
            peak_tariffs_by_category[p_cat] != t_value
            throw(ErrorException("Peak tariff category $p_cat corresponds multiple prices (e.g. $t_value and $(peak_tariffs_by_category[p_cat])"))
        elseif p_cat ∉ keys(peak_tariffs_by_category)
            peak_tariffs_by_category[p_cat] = parse_to_float(t_value)
        end
    end

    return peak_tariffs_by_category
end


"""
    _jump_to_dict

Function to turn a JuMP model to a dictionary.
If the stochastich flag is set, only relevant quantities are inserted into the dictionary.
"""
function _jump_to_dict(model::Model, stoch_flag = 0)
    results = Dict{Symbol, Any}()

    # push the information on the optimization status
    results[:solve_time]  = solve_time(model)
    results[:termination_status] = Int(termination_status(model))
    results[:objective_value] = objective_value(model)

    if stoch_flag == 0
        # push all JuMP objects values into the dict
        for key_model in keys(model.obj_dict)
            push!(results, key_model=>value.(model[key_model]))
        end
    else
        # push all (relevant) JuMP objects values into the dict
        for key_model in keys(model.obj_dict)
            if (findfirst("con_",String(key_model)) == nothing) # constraint value are not relevant
                try
                    push!(results, String(key_model)=>value.(model[key_model]))
                catch
                    if findfirst("tot",String(key_model)) != nothing || findfirst("NPV",String(key_model)) != nothing  
                            || findfirst("SW",String(key_model)) != nothing # all total cost and NPV user are relevant
                        if (typeof(model[key_model]) == DecisionAffExpr{Float64})
                            val = value.(model[key_model].decisions)
                        else
                            val = extract_value_DecisionAffExpr(model[key_model])
                        end
                        push!(results, String(key_model)=>val)
                    end
                end
            end
        end
    end

    return results
end

"""
Function to extract values from a JuMP DecisionAffExpr for stochastich models.
"""
function extract_value_DecisionAffExpr(exp::JuMP.Containers.DenseAxisArray)
    keys_exp = keys(exp)
    values = map(keys_exp) do k
        v = exp[k]
        if v isa JuMP.DecisionAffExpr{Float64}
            return value.(v.decisions)
        else
            return 0
        end
    end
    return JuMP.Containers.DenseAxisArray(values, keys_exp)
end

"""
Convert a flat scenario index into its corresponding (s, eps) pair. Throws an error if `scen` is out of range.
"""
function convert_scen(n_scen_s::Int, n_scen_eps::Int, scen::Int)
    s = ceil(Int, scen / n_scen_eps)
    s > n_scen_s && error("Scenario index out of range")

    eps = scen - (s - 1) * n_scen_eps
    return (s, eps)
end

"""
    delta_t_tes_lb(users_data, u, s, t)

Function to compute the lower bound of the temperature difference for a thermal energy storage (TES) at time t.
When the thermal load the TES is linked to is in cooling mode, the lower bound is the difference between the reference temperature (T_ref_cool) and the input temperature (T_input_cool) for cooling.
When the load is in heating mode, the lower bound is 0.0.
The corresponding thermal load is identified by the `corr_asset` field in the load component.

## Arguments
- `users_data`: dictionary with the users data
- `u`: user index
- `s`: name of the thermal energy storage
- `t`: time index

## Returns
- [°C] The lower bound of the temperature difference for the TES at time t
"""
function delta_t_tes_lb(users_data, u, s, t)
    l = first([  # Load corresponding to the TES
        l for l in asset_names(users_data[u], T_LOAD)
        if field_component(users_data[u], l, "corr_asset") == s || s in field_component(users_data[u], l, "corr_asset")
    ])
    md = profile_component(users_data[u], l, "mode")[t]  # mode of the load at time t
    if md < -0.5 # cooling
        return field_component(users_data[u], s, "T_ref_cool") - field_component(users_data[u], s, "T_input_cool") # T_ref < T_input -> valore negativo
    else
        return 0.0
    end
end



"""
    delta_t_tes_ub(users_data, u, s, t)

Function to compute the upper bound of the temperature difference for a thermal energy storage (TES) at time t.
When the thermal load the TES is linked to is in heating mode, the upper bound is the difference between the reference temperature (T_ref_heat) and the input temperature (T_input_heat) for heating.
When the load is in cooling mode, the upper bound is 0.0.
The corresponding thermal load is identified by the `corr_asset` field in the first load component that contains the object.

## Arguments
- `users_data`: dictionary with the users data
- `u`: user index
- `s`: name of the thermal energy storage
- `t`: time index

## Returns
- [°C] The lower bound of the temperature difference for the TES at time t
"""
function delta_t_tes_ub(users_data, u, s, t)
    l = first([  # Load corresponding to the TES
        l for l in asset_names(users_data[u], T_LOAD)
        if field_component(users_data[u], l, "corr_asset") == s || s in field_component(users_data[u], l, "corr_asset")
    ])
    md = profile_component(users_data[u], l, "mode")[t]  # mode of the load at time t
    if md > 0.5 # heating
        return field_component(users_data[u], s, "T_ref_heat") - field_component(users_data[u], s, "T_input_heat")
    else
        return 0.0
    end
end

# Convert Dict{Int, T} → Vector{T}
dict2array(A::Dict{Int,T}, n::Int) where {T} = [A[i] for i in 1:n]

# Convert AbstractVector{T} → Dict{Int, T}
array2dict(p::AbstractVector{T}) where {T} = Dict(i => p[i] for i in eachindex(p))