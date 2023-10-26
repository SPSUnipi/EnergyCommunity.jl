"Return main data elements of the dataset of the ECModel: general parameters, users data and market data"
function explode_data(ECModel::AbstractEC)
    return general(ECModel.data), users(ECModel.data), market(ECModel.data)
end


"Get the EC group type"
function get_group_type(ECModel::AbstractEC)
    return ECModel.group_type
end

"Set the EC group type"
function set_group_type!(ECModel::AbstractEC, group::AbstractGroup)
    ECModel.group_type = group
end


"Get the EC user set"
function get_user_set(ECModel::AbstractEC)
    return ECModel.user_set
end


"Set the EC user set"
function set_user_set!(ECModel::AbstractEC, user_set)
    if EC_CODE in user_set
        println("Aggregator code '$EC_CODE' removed from the list of users")
        user_set = setdiff(user_set, [EC_CODE])
    end
    ECModel.user_set = collect(user_set)
end


"Set the EC user set equal to the stored user_set"
function reset_user_set!(ECModel::AbstractEC)
    set_user_set!(ECModel::AbstractEC, collect(keys(ECModel.users_data)))
end

"Build the mathematical problem for the EC"
function build_model!(ECModel::AbstractEC; kwargs...)

    # build the model
    build_model!(ECModel.group_type, ECModel, ECModel.optimizer; kwargs...)

    # return the model
    return ECModel
end

"""
Function to return the objective function by User
"""
function objective_by_user(ECModel::AbstractEC; add_EC=true)
    return objective_by_user(ECModel.group_type, ECModel; add_EC=add_EC)
end

"""
Function to return the objective function by User
"""
function JuMP.objective_value(ECModel::AbstractEC)
    if isempty(ECModel.results)
        return throw(UndefVarError("Optimization not performed"))
    else
        return ECModel.results[:objective_value]
    end
end

"Abstract build function model for generic EnergyCommunity model"
function build_model!(group_type::AbstractGroup, ECModel::AbstractEC, optimizer; use_notations=false)

    # the build model for the NC/ANC case is eqvuivalent to the base model
    build_base_model!(ECModel, optimizer; use_notations=use_notations)

    # add the NC/ANC-specific model
    build_specific_model!(group_type, ECModel)

    # set objective
    set_objective!(group_type, ECModel)

    # return the model
    return ECModel
end


"Solve the optimization problem for the EC"
function JuMP.optimize!(ECModel::AbstractEC; update_results=true)
    optimize!(ECModel.model)
    ECModel.results = _jump_to_dict(ECModel.model)
    finalize_results!(ECModel.group_type, ECModel)
    return ECModel
end


"Solve the optimization problem for the EC"
function JuMP.result_count(ECModel::AbstractEC)
    return result_count(ECModel.model)
end


"Output results for the NC configuration"
function output_results(ECModel::AbstractEC,
    output_file::AbstractString, output_file_plot::AbstractString,
    ::Union{GroupNC, GroupANC}; user_set::Vector = Vector())
    return output_results_NC(ECModel.data, ECModel.results_NC, 
            output_file, output_file_plot, user_set=user_set)
end

"Output results for the EC configuration"
function output_results(ECModel::AbstractEC,
    output_file::AbstractString, output_file_plot::AbstractString,
    ::GroupCO; user_set::Vector = Vector())
    return output_results_EC(ECModel.data, ECModel.results,
            output_file, output_file_plot, ECModel.results_NC, user_set=user_set)
end

"""
    to_objective_callback_by_subgroup(ECModel::AbstractEC)

Function that returns a callback function that quantifies the objective of a given subgroup of users
The returned function objective_func accepts as arguments an AbstractVector of users and
returns the objective of the aggregation for any model

Parameters
----------
ECModel : AbstractEC
    Cooperative EC Model of the EC to study.
    When the model is not cooperative an error is thrown.

Return
------
objective_callback_by_subgroup : Function
    Function that accepts as input an AbstractVector (or Set) of users and returns
    as output the benefit of the specified community
"""
function to_objective_callback_by_subgroup(ECModel::AbstractEC; kwargs...)
    return to_objective_callback_by_subgroup(ECModel.group_type, ECModel; kwargs...)
end



"""
    save(output_file::AbstractString, ECModel::AbstractEC)
Function to save the results and the model to the hard drive
"""
function FileIO.save(output_file::AbstractString, ECModel::AbstractEC)
    save_model = Dict(
        "data"=> ECModel.data,
        "user_set"=>ECModel.user_set,
        "group_type"=>string(typeof(ECModel.group_type)),
        "results"=>ECModel.results
    )
    FileIO.save(output_file, save_model)
end

