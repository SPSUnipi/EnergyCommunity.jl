# """

# Builds the specific model for the Non-Cooperative (and Aggregated Non-Cooperative) models
# """
# function build_model!(group_type::AbstractGroupNC, ECModel::AbstractEC, optimizer)
#     # the build model for the NC/ANC case is eqvuivalent to the base model
#     build_base_model!(ECModel, optimizer)

#     # add the NC/ANC-specific model
#     build_specific_model!(group_type, ECModel)

#     # set objective
#     set_objective!(group_type, ECModel)
#     return ECModel
# end


"""

Set the NC/ANC-specific model for the EC
"""
function build_specific_model!(::AbstractGroupNC, ECModel::AbstractEC)

    # get user set
    user_set = ECModel.user_set
    # general data dictionary
    gen_data = ECModel.gen_data

    # get time set
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    time_set = 1:n_steps

    # Energy flow at the aggregation level
    @expression(ECModel.model, P_agg[t = time_set],
        sum(ECModel.model[:P_us][:, t])
    )

    return ECModel
end


"""
    Function to set the objective function of the model of the Non-Cooperative model
"""
function set_objective!(::AbstractGroupNC, ECModel::AbstractEC)
    ## Setting the objective

    # Setting the objective of maximizing the annual profits NPV_us
    @objective(ECModel.model, Max, sum(
        ECModel.model[:NPV_us][u] for u in ECModel.user_set))

    return ECModel
end


""" 
    print_summary(::AbstractGroupNC, ECModel::AbstractEC)
Function to print the main results of the model
"""
function print_summary(::AbstractGroupNC, ECModel::AbstractEC)

    # get main parameters
    gen_data = ECModel.gen_data
    users_data = ECModel.users_data
    market_data = ECModel.market_data

    n_users = length(users_data)
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    project_lifetime = field(gen_data, "project_lifetime")
    

    # Set definitions
    user_set = ECModel.user_set
    year_set = 1:project_lifetime
    time_set = 1:n_steps
    peak_categories = profile(gen_data,"peak_categories")
    peak_set = unique(peak_categories)
    
    # parameters
    user_set = ECModel.user_set
    results = ECModel.results

    # set of all types of assets among the users
    asset_set_unique = unique([name for u in user_set for name in asset_names(users_data[u])])

    ## Print general outputs
    printfmtln("\nRESULTS - AGGREGATOR")

    printf_code_user = string("{:<18s}: {: 7.2e}", join([", {: 7.2e}" for i in 1:length(user_set) if i > 1]))
    printf_code_description = string("{:<18s}: {:>9s}", join([", {:>9s}" for i in 1:length(user_set) if i > 1]))
    printf_code_energy_share = string("{:<18s}: ", join([if (a == asset_set_unique[1]) "{: 7.2e}" else ", {: 7.2e}" end for a in asset_set_unique]))

    printfmtln(printf_code_description, "USER", [u for u in user_set]...)  # heading
    for a in asset_set_unique  # print capacities of each asset by user
        printfmtln(printf_code_user, a, [
            (a in device_names(users_data[u])) ? results[:x_us][u, a] : 0
                for u in user_set]...)
    end

    printfmtln(printf_code_user, "NPV [k€]", results[:NPV_us]/1000...)  # print NPV by user
    printfmtln(printf_code_user, "CAPEX [k€]",
        [sum(results[:CAPEX_tot_us][u]/1000)
            for u in user_set]...)  # print CAPEX by user
    printfmtln(printf_code_user, "OPEX [k€]",
        [sum(results[:C_OEM_tot_us][u]/1000)
            for u in user_set]...)  # print CAPEX by user
    printfmtln(printf_code_user, "YBill [k€]", results[:yearly_rev]/1000...)  # print yearly bill by user
    printfmtln(printf_code_user, "Cthermal [k€]", 
            [sum( !has_asset(users_data[u], THER) ? 0.0 : results[:C_gen_tot_us][u]/1000)
                for u in user_set]...)  # print costs of thermal generators
    printfmtln("\n\nEnergy flows")
    printfmtln(printf_code_description, "USER", [u for u in user_set]...)
    printfmtln(printf_code_user, "PtotPusP [MWh]",
        [sum(results[:P_P_us][u, :]) for u in user_set]/1000...)  # Total power supplied by user to the grid
    printfmtln(printf_code_user, "PtotPusN [MWh]",
        [sum(results[:P_N_us][u, :]) for u in user_set]/1000...)  # Total power bought by user from the grid
    printfmtln(printf_code_user, "PconvP [MWh]",
        [sum(Float64[results[:P_conv_P_us][u, c, t] 
                for c in asset_names(users_data[u], CONV) for t in time_set
            ]) for u in user_set]/1000...)  # Total power supplied by converters by user
    printfmtln(printf_code_user, "PconvN [MWh]",
        [sum(Float64[results[:P_conv_N_us][u, c, t] 
        for c in asset_names(users_data[u], CONV) for t in time_set
            ]) for u in user_set]/1000...)  # Total power loaded by converters by user
    printfmtln(printf_code_user, "Pren [MWh]",
        [sum(results[:P_ren_us][u,:]) for u in user_set]/1000...)  # Total power supplied by renewables by each user
    printfmtln(printf_code_user, "Pgen [MWh]",
        [sum(Float64[results[:P_gen_us][u, g, t] 
                for g in asset_names(users_data[u], THER) for t in time_set
            ]) for u in user_set]/1000...)  # Total power supplied by thermal generators by user
    printfmtln(printf_code_user, "Load [MWh]",
        [sum(
            Float64[profile_component(users_data[u], l, "load")[t]
                for t in time_set for l in asset_names(users_data[u], LOAD)]
        ) for u in user_set]/1000...)  # Total load by user

