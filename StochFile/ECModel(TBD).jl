"""
    set_parameters_ECmodel(ECModel::AbstractEC,
        tol::Float64=1e-3, # default gap set to 0.1
        time_limit::Int=60*60, # default time limit set to one hour
        threads::Int=1)
Function to set the parameters for the stochastic optimization of the model

# Arguments
    tol = set the primal gap in order to stop the optimization when reached
    time_limit = maximum time for the optimization (in second)
    threads = number of threads used for the parallel mode
"""
# TODO manca gestione esplicita Gurobi, HiGHS e GLPK
function set_parameters_ECmodel!(ECModel::AbstractEC,
        tol::Float64=1e-3, # default gap set to 0.1
        time_limit::Int=60*60, # default time limit set to one hour
        threads::Int=1,
        verbosity::Int=0)

    model = ECModel.model
    deterministic_model = ECModel.deterministic_model

    set_optimizer_attribute(model, "CPX_PARAM_EPGAP", tol)
    set_optimizer_attribute(model, "CPX_PARAM_TILIM", time_limit)
    set_optimizer_attribute(model, "CPX_PARAM_THREADS", threads)
    set_optimizer_attribute(model, "CPX_PARAM_SCRIND", verbosity)

    set_optimizer_attribute(deterministic_model, "CPX_PARAM_EPGAP", tol)
    set_optimizer_attribute(deterministic_model, "CPX_PARAM_TILIM", time_limit)
    set_optimizer_attribute(deterministic_model, "CPX_PARAM_THREADS", threads)
    set_optimizer_attribute(deterministic_model, "CPX_PARAM_SCRIND", verbosity)

    return ECModel
end

"""
    optimize_ECmodel(ECModel::AbstractEC)
Function used to optimize the model contained in the AbstractEC
"""
function optimize_ECmodel(ECModel::AbstractEC)

    model = ECModel.model

    optimize!(model)
end

"""
    optimize_deterministic_ECmodel(ECModel::AbstractEC)
Function used to optimize the deterministic equivalent of the model contained in the AbstractEC
"""
function optimize_deterministic_ECmodel(ECModel::AbstractEC)

    model = ECModel.deterministic_model

    optimize!(model)

    ECModel.results = _jump_to_dict(model)
    
    return ECModel
end

