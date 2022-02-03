# """
# This function build the JuMP model corresponding to the problem of a given aggregation (user_set)
# '''
# # Arguments
# - data: represent the main input data
# - model_user: model of the problem representing the inpedendent optimization of the single users
# - sigma: fixed discount offered by the aggregator to each user
# - discount_configuration: dictionary of the other discount tariffs related
#        to the installed capacity (the rhos)
# - user_set(optional): set of users ids the of the aggregation;
#              it must be a subset of those defined in data
# '''
# """
# function build_model!(group_type::AbstractGroupCO, ECModel::AbstractEC, optimizer)

#     # start from the base model of the NC solutions
#     build_base_model!(ECModel, optimizer)

#     # add the CO-specific model
#     build_specific_model!(group_type, ECModel)

#     # set the CO-specific objective
#     set_objective!(group_type, ECModel)

#     return ECModel
# end


"""

Set the CO-specific model for the EC
"""
function build_specific_model!(::AbstractGroupCO, ECModel::AbstractEC)

    # get main parameters
    gen_data = ECModel.gen_data
    users_data = ECModel.users_data
    market_data = ECModel.market_data

    n_users = length(users_data)
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    project_lifetime = field(gen_data, "project_lifetime")
    peak_categories = profile(market_data, "peak_categories")

    # Set definitions

    year_set = 1:project_lifetime
    year_set_0 = 0:project_lifetime
    time_set = 1:n_steps
    peak_set = unique(peak_categories)

    # Set definition when optional value is not included
    user_set = ECModel.user_set

    ## Model definition

    # Definition of JuMP model
    model = ECModel.model

    ## Constant expressions
    # Overestimation of the power exchanged by each POD when selling to the external market
    @expression(model, P_P_agg_overestimate,
        sum(model[:P_P_us_overestimate])
    )

    # Overestimation of the power exchanged by each POD when selling to the external market
    @expression(model, P_N_agg_overestimate,
        sum(model[:P_N_us_overestimate])
    )

    ## Variable definition

    @variable(model, 0 <= P_P_agg[t=time_set] <= P_P_agg_overestimate)  # Power supplied to the public market
    @variable(model, 0 <= P_N_agg[t=time_set] <= P_N_agg_overestimate)  # Power absorbed from the public market


    # NPV of the aggregator
    @variable(model, NPV_agg >= 0)

    ## Expressions

    # Power shared among the users
    @expression(model, P_shared_agg[t in time_set],
        sum(model[:P_P_us][u, t] - P_P_agg[t] for u in user_set)
    )

    # Total net power exchanged by a virtual POD corresponding to the entire EC:
    #      positive when supplying power to the external market
    @expression(model, P_agg[t in time_set],
        P_P_agg[t] - P_N_agg[t]
    )


    # Total reward awarded to the community at each time step
    @expression(model, R_Reward_agg[t in time_set],
        profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] *
            profile(market_data, "reward_price")[t] * P_shared_agg[t]
    )

    # Total reward awarded to the community by year
    @expression(model, R_Reward_agg_tot,
        sum(R_Reward_agg)
    )

    # Total reward awarded to the community in NPV terms
    @expression(model, R_Reward_agg_NPV,
        R_Reward_agg_tot * sum(1 / ((1 + field(gen_data, "d_rate"))^y) for y in year_set)
    )

    # Cash flow
    @expression(model, Cash_flow_agg[y in year_set_0],
        (y == 0) ? 0.0 : R_Reward_agg_tot
    )

    # Cash flow
    @expression(model, Cash_flow_tot[y in year_set_0],
        sum(model[:Cash_flow_us][y, :])
        + Cash_flow_agg[y]
    )

    # Social welfare of the entire aggregation
    @expression(model, SW,
        sum(model[:NPV_us]) + R_Reward_agg_NPV
    )

    # Social welfare of the users
    @expression(model, SW_us,
        SW - NPV_agg
    )

    # Other expression

    ## Constraints

    
    ## Equality Constraints

    # Set the commercial energy flows within the aggregate to have sum equal to zero
    @constraint(model,
        con_micro_balance[t in time_set],
        P_agg[t] == sum(model[:P_us][:, t])
    )

    # Simmetry constraints: the energy sold by the aggregate cannot be higher than its production
    @constraint(model,
        con_simmetry_P[t in time_set],
        P_P_agg[t] <= sum(model[:P_P_us][:, t])
    )

    # Simmetry constraints: the energy bought by the aggregate cannot be higher than its total consumption
    @constraint(model,
        con_simmetry_N[t in time_set],
        P_N_agg[t] <= sum(model[:P_N_us][:, t])
    )