end


"""
    plot(::AbstractGroupNC, ECModel::AbstractEC, output_plot_file::AbstractString;
        user_set::Vector=Vector(), line_width=2.0)

Function to plot the results of the user model
"""
function Plots.plot(::AbstractGroupNC, ECModel::AbstractEC, output_plot_file::AbstractString;
    user_set::AbstractVector=Vector(), line_width=2.0)

    # get main parameters
    gen_data = ECModel.gen_data
    users_data = ECModel.users_data
    market_data = ECModel.market_data
    results = ECModel.results

    n_users = length(users_data)
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")

    n_steps = final_step - init_step + 1

    # Set definitions

    time_set_plot = init_step:final_step
    time_set = 1:n_steps

    # reset the user_set if not specified
    if isempty(user_set)
        user_set = ECModel.user_set
    end

    ## Retrive results

    ## Plots

    Plots.PlotlyBackend()
    pt = Array{Plots.Plot, 2}(undef, n_users, 3)
    lims_y_axis_dispatch = [(-30, 60),(-30, 60)]
    lims_y_axis_batteries = [(0, 120), (0, 120)]
    for (u_i, u_name) in enumerate(ECModel.user_set)

        # Power dispatch plot
        pt[u_i, 1] = plot(time_set_plot, [sum(Float64[profile_component(ECModel.users_data[u_name], l, "load")[t] 
                                        for l in asset_names(ECModel.users_data[u_name], LOAD)]) for t in time_set],
                        label="Load", w=line_width, legend=:outerright)
        plot!(pt[u_i, 1], time_set_plot, results[:P_us][u_name, :].data, label="Grid", w=line_width)
        plot!(pt[u_i, 1], time_set_plot, [
            sum(Float64[results[:P_conv_us][u_name, c, t] 
                for c in asset_names(users_data[u_name], CONV)]) for t in time_set],
            label="Converters", w=line_width)
        plot!(pt[u_i, 1], time_set_plot, results[:P_ren_us][u_name, :].data, label="Renewables", w=line_width)
        plot!(pt[u_i, 1], time_set_plot, [
            sum(Float64[results[:P_gen_us][u_name, g, t] 
                for g in asset_names(users_data[u_name], THER)]) for t in time_set],
            label="Thermal", w=line_width)
        xaxis!("Time step [#]")
        yaxis!("Power [kW]")
        # ylims!(lims_y_axis_dispatch[u])

        # Battery status plot
        pt[u_i, 2] = plot(time_set_plot, [
            sum(Float64[results[:E_batt_us][u_name, b, t] 
                for b in asset_names(users_data[u_name], BATT)]) for t in time_set],
                label="Energy      ", w=line_width, legend=:outerright)
        xaxis!("Time step [#]")
        yaxis!("Energy [kWh]")
        # ylims!(lims_y_axis_batteries[u])

        pt[u_i,3] = plot(pt[u_i, 1], pt[u_i, 2], layout=(2,1))
        display(pt[u_i,3])

        # if the output file is specified save the plots to file
        if !isempty(output_plot_file)
            # get file path where to save the image
            file_path = format(output_plot_file, u_i)

            # create folder if it doesn't exists
            mkpath(dirname(file_path))

            # save as 
            png(pt[u_i, 3], file_path)
        end
    end