""" 
    print_summary(::AbstractGroupCO, ECModel::AbstractEC)
Function to print the main results of the model
"""
function print_summary(::AbstractGroupCO, ECModel::AbstractEC, scenarios::Array{Scenario_Load_Renewable, 1}, control_stoch::Bool)

    # get main parameters
    gen_data, users_data, market_data = explode_data(ECModel.data)
    n_users = length(users_data)
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    project_lifetime = field(gen_data, "project_lifetime")
    peak_categories = profile(market_data, "peak_categories")

    # Set definitions

    year_set = 1:project_lifetime
    time_set = 1:n_steps
    peak_set = unique(peak_categories)

    # Set definition when optional value is not included
    user_set = ECModel.user_set

    # get number of scenarios
    n_scen_s = ECModel.n_scen_s
    n_scen_eps = ECModel.n_scen_eps
    n_scen = n_scen_s * n_scen_eps

    # set of all types of assets among the users
    asset_set_unique = unique([name for u in user_set for name in device_names(users_data[u])])

    # format types to print at screen the results
    printf_code_user = string("{:18s}: {: 7.2e}", join([", {: 7.2e}" for i in 1:length(user_set) if i > 1]))
    printf_code_agg = string("{:18s}: {: 7.2e}")
    printf_code_description = string("{:<18s}: {:>9s}", join([", {:>9s}" for i in 1:length(user_set) if i > 1]))
    printf_code_second_stage_description = string("{:18s}: {: 9d}", join([", {: 9d}" for i in 1:n_scen_s if i > 1]))
    printf_code_second_stage = string("{:18s}: {: 7.2e}", join([", {: 7.2e}" for i in 1:n_scen_s if i > 1]))
    printf_code_third_stage_description = string("{:8s}: ({:1d} - {:1d})")

    ## start printing

    ## Print first stage variable -- installed capacities
    printfmtln("\nFIRST STAGE RESULTS")

    printfmtln(printf_code_description, "USER", [u for u in user_set]...)  # heading
    for a in asset_set_unique  # print capacities of each asset by user
        printfmtln(printf_code_user, a, [
            (a in device_names(users_data[u])) ? value.(ECModel.model[1,:x_us])[u, a] * field_component(users_data[u], a, "nom_capacity") : 0
                for u in user_set]...)
    end

    ## Print second stage variable -- declared dispatch

    printfmtln("\nSECOND STAGE RESULTS")

    printfmtln(printf_code_second_stage_description, "SCENARIO S", [s for s=1:n_scen_s]...)

    printfmtln(printf_code_second_stage, "P_agg_dec_P", [sum(value.(ECModel.model[1,:P_agg_dec_P]).data[s,:]) for s=1:n_scen_s]...)
    printfmtln(printf_code_second_stage, "P_agg_dec_N", [sum(value.(ECModel.model[1,:P_agg_dec_N]).data[s,:]) for s=1:n_scen_s]...)

    ## Print third stage variable for combiantion of scenario

    printfmtln("\nTHIRD STAGE RESULTS")

    for s = 1:n_scen_s
        for eps = 1:n_scen_eps
            scen = eps+(s-1)*n_scen_eps

            printfmtln(printf_code_third_stage_description, "\n\nSCENARIO", [s,eps]...)

            _NPV_agg = value.(ECModel.model[2,:NPV_agg],scen)/1000 # NPV aggregator
            _NPV_us = value.(ECModel.model[2,:AP_user],scen)/1000 # NPV by user

            # aggregator results
            printfmtln("\n\nRESULTS - AGGREGATOR")
            printfmtln(printf_code_agg, "NPV Agg [k€]", _NPV_agg)  # NPV aggregator
            printfmtln(printf_code_agg, "SWtot [k€]", _NPV_agg + sum(_NPV_us.data))  # Total social welfare
            printfmtln(printf_code_agg, "SWus [k€]",  sum(_NPV_us.data))  # Social welfare of the users

            printfmtln(printf_code_agg, "ESha [MWh]",  sum(value.(EC_Cooperative.model[2,:P_shared_agg],scen).data)/ 1000)  # Shared Energy

            # results of the users
            printfmtln("\n\nRESULTS - USER")

            printfmtln(printf_code_user, "NPV [k€]", _NPV_us.data...)  # print NPV by user

            # print energy flows
            printfmtln("\n\nEnergy flows")
            printfmtln(printf_code_description, "USER", [u for u in user_set]...)

            printfmtln(printf_code_user, "PtotPusP [MWh]",
                [sum(value.(ECModel.model[2,:P_P_us],scen)[u, :]) for u in user_set]/1000...)  # Total power supplied by user to the grid
            printfmtln(printf_code_user, "PtotPusN [MWh]",
                [sum(value.(ECModel.model[2,:P_N_us],scen)[u, :]) for u in user_set]/1000...)  # Total power bought by user to the grid
            
            ### TOO SLOW
            #printfmtln(printf_code_user, "PconvP [MWh]",
            #    [sum(Float64[value.(ECModel.model[2,:P_conv_P_us],scen)[u, c, t] 
            #            for c in asset_names(users_data[u], CONV) for t in time_set]) 
            #                for u in user_set]/1000...)  # Total power supplied by converters by user
            #printfmtln(printf_code_user, "PconvN [MWh]",
            #    [sum(Float64[value.(ECModel.model[2,:P_conv_N_us],scen)[u, c, t] 
            #            for c in asset_names(users_data[u], CONV) for t in time_set]) 
            #                for u in user_set]/1000...)  # Total power loaded by converters by user
            printfmtln(printf_code_user, "Pren [MWh]",
                [sum(value.(ECModel.model[2,:P_ren_us],scen)[u,:]) for u in user_set]/1000...)  # Total power supplied by renewables by each user
            demand_EC = calculate_demand(ECModel,scenarios,control_stoch)[scen]
            printfmtln(printf_code_user, "Load [MWh]",demand_EC[user_set]/1000...)  # Total load by user
        end
    end
end

"""
    save(output_file::AbstractString, ECModel::AbstractEC)
Function to save the results and the model to the hard drive

NOTE: the output file should be in .jld2 format
"""
function FileIO.save(output_file::AbstractString, ECModel::AbstractEC)
    save_model = Dict(
        "data"=> ECModel.data,
        "user_set"=>ECModel.user_set,
        "group_type"=>string(typeof(ECModel.group_type)),
        "scenarios"=>ECModel.scenarios,
        "n_scen_s"=>ECModel.n_scen_s,
        "n_scen_eps"=>ECModel.n_scen_eps,
        "results"=>ECModel.results
    )
    FileIO.save(output_file, save_model)
end