end

"""

Set the objective for the cooperative approach
"""
function set_objective!(::AbstractGroupCO, ECModel::AbstractEC)

    #Set the objective of maximizing the profit of the aggregator
    @objective(ECModel.model, Max, ECModel.model[:SW])

    return ECModel
end

""" 
    print_summary(::AbstractGroupCO, ECModel::AbstractEC)
Function to print the main results of the model
"""
function print_summary(::AbstractGroupCO, ECModel::AbstractEC; base_case::AbstractEC=ModelEC())

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

    results_EC = ECModel.results
    results_base = base_case.results

    # set of all types of assets among the users
    asset_set_unique = unique([name for u in user_set for name in device_names(users_data[u])])

    # format types to print at screen the results
    printf_code_user = string("{:18s}: {: 7.2e}", join([", {: 7.2e}" for i in 1:length(user_set) if i > 1]))
    printf_code_agg = string("{:18s}: {: 7.2e}")
    printf_code_description = string("{:<18s}: {:>9s}", join([", {:>9s}" for i in 1:length(user_set) if i > 1]))

    ## start printing

    # aggregated results
    printfmtln("\nRESULTS - AGGREGATOR")
    printfmtln(printf_code_agg, "NPV Agg [k€]", results_EC[:NPV_agg]/1000)  # NPV aggregator
    printfmtln(printf_code_agg, "SWtot [k€]", results_EC[:SW]/1000)  # Total social welfare
    printfmtln(printf_code_agg, "SWus [k€]",  results_EC[:SW_us]/ 1000)  # Social welfare of the users
    if !isempty(base_case.user_set)
        printfmtln(printf_code_agg, "SWusNOA [k€]", base_case.results[:SW_us] / 1000)  # Social Welfare of the base case scenario
    end
    printfmtln(printf_code_agg, "ESha [MWh]",  sum(results_EC[:P_shared_agg][:])/ 1000)  # Shared Energy

    # results of the users
    printfmtln("\n\nRESULTS - USER")

    printfmtln(printf_code_description, "USER", [u for u in user_set]...)  # heading
    for a in asset_set_unique  # print capacities of each asset by user
        printfmtln(printf_code_user, a, [
            (a in device_names(users_data[u])) ? results_EC[:x_us][u, a] : 0
                for u in user_set]...)
    end

    printfmtln(printf_code_user, "NPV [k€]", results_EC[:NPV_us]/1000...)  # print NPV by user
    printfmtln(printf_code_user, "CAPEX [k€]",
        [sum(results_EC[:CAPEX_tot_us][u]/1000)
            for u in user_set]...)  # print CAPEX by user
    printfmtln(printf_code_user, "OPEX [k€]",
        [sum(results_EC[:C_OEM_tot_us][u])/1000
            for u in user_set]...)  # print OPEX by user
    printfmtln(printf_code_user, "YBill [k€]", results_EC[:yearly_rev]/1000...)  # print yearly bill by user
    if !isempty(base_case.user_set)
        printfmtln(printf_code_user, "NPVNOA[k€]", results_base[:NPV_us]/1000...)  # print NPV by user in the base case
        printfmtln(printf_code_user, "CAPEXNOA [k€]",
            [sum(results_base[:CAPEX_tot_us][u]/1000)
                for u in user_set]...)  # print CAPEX by user in the base case
        printfmtln(printf_code_user, "OPEXNOA [k€]",
            [sum(results_base[:C_OEM_tot_us][u]/1000)
                for u in user_set]...)  # print OPEX by user in the base case
        printfmtln(printf_code_user, "YBillNOA [k€]", results_base[:yearly_rev]/1000...)  # print yearly revenue by user in the base case

        Delta_NPV_us = 100 .* (results_EC[:NPV_us] - results_base[:NPV_us])./results_base[:NPV_us]
        Delta_yearly_rev = 100 .* (results_EC[:yearly_rev] - results_base[:yearly_rev])./results_base[:yearly_rev]
        
        printfmtln(printf_code_user, "DeltaNPV [%]", Delta_NPV_us...)  # print Delta NPV in percentage by user in the base case
        printfmtln(printf_code_user, "DeltaYBill [%]", Delta_yearly_rev...) # print Delta yearly bill in percentage by user in the base case
    end

    # print energy flows
    printfmtln("\n\nEnergy flows")
    printfmtln(printf_code_description, "USER", [u for u in user_set]...)
    printfmtln(printf_code_user, "PtotPusP [MWh]",
        [sum(results_EC[:P_P_us][u, :]) for u in user_set]/1000...)  # Total power supplied by user to the grid
    printfmtln(printf_code_user, "PtotPusN [MWh]",
        [sum(results_EC[:P_N_us][u, :]) for u in user_set]/1000...)  # Total power bought by user from the grid
    printfmtln(printf_code_user, "PconvP [MWh]",
        [sum(Float64[results_EC[:P_conv_P_us][u, c, t] 
                for c in asset_names(users_data[u], CONV) for t in time_set
            ]) for u in user_set]/1000...)  # Total power supplied by converters by user
    printfmtln(printf_code_user, "PconvN [MWh]",
        [sum(Float64[results_EC[:P_conv_N_us][u, c, t] 
        for c in asset_names(users_data[u], CONV) for t in time_set
            ]) for u in user_set]/1000...)  # Total power loaded by converters by user
    printfmtln(printf_code_user, "Pren [MWh]",
        [sum(results_EC[:P_ren_us][u,:]) for u in user_set]/1000...)  # Total power supplied by renewables by each user
    printfmtln(printf_code_user, "Load [MWh]",
        [sum(
            Float64[profile_component(users_data[u], l, "load")[t]
                for t in time_set for l in asset_names(users_data[u], LOAD)]
        ) for u in user_set]/1000...)  # Total load by user