end


"""

Function to create the dataframe to report the status of the optimization
"""
function add_info_solution_summary!(
    output_list::Vector, ECModel::AbstractEC)

    _solve_time = ECModel.results[:solve_time]  # solve_time(ECModel.model)
    _termination_status = ECModel.results[:termination_status]  # Int(termination_status(ECModel.model))  # termination status

    info_solution = DataFrames.DataFrame(comp_time = _solve_time, exit_flag=_termination_status)

    # add dataframe to the output list
    push!(output_list, "info_solution"=>info_solution)
end

"""

Function to create the output dataframe of design capacity
"""
function add_users_design_summary!(
    output_list::Vector, ECModel::AbstractEC, user_set::AbstractVector)

    # get main parameters
    gen_data = ECModel.gen_data
    users_data = ECModel.users_data
    market_data = ECModel.market_data
    
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")

    # Set definitions
    time_set = init_step:final_step

    asset_set_unique = unique([name for u in user_set for name in asset_names(users_data[u])])

    ## Retrive results

    _x_us = ECModel.results[:x_us] # Optimal size of the system
    
    design_users = DataFrames.DataFrame(
        vcat(
            [[u for u in user_set]],
            [[maximum(sum(Float64[profile_component(users_data[u], l, "load")[t]
                for l in asset_names(users_data[u]) if asset_type(users_data[u], l) == LOAD]) for t in time_set) for u in user_set]],
            [[sum(Float64[profile_component(users_data[u], l, "load")[t] * profile(ECModel.gen_data, "energy_weight")[t] * profile(ECModel.gen_data,"time_res")[t]/1000
                for t in time_set for l in asset_names(users_data[u], LOAD)]) for u in user_set]],
            [[if (a in device_names(users_data[u])) _x_us[u, a] else missing end for u in user_set] for a in asset_set_unique]
        ),
        map(Symbol, vcat("User", "Peak demand [kW]", "Yearly Demand [MWh]", ["x_us_$a" for a in asset_set_unique]))
    )

    # add dataframe to the output list
    push!(output_list, "design_users"=>design_users)
end