"""
    load!(output_file::AbstractString, ECModel::AbstractEC)
Function to read the results and the model previously stored to the hard drive

NOTE: the input file should be in .jld2 format
"""
function load!(input_file::AbstractString, ECModel::AbstractEC)

    ## load raw data and preliminary checks
    raw_data = FileIO.load(input_file)

    # check if file contains the data of the ECModel
    for k_val in ["data", "user_set", "group_type", "n_scen_s", "n_scen_eps", "scenarios", "results"]
        if k_val ∉ keys(raw_data)
            throw(ArgumentError("File $input_file not a valid ECModel: missing keyword $k_val"))
        end
    end

    function _all_types(x)
        sub_x = InteractiveUtils.subtypes(x)
        if length(sub_x) > 0
            return [sub_x; [_all_types(sx) for sx in sub_x]...]
        else
            return sub_x
        end
    end

    # check if the group_type is compatible with the available instances
    if !any([string(g) == raw_data["group_type"] for g in _all_types(AbstractGroup)])
        throw(ArgumentError("File $input_file not a valid EC group type"))
    end

    ## load data 
    ECModel.data = raw_data["data"]
    ECModel.gen_data = general(ECModel.data)
    ECModel.market_data = market(ECModel.data)
    ECModel.users_data = users(ECModel.data)

    # load user_set available from configuration file
    user_set_from_user_set = collect(keys(ECModel.users_data))

    ## load user_set
    ECModel.user_set = unique(get(raw_data, "user_set", user_set_from_user_set))

    if isempty(ECModel.user_set)  # check if user_set is not empty
        throw(Error("user_set in configuration file $input_file is empty"))
    else  # check if all user_set names are available in the config
        diffset = setdiff(Set(ECModel.user_set), Set(user_set_from_user_set))  # elements of user_set not in the config
        if !isempty(diffset) #check that all user_set elements are in the list
            throw(Error("user_set in configuration file $input_file is empty: missing elements $(collect(diffset))"))
        end
    end


    # load group_type
    ECModel.group_type = eval(Meta.parse(raw_data["group_type"] * "()"))

    # load the scenarios considered
    ECModel.scenarios = raw_data["scenarios"]
    ECModel.n_scen_s = raw_data["n_scen_s"]
    ECModel.n_scen_eps = raw_data["n_scen_eps"]

    ECModel.model = StochasticProgram(ECModel.scenarios, Deterministic())
    ECModel.deterministic_model = Model()
    ECModel.results = raw_data["results"]
    
    return ECModel
end

"""
    load(output_file::AbstractString)
    Function to read the results and the model previously stored to the hard drive

    NOTE: the input file should be in .jld2 format
"""
function FileIO.load(input_file::AbstractString, ECModel::AbstractEC)
    return load!(input_file, zero(ECModel))
end

function save_first_stage_model(ECModel::AbstractEC, output_file::AbstractString)

    jld2_file = output_file * ".jld2"

    save(jld2_file,ECModel)

    xlsx_file = output_file * ".xlsx"

    print_first_stage(xlsx_file,ECModel)
end

function extract_economic_values_NC(ECModel::ModelEC)

    sub_scen = Char(0x02080+1)

    SW = ECModel.results["SW"*sub_scen]
    R_ene_tot = sum(ECModel.results["R_Energy_tot_us"*sub_scen])
    C_gen_tot = sum(ECModel.results["C_gen_tot_us"*sub_scen])
    C_sq_tot = sum(ECModel.results["C_sq_tot_us"*sub_scen])
    C_peak_tot = sum(ECModel.results["C_Peak_tot_us"*sub_scen])

    return (SW,R_ene_tot,C_gen_tot,C_sq_tot,C_peak_tot)
end

function extract_economic_values_CO(ECModel::ModelEC)

    sub_scen = Char(0x02080+1)

    SW = ECModel.results["SW"*sub_scen]
    R_ene_tot = sum(ECModel.results["R_Energy_tot_us"*sub_scen])
    C_gen_tot = sum(ECModel.results["C_gen_tot_us"*sub_scen])
    C_sq_tot = ECModel.results["C_sq_tot_agg"*sub_scen]
    C_peak_tot = sum(ECModel.results["C_Peak_tot_us"*sub_scen])
    R_rew_agg_tot = ECModel.results["R_Reward_agg_tot"*sub_scen]

    return (SW,R_ene_tot,C_gen_tot,C_sq_tot,C_peak_tot,R_rew_agg_tot)
end

