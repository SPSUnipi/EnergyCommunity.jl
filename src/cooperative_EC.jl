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
        P_agg[t] == sum(model[:P_us])
    )

    # Simmetry constraints: the energy sold by the aggregate cannot be higher than its production
    @constraint(model,
        con_simmetry_P[t in time_set],
        P_P_agg[t] <= sum(model[:P_P_us])
    )

    # Simmetry constraints: the energy bought by the aggregate cannot be higher than its total consumption
    @constraint(model,
        con_simmetry_N[t in time_set],
        P_N_agg[t] <= sum(model[:P_N_us])
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
    output_results_EC(data, model, output_file, output_plot_user, model_user, user_set, NPV_us_NOA)

Function to save the results in a file, print the plots and output on commandline
"""
function output_results_EC(data, model::Model, output_file,
    output_plot_user, model_user::Model;
    user_set::AbstractVector = Vector(),
    NPV_us_NOA = nothing, line_width = 2.0)

     # get main parameters
     gen_data, users_data, market_data = explode_data(data)
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
    if isempty(user_set)
        user_set = user_names(gen_data, users_data)
    end

    # set of all types of assets among the users
    asset_set_unique = unique([name for u in user_set for name in device_names(users_data[u])])

    # format types to print at screen the results
    printf_code_user = string("{:18s}: {: 7.2e}", join([", {: 7.2e}" for i in 1:length(user_set) if i > 1]))
    printf_code_agg = string("{:18s}: {: 7.2e}")
    printf_code_description = string("{:<18s}: {:>9s}", join([", {:>9s}" for i in 1:length(user_set) if i > 1]))
    printf_code_energy_share = string("{:<18s}: ", join([if (a == asset_set_unique[1]) "{: 7.2e}" else ", {: 7.2e}" end for a in asset_set_unique]))

    # variables of the users optimized without aggregator
    if isnothing(NPV_us_NOA)
        NPV_us_NOA = value.(model_user[:NPV_user])  # Power bought (-) or supplied (+) to the public market
    end
    CAPEX_tot_us_NOA = value.(model_user[:CAPEX_tot_us])  # Previous investment costs
    C_OEM_tot_us_NOA = value.(model_user[:C_OEM_tot_us])  # Previous investment costs
    yearly_rev_NOA = value.(model_user[:yearly_rev])  # yearly revenues NOA
    SW_us_NOA = sum(NPV_us_NOA[u] for u in user_set)  # social welfare of the users with no aggregation
    P_tot_max_isolated = value.(model_user[:P_max_us])  # Equivalent maximum aggregator power at the external POD without aggregation

    # get values of each variable
    _P_public_P_us = value.(model[:P_public_P_us])  # Power supplied to the public market by the user
    _P_public_N_us = value.(model[:P_public_N_us])  # Power absorbed from the public market by the user
    _P_micro_P_us = value.(model[:P_micro_P_us])  # Power supplied to the microgrid market by the user
    _P_micro_N_us = value.(model[:P_micro_N_us])  # Power absorbed from the microgrid market by the user
    _E_batt_us = value.(model[:E_batt_us])  # Energy stored in the battery
    _P_conv_P_us = value.(model[:P_conv_P_us]) # Converter dispatch positive when supplying to AC
    _P_conv_N_us = value.(model[:P_conv_N_us])  # Converter dispatch positive when absorbing from AC
    _P_ren_us = value.(model[:P_ren_us]) # Dispath of renewable assets
    _x_us = value.(model[:x_us])  # Optimal size of the system

    _NPV_us = value.(model[:NPV_us])  # Annualized profits of the users
    _NPV_agg = value(model[:NPV_agg])  # Annualized profits of the aggregator

    # get values of expressions

    _CAPEX_us = value.(model[:CAPEX_us])  # CAPEX by user and asset
    _CAPEX_tot_us = value.(model[:CAPEX_tot_us])  # Total CAPEX by user
    _C_OEM_us = value.(model[:C_OEM_us]) # Maintenance cost by user and asset
    _C_OEM_tot_us = value.(model[:C_OEM_tot_us]) # Total maintenance cost by asset
    _C_REP_us = value.(model[:C_REP_us])  # Replacement costs by user and asset
    _C_REP_tot_us = value.(model[:C_REP_tot_us])  # Total replacement costs by user
    _C_RV_us = value.(model[:C_RV_us])  # Residual value by user and asset
    _R_RV_tot_us = value.(model[:R_RV_tot_us])  # Residual value by user
    _yearly_rev = value.(model[:yearly_rev])  # yearly revenues by user
    _C_Peak_us = value.(model[:C_Peak_us])  # Peak tariff cost
    _R_Energy_us = value.(model[:R_Energy_us])  # revenues by selling electricity of each user
    _R_Energy_tot_us = value.(model[:R_Energy_tot_us])  # Revenues by selling electricity by each user
    _R_Energy_agg_time = value.(model[:R_Energy_agg_time])  # Revenues by selling electricity by the aggregation
    _SW = value(model[:SW])  # Social welfare of the aggregation
    _SW_us = value.(model[:SW_us])  # Social welfare of the users

#     _guaranteed_discount = value.(model[:guaranteed_discount])  # guaranteed discount by user
    _R_Reward_agg = value.(model[:R_Reward_agg])  # reward awarded to the community by time step
    _R_Reward_agg_tot = value.(model[:R_Reward_agg_tot])  # reward awarded to the community by year
    _R_Reward_agg_NPV = value.(model[:R_Reward_agg_NPV])  # reward awarded to the community in NPV terms

    _CAPEX_tot_us = value.(model[:CAPEX_tot_us])  # total capex by user including CRF
    _C_OEM_tot_us = value.(model[:C_OEM_tot_us])  # total maintenance cost by user

    _P_public_us = value.(model[:P_public_us])  # Power bought (-) or supplied (+) to the public market
    _P_micro_us = value.(model[:P_micro_us])  # Power bought (-) or supplied (+) to the microgrid market
    _P_tot_us = value.(model[:P_tot_us])  # Dispatch of each user in each time step: value is positive when power is supplied to external markets
    _P_max_us = value.(model[:P_max_us])  # Maximum power dispatch at the user POD
    _E_batt_tot_us = value.(model[:E_batt_tot_us])  # Total energy available in the batteries
    _P_conv_P_tot_us = value.(model[:P_conv_P_tot_us])  # Total converters dispatch when supplying to the grid
    _P_conv_N_tot_us = value.(model[:P_conv_N_tot_us])  # Total converters dispatch when absorbing from the grid
    _P_conv_tot_us = value.(model[:P_conv_tot_us])  # Total converters dispatch
    _P_conv_us = value.(model[:P_conv_us])  # Total dispatch of a converter by user
    _P_conv_tot_agg = value.(model[:P_conv_tot_agg])  # converter dispatch
    _P_tot_agg = value.(model[:P_tot_agg])  # Power bought (-) or supplied (+) to the public market

    _P_max_agg = JuMP.Containers.DenseAxisArray(
        [maximum(abs(_P_tot_agg[t]) for t in time_set if peak_categories[t] == w)
        for w in peak_set],
            peak_set)

    Delta_NPV_us = JuMP.Containers.DenseAxisArray([
        100*(_NPV_us[u] - NPV_us_NOA[u])/abs(NPV_us_NOA[u])
        for u in user_set], user_set)  # Discount on annualized profits
    Delta_yearly_rev = JuMP.Containers.DenseAxisArray([
        100*(_yearly_rev[u] - yearly_rev_NOA[u])/abs(yearly_rev_NOA[u])
            for u in user_set], user_set)  # Discount on the yearly bill

    _solve_time = solve_time(model)
    _termination_status = Int(termination_status(model))  # termination status

    info_solution = DataFrames.DataFrame(comp_time = _solve_time, exit_flag=_termination_status)

    dispatch_aggregator = DataFrames.DataFrame(
        vcat(
            [[t for t in time_set]],
            [profile(market_data, "buy_price")],
            [profile(market_data, "consumption_price")],
            [profile(market_data, "sell_price")],
            [profile(market_data, "energy_weight")],
            [_R_Energy_agg_time[:].data],
            [_R_Reward_agg[:].data],
            [_P_tot_agg[:].data]
        ),
            map(Symbol, vcat("time_step (t)", "Buy_public_price variable  (\\pi^{P-,V}_t)",
                "Buy_public_price fixed  (\\pi^{P-,F}_t)",
                "Sell_public_price (\\pi^{P+}_t)", "time_weight (m^T_t)",
                "R_Energy_tot_us (\\sum_t R^{U,P}_{i,t})", "R_Reward_agg", "P_tot_agg"))
    )

    peak_aggregator = DataFrames.DataFrame(
        vcat(
            [peak_set],
            [[profile(market_data, "peak_weight")[p_name] for p_name in peak_set]],
            [[profile(market_data, "peak_tariff")[w] for w in peak_set]],
            [_P_max_agg[:].data]
        ),
            map(Symbol, vcat("Peak period (w)", "Peak period weight (m^W_w)",
                "peak_price_public (c^{PP}_w)", "max_peak_power P^{M,max}_w"))
    )

    if !haskey(model.obj_dict, :NPV_shapley_agg)
        economics_aggregator = DataFrames.DataFrame(
            vcat(
                [[_NPV_agg]],
                [[sum(_R_Energy_tot_us)]],
                [[_R_Reward_agg_NPV]],
                [[_SW]],
                [[_SW_us]],
                [[SW_us_NOA]],
                [[100*(_SW - SW_us_NOA)/abs(SW_us_NOA)]],
                [[100*(_SW_us - SW_us_NOA)/abs(SW_us_NOA)]],
                [[_R_Reward_agg_tot]]
            ),
                map(Symbol, vcat("annualized_profits (AP^A)",
                    "energy_revenues (\\sum R^M_t)",
                    "total reward (\\sum R_Reward_t)",
                    "Social welfare (SW)",
                    "Social welfare users (SW^U)",
                    "Social welfare without aggregator (SW^{[U,]NOA})",
                    "Increase in total social welfare with aggregation [%]",
                    "Increase in users' social welfare with aggregation [%]",
                    "yearly Reward"))
        )
    end


    design_users = DataFrames.DataFrame(
        vcat(
            [user_set],
            [[maximum(sum(Float64[profile_component(users_data[u], l, "load")[t]
                for l in asset_names(users_data[u]) if asset_type(users_data[u], l) == LOAD]) for t in time_set) for u in user_set]],
            [[sum(Float64[profile_component(users_data[u], l, "load")[t] * profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t]/1000
                for t in time_set for l in asset_names(users_data[u], LOAD)]) for u in user_set]],
            [[if (a in device_names(users_data[u])) _x_us[u, a] else missing end for u in user_set] for a in asset_set_unique]
        ),
        map(Symbol, vcat("User", "Peak demand [kW]", "Yearly Demand [MWh]", ["x_us_$a" for a in asset_set_unique]))
    )

    if !haskey(model.obj_dict, :NPV_shapley_us)
        economics_users = DataFrames.DataFrame(
            vcat(
                [[u for u in user_set]],
                # [_guaranteed_discount[:].data],
                [[_NPV_us[u] for u in user_set]],
                [[NPV_us_NOA[u] for u in user_set]],
                # [[NPV_us_NOA[u] + _guaranteed_discount[u] * abs.(NPV_us_NOA[u])
                #     for u in user_set]],
                [[Delta_NPV_us[u] for u in user_set]],
                [_yearly_rev[:].data],
                [yearly_rev_NOA[:].data],
                [Delta_yearly_rev[:].data],
                [_CAPEX_tot_us[:].data],
                [CAPEX_tot_us_NOA[:].data],
                [[sum(1 / (1 + field(gen_data, "d_rate"))^y for y in year_set) * _C_OEM_tot_us[u] for u in user_set]],
                [[sum(1 / (1 + field(gen_data, "d_rate"))^y for y in year_set) * C_OEM_tot_us_NOA[u] for u in user_set]],
                [[sum(_C_REP_tot_us[y, u] / (1 + field(gen_data, "d_rate"))^y for y in year_set) for u in user_set]],
                [[_R_RV_tot_us[project_lifetime, u] / (1 + field(gen_data, "d_rate"))^project_lifetime for u in user_set]],
                [[sum(1 / (1 + field(gen_data, "d_rate"))^y for y in year_set) * _R_Energy_tot_us[u] for u in user_set]],
                [[((a in device_names(users_data[u])) ? _CAPEX_us[u, a] : missing) for u in user_set] for a in asset_set_unique]
                # [[((a in device_names(users_data[u])) ? _C_OEM_us[u, a] : missing) for u in user_set] for a in asset_set_unique]
            ),
            map(Symbol, vcat("User_id (i)",
                "NPV_user (AP^U_i)",
                "NPV_user_NOA (AP^{U,NOA}_i)",
                "AP discount w.r.t. NOA [%]",
                "Yearly revenue by user",
                "Yearly revenue by user NOA", "Yearly revenue discount w.r.t. NOA [%]",
                "CAPEX_tot_us (\\sum_a CAPEX^{CRF,U}_{i,a})", "CAPEX_NOA",
                "SDCF Maintenance", "SDCF Maintenance NOA",
                "SDCF C_REP_tot_us", "SDCF R_RV_tot_us",
                "SDCF R_Energy_tot_us",
                ["CAPEX_us_$a (CAPEX_{i,$a})" for a in asset_set_unique]
                #["C_OEM_us_$a (C^{U,M}_{i,$a})" for a in asset_set_unique]
                )
            )
        )
    end
    
    peak_users = Dict((u) => DataFrames.DataFrame(
        vcat(
            [peak_set],
            [[_P_max_us[u, w] for w in peak_set]],
            [[_P_max_agg[w] for w in peak_set]]
        ),
            map(Symbol, ["Peak_set (w)", "P_max_us (at POD)",
                "P_max_agg (P^{U,P,max}_{$u,w})"]
            )
    ) for u in user_set)

    dispatch_users = Dict((u) => DataFrames.DataFrame(
        vcat(
                [[t for t in time_set]],
                [[sum(Float64[profile_component(users_data[u], l, "load")[t] 
                        for l in asset_names(users_data[u], LOAD)]) for t in time_set]],
                [_P_tot_us[u, :].data],
                [_P_public_us[u, :].data],
                [_P_public_P_us[u, :].data],
                [_P_public_N_us[u, :].data],
                [_P_micro_us[u, :].data],
                [_P_micro_P_us[u, :].data],
                [_P_micro_N_us[u, :].data],
                [_P_ren_us[u, :].data],
                [_P_conv_tot_us[u, :].data],
                [_P_conv_P_tot_us[u, :].data],
                [_P_conv_N_tot_us[u, :].data],
                [_E_batt_tot_us[u, :].data],
                [[_P_conv_us[u, c, t] for t in time_set]
                    for c in asset_names(users_data[u], CONV)],
                [[_P_conv_P_us[u, c, t] for t in time_set]
                    for c in asset_names(users_data[u], CONV)],
                [[_P_conv_N_us[u, c, t] for t in time_set]
                    for c in asset_names(users_data[u], CONV)],
                [[_E_batt_us[u, b, t] for t in time_set]
                    for b in asset_names(users_data[u], BATT)],
                [[profile_component(users_data[u], r, "ren_pu")[t]*_x_us[u, r] for t in time_set]
                    for r in asset_names(users_data[u], REN)]
            ),
            map(Symbol, vcat(
                    "time_step (t)", "P_L_us (P^{L}_$u)",
                    "P_tot_us (P^{U,M/P+}_{$u,t} - P^{U,M/P-}_{$u,t})",
                    "P_public_us (P^{U,P+}_{$u,t} - P^{U,P-}_{$u,t})",
                    "P_public_P_us (P^{U,P+}_{$u,t})", "P_public_N_us (P^{U,P-}_{$u,t})",
                    "P_micro_us (P^{U,M+}_{$u,t} - P^{U,M-}_{$u,t})",
                    "P_micro_P_us (P^{U,M+}_{$u,t})", "P_micro_N_us (P^{U,M-}_{$u,t})",
                    "P_ren_us (P^{R,U}_{$u,t})",
                    "P_conv_us_tot (\\sum_c P^{c+,U}_{$u,t} - P^{c-,U}_{$u,t})",
                    "P_conv_P_us_tot (\\sum_c P^{c+,U}_{$u,t})",
                    "P_conv_N_us_tot (\\sum_c P^{c-,U}_{$u,t})",
                    "E_batt_us_tot (\\sum_b E^{b,U}_{$u,t})",
                    ["P_conv_us_$c (P^{$c+,U}_{$u,t}-P^{$c-,U}_{$u,t})"
                        for c in asset_names(users_data[u], CONV)],
                    ["P_conv_P_us_$c (P^{$c+,U}_{$u,t})"
                        for c in asset_names(users_data[u], CONV)],
                    ["P_conv_N_us_$c (P^{$c-,U}_{$u,t})"
                        for c in asset_names(users_data[u], CONV)],
                    ["E_batt_us_$b (E^{$b,U}_{$u,t})"
                        for b in asset_names(users_data[u], BATT)],
                    ["P_ren_av_us_$r (p^{$r,U}_{$u,t}x^{$r,U}_{$u})"
                        for r in asset_names(users_data[u], REN)]
                )
            )
    ) for u in user_set)


    
    # Write XLSX table
    XLSX.openxlsx(output_file, mode="w") do xf
        # write the dataframe calculated before as an excel file

        #Rename first empty sheet to design_users amd write the corresponding DataFrame
        xs = xf[1]
        XLSX.rename!(xs, "info_solution")
        XLSX.writetable!(xs, DataFrames.eachcol(info_solution),
            DataFrames.names(info_solution))

        xs = XLSX.addsheet!(xf, "economics_aggregator")
        XLSX.writetable!(xs, (DataFrames.eachcol(economics_aggregator)),
            DataFrames.names(economics_aggregator))

        xs = XLSX.addsheet!(xf, "peak_aggregator")
        XLSX.writetable!(xs, (DataFrames.eachcol(peak_aggregator)),
            DataFrames.names(peak_aggregator))

        xs = XLSX.addsheet!(xf, "dispatch_aggregator")
        XLSX.writetable!(xs, (DataFrames.eachcol(dispatch_aggregator)),
            DataFrames.names(dispatch_aggregator))

        xs = XLSX.addsheet!(xf, "design_users")
        XLSX.writetable!(xs, (DataFrames.eachcol(design_users)),
            DataFrames.names(design_users))

        #Write DataFrame economics_users in a new sheed
        xs = XLSX.addsheet!(xf, "economics_users")
        XLSX.writetable!(xs, (DataFrames.eachcol(economics_users)),
            DataFrames.names(economics_users))

        for u = user_set

            #Write DataFrame peak_users related to user u in a new sheet
            xs = XLSX.addsheet!(xf, "peak_user$u")
            XLSX.writetable!(xs, (DataFrames.eachcol(peak_users[u])), DataFrames.names(peak_users[u]))

            #Write DataFrame dispatch_users related to user u in a new sheet
            xs = XLSX.addsheet!(xf, "dispatch_user$u")
            XLSX.writetable!(xs, (DataFrames.eachcol(dispatch_users[u])), DataFrames.names(dispatch_users[u]))
        end
    end

    # Print some information on the solutions (maybe better to be checked)

    printfmtln("\nRESULTS - AGGREGATOR")
    printfmtln(printf_code_agg, "AnnPr [k€]", _NPV_agg/1000)
    printfmtln(printf_code_agg, "SWelf [k€]", _SW/1000)
    printfmtln(printf_code_agg, "SWus [k€]",  _SW_us/ 1000)
    printfmtln(printf_code_agg, "SWusNOA [k€]", SW_us_NOA / 1000)

    printfmtln("\n\nRESULTS - USER")

    printfmtln(printf_code_description, "USER", [u for u in user_set]...)
    for a in asset_set_unique
        printfmtln(printf_code_user, a, [
            (a in device_names(users_data[u])) ? _x_us[u, a] : 0
                for u in user_set]...)
    end

    printfmtln(printf_code_user, "NPV [k€]", _NPV_us/1000...)
    printfmtln(printf_code_user, "CAPEX [k€]",
        [sum(_CAPEX_tot_us[u]/1000)
            for u in user_set]...)
    printfmtln(printf_code_user, "OPEX [k€]",
        [sum(_C_OEM_tot_us[u])/1000
            for u in user_set]...)
    printfmtln(printf_code_user, "YBill [k€]", _yearly_rev/1000...)
    printfmtln(printf_code_user, "AnnPrNOA[k€]", NPV_us_NOA/1000...)
    printfmtln(printf_code_user, "CAPEXNOA [k€]",
        [sum(CAPEX_tot_us_NOA[u]/1000)
            for u in user_set]...)
    printfmtln(printf_code_user, "OPEXNOA [k€]",
        [sum(C_OEM_tot_us_NOA[u]/1000)
            for u in user_set]...)
    printfmtln(printf_code_user, "YBillNOA [k€]", yearly_rev_NOA/1000...)
    printfmtln(printf_code_user, "DeltaAnnPr [%]", Delta_NPV_us...)
    printfmtln(printf_code_user, "DeltaYBill [%]", Delta_yearly_rev...)

    printfmtln("\n\nEnergy flows")
    printfmtln(printf_code_description, "USER", [u for u in user_set]...)
    printfmtln(printf_code_user, "PtotPubP [MWh]",
        [sum(_P_public_P_us[u, :]) for u in user_set]/1000...)
    printfmtln(printf_code_user, "PtotPubN [MWh]",
        [sum(_P_public_N_us[u, :]) for u in user_set]/1000...)
    printfmtln(printf_code_user, "PtotMicP [MWh]",
        [sum(_P_micro_P_us[u, :]) for u in user_set]/1000...)
    printfmtln(printf_code_user, "PtotMicN [MWh]",
        [sum(_P_micro_N_us[u, :]) for u in user_set]/1000...)
    printfmtln(printf_code_user, "PconvP [MWh]",
        [sum(_P_conv_P_tot_us[u, t] for t in time_set) for u in user_set]/1000...)
    printfmtln(printf_code_user, "PconvN [MWh]",
        [sum(_P_conv_N_tot_us[u, t] for t in time_set) for u in user_set]/1000...)
    printfmtln(printf_code_user, "Pren [MWh]",
        [sum(_P_ren_us[u,:]) for u in user_set]/1000...)
    printfmtln(printf_code_user, "Load [MWh]",
        [sum(Float64[profile_component(users_data[u], l, "load")[t]
                for t in time_set for l in asset_names(users_data[u], LOAD)
            ]) for u in user_set]/1000...)

    ## Plots

    Plots.PlotlyBackend()
    pt = Array{Plots.Plot, 2}(undef, n_users, 3)
    lims_y_axis_dispatch = [(-20, 20),(-20, 20)]
    lims_y_axis_batteries = [(0, 120), (0, 120)]
    dpi=3000
    for (u_i, u_name) in enumerate(user_set)

        # Power dispatch plot
        pt[u_i, 1] = plot(time_set, [-sum(Float64[profile_component(users_data[u_name], l, "load")[t] 
                                        for l in asset_names(users_data[u_name], LOAD)]) for t in time_set],
                            label="Load", w=line_width, legend=:outerright, dpi=3000)
        # plot!(pt[u_i, 1], time_set, _P_public_us[u_name, :].data, label="Public grid", w=line_width)
        # plot!(pt[u_i, 1], time_set, _P_micro_us[u_name, :].data, label="Microgrid", w=line_width)
        plot!(pt[u_i, 1], time_set, _P_conv_tot_us[u_name, :].data, label="Converters", w=line_width)
        plot!(pt[u_i, 1], time_set, _P_ren_us[u_name, :].data, label="Renewables", w=line_width)
        plot!(pt[u_i, 1], time_set, _P_tot_us[u_name, :].data, label="Commercial POD", w=line_width, linestyle = :dash)
        xaxis!("Time step [#]")
        yaxis!("Power [kW]")
        #ylims!(lims_y_axis_dispatch[u])

        # Battery status plot
        pt[u_i, 2] = plot(time_set, _E_batt_tot_us[u_name, :].data, label="Energy      ",
            w=line_width, legend=:outerright)
        xaxis!("Time step [#]")
        yaxis!("Energy [kWh]")
        #ylims!(lims_y_axis_batteries[u])

        pt[u_i, 3] = plot(pt[u_i, 1], pt[u_i, 2], layout=(2,1))

        display(pt[u_i, 3])
        png(pt[u_i, 3], format(output_plot_user, u_i))
    end
end