end


"""

Function to plot the results of the Cooperative EC
"""
function Plots.plot(::AbstractGroupCO, ECModel::AbstractEC, output_plot_file::AbstractString;
    user_set::AbstractVector = Vector(), line_width = 2.0)
 
     # Set definitions

    # Set definition when optional value is not included
    if isempty(user_set)
        user_set = ECModel.user_set
    end

    # auxiliary variables
    results = ECModel.results
    users_data = ECModel.users_data
    gen_data = ECModel.gen_data

    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1

    # Set definitions

    time_set_plot = init_step:final_step
    time_set = 1:n_steps


    ## Plots

    Plots.PlotlyBackend()
    pt = Array{Plots.Plot, 2}(undef, length(user_set), 3)
    lims_y_axis_dispatch = [(-20, 20),(-20, 20)]
    lims_y_axis_batteries = [(0, 120), (0, 120)]
    dpi=3000
    for (u_i, u_name) in enumerate(user_set)

        # Power dispatch plot
        pt[u_i, 1] = plot(time_set_plot, [-sum(Float64[profile_component(users_data[u_name], l, "load")[t] 
                                        for l in asset_names(users_data[u_name], LOAD)]) for t in time_set],
                            label="Load", width=line_width, legend=:outerright, dpi=3000)
        # plot!(pt[u_i, 1], time_set_plot, _P_public_us[u_name, :].data, label="Public grid", w=line_width)
        # plot!(pt[u_i, 1], time_set_plot, _P_micro_us[u_name, :].data, label="Microgrid", w=line_width)
        plot!(pt[u_i, 1], time_set_plot, [
            sum(Float64[results[:P_conv_us][u_name, c, t] 
                for c in asset_names(users_data[u_name], CONV)]) for t in time_set],
            label="Converters", w=line_width)
        plot!(pt[u_i, 1], time_set_plot, results[:P_ren_us][u_name, :].data, label="Renewables", w=line_width)
        plot!(pt[u_i, 1], time_set_plot, results[:P_us][u_name, :].data, label="Commercial POD", w=line_width, linestyle = :dash)
        xaxis!("Time step [#]")
        yaxis!("Power [kW]")
        #ylims!(lims_y_axis_dispatch[u])

        # Battery status plot
        pt[u_i, 2] = plot(time_set_plot, [
            sum(Float64[results[:E_batt_us][u_name, b, t] 
                for b in asset_names(users_data[u_name], BATT)]) for t in time_set],
                label="Energy      ", w=line_width, legend=:outerright)
        xaxis!("Time step [#]")
        yaxis!("Energy [kWh]")
        #ylims!(lims_y_axis_batteries[u])

        pt[u_i, 3] = plot(pt[u_i, 1], pt[u_i, 2], layout=(2,1))

        display(pt[u_i, 3])

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