function extract_dispatch_values_NC(ECModel::ModelEC)

    sub_scen = Char(0x02080+1)

    market_data = ECModel.market_data

    energy_weight = profile(market_data, "energy_weight")[1]
    time_res = profile(market_data, "time_res")[1]

    load_demand_tot = sum(calculate_demand(ECModel)[1][u] for u in useextract_dispatch_values_COr_set)
    P_P_tot = sum(ECModel.results["P_P_us" * sub_scen]) * time_res * energy_weight
    P_N_tot = sum(ECModel.results["P_N_us" * sub_scen]) * time_res * energy_weight
    P_sq_P_tot = sum(ECModel.results["P_sq_P_us" * sub_scen]) * time_res * energy_weight
    P_sq_N_tot = sum(ECModel.results["P_sq_N_us" * sub_scen]) * time_res * energy_weight
    P_ren_tot = sum(ECModel.results["P_ren_us" * sub_scen]) * time_res * energy_weight
    P_gen_tot = sum(ECModel.results["P_gen_us" * sub_scen]) * time_res * energy_weight
    P_conv_P_tot = sum(ECModel.results["P_conv_P_us" * sub_scen]) * time_res * energy_weight
    P_conv_N_tot = sum(ECModel.results["P_conv_N_us" * sub_scen]) * time_res * energy_weight

    return (load_demand_tot,P_P_tot,P_N_tot,P_sq_P_tot,P_sq_N_tot,P_ren_tot,P_gen_tot,P_conv_P_tot,P_conv_N_tot)
end

function extract_dispatch_values_CO(ECModel::ModelEC)

    sub_scen = Char(0x02080+1)

    market_data = ECModel.market_data

    energy_weight = profile(market_data, "energy_weight")[1]
    time_res = profile(market_data, "time_res")[1]

    load_demand_tot = sum(calculate_demand(ECModel)[1][u] for u in user_set)
    P_P_tot = sum(ECModel.results["P_P_us" * sub_scen]) * time_res * energy_weight
    P_N_tot = sum(ECModel.results["P_N_us" * sub_enscen]) * time_res * energy_weight
    P_sq_P_tot = sum(ECModel.results["P_sq_P_agg" * sub_scen]) * time_res * energy_weight
    P_sq_N_tot = sum(ECModel.results["P_sq_N_agg" * sub_scen]) * time_res * energy_weight
    P_ren_tot = sum(ECModel.results["P_ren_us" * sub_scen]) * time_res * energy_weight
    P_gen_tot = sum(ECModel.results["P_gen_us" * sub_scen]) * time_res * energy_weight
    P_conv_P_tot = sum(ECModel.results["P_conv_P_us" * sub_scen]) * time_res * energy_weight
    P_conv_N_tot = sum(ECModel.results["P_conv_N_us" * sub_scen]) * time_res * energy_weight
    P_Shared_tot = sum(ECModel.results["P_shared_agg" * sub_scen]) * time_res * energy_weight

    return (load_demand_tot,P_P_tot,P_N_tot,P_sq_P_tot,P_sq_N_tot,P_ren_tot,P_gen_tot,P_conv_P_tot,P_conv_N_tot,P_Shared_tot)
end


#===============================================================================
TODO verificare se ci piacciono di più.
===============================================================================#

"""
    extract_economic_values(ECModel::AbstractEC)

Extract economic values based on the model's group type (determined at runtime).
Uses accessor functions for compatibility with both ModelEC and StochasticEC.

## Returns
- For Non-Cooperative (NC): (SW, R_ene_tot, C_gen_tot, C_sq_tot, C_peak_tot)
- For Cooperative (CO): (SW, R_ene_tot, C_gen_tot, C_sq_tot, C_peak_tot, R_rew_agg_tot)

## Example
```julia
values = extract_economic_values(ECModel)  # Works for both NC and CO
```
"""
function extract_economic_values(ECModel::AbstractEC)
    sub_scen = Char(0x02080+1)

    res = results(ECModel)
    gt = group_type(ECModel)

    # Common values for both NC and CO
    SW = res["SW"*sub_scen]
    R_ene_tot = sum(res["R_Energy_tot_us"*sub_scen])
    C_gen_tot = sum(res["C_gen_tot_us"*sub_scen])
    C_peak_tot = sum(res["C_Peak_tot_us"*sub_scen])

    # Type-specific values
    if gt isa AbstractGroupNC
        # NC: C_sq from users
        C_sq_tot = sum(res["C_sq_tot_us"*sub_scen])
        return (SW, R_ene_tot, C_gen_tot, C_sq_tot, C_peak_tot)

    elseif gt isa AbstractGroupCO
        # CO: C_sq from aggregator + reward
        C_sq_tot = res["C_sq_tot_agg"*sub_scen]
        R_rew_agg_tot = res["R_Reward_agg_tot"*sub_scen]
        return (SW, R_ene_tot, C_gen_tot, C_sq_tot, C_peak_tot, R_rew_agg_tot)

    else
        throw(ArgumentError("Unsupported group type: $(typeof(gt))"))
    end