"""

Function to create the output dataframe of the users' economics
"""
function add_users_economics_summary!(
    output_list::Vector, ECModel::AbstractEC, user_set::AbstractVector)

    # get main parameters
    gen_data = ECModel.gen_data
    users_data = ECModel.users_data
    market_data = ECModel.market_data

    n_users = length(users_data)
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    project_lifetime = field(gen_data, "project_lifetime")
    

    # Set definitions
    user_set = ECModel.user_set
    year_set = 1:project_lifetime
    time_set = init_step:final_step
    peak_categories = profile(gen_data,"peak_categories")
    peak_set = unique(peak_categories)

    asset_set_unique = unique([name for u in user_set for name in asset_names(users_data[u])])

    ## Retrive results

    _x_us = ECModel.results[:x_us]  # Optimal size of the system
    _E_batt_us = ECModel.results[:E_batt_us]  # Energy stored in the battery
    _E_batt_tot_us = JuMP.Containers.DenseAxisArray([sum(Float64[_E_batt_us[u, b, t] for b in asset_names(users_data[u], BATT)]) for u in user_set, t in time_set], user_set, time_set)  # Total energy available in the batteries
    _P_conv_P_us = ECModel.results[:P_conv_P_us] # Converter dispatch positive when supplying to AC
    _P_conv_P_tot_us = JuMP.Containers.DenseAxisArray([sum(Float64[_P_conv_P_us[u, c, t] for c in asset_names(users_data[u])  if asset_type(users_data[u], c) == CONV]) for u in user_set, t in time_set], user_set, time_set)  # Total converters dispatch when supplying to the grid
    _P_conv_N_us = ECModel.results[:P_conv_N_us]  # Converter dispatch positive when absorbing from AC
    _P_conv_N_tot_us = JuMP.Containers.DenseAxisArray([sum(Float64[_P_conv_N_us[u, c, t] for c in asset_names(users_data[u])  if asset_type(users_data[u], c) == CONV]) for u in user_set, t in time_set], user_set, time_set)  # Total converters dispatch when absorbing from the grid
    _P_conv_tot_us = JuMP.Containers.DenseAxisArray([_P_conv_P_tot_us[u, t] - _P_conv_N_tot_us[u, t] for u in user_set, t in time_set], user_set, time_set)  # Total converters dispatch
    _P_conv_us = JuMP.Containers.SparseAxisArray(Dict((u, c, t) => _P_conv_P_us[u, c, t] - _P_conv_N_us[u, c, t]  for u in user_set for c in asset_names(users_data[u])  if asset_type(users_data[u], c) == CONV for t in time_set))  # converter dispatch
    _P_ren_us = ECModel.results[:P_ren_us]  # Dispath of renewable assets
    _P_gen_us = ECModel.results[:P_gen_P_us] # Thermal generators dispatch 
    _P_gen_tot_us = JuMP.Containers.DenseAxisArray([sum(Float64[_P_gen_P_us[u, g, t] for g in asset_names(users_data[u])  if asset_type(users_data[u], g) == THER]) for u in user_set, t in time_set], user_set, time_set)  # Total converters dispatch when supplying to the grid
    _P_max_us = ECModel.results[:P_max_us]  # Maximum dispatch of the user for every peak period
    _P_tot_P_us = ECModel.results[:P_P_us]  # Total dispatch of the user, positive when supplying to public grid
    _P_tot_N_us = ECModel.results[:P_N_us]  # Total dispatch of the user, positive when absorbing from public grid
    _P_tot_us = ECModel.results[:P_us]  # Total user dispatch

    _CAPEX_us = ECModel.results[:CAPEX_us]  # CAPEX by user and asset
    _CAPEX_tot_us = ECModel.results[:CAPEX_tot_us]  # Total CAPEX by user
    _C_OEM_us = ECModel.results[:C_OEM_us] # Maintenance cost by user and asset
    _C_OEM_tot_us = ECModel.results[:C_OEM_tot_us] # Total maintenance cost by asset
    _C_REP_us = ECModel.results[:C_REP_us]  # Replacement costs by user and asset
    _C_REP_tot_us = ECModel.results[:C_REP_tot_us]  # Total replacement costs by user
    _C_RV_us = ECModel.results[:C_RV_us]  # Residual value by user and asset
    _R_RV_tot_us = ECModel.results[:R_RV_tot_us]  # Residual value by user
    _yearly_rev = ECModel.results[:yearly_rev]  # yearly revenues by user
    _NPV_us = ECModel.results[:NPV_us]  # Annualized profits by the user
    _C_Peak_us = ECModel.results[:C_Peak_us]  # Peak tariff cost by user and peak period
    _C_Peak_tot_us = ECModel.results[:C_Peak_tot_us]  # Peak tariff cost by user
    _R_Energy_us = ECModel.results[:R_Energy_us]  # Energy revenues by user and time
    _R_Energy_tot_us = ECModel.results[:R_Energy_tot_us]  # Energy revenues by user
    _C_gen_tot_us = ECModel.results[:C_gen_tot_us]  # Generators cost

    economics_users = DataFrames.DataFrame(
        vcat(
            [user_set],
            [[_NPV_us[u] for u in user_set]],
            [_CAPEX_tot_us[:].data],
            [_yearly_rev[:].data],
            [_C_gen_tot_us[:].data],
            [[sum(1 / (1 + field(gen_data, "d_rate"))^y for y in year_set) * _C_OEM_tot_us[u] for u in user_set]],
            [[sum(_C_REP_tot_us[y, u] / (1 + field(gen_data, "d_rate"))^y for y in year_set) for u in user_set]],
            [[_R_RV_tot_us[project_lifetime, u] / (1 + field(gen_data, "d_rate"))^project_lifetime for u in user_set]],
            [[sum(1 / (1 + field(gen_data, "d_rate"))^y for y in year_set) * _C_Peak_tot_us[u] for u in user_set]],
            [[sum(1 / (1 + field(gen_data, "d_rate"))^y for y in year_set) * _R_Energy_tot_us[u] for u in user_set]],
            [[if (a in device_names(users_data[u])) _CAPEX_us[u, a] else missing end for u in user_set]
                for a in asset_set_unique],
            [[if (a in device_names(users_data[u])) _C_OEM_us[u, a] else missing end for u in user_set]
                for a in asset_set_unique]
        ),
            map(Symbol, vcat("User_id", "NPV_us", "CAPEX_tot_us", "yearly_rev", "C_gen_tot_us",
                "SDCF C_OEM_tot_us", "SDCF C_REP_tot_us", "SDCF R_RV_tot_us",
                "SDCF C_Peak_tot_us", "SDCF R_Energy_tot_us",
                ["CAPEX_us_$a" for a in asset_set_unique], ["C_OEM_us_$a" for a in asset_set_unique]))
    )

    # add dataframe to the output list
    push!(output_list, "economics_users"=>economics_users)