"""
    load!(output_file::AbstractString, ECModel::AbstractEC)
Function to save the results and the model to the hard drive
"""
function load!(output_file::AbstractString, ECModel::AbstractEC)

    ## load raw data and preliminary checks
    raw_data = FileIO.load(output_file)

    # check if file contains the data of the ECModel
    for k_val in ["data", "user_set", "group_type", "results"]
        if k_val ∉ keys(raw_data)
            throw(ArgumentError("File $output_file not a valid ECModel: missing keyword $k_val"))
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
        throw(ArgumentError("File $output_file not a valid EC group type"))
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
        throw(Error("user_set in configuration file $output_file is empty"))
    else  # check if all user_set names are available in the config
        diffset = setdiff(Set(ECModel.user_set), Set(user_set_from_user_set))  # elements of user_set not in the config
        if !isempty(diffset) #check that all user_set elements are in the list
            throw(Error("user_set in configuration file $output_file is empty: missing elements $(collect(diffset))"))
        end
    end


    # load group_type
    ECModel.group_type = eval(Meta.parse(raw_data["group_type"] * "()"))

    ECModel.model = Model()  # JuMP model not initialized
    ECModel.results = raw_data["results"]
    
    return ECModel
end

"""
    load(output_file::AbstractString)
Function to save the results and the model to the hard drive
"""
function FileIO.load(output_file::AbstractString, ECModel::AbstractEC)
    return load!(output_file, zero(ECModel))
end


"""

Function to verify the data loaded from the disk
"""
function _verify_data(data::Dict)


end


