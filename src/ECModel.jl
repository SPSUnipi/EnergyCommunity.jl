"Return main data elements of the dataset of the ECModel: general parameters, users data and market data"
function explode_data(ECModel::AbstractEC)
    return general(ECModel.data), users(ECModel.data), market(ECModel.data)
end


"Set the EC group type"
function set_group_type!(ECModel::AbstractEC, group::AbstractGroup)
    ECModel.group_type = group
end

"Build the mathematical problem for the EC"
function build_model!(ECModel::AbstractEC)

    # build the model
    build_model!(ECModel.group_type, ECModel, ECModel.optimizer)

    # return the model
    return ECModel
end

"Abstract build function model for generic EnergyCommunity model"
function build_model!(group_type::AbstractGroup, ECModel::AbstractEC, optimizer)

    # the build model for the NC/ANC case is eqvuivalent to the base model
    build_base_model!(ECModel, optimizer)

    # add the NC/ANC-specific model
    build_specific_model!(group_type, ECModel)

    # set objective
    set_objective!(group_type, ECModel)

    # return the model
    return ECModel
end


"Solve the optimization problem for the EC"
function JuMP.optimize!(ECModel::AbstractEC)
    optimize!(ECModel.model)
    ECModel.results = jump_to_dict(ECModel.model)
    return ECModel
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

    # check if the group_type is compatible with the available instances
    if !any([string(g) == raw_data["group_type"] for g in subtypes(AbstractGroup)])
        throw(ArgumentError("File $output_file not a valid EC group type"))
    end

    ## load data
    ECModel.data = raw_data["data"]
    ECModel.gen_data = general(ECModel.data)
    ECModel.market_data = market(ECModel.data)
    ECModel.users_data = users(ECModel.data)

    # load user_set available from configuration file
    user_set_from_user_list = collect(keys(ECModel.users_data))

    ## load user_set
    ECModel.user_set = unique(get(raw_data, "user_set", user_set_from_user_list))

    if isempty(ECModel.user_set)  # check if user_set is not empty
        throw(Error("user_set in configuration file $output_file is empty"))
    else  # check if all user_set names are available in the config
        diffset = setdiff(Set(ECModel.user_set), Set(user_set_from_user_list))  # elements of user_set not in the config
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
function FileIO.load(output_file::AbstractString)
    return load!(output_file, ModelEC())
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
    plotting=true,
    name_units=nothing,
    norm_value=nothing,
    market_color = palette(:rainbow)[2],
    community_color = palette(:rainbow)[5],
    users_colors = palette(:default)
    )

    user_set = ECModel.user_set

    # specify labels if not provided
    if isnothing(name_units)
        name_units = ["Market buy"; string.(user_set) .* " prod.";
            "Community"; "Market sell"; string.(user_set) .* " cons."]
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
    market_id_from = 1
    market_id_to = length(user_set) + 3
    community_id = length(user_set) + 2
    user_id_from(x) = x + 1
    user_id_to(x) = x + length(user_set) + 3

    # specify the desired location of each entity id in the layers of the Sankey diagram
    # On the first layers all users that produce energy and the market when buying
    # On the second layer "Community"
    # On the third layer all users that consume energy and the market when selling
    node_layer = Dict([
        market_id_from => 1;
        [user_id_from(id) => 1 for id in 1:length(user_set)];
        community_id => 2;
        market_id_to => 3;
        [user_id_to(id) => 3 for id in 1:length(user_set)];
    ])

    # create an ordering of the labels
    order_list = Dict(id => id +1 for id in 1:length(name_units) if market_id_to != id)
    push!(order_list, length(name_units)=>market_id_to)  # move market to before the users
    
    source_sank = Int[]  # sources of the Sankey
    target_sank = Int[]  # targets of the Sankey
    value_sank = Float64[]  # value of each flow

    # calculate produced energy and energy sold to the market by user
    for (u_i, u_name) in enumerate(user_set)
        # demand from the market
        demand_market = grid_import[u_name]
        if demand_market > 0.001
            append!(source_sank, market_id_from)
            append!(target_sank, user_id_to(u_i))
            append!(value_sank, demand_market)
        end

        # production to the market
        prod_market = grid_export[u_name]
        if prod_market > 0.001
            append!(source_sank, user_id_from(u_i))
            append!(target_sank, market_id_to)
            append!(value_sank, prod_market)
        end

        # shared energy
        shared_en = shared_production[u_name]
        if shared_en > 0.001
            append!(source_sank, user_id_from(u_i))
            append!(target_sank, community_id)
            append!(value_sank, shared_en)
        end

        # shared consumption
        shared_cons = shared_consumption[u_name]
        if shared_cons > 0.001
            append!(source_sank, community_id)
            append!(target_sank, user_id_to(u_i))
            append!(value_sank, shared_cons)
        end
        
        # self consumption
        self_cons = self_consumption[u_name]
        if self_cons > 0.001
            append!(source_sank, user_id_from(u_i))
            append!(target_sank, user_id_to(u_i))
            append!(value_sank, self_cons)
        end
    end

    if !isnothing(norm_value)
        value_sank = value_sank/maximum(value_sank)*norm_value
    end

    # s = sankey(name_units, source_sank.-1, target_sank.-1, value_sank)  # ECharts style
    tot_colors = [market_color; users_colors[1:length(user_set)]; community_color;
        market_color; users_colors[1:length(user_set)]]

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

    # initialize handle_plot
    handle_plot = nothing

    # if plotting is true, then plot the graph
    if plotting
        # Version for SankeyPlots.jl
        # handle_plot = sankey(source_sank, target_sank, value_sank;
        #     node_labels=name_units,
        #     node_colors=tot_colors,
        #     edge_color=:gradient,
        #     compact=true,
        #     label_size=15,
        #     opt_layer_assign=node_layer,
        #     opt_node_order=order_list
        #     )  # SankeyPlots style

        # Version for ECharts
        handle_plot = ECharts.sankey(name_units, source_sank.-1, target_sank.-1, value_sank)
    end
    
    return handle_plot, sank_data
end