end


"""

Function to create the output dataframe of peak power
"""
function add_users_peak_summary!(
    output_list::Vector, ECModel::AbstractEC, user_set::AbstractVector)

    # get main parameters
    market_data = ECModel.market_data
    gen_data = ECModel.gen_data

    # Set definitions
    user_set = ECModel.user_set
    peak_categories = profile(gen_data,"peak_categories")
    peak_set = unique(peak_categories)

    ## Retrive results
    _P_max_us = ECModel.results[:P_max_us]  # Maximum dispatch of the user for every peak period

    peak_users = DataFrames.DataFrame(
        vcat(
            [[user_set]],
            [[_P_max_us[:, w].data] for w in peak_set]
        ),
            map(Symbol, ["User_id"; map(x->"Peak_id $x", peak_set)])
    )

    # add dataframe to the output list
    push!(output_list, "peak_users"=>peak_users)
end



"""
    prepare_summary(::AbstractGroupNC, ECModel::AbstractEC, file_summary_path::AbstractString;
        user_set::Vector=Vector())

Prepare the dataframe lists to be saved in an excel file

Outputs
-------
output_list: Vector{Pair{String, DataFrame}}
    Vector of pairs representing the sheets of the Excel file and the corresponding data to save
"""
function prepare_summary(::AbstractGroupNC, ECModel::AbstractEC; user_set::AbstractVector)

    # output list
    output_list = []

    # add solutions on the optimization process
    add_info_solution_summary!(output_list, ECModel)
    # add users design info
    add_users_design_summary!(output_list, ECModel, user_set)
    # add users economics
    add_users_economics_summary!(output_list, ECModel, user_set)
    # add peak power
    add_users_peak_summary!(output_list, ECModel, user_set)

    return output_list