Function to create the output dataframe of peak power for the EC
"""
function add_EC_peak_summary!(
    output_list::Vector, ECModel::AbstractEC)

    # get main parameters
    market_data = ECModel.market_data
    peak_categories = profile(market_data, "peak_categories")

    # Set definitions
    peak_set = unique(peak_categories)

    ## Retrive results
    _P_max_agg = JuMP.Containers.DenseAxisArray(
        [maximum(abs.(ECModel.results[:P_agg][findall(==(w), peak_categories)].data))
        for w in peak_set],
            peak_set)  # Maximum dispatch of the user for every peak period

    peak_aggregator = DataFrames.DataFrame(
        vcat(
            [[EC_CODE]],
            [[[_P_max_agg[w]]] for w in peak_set]...
        ),
        map(Symbol, ["Agg_id"; map(x->"Peak_id $x", peak_set)])
    )

    # add dataframe to the output list
    push!(output_list, "peak_aggregator"=>peak_aggregator)
end


"""

Function to create the output dataframe of the economics of the EC
"""
function add_EC_economics_summary!(
    output_list::Vector, ECModel::AbstractEC)
    
    # get values of each variable
    _NPV_agg = ECModel.results[:NPV_agg]  # Annualized profits of the aggregator

    # get values of expressions

    _R_Energy_tot_us = ECModel.results[:R_Energy_tot_us]  # Revenues by selling electricity by each user
    _SW = ECModel.results[:SW]  # Social welfare of the aggregation
    _SW_us = ECModel.results[:SW_us]  # Social welfare of the users

    _R_Reward_agg_tot = ECModel.results[:R_Reward_agg_tot]  # reward awarded to the community by year
    _R_Reward_agg_NPV = ECModel.results[:R_Reward_agg_NPV]  # reward awarded to the community in NPV terms

    economics_aggregator = DataFrames.DataFrame(
        vcat(
            [[_NPV_agg]],
            [[sum(_R_Energy_tot_us)]],
            [[_R_Reward_agg_NPV]],
            [[_SW]],
            [[_SW_us]],
            [[_R_Reward_agg_tot]]
        ),
            map(Symbol, vcat("annualized_profits (AP^A)",
                "energy_revenues (\\sum R^M_t)",
                "total reward (\\sum R_Reward_t)",
                "Social welfare (SW)",
                "Social welfare users (SW^U)",
                "yearly Reward"))
    )
    
    # add dataframe to the output list
    push!(output_list, "economics_aggregator"=>economics_aggregator)
end


"""
    prepare_summary(::AbstractGroupCO, ECModel::AbstractEC;
        user_set::Vector=Vector())