"""

Function to verify the users data loaded from the disk
"""
function _verify_users_data(users_data::Dict)
    # check non-empty users data
    if isempty(users_data)
        throw(ArgumentError("Input users data are empty"))
    end

    # loop over each user to check whether the names of the assets
    # are in the accepted list
    for (user_name, u_data) in users_data
        # loop for every technology
        if u_data isa AbstractDict
            for (tech_name, tech_value) in u_data
                # check if keyword "type" is in the list
                if "type" ∉ tech_value
                    throw(ArgumentError("Type of technology not specified for technology name $tech_name of user $user_name"))
                end
                if tech_value["type"] ∉ ACCEPTED_TECHS
                    throw(ArgumentError("Type of technology $(tech_value["type"]) not in the available techs 
                        for user $user_name and technology name $tech_name"))
                end
            end
        end
    end

end

"""

Function to plot the EC model
"""
function Plots.plot(ECModel::ModelEC, output_plot_file::AbstractString="")
    Plots.plot(ECModel.group_type, ECModel, output_plot_file)
end


"""
Function to print a summary of the results of the model.
The function dispatches the execution to the appropriate function depending on the Aggregation type of the EC
"""
function print_summary(ECModel::AbstractEC; kwargs...)
    print_summary(ECModel.group_type, ECModel, kwargs...)
end


"""
Function to save a summary of the results of the model.
The function dispatches the execution to the appropriate function depending on the Aggregation type of the EC
"""
function save_summary(ECModel::AbstractEC, output_file::AbstractString; kwargs...)

    # set user_set into kwargs by externak kwargs or deafault user_set of ECModel
    kwargs_dict = Dict{Symbol, Any}(kwargs)
    # if user_set not in the inputs, add it
    if :user_set ∉ keys(kwargs_dict)
        kwargs_dict[:user_set] = ECModel.user_set
    end
    
    # get list of DataFrames to save
    output_list = prepare_summary(ECModel.group_type, ECModel; kwargs_dict...)

    # create parent dirs as needed
    mkpath(dirname(output_file))

    # Write XLSX table
    XLSX.openxlsx(output_file, mode="w") do xf
        # write the dataframe calculated before as an excel file

        if !isempty(output_list)
            #Rename first empty sheet to design_users amd write the corresponding DataFrame
            xs = xf[1]
            XLSX.rename!(xs, output_list[1][1])
            XLSX.writetable!(xs, DataFrames.eachcol(output_list[1][2]),
                DataFrames.names(output_list[1][2]))
        
            # add all the others sheets
            for i = 2:length(output_list)
                xs = XLSX.addsheet!(xf, output_list[i][1])
                XLSX.writetable!(xs, DataFrames.eachcol(output_list[i][2]),
                    DataFrames.names(output_list[i][2]))
            end
        end
    end
end


"""
    calculate_grid_import(ECModel::AbstractEC; per_unit::Bool=true)

Calculate grid usage for the energy community and users.
Output is normalized with respect to the demand when per_unit is true

'''
Outputs
-------
grid_frac : DenseAxisArray
    Reliance on the grid demand for each user and the aggregation
'''
"""
function calculate_grid_import(ECModel::AbstractEC; per_unit::Bool=true)
    return calculate_grid_import(ECModel.group_type, ECModel, per_unit=per_unit)
end


"""
    calculate_grid_export(ECModel::AbstractEC; per_unit::Bool=true)

Calculate grid export for the energy community and users.
Output is normalized with respect to the demand when per_unit is true

'''
Outputs
-------
grid_frac : DenseAxisArray
    Reliance on the grid demand for each user and the aggregation
'''
"""
function calculate_grid_export(ECModel::AbstractEC; per_unit::Bool=true)
    return calculate_grid_export(ECModel.group_type, ECModel, per_unit=per_unit)
end

"""
    calculate_time_shared_production(ECModel::AbstractEC; kwargs...)

Calculate the time series of the shared consumed energy for the Energy Community.

For every time step and user, this time series highlight the quantity of production that meets
needs by other users.

'''
Outputs
-------
shared_prod_us : DenseAxisArray
    Shared production for each user and the aggregation and time step
'''
"""
function calculate_time_shared_production(ECModel::AbstractEC; kwargs...)
    return calculate_time_shared_production(ECModel.group_type, ECModel; kwargs...)
end

"""
    calculate_time_shared_consumption(ECModel::AbstractEC)

Calculate the time series of the shared consumed energy for the Energy Community.

For every time step and user, this time series highlight the quantity of load that is met
by using shared energy.

'''
Outputs
-------
shared_cons_us : DenseAxisArray
    Shared consumption for each user and the aggregation and time step
'''
"""
function calculate_time_shared_consumption(ECModel::AbstractEC; kwargs...)
    return calculate_time_shared_consumption(ECModel.group_type, ECModel; kwargs...)
end


"""
    calculate_shared_consumption(ECModel::AbstractEC; per_unit::Bool=true)

Calculate the demand that each user meets using its own sources or other users.
When only_shared is false, also self consumption is considered, otherwise only shared consumption.
Output is normalized with respect to the demand when per_unit is true

'''
Outputs
-------
shared_cons_frac : DenseAxisArray
    Shared consumption for each user and the aggregation
'''
"""
function calculate_shared_consumption(ECModel::AbstractEC; per_unit::Bool=true, only_shared::Bool=false)
    return calculate_shared_consumption(ECModel.group_type, ECModel,
                                        per_unit=per_unit, only_shared=only_shared)
end


"""
    calculate_shared_production(ECModel::AbstractEC; per_unit::Bool=true)

Calculate the energy that each user produces and uses in its own POD or it is
commercially consumed within the EC, when creaded.
When only_shared is false, also self production is considered, otherwise only shared energy.
Output is normalized with respect to the demand when per_unit is true

'''
Outputs
-------
shared_cons_frac : DenseAxisArray
    Shared consumption for each user and the aggregation
'''
"""
function calculate_shared_production(ECModel::AbstractEC; per_unit::Bool=true, only_shared::Bool=false)
    return calculate_shared_production(ECModel.group_type, ECModel,
                                    per_unit=per_unit, only_shared=only_shared)
end


"""

    termination_status(ECModel::AbstractEC)

Calculate the optimization status of the model
"""
function JuMP.termination_status(ECModel::AbstractEC)
    if isempty(ECModel.results)
        return MOI.OPTIMIZE_NOT_CALLED
    else
        return MOI.TerminationStatusCode(ECModel.results[:termination_status])
    end
end


"""

    objective_function(ECModel::AbstractEC)

Get the objective function of the model
"""
function JuMP.objective_function(ECModel::AbstractEC)
    if isempty(ECModel.results)
        return MOI.OPTIMIZE_NOT_CALLED
    else
        return ECModel.results[:objective_function]
    end
end


"""
    plot_sankey(ECModel::AbstractEC)

Function to create the input data for plotting any Sankey diagram representing the energy flows across the energy community

Inputs
------
ECModel : AbstractEC
    Energy Community model
name_units : (optional) Vector
    Labels used for the sankey diagram with the following order:
    "Market buy", [users labels], "Community", "Market sell", [users labels]

"""
function data_sankey(ECModel::AbstractEC;
    name_units=nothing,
    norm_value=nothing,
    market_color = palette(:rainbow)[2],
    community_color = palette(:rainbow)[5],
    users_colors = palette(:default)
    )

    user_set = ECModel.user_set

    # specify labels if not provided
    if isnothing(name_units)
        name_units = [string.(user_set) .* " prod."; "Market sell";
            "Community"; "Market buy"; string.(user_set) .* " cons."]
    end

    # Calculation of energy quantities
    shared_production = calculate_shared_production(ECModel, per_unit=false, only_shared=true)
    shared_consumption = calculate_shared_consumption(ECModel, per_unit=false, only_shared=true)
    self_consumption = calculate_self_consumption(ECModel, per_unit=false)
    self_production = calculate_self_production(ECModel, per_unit=false)
    grid_import = calculate_grid_import(ECModel, per_unit=false)
    grid_export = calculate_grid_export(ECModel, per_unit=false)
    demand_us = calculate_demand(ECModel)
    production_us = calculate_production(ECModel)

    # definition of the ids of the resources
    user_id_from(x) = x
    market_id_sell = length(user_set) + 1
    market_id_buy = length(user_set) + 3
    community_id = length(user_set) + 2
    user_id_to(x) = x + length(user_set) + 3

    # specify the desired location of each entity id in the layers of the Sankey diagram
    # On the first layers all users that produce energy and the market when buying
    # On the second layer "Community"
    # On the third layer all users that consume energy and the market when selling
    node_layer = Dict([
        [user_id_from(id) => 1 for id in 1:length(user_set)];
        market_id_sell => 2;
        community_id => 3;
        market_id_buy => 4;
        [user_id_to(id) => 5 for id in 1:length(user_set)];
    ])

    # create an ordering of the labels
    order_list = Dict(id => id +1 for id in 1:length(name_units))
    
    source_sank = Int[]  # sources of the Sankey
    target_sank = Int[]  # targets of the Sankey
    value_sank = Float64[]  # value of each flow

    # calculate produced energy and energy sold to the market by user
    for (u_i, u_name) in enumerate(user_set)
        
        demand_market = grid_import[u_name]
        prod_market = grid_export[u_name]
        shared_en = shared_production[u_name]
        shared_cons = shared_consumption[u_name]
        self_cons = self_consumption[u_name]

        # energy sold to the grid
        total_sold = prod_market + shared_en
        if total_sold > 0.001
            append!(source_sank, user_id_from(u_i))
            append!(target_sank, market_id_sell)
            append!(value_sank, total_sold)
        end
        
        # energy bought from the grid
        total_bought = demand_market + shared_cons
        if total_bought > 0.001
            append!(source_sank, market_id_buy)
            append!(target_sank, user_id_to(u_i))
            append!(value_sank, total_bought)
        end
        
        # self consumption user to user
        if total_bought > 0.001
            append!(source_sank, user_id_from(u_i))
            append!(target_sank, user_id_to(u_i))
            append!(value_sank, self_cons)
        end
    end

    # market_sell to shared energy
    total_shared_prod = sum(shared_production[u] for u in user_set)
    if total_shared_prod > 0.001
        append!(source_sank, market_id_sell)
        append!(target_sank, community_id)
        append!(value_sank, total_shared_prod)
    end

    # shared consumption to market_buy
    total_shared_cons = sum(shared_consumption[u] for u in user_set)
    if total_shared_cons > 0.001
        append!(source_sank, community_id)
        append!(target_sank, market_id_buy)
        append!(value_sank, total_shared_cons)
    end

    if !isnothing(norm_value)
        value_sank = value_sank/maximum(value_sank)*norm_value
    end

    # s = sankey(name_units, source_sank.-1, target_sank.-1, value_sank)  # ECharts style
    colors_ids_users = mod1.(1:length(user_set), length(users_colors))
    tot_colors = [
        users_colors[colors_ids_users];
        market_color;
        community_color;
        market_color;
        users_colors[colors_ids_users]
    ]

    # Check and remove the ids that do not appear in the lists
    no_shows = []
    for i=1:length(name_units)
        if !((i in source_sank) || (i in target_sank))
            append!(no_shows, i)
        end
    end
    if !isempty(no_shows)
        # auxiliary functions definition
        update_index(data_idx, no_shows) = map((x) -> x - sum(x .> no_shows), data_idx)
        update_index!(data_idx, no_shows) = map!((x) -> x - sum(x .> no_shows), data_idx, data_idx)
        # map!((x) -> x - sum(x .> no_shows), source_sank, source_sank)
        # map!((x) -> x - sum(x .> no_shows), target_sank, target_sank)
        update_index!(source_sank, no_shows)
        update_index!(target_sank, no_shows)
        deleteat!(name_units, no_shows)
        deleteat!(tot_colors, no_shows)
        filter!(x->!(x.first in no_shows), node_layer)
        filter!(x->!(x.first in no_shows), order_list)
        
        node_layer = Dict(update_index(k, no_shows) => node_layer[k] for k in keys(node_layer))
        order_list = Dict(update_index(k, no_shows) => update_index(order_list[k], no_shows) for k in keys(order_list))
    end

    data_sort = sortslices(hcat(source_sank, target_sank, value_sank),
        dims=1,by=x->(x[1],x[2]),rev=false)
    source_sank = convert.(Int, data_sort[:, 1])
    target_sank = convert.(Int, data_sort[:, 2])
    value_sank = data_sort[:, 3]

    # Dictionary to return output data if desired
    sank_data = Dict(
        "source"=>source_sank,
        "target"=>target_sank,
        "value"=>value_sank,
        "labels"=>name_units,
        "colors"=>tot_colors,
        "layer"=>node_layer,
        "order"=>order_list,
    )
    
    return sank_data
end


"""
    plot_sankey(ECModel::AbstractEC, sank_data::Dict)

Function to plot the Sankey diagram representing the energy flows across the energy community.
This function can be used to plot the sankey diagram of already processed data sank_data.

Inputs
------
ECModel : AbstractEC
    Energy Community model
name_units : (optional) Vector
    Labels used for the sankey diagram with the following order:
    "Market buy", [users labels], "Community", "Market sell", [users labels]

"""
function plot_sankey(ECModel::AbstractEC, sank_data::Dict; label_size = 10)

    # Version for SankeyPlots.jl
    handle_plot = SankeyPlots.sankey(sank_data["source"], sank_data["target"], sank_data["value"];
        node_labels=sank_data["labels"],
        node_colors=sank_data["colors"],
        edge_color=:gradient,
        compact=true,
        label_size=label_size,
        force_layer=collect(pairs(sank_data["layer"])),
        force_order=collect(pairs(sank_data["order"])),
        )  # SankeyPlots style

    # Version for ECharts
    # handle_plot = ECharts.sankey(name_units, source_sank.-1, target_sank.-1, value_sank)
    
    return handle_plot
end


"""
    plot_sankey(ECModel::AbstractEC)

Function to plot the Sankey diagram representing the energy flows across the energy community

Inputs
------
ECModel : AbstractEC
    Energy Community model
name_units : (optional) Vector
    Labels used for the sankey diagram with the following order:
    "Market buy", [users labels], "Community", "Market sell", [users labels]

"""
function plot_sankey(ECModel::AbstractEC;
        name_units=nothing,
        norm_value=nothing,
        market_color = palette(:rainbow)[2],
        community_color = palette(:rainbow)[5],
        users_colors = palette(:default),
        label_size = 10,
    )

    sank_data = data_sankey(ECModel;
        name_units=name_units,
        norm_value=norm_value,
        market_color=market_color,
        community_color=community_color,
        users_colors=users_colors
    )
    
    return plot_sankey(ECModel, sank_data; label_size=label_size)
end

"""
    split_financial_terms(ECModel::AbstractEC, profit_distribution)

Function to describe the cost term distributions by all users.

Parameters
----------
- ECModel : AbstractEC
    EnergyCommunity model
- profit_distribution
    Final objective function

Returns
-------
    The output value is a NamedTuple with the following elements
    - NPV: the NPV of each user given the final profit_distribution adjustment
    by game theory techniques
    - CAPEX: the annualized CAPEX
    - OPEX: the annualized operating costs (yearly maintenance and yearly peak and energy grid charges)
    - REP: the annualized replacement costs
    - RV: the annualized recovery charges
    - REWARD: the annualized reward distribution by user
    - PEAK: the annualized peak costs
    - EN_SELL: the annualized revenues from energy sales
    - EN_BUY: the annualized costs from energy consumption and buying
    - EN_NET: the annualized net energy costs
"""
function split_financial_terms(ECModel::AbstractEC, profit_distribution=nothing)
    if isnothing(profit_distribution)
        user_set = get_user_set(ECModel)
        profit_distribution = JuMP.Containers.DenseAxisArray(
            fill(0.0, length(user_set)),
            user_set,
        )
    end
    @assert termination_status(ECModel) != MOI.OPTIMIZE_NOT_CALLED
    
    gen_data = ECModel.gen_data
    users_data = ECModel.users_data
    market_data = ECModel.market_data
    
    project_lifetime = field(gen_data, "project_lifetime")

    get_value = ((dense_axis, element) -> (if (element in axes(dense_axis)[1]) dense_axis[element] else 0.0 end))

    user_set = axes(profit_distribution)[1]
    year_set = 1:project_lifetime

    ann_factor = sum(1. ./((1 + field(gen_data, "d_rate")).^year_set))

    # Investment costs
    CAPEX = JuMP.Containers.DenseAxisArray(
        [get_value(ECModel.results[:CAPEX_tot_us], u) for u in user_set]
        , user_set
    )
    # Maintenance costs
    Ann_Maintenance = JuMP.Containers.DenseAxisArray(
        [get_value(ECModel.results[:C_OEM_tot_us], u) * ann_factor for u in user_set]
        , user_set
    )
    # Replacement costs
    Ann_Replacement = JuMP.Containers.DenseAxisArray(
        [
            sum([
                get_value(ECModel.results[:C_REP_tot_us][y, :], u) / ((1 + field(gen_data, "d_rate"))^y)
                for y in year_set
            ])
            for u in user_set
        ]
        , user_set
    )
    # Recovery value
    Ann_Recovery = JuMP.Containers.DenseAxisArray(
        [
            sum([
                get_value(ECModel.results[:R_RV_tot_us][y, :], u) / ((1 + field(gen_data, "d_rate"))^y)
                for y in year_set
            ])
            for u in user_set
        ]
        , user_set
    )

    # Peak energy charges
    Ann_peak_charges = JuMP.Containers.DenseAxisArray(
        [get_value(ECModel.results[:C_Peak_tot_us], u) * ann_factor for u in user_set]
        , user_set
    )

    # Get revenes by selling energy and costs by buying or consuming energy
    zero_if_negative = x->((x>=0) ? x : 0.0)
    Ann_energy_revenues = JuMP.Containers.DenseAxisArray(
        [
            if (u in axes(ECModel.results[:R_Energy_us])[1])
                sum(zero_if_negative.(ECModel.results[:R_Energy_us][u, :])) * ann_factor
            else
                0.0
            end
            for u in user_set
        ],
        user_set
    )
    Ann_energy_costs = JuMP.Containers.DenseAxisArray(
        [
            if (u in axes(ECModel.results[:R_Energy_us])[1])
                sum(zero_if_negative.(.-(ECModel.results[:R_Energy_us][u, :]))) * ann_factor
            else
                0.0
            end
            for u in user_set
        ],
        user_set
    )
    Ann_net_energy_costs = Ann_energy_costs .- Ann_energy_revenues
    
    # Total OPEX costs
    OPEX = Ann_Maintenance .+ Ann_peak_charges .+ Ann_net_energy_costs

    # get NPV given the reward allocation
    NPV = profit_distribution

    # Total reward
    Ann_reward = JuMP.Containers.DenseAxisArray(
        [
            NPV[u] + (CAPEX[u] + OPEX[u] + Ann_Replacement[u] - Ann_Recovery[u])
            for u in user_set
        ],
        user_set
    )
    
    return (
        NPV=NPV,
        CAPEX=CAPEX,
        OPEX=OPEX,
        OEM = Ann_Maintenance,
        REP=Ann_Replacement,
        RV=Ann_Recovery,
        REWARD=Ann_reward,
        PEAK=Ann_peak_charges,
        EN_SELL=Ann_energy_revenues,
        EN_CONS=Ann_energy_costs,
        EN_NET=Ann_net_energy_costs,
    )
end

""" TO BE IMPROVED
split_yearly_financial_terms(ECModel::AbstractEC, profit_distribution)

Function to describe the cost term distributions by all users for all years.

Parameters
----------
- ECModel : AbstractEC
    EnergyCommunity model
- profit_distribution
    Final objective function
- user_set_financial
    User set to be considered for the financial analysis

Returns
-------
    The output value is a NamedTuple with the following elements
    - NPV: the NPV of each user given the final profit_distribution adjustment
    by game theory techniques
    - CAPEX: the annualized CAPEX
    - OPEX: the annualized operating costs (yearly maintenance and yearly peak and energy grid charges)
    - REP: the annualized replacement costs
    - RV: the annualized recovery charges
    - REWARD: the annualized reward distribution by user
    - PEAK: the annualized peak costs
    - EN_SELL: the annualized revenues from energy sales
    - EN_BUY: the annualized costs from energy consumption and buying
    - EN_NET: the annualized net energy costs
"""

function split_yearly_financial_terms(ECModel::AbstractEC, profit_distribution=nothing)
    gen_data = ECModel.gen_data
    
    project_lifetime = field(gen_data, "project_lifetime")

    get_value = (dense_axis, element) -> (element in axes(dense_axis)[1] ? dense_axis[element] : 0.0)
    zero_if_negative = x->((x>=0) ? x : 0.0)

    year_set = 0:project_lifetime
   
    user_set_financial = [EC_CODE; get_user_set(ECModel)]

    if isnothing(profit_distribution)
        user_set = get_user_set(ECModel)
        profit_distribution = JuMP.Containers.DenseAxisArray(
            fill(0.0, length(user_set)),
            user_set,
        )
    end

    @assert termination_status(ECModel) != MOI.OPTIMIZE_NOT_CALLED

    user_set = axes(profit_distribution)[1]
    ann_factor = [1. ./((1 + field(gen_data, "d_rate")).^y) for y in year_set]

    # Investment costs
    CAPEX = JuMP.Containers.DenseAxisArray(
        [(y == 0) ? sum(Float64[get_value(ECModel.results[:CAPEX_tot_us], u)]) : 0.0
            for y in year_set, u in setdiff(user_set_financial, [EC_CODE])]
           , year_set, user_set_financial
    )
    # Maintenance costs
    Ann_Maintenance = JuMP.Containers.DenseAxisArray(
        [get_value(ECModel.results[:C_OEM_tot_us], u)
            for y in year_set, u in setdiff(user_set_financial, [EC_CODE])]
        , year_set, user_set_financial
    )
    # Replacement costs
    #The index is 1:20 so in the result should be proper changed. I'll open an issue
    Ann_Replacement = JuMP.Containers.DenseAxisArray(
            [(y == 10) ? get_value(ECModel.results[:C_REP_tot_us][y, :], u) : 0.0 
                for y in year_set, u in setdiff(user_set_financial, [EC_CODE])]
            , year_set, user_set_financial
     )
    # Recovery value
    Ann_Recovery = JuMP.Containers.DenseAxisArray(
        [(y == project_lifetime) ? (get_value(ECModel.results[:R_RV_tot_us][y, :], u)) : 0.0
            for y in year_set, u in setdiff(user_set_financial, [EC_CODE])]
                , year_set, user_set_financial
    )
    # Peak energy charges
    Ann_peak_charges = JuMP.Containers.DenseAxisArray(
        [get_value(ECModel.results[:C_Peak_tot_us], u)
            for y in year_set, u in setdiff(user_set_financial, [EC_CODE])]
                , year_set, user_set_financial
    )
    # Get revenes by selling energy and costs by buying or consuming energy
    Ann_energy_revenues = JuMP.Containers.DenseAxisArray(
        [(u in axes(ECModel.results[:R_Energy_us])[1]) ? sum(zero_if_negative.(ECModel.results[:R_Energy_us][u,:])) : 0.0
            for y in year_set, u in setdiff(user_set_financial, [EC_CODE])]
            , year_set, user_set_financial
    )
    Ann_energy_costs = JuMP.Containers.DenseAxisArray(
        [(u in axes(ECModel.results[:R_Energy_us])[1]) ? sum(zero_if_negative.(.-(ECModel.results[:R_Energy_us][u, :]))) : 0.0
        for y in year_set, u in setdiff(user_set_financial, [EC_CODE])]
            , year_set, user_set_financial
    )

    Ann_energy_reward = JuMP.Containers.DenseAxisArray(
        [ECModel == ECModel ? ECModel.results[:R_Reward_agg_tot] : 0.0
        for y in year_set, u in [EC_CODE]]
            , year_set, user_set_financial
    )

    # Total OPEX costs
    # I think that I miss the reward here
    Ann_ene_net_costs = Ann_energy_costs .- Ann_energy_revenues

    OPEX = Ann_Maintenance .+ Ann_peak_charges .+ Ann_ene_net_costs 

    # get NPV given the reward allocation
    #=
    Basically, what we may need to do is to create a proxy total discounted cost of all terms but NPV so to reproduce the old (CAPEX .+ OPEX .+ Ann_Replacement .- Ann_Recovery).
    For example, something like:
    (CAPEX .+ OPEX .+ Ann_Replacement .- Ann_Recovery).data * ann_factor (note that since they are matrix operation, there may be the need for some transpositions

    Then, the resulting vector shall be a 1 column or 1 vector and we can create the equivalent 1D cost vector, so that we can do (total_discounted_reward = NPV .- new_vector).
    Then, we can do total_discounted_reward ./(sum(act_factor) - 1) and this should be a 1D vector of the yearly reward allocation by user, that can be exploded into 2D by simply duplicating the entries.

    =#
    NPV = JuMP.Containers.DenseAxisArray(
        [get_value(profit_distribution, u)
            for u in setdiff(user_set_financial, [EC_CODE])]
                , user_set_financial
    )

    # Total reward
    # This is the total discounted cost of all terms but NPV. I think that this must be improved
    total_discounted_cost= CAPEX .+ OPEX .+ Ann_Replacement .- Ann_Recovery

    #=Ann_reward = JuMP.Containers.DenseAxisArray(
        [(NPV[u] .- sum(total_discounted_cost[:,u]))/(sum(ann_factor) - 1) for y in year_set, u in setdiff(user_set_financial, [EC_CODE])]
            , year_set, user_set_financial
    )=#

    return (
        NPV=NPV,
        CAPEX=CAPEX,
        OPEX=OPEX,
        OEM = Ann_Maintenance,
        REP = Ann_Replacement,
        RV = Ann_Recovery,
        REWARD = Ann_energy_reward,
        PEAK = Ann_peak_charges,
        EN_SELL = Ann_energy_revenues,
        EN_CONS = Ann_energy_costs,
        year_set = year_set
    )
end

"""
    business_plan(ECModel::AbstractEC, profit_distribution)

Function to describe the cost term distributions by all users for all years.

Parameters
----------
- ECModel : AbstractEC
    EnergyCommunity model
- profit_distribution
    Final objective function
- user_set_financial
    User set to be considered for the financial analysis

Returns
-------
    The output value is a NamedTuple with the following elements
    - df_business
        Dataframe with the business plan information
"""

function business_plan(ECModel::AbstractEC,profit_distribution=nothing, user_set_financial=nothing)
    gen_data = ECModel.gen_data
    
    project_lifetime = field(gen_data, "project_lifetime")
    
    if isnothing(user_set_financial)
        user_set_financial = get_user_set(ECModel)
    end

    # Create a vector of years from 2023 to (2023 + project_lifetime)
    gen_data = ECModel.gen_data
    project_lifetime = field(gen_data, "project_lifetime")

    business_plan = split_yearly_financial_terms(ECModel)
    year_set = business_plan.year_set

    # Create an empty DataFrame
    df_business = DataFrame(Year = Int[], CAPEX = Float64[], OEM = Float64[], EN_SELL = Float64[], EN_CONS = EN_SELL = Float64[], PEAK = Float64[], REP = Float64[], 
    REWARD = Float64[], RV = Float64[])
    for i in year_set
        Year = 0 + year_set[i+1]
        CAPEX = sum(business_plan.CAPEX[i, :])
        OEM = sum(business_plan.OEM[i, :])
        EN_SELL = sum(business_plan.EN_SELL[i, :])
        EN_CONS = sum(business_plan.EN_CONS[i, :])
        PEAK = sum(business_plan.PEAK[i, :])
        REP = sum(business_plan.REP[i, :])
        REWARD = sum(business_plan.REWARD[i, :])
        RV = sum(business_plan.RV[i, :])
        push!(df_business, (Year, CAPEX, OEM,  EN_SELL, EN_CONS, PEAK, REP, REWARD, RV))
    end

    return df_business
end

"""
    business_plan_plot(ECModel::AbstractEC, profit_distribution)

Function to describe the cost term distributions by all users for all years.

Parameters
----------
- ECModel : AbstractEC
    EnergyCommunity model
- df_business
    Dataframe with the business plan information

Returns
-------
    The output value is a plot with the business plan information
"""

function business_plan_plot(ECModel::AbstractEC, df_business=nothing)
    if df_business === nothing
        df_business = business_plan(ECModel)
    end

    # Extract the required columns from the DataFrame
    years = df_business.Year
    capex = -df_business.CAPEX
    oem = -df_business.OEM
    en_sell = df_business.EN_SELL
    en_cons = -df_business.EN_CONS
    rep = -df_business.REP
    reward = df_business.REWARD
    rv = df_business.RV
    peak = -df_business.PEAK

    # Create a bar plot
    p = bar(years, [capex, oem, en_sell, en_cons, rep, reward, rv, peak],
            label=["CAPEX" "OEM" "Energy sell" "Energy consumption" "Replacement" "Reward" "Recovery" "Peak charges"],
            xlabel="Year", ylabel="Amount [€]",
            title="Business Plan Over 20 Years",
            #ylims=(maximum([capex; oem; en_cons; rep; peak]), maximum([oem; en_sell; reward; rv])*1.2),
            legend=:bottomright,
            color=:auto,
            xrotation=45,
            bar_width=0.6,
            grid=false,
            framestyle=:box,
            barmode=:stack,
            )

    #p = @df_business df_business bar(:Year, [:CAPEX, :OEM, :EN_SELL, :EN_CONS, :REP, :REWARD, :RV, :PEAK], xlabel="Year", ylabel="Value", title="Business plan information", bar_position=:stacked, bar_width=0.5, color=[:red :blue :green :orange :purple :yellow :brown :pink], legend=:topleft)

    print(df_business)
    savefig(p, joinpath("results","Img","business_plan","CO")) # Save the plot
    return p
end

function EnergyCommunity.split_financial_terms(ECModel::AbstractEC, profit_distribution::Dict)
    return split_financial_terms(
        ECModel,
        JuMP.Containers.DenseAxisArray(
            collect(values(profit_distribution)),
            collect(keys(profit_distribution)),
        )
    )
end