end

"""
    calculate_grid_import(::AbstractGroupNC, ECModel::AbstractEC; per_unit::Bool=true)

Calculate grid usage for the Non-Cooperative case
Output is normalized with respect to the demand when per_unit is true

'''
Outputs
-------
grid_frac : DenseAxisArray
    Reliance on the grid demand for each user and the aggregation
'''
"""
function calculate_grid_import(::AbstractGroupNC, ECModel::AbstractEC; per_unit::Bool=true)

    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)

    gen_data = ECModel.gen_data
    market_data = ECModel.market_data

    # get time set
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    time_set = 1:n_steps

    # time step resolution
    time_res = profile(ECModel.gen_data,"time_res")
    energy_weight = profile(ECModel.gen_data,"energy_weight")

    _P_tot_us = ECModel.results[:P_us]  # power dispatch of users - users mode

    # fraction of grid resiliance of the aggregate case noagg
    grid_frac_tot = sum(Float64[-sum(min.(_P_tot_us[u,:], 0) .* time_res .* energy_weight) for u in user_set])
    
    # fraction of grid reliance with respect to demand by user noagg case
    grid_frac = JuMP.Containers.DenseAxisArray(
        vcat(
            grid_frac_tot,
            [-sum(min.(_P_tot_us[u,:] .* time_res .* energy_weight, 0))
                for u in user_set]
        ),
        user_set_EC
    )

    # normalize output if perunit is required
    if per_unit

        # calculate the demand by EC and user
        demand_EC_us = calculate_demand(ECModel)
        
        # update value
        grid_frac = grid_frac ./ demand_EC_us

    end
    
    return grid_frac
end

"""
    calculate_grid_export(::AbstractGroupNC, ECModel::AbstractEC; per_unit::Bool=true)

Calculate grid export for the Non-Cooperative case
Output is normalized with respect to the demand when per_unit is true

'''
Outputs
-------
grid_frac : DenseAxisArray
    Reliance on the grid demand for each user and the aggregation
'''
"""
function calculate_grid_export(::AbstractGroupNC, ECModel::AbstractEC; per_unit::Bool=true)

    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)

    gen_data = ECModel.gen_data
    market_data = ECModel.market_data

    # get time set
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    time_set = 1:n_steps

    # time step resolution
    time_res = profile(ECModel.gen_data,"time_res")
    energy_weight = profile(ECModel.gen_data,"energy_weight")

    _P_tot_us = ECModel.results[:P_us]  # power dispatch of users - users mode

    # fraction of grid resiliance of the aggregate case noagg
    grid_frac_tot = sum(Float64[sum(min.(_P_tot_us[u,:], 0) .* time_res .* energy_weight) for u in user_set])

    # fraction of grid reliance with respect to demand by user noagg case
    grid_frac = JuMP.Containers.DenseAxisArray(
        vcat(
            grid_frac_tot,
            [sum(max.(_P_tot_us[u,:] .* time_res .* energy_weight, 0))
                for u in user_set]
        ),
        user_set_EC
    )

    # normalize output if perunit is required
    if per_unit

        # calculate the demand by EC and user
        demand_EC_us = calculate_demand(ECModel)
        
        # update value
        grid_frac = grid_frac ./ demand_EC_us

    end
    
    return grid_frac
end