Save base excel file with a summary of the results for the Cooperative case
"""
function prepare_summary(::AbstractGroupCO, ECModel::AbstractEC; user_set::AbstractVector)

    # output list
    output_list = []

    # add solutions on the optimization process
    add_info_solution_summary!(output_list, ECModel)

    # add EC economics
    add_EC_economics_summary!(output_list, ECModel)
    # add EC peak powers
    add_EC_peak_summary!(output_list, ECModel)

    # add users design info
    add_users_design_summary!(output_list, ECModel, user_set)
    # add users economics
    add_users_economics_summary!(output_list, ECModel, user_set)
    # add peak power of users
    add_users_peak_summary!(output_list, ECModel, user_set)

    return output_list
end


"""
    calculate_grid_import(::AbstractGroupCO, ECModel::AbstractEC; per_unit::Bool=true)

Calculate grid usage for the Cooperative case.
Output is normalized with respect to the demand when per_unit is true
'''
Outputs
-------
grid_frac : DenseAxisArray
    Reliance on the grid demand for each user and the aggregation
'''
"""
function calculate_grid_import(::AbstractGroupCO, ECModel::AbstractEC; per_unit::Bool=true)

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

    _P_tot_us = ECModel.results[:P_us]  # power dispatch of users - users mode
    _P_agg = ECModel.results[:P_agg]  # Ren production dispatch of users - users mode

    # fraction of grid resiliance of the aggregate case agg
    grid_frac_tot = sum(max.(-_P_agg, 0))

    # time step resolution
    time_res = profile(market_data, "time_res")

    # fraction of grid reliance with respect to demand by user agg case
    grid_frac = JuMP.Containers.DenseAxisArray(
        Float64[
            grid_frac_tot;
            Float64[
                sum(
                    _P_agg[t] >= 0 ? 0.0 : 
                        -_P_agg[t]*max(-_P_tot_us[u,t], 0.0)/sum(max.(-_P_tot_us[:,t], 0.0))*time_res[t]
                    for t in time_set)
                for u in user_set
            ]
        ],
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
    calculate_grid_export(::AbstractGroupCO, ECModel::AbstractEC; per_unit::Bool=true)

Calculate grid export for the Cooperative case.
Output is normalized with respect to the demand when per_unit is true
'''
Outputs
-------
grid_frac : DenseAxisArray
    Reliance on the grid demand for each user and the aggregation
'''
"""
function calculate_grid_export(::AbstractGroupCO, ECModel::AbstractEC; per_unit::Bool=true)

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

    _P_tot_us = ECModel.results[:P_us]  # power dispatch of users - users mode
    _P_agg = ECModel.results[:P_agg]  # Ren production dispatch of users - users mode

    # fraction of grid resiliance of the aggregate case agg
    grid_frac_tot = sum(max.(_P_agg, 0))

    # time step resolution
    time_res = profile(market_data, "time_res")

    # fraction of grid reliance with respect to demand by user agg case
    grid_frac = JuMP.Containers.DenseAxisArray(
        Float64[
            grid_frac_tot;
            Float64[
                sum(
                    _P_agg[t] <= 0 ? 0.0 : 
                        _P_agg[t]*max(_P_tot_us[u,t], 0.0)/sum(max.(_P_tot_us[:,t], 0.0))*time_res[t]
                    for t in time_set)
                for u in user_set
            ]
        ],
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
    calculate_shared_energy(::AbstractGroupCO, ECModel::AbstractEC; per_unit::Bool=true, only_shared::Bool=false)

Calculate the shared produced energy for the Cooperative case.
In the Cooperative case, there can be shared energy between users, not only self production.
When only_shared is false, also self production is considered, otherwise only shared energy.
Shared energy means energy that is shared between 
Output is normalized with respect to the demand when per_unit is true

'''
Outputs
-------
shared_en_frac : DenseAxisArray
    Shared energy for each user and the aggregation
'''
"""
function calculate_shared_energy(::AbstractGroupCO, ECModel::AbstractEC; per_unit::Bool=true, only_shared::Bool=false)

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

    _P_us = ECModel.results[:P_us]  # power dispatch of users - users mode
    _P_agg = ECModel.results[:P_agg]  # power dispatch of the EC

    # time step resolution
    time_res = profile(ECModel.market_data, "time_res")

    # total shared production for every time step
    shared_prod_by_time = JuMP.Containers.DenseAxisArray(
        Float64[sum((max.(_P_us[:, t], 0.0)) - max(_P_agg[t], 0.0))*time_res[t] for t in time_set],
        time_set
    )

    # total shared production
    total_shared_prod = sum(shared_prod_by_time)
    
    # shared production by user and EC
    shared_prod_us = JuMP.Containers.DenseAxisArray(
        Float64[
            total_shared_prod;
            [
                sum(Float64[
                    shared_prod_by_time[t] <= 0.0 || _P_us[u,t] <=0 ? 0.0 : _P_us[u,t]^2/total_shared_cons[t]*time_res[t]
                    fot t in time_set
                ])
                for u in user_set
            ]
        ],
        user_set_EC
    )

    # normalize output if perunit is required
    if per_unit

        # calculate the demand by EC and user
        demand_EC_us = calculate_demand(ECModel)
        
        # update value
        shared_prod_us = shared_prod_us ./ demand_EC_us
        
    end
    
    if only_shared
        return shared_prod_us
    else
        # add self production
        self_prod = calculate_self_production(ECModel, per_unit=per_unit)

        return self_prod + shared_prod_us
    end
end

"""
    calculate_shared_consumption(::AbstractGroupCO, ECModel::AbstractEC; per_unit::Bool=true, only_shared::Bool=false)

Calculate the demand that each user meets using its own sources or other users for the Cooperative case.
In the Cooperative case, there can be shared energy, non only self consumption.
When only_shared is false, also self consumption is considered, otherwise only shared energy.
Shared energy means energy that is shared between 
Output is normalized with respect to the demand when per_unit is true

'''
Outputs
-------
shared_cons_frac : DenseAxisArray
    Shared consumption for each user and the aggregation
'''
"""
function calculate_shared_consumption(::AbstractGroupCO, ECModel::AbstractEC; per_unit::Bool=true, only_shared::Bool=false)

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

    _P_us = ECModel.results[:P_us]  # power dispatch of users - users mode
    _P_agg = ECModel.results[:P_agg]  # power dispatch of the EC

    # time step resolution
    time_res = profile(ECModel.market_data, "time_res")

    # total shared consumption for every time step
    shared_cons_by_time = JuMP.Containers.DenseAxisArray(
        Float64[(-sum(min.(_P_us[:, t], 0.0)) - min(_P_agg[t], 0.0))*time_res[t] for t in time_set],
        time_set
    )

    # total shared consumption
    total_shared_cons = sum(shared_cons_by_time)
    
    # shared consumption by user and EC
    shared_cons_us = JuMP.Containers.DenseAxisArray(
        Float64[
            total_shared_cons;
            [
                sum(Float64[
                    total_shared_cons[t] <= 0.0 || _P_us[u,t] >=0 ? 0.0 : _P_us[u,t]^2/total_shared_cons[t]*time_res[t]
                    fot t in time_set
                ])
                for u in user_set
            ]
        ],
        user_set_EC
    )

    # normalize output if perunit is required
    if per_unit

        # calculate the demand by EC and user
        demand_EC_us = calculate_demand(ECModel)
        
        # update value
        shared_cons_us = shared_cons_us ./ demand_EC_us
        
    end
    
    if only_shared
        return shared_cons_us
    else
        # add self consumption
        self_consump = calculate_self_consumption(ECModel, per_unit=per_unit)

        return self_consump + shared_cons_us
    end
end