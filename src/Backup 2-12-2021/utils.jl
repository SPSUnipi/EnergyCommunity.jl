@enum ASSET_TYPE LOAD=0 REN=1 BATT=2 CONV=3
ANY = collect(instances(ASSET_TYPE))  # all assets code
DEVICES = setdiff(ANY, [LOAD])  # devices codes
GENS = [REN]  # generator codes

type_codes = Base.Dict("renewable"=>REN, "battery"=>BATT,"converter"=>CONV,"load"=>LOAD)

# Get the previous time step, with circular time step
@inline pre(time_step::Int, gen_data::Dict) = if (time_step > field(gen_data, "init_step")) time_step-1 else field(gen_data, "final_step") end
@inline pre(time_step::V, time_set::UnitRange{V}) where{V <: Int} = if (time_step > time_set[1]) time_step-1 else time_set[end] end


"Function to safely get a field of a dictionary with default value"
@inline field_d(d::AbstractDict, field, default=nothing) = (field in keys(d) ? d[field] : default)
@inline field_i(d, field) = field_d(d, field, 0)
@inline field_f(d, field) = field_d(d, field, 0.0)
"Function get field that throws an error if the field is not found"
@inline function field(d, field, desc=nothing)
    if d isa AbstractDict && field in keys(d)
        return d[field]
    else
        msg = isnothing(desc) ? "Field $field not found in dictionary $(keys(d))" : desc
        throw(KeyError(msg))
    end
end

"Function to get the general parameters"
general(d) = field(d, "general")
"Function to get the users configuration"
users(d) = field(d, "users")
"Function to get the market configuration"
market(d) = field(d, "market")
"Function to get the profile dictionary"
profiles(d) = field_d(d, "profile")
"Function to get the components list of a dictionary"
components(d) = d
"Function to get the components value of a dictionary"
component(d, c_name) = field(components(d), c_name)
"Function to get the components value of a dictionary"
field_component(d, c_name, f_name) = field(component(d, c_name), f_name)
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
    accepted_types = set_diff(ANY, ex)
    return asset_names(d, accepted_types)
end

"Function to get the list of devices for a user"
device_names(d) = asset_names(d, DEVICES)

"Get the list of users"
function user_names(gen_data, users_data)
    # get the list of users if set
    user_list = field_d(gen_data, "user_list")
    if isnothing(user_list)
        @info "List of users not specified: all users selected"
        user_list = collect(keys(users_data))
    elseif isempty(user_list)
        throw(ErrorException("Input user list is empty"))
    elseif !(user_list isa AbstractVector)
        throw(ErrorException("Input user list is not a vector"))
    end
    return sort!(user_list)
end


"""
Function to parse a string value of a profile to load the corresponding dataframe
"""
function parse_dataprofile(gen_config, data, profile_name, profile_value::AbstractString)

    if profile_value in names(data)
        return data[!, profile_value]
    else
        throw(KeyError("Profile name $profile_value not found in available dataframes"))
    end
end

"""
Function to parse a string value of a profile to load the corresponding dataframe
"""
function parse_dataprofile(gen_config, data, profile_name, profile_value::AbstractVector{T}) where T <: Integer

    if length(profile_value) < gen_config["final_step"] - gen_config["init_step"] + 1
        throw(ErrorException("Not enough profile data available for the current profile list"))
    end
    
    return profile_value
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

    data = YAML.load_file(file_name)

    gen_data = general(data)

    # optional data by csv files
    opt_data = DataFrame()
    opt_files = field(gen_data, "optional_datasets")
    if !isnothing(opt_files)  # datasets are available
        for f_name in opt_files
            # read dataset and join to the original dataset
            d = CSV.read(f_name, DataFrame)
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

    change_profile!(market_data, opt_data)

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
    jump_to_dict

Function to turn a JuMP model to a dictionary
"""
function jump_to_dict(model::Model)
    results = Dict{Symbol, Any}()

    for key_model in keys(model.obj_dict)
        push!(results, key_model=>value.(model[key_model]))
    end

    results
end