"""
    calculate_time_shared_production(::AbstractGroupNC, ECModel::AbstractEC; add_EC=true, kwargs...)

Calculate the time series of the shared produced energy for the Cooperative case.
In the Cooperative case, there can be shared energy between users, not only self production.

For every time step and user, this time series highlight the quantity of production that meets
needs by other users.

'''
Outputs
-------
shared_prod_us : DenseAxisArray
    Shared production for each user and the aggregation and time step
'''
"""
function calculate_time_shared_production(::AbstractGroupNC, ECModel::AbstractEC; add_EC=true, kwargs...)
    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)
    
    # shared energy produced by user and EC
    shared_prod_us = JuMP.Containers.DenseAxisArray(
        fill(0.0, add_EC ? length(user_set_EC) : length(user_set), length(time_set)),
        add_EC ? user_set_EC : user_set,
        time_set
    )

    return shared_prod_us
end

"""
    calculate_time_shared_consumption(::AbstractGroupNC, ECModel::AbstractEC; add_EC=true, kwargs...)

Calculate the time series of the shared consumed energy for the Cooperative case.
In the Cooperative case, there can be shared energy between users, not only self production.

For every time step and user, this time series highlight the quantity of load that is met
by using shared energy.

'''
Outputs
-------
shared_cons_us : DenseAxisArray
    Shared consumption for each user and the aggregation and time step
'''
"""
function calculate_time_shared_consumption(::AbstractGroupNC, ECModel::AbstractEC; add_EC=true, kwargs...)
    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)
    
    # shared energy produced by user and EC
    shared_cons_us = JuMP.Containers.DenseAxisArray(
        fill(0.0, add_EC ? length(user_set_EC) : length(user_set), length(time_set)),
        add_EC ? user_set_EC : user_set,
        time_set
    )

    return shared_cons_us
end

"""
    calculate_shared_consumption(::AbstractGroupNC, ECModel::AbstractEC; kwargs...)

Calculate the demand that each user meets using its own sources or other users for the Non-Cooperative case.
In the Non-Cooperative case, there is no shared energy, only self consumption.
Shared energy means energy that is shared between 
Output is normalized with respect to the demand when per_unit is true

'''
Outputs
-------
shared_cons_frac : DenseAxisArray
    Shared consumption for each user and the aggregation
'''
"""
function calculate_shared_consumption(::AbstractGroupNC, ECModel::AbstractEC; kwargs...)
    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)
    
    return JuMP.Containers.DenseAxisArray(
        fill(0.0, length(user_set_EC)),
        user_set_EC
    )
end


"""
    calculate_shared_production(::AbstractGroupNC, ECModel::AbstractEC; kwargs...)

Calculate the shared produced energy for the Non-Cooperative case.
In the Non-Cooperative case, there is no shared energy between users, only self production.
Output is normalized with respect to the demand when per_unit is true

'''
Outputs
-------
shared_en_frac : DenseAxisArray
    Shared energy for each user and the aggregation
'''
"""
function calculate_shared_production(::AbstractGroupNC, ECModel::AbstractEC; kwargs...)

    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)
    
    return JuMP.Containers.DenseAxisArray(
        fill(0.0, length(user_set_EC)),
        user_set_EC
    )
end


"""
Function to return the objective function by user in the NonCooperative case
"""
function objective_by_user(::AbstractGroupNC, ECModel::AbstractEC; add_EC=true)
    if isempty(ECModel.results)
        throw(ErrorException("EnergyCommunity model not solved"))
        return nothing
    elseif add_EC  # if add_EC option is enabled, add the EC_CODE to the users
        ret_value = ECModel.results[:NPV_us]
        user_set_EC = vcat(EC_CODE, axes(ret_value)[1])
        # add the EC to the users
        ret_tot = JuMP.Containers.DenseAxisArray(
            [0.0; ret_value.data],
            user_set_EC
        )
        return ret_tot
    else  # Otherwise return only the users
        return ECModel.results[:NPV_us]
    end
end