end


"""
    extract_dispatch_values(ECModel::AbstractEC)

Extract dispatch values based on the model's group type (determined at runtime).
Uses accessor functions for compatibility with both ModelEC and StochasticEC.

===============================================================================
## Returns
- For Non-Cooperative (NC): 9 values (without P_Shared_tot)
- For Cooperative (CO): 10 values (includes P_Shared_tot)

## Example
```julia
values = extract_dispatch_values(ECModel)  # Works for both NC and CO
```
"""
function extract_dispatch_values(ECModel::AbstractEC)
    sub_scen = Char(0x02080+1)

    mkt_data = market_data(ECModel)
    res = results(ECModel)
    gt = group_type(ECModel)

    # Common setup
    energy_weight = profile(mkt_data, "energy_weight")[1]
    time_res = profile(mkt_data, "time_res")[1]

    # Common values for both NC and CO
    load_demand_tot = sum(calculate_demand(ECModel)[1][u] for u in user_set)
    P_P_tot = sum(res["P_P_us" * sub_scen]) * time_res * energy_weight
    P_N_tot = sum(res["P_N_us" * sub_scen]) * time_res * energy_weight
    P_ren_tot = sum(res["P_ren_us" * sub_scen]) * time_res * energy_weight
    P_gen_tot = sum(res["P_gen_us" * sub_scen]) * time_res * energy_weight
    P_conv_P_tot = sum(res["P_conv_P_us" * sub_scen]) * time_res * energy_weight
    P_conv_N_tot = sum(res["P_conv_N_us" * sub_scen]) * time_res * energy_weight

    # Type-specific values
    if gt isa AbstractGroupNC
        # NC: P_sq from users
        P_sq_P_tot = sum(res["P_sq_P_us" * sub_scen]) * time_res * energy_weight
        P_sq_N_tot = sum(res["P_sq_N_us" * sub_scen]) * time_res * energy_weight

        return (load_demand_tot, P_P_tot, P_N_tot, P_sq_P_tot, P_sq_N_tot,
                P_ren_tot, P_gen_tot, P_conv_P_tot, P_conv_N_tot)

    elseif gt isa AbstractGroupCO
        # CO: P_sq from aggregator + shared energy
        P_sq_P_tot = sum(res["P_sq_P_agg" * sub_scen]) * time_res * energy_weight
        P_sq_N_tot = sum(res["P_sq_N_agg" * sub_scen]) * time_res * energy_weight
        P_Shared_tot = sum(res["P_shared_agg" * sub_scen]) * time_res * energy_weight

        return (load_demand_tot, P_P_tot, P_N_tot, P_sq_P_tot, P_sq_N_tot,
                P_ren_tot, P_gen_tot, P_conv_P_tot, P_conv_N_tot, P_Shared_tot)

    else
        throw(ArgumentError("Unsupported group type: $(typeof(gt))"))
    end
end


"""
    extract_declared_values(ECModel::AbstractEC)

Extract declared dispatch values based on the model's group type (determined at runtime).
Uses accessor functions for compatibility with both ModelEC and StochasticEC.

## Returns
- For Non-Cooperative (NC): (P_dec_P, P_dec_N) with user-level data
- For Cooperative (CO): (P_dec_P, P_dec_N) with aggregator-level data

## Example
```julia
(P_dec_P, P_dec_N) = extract_declared_values(ECModel)  # Works for both NC and CO
```
"""
function extract_declared_values(ECModel::AbstractEC) sub_scen = Char(0x02080+1)
    res = results(ECModel)
    gt = group_type(ECModel)

    if gt isa AbstractGroupNC
        # NC: declared values from users
        P_dec_P = res["P_us_dec_P"*sub_scen].data
        P_dec_N = res["P_us_dec_N"*sub_scen].data
        return (P_dec_P, P_dec_N)

    elseif gt isa AbstractGroupCO
        # CO: declared values from aggregator
        P_dec_P = res["P_agg_dec_P"*sub_scen].data
        P_dec_N = res["P_agg_dec_N"*sub_scen].data
        return (P_dec_P, P_dec_N)
        
    else
        throw(ArgumentError("Unsupported group type: $(typeof(gt))"))
    end
end