"""
finalize_results!(::AbstractGroupNC, ECModel::AbstractEC)

Function to finalize the results of the Non Cooperative model after the execution
Many of the variables are set to zero due to the absence of cooperation between users

"""
function finalize_results!(::AbstractGroupNC, ECModel::AbstractEC)

    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)


    gen_data = ECModel.gen_data
    users_data = ECModel.users_data
    market_data = ECModel.market_data

    # get time set
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    time_set = 1:n_steps
    project_lifetime = field(gen_data, "project_lifetime")


    # Set definitions
    user_set = ECModel.user_set
    year_set = 1:project_lifetime
    year_set_0 = 0:project_lifetime
    time_set = 1:n_steps
    peak_categories = profile(gen_data,"peak_categories")
    # Set definition when optional value is not included
    user_set = ECModel.user_set

    # Power of the aggregator
    ECModel.results[:P_agg] = JuMP.Containers.DenseAxisArray(
        [0.0 for t in time_set],
        time_set
    )

    # Shared power: the minimum between the supply and demand for each time step
    ECModel.results[:P_shared_agg] = JuMP.Containers.DenseAxisArray(
        [0.0
        for t in time_set],
        time_set
    )

    # Total reward awarded to the community at each time step
    ECModel.results[:R_Reward_agg] = JuMP.Containers.DenseAxisArray(
        [0.0
        for t in time_set],
        time_set
    )

    # Total reward awarded to the community in a year
    ECModel.results[:R_Reward_agg_tot] = sum(ECModel.results[:R_Reward_agg])


    # Total reward awarded to the aggregator in NPV terms
    ECModel.results[:R_Reward_agg_NPV] = 0.0


    # Total reward awarded to the aggregator in NPV terms
    ECModel.results[:NPV_agg] = ECModel.results[:R_Reward_agg_NPV]

    
    # Cash flow
    ECModel.results[:Cash_flow_agg] = JuMP.Containers.DenseAxisArray(
        [(y == 0) ? 0.0 : ECModel.results[:R_Reward_agg_tot] for y in year_set_0],
        year_set_0
    )
    
    
    # Cash flow total
    ECModel.results[:Cash_flow_tot] = JuMP.Containers.DenseAxisArray(
        [
            ((y == 0) ? 0.0 : 
                sum(ECModel.results[:Cash_flow_us][y, :]) + ECModel.results[:Cash_flow_agg][y])
            for y in year_set_0
        ],
        year_set_0
    )
    
    # Social welfare of the users
    ECModel.results[:SW_us] = sum(ECModel.results[:NPV_us])

    # Social welfare of the entire aggregation
    ECModel.results[:SW] = ECModel.results[:SW_us] + ECModel.results[:NPV_agg]
    ECModel.results[:objective_value] = ECModel.results[:SW]
end



"""
    to_objective_callback_by_subgroup(::AbstractGroupNC, ECModel::AbstractEC)

Function that returns a callback function that quantifies the objective of a given subgroup of users
The returned function objective_func accepts as arguments an AbstractVector of users and
returns the objective of the aggregation for Non Cooperative models

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
function to_objective_callback_by_subgroup(::AbstractGroupNC, ECModel::AbstractEC; kwargs...)

    # work on a copy
    ecm_copy = deepcopy(ECModel)

    # build the model with the updated set of users
    build_model!(ecm_copy)

    # optimize the model
    optimize!(ecm_copy)

    obj_users = objective_by_user(ecm_copy)

    # create a backup of the model and work on it
    let obj_users = obj_users

        # general implementation of objective_callback_by_subgroup
        function objective_callback_by_subgroup(user_set_callback)

            user_set_no_EC = setdiff(user_set_callback, [EC_CODE])

            # return the objective
            if length(user_set_no_EC) > 0
                return sum(obj_users[u] for u in user_set_no_EC)
            else
                return 0.0
            end
            
        end

        return objective_callback_by_subgroup
    end
end