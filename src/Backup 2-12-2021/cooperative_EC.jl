"""
This function build the JuMP model corresponding to the problem of a given aggregation (user_set)
'''
# Arguments
- data: represent the main input data
- model_user: model of the problem representing the inpedendent optimization of the single users
- sigma: fixed discount offered by the aggregator to each user
- discount_configuration: dictionary of the other discount tariffs related
       to the installed capacity (the rhos)
- user_set(optional): set of users ids the of the aggregation;
             it must be a subset of those defined in data
'''
"""
function build_model_EC(data, user_set::Vector = Vector(),
    optimizer=optimizer_with_attributes(Gurobi.Optimizer))

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
     time_set = init_step:final_step
     peak_set = unique(peak_categories)

    # Set definition when optional value is not included
    if isempty(user_set)
        user_set = user_names(gen_data, users_data)
    end

    ## Model definition

    # Definition of JuMP model
    model = Model(optimizer)

    ## Constant expressions

    # costant value used in the bounds of the power dispatch
    @expression(model, P_tot_P_overestimate[u in user_set],
        max(0,
            sum(Float64[field_component(users_data[u], c, "max_capacity") 
                for c in asset_names(users_data[u], CONV)]) # Maximum capacity of the converters
            + maximum(sum(Float64[field_component(users_data[u], r, "max_capacity")*profile_component(users_data[u], r, "ren_pu")[t] 
                for r = asset_names(users_data[u], REN)]) for t in time_set) # Maximum dispatch of renewable assets
            - minimum(
                sum(Float64[profile_component(users_data[u], l, "load")[t] for l in asset_names(users_data[u], LOAD)])
                for t in time_set)  # Minimum demand
        )
    )

    @expression(model, P_tot_N_overestimate[u in user_set],
        max(0,
            maximum(
                sum(Float64[profile_component(users_data[u], l, "load")[t] for l in asset_names(users_data[u], LOAD)])
                for t in time_set)  # Maximum demand
            + sum(Float64[field_component(users_data[u], c, "max_capacity") 
                for c in asset_names(users_data[u], CONV)])  # Maximum capacity of the converters
        )
    )

    @expression(model, P_tot_us_overestimate[u in user_set],
        max(P_tot_P_overestimate[u], P_tot_N_overestimate[u])  # Max between the maximum values calculated previously
    )

    ## Variable definition
    @variable(model, 0 <= P_max_us[u=user_set, w=peak_set] <=  2000)#sum(P_tot_max_isolated[u, w] for u in user_set))  # Power peak usage of the microgrid

    @variable(model, 0 <= P_public_P_us[u=user_set, t=time_set] <= 1000)#P_tot_P_overestimate[u, t])  # Power supplied to the public market
    @variable(model, 0 <= P_public_N_us[u=user_set, t=time_set] <= 1000)#PP_tot_N_overestimate[u, t])  # Power absorbed from the public market
    @variable(model, 0 <= P_micro_P_us[u=user_set, t=time_set] <= 1000)#PP_tot_P_overestimate[u, t])  # Power supplied to the microgrid market
    @variable(model, 0 <= P_micro_N_us[u=user_set, t=time_set] <= 1000)#PP_tot_N_overestimate[u, t])  # Power absorbed from the microgrid market
    @variable(model, 0 <= E_batt_us[u=user_set, b=asset_names(users_data[u], BATT), t=time_set] <= field_component(users_data[u], b, "max_capacity"))  # Energy stored in the battery
    @variable(model, 0 <= P_conv_P_us[u=user_set, c=asset_names(users_data[u], CONV), time_set] <= field_component(users_data[u], c, "max_capacity"))  # Converter dispatch positive when supplying to AC
    @variable(model, 0 <= P_conv_N_us[u=user_set, c=asset_names(users_data[u], CONV), time_set] <= field_component(users_data[u], c, "max_capacity"))  # Converter dispatch positive when absorbing from AC
    @variable(model, 0 <= P_ren_us[u=user_set, time_set] <= sum(Float64[field_component(users_data[u], r, "max_capacity") for r in asset_names(users_data[u], REN)]))  # Dispath of renewable assets
    @variable(model, 0 <= x_us[u=user_set, a=device_names(users_data[u])] <= field_component(users_data[u], a, "max_capacity"))  # Design of assets of the user


    # NPV of the aggregator
    @variable(model, NPV_agg >= 0)

    ## Expressions
    # CAPEX by user and asset
    @expression(model, CAPEX_us[u in user_set, a in device_names(users_data[u])],
        x_us[u,a]*field_component(users_data[u], a, "CAPEX_lin")
    )
    # CAPEX tot by user
    @expression(model, CAPEX_tot_us[u in user_set],
        sum(CAPEX_us[u, a] for a in device_names(users_data[u]))
    )

    # Maintenance cost by user and asset
    @expression(model, C_OEM_us[u in user_set, a in device_names(users_data[u])],
        x_us[u,a]*field_component(users_data[u], a, "OEM_lin")
    )
    # Maintenance cost by user
    @expression(model, C_OEM_tot_us[u in user_set],
        sum(C_OEM_us[u, a] for a in device_names(users_data[u]))
    )

    # Replacement cost by year, user and asset
    @expression(model, C_REP_us[y in year_set, u in user_set, a in device_names(users_data[u])],
        (mod(y, field_component(users_data[u], a, "lifetime_y")) == 0 && y != project_lifetime) ? CAPEX_us[u, a] : 0.0
    )

    # Replacement cost by year and user
    @expression(model, C_REP_tot_us[y in year_set, u in user_set],
        (y != project_lifetime) ? sum(GenericAffExpr{Float64,VariableRef}[C_REP_us[y, u, a] for a in device_names(users_data[u])]) : 0.0
    )

    # Replacement cost by year, user and asset
    @expression(model, C_RV_us[y in year_set, u in user_set, a in device_names(users_data[u])],
        (y == project_lifetime && mod(y, field_component(users_data[u], a, "lifetime_y")) != 0) ? CAPEX_us[u, a] *
            (1.0 - mod(y, field_component(users_data[u], a, "lifetime_y"))/field_component(users_data[u], a, "lifetime_y")) : 0.0
    )

    # Replacement cost by year and user
    @expression(model, R_RV_tot_us[y in year_set, u in user_set],
        sum(GenericAffExpr{Float64,VariableRef}[C_RV_us[y, u, a] for a in device_names(users_data[u])])
    )

    # Economic balance of each user with respect to the public market
    @expression(model, R_Energy_us[u in user_set, t in time_set],
        profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] *
            (profile(market_data, "sell_price")[t]*(P_public_P_us[u,t] + P_micro_P_us[u,t])
            - profile(market_data, "buy_price")[t]*(P_public_N_us[u,t] + P_micro_N_us[u,t])
            - profile(market_data, "consumption_price")[t] * sum(
                Float64[profile_component(users_data[u], l, "load")[t]
                    for l in asset_names(users_data[u], LOAD)]))  # economic flow with the market
    )

    # Total reward awarded to the community at each time step
    @expression(model, R_Reward_agg[t in time_set],
        profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] *
            profile(market_data, "reward_price")[t] * sum(P_micro_N_us[u,t] for u in user_set)
    )

    # Total reward awarded to the community by year
    @expression(model, R_Reward_agg_tot,
        sum(R_Reward_agg)
    )

    # Total reward awarded to the community in NPV terms
    @expression(model, R_Reward_agg_NPV,
        R_Reward_agg_tot * sum(1 / ((1 + field(gen_data, "d_rate"))^y) for y in year_set)
    )

    # Economic balance of the group of each user with respect to the public market
    @expression(model, R_Energy_tot_us[u in user_set],
        sum(R_Energy_us[u, t] for t in time_set)
    )

    # Economic balance of the aggregation with respect to the public market in every hour
    @expression(model, R_Energy_agg_time[t in time_set],
        sum(R_Energy_us[u, t] for u in user_set)
    )

    # Yearly revenue of the user
    @expression(model, yearly_rev[u=user_set],
        R_Energy_tot_us[u] - C_OEM_tot_us[u]
    )


    # Dispatch of each user in each time step: value is positive when power is supplied to external markets
    @expression(model, P_tot_us[u=user_set, t=time_set],
        P_micro_P_us[u, t] - P_micro_N_us[u, t] + P_public_P_us[u, t] - P_public_N_us[u, t]
    )

    @constraint(model,
        con_us_max_P_user_usA[u = user_set, t = time_set],
        P_max_us[u, profile(market_data, "peak_categories")[t]] >= P_tot_us[u, t]  # P_public_P_us[u, t] - P_public_N_us[u, t]
        )
    @constraint(model,
        con_us_max_P_user_usB[u = user_set, t = time_set],
        P_max_us[u, profile(market_data, "peak_categories")[t]] >= -P_tot_us[u, t]  # - P_public_P_us[u, t] + P_public_N_us[u, t]
        )

    # Peak tariff cost paid by the aggregation
    @expression(model, C_Peak_us[u in user_set, w in peak_set],
        profile(market_data, "peak_weight")[w] * profile(market_data, "peak_tariff")[w] * P_max_us[u, w]
    )

    # Peak tariff cost paid by the aggregation
    @expression(model, C_Peak_tot_us[u = user_set],
        sum(C_Peak_us[u, w] for w in peak_set)
    )




    # Cash flow
    @expression(model, Cash_flow_us[u in user_set, y in append!([0], year_set)],
        (y == 0) ? 0.0 - CAPEX_tot_us[u] : (
            R_Energy_tot_us[u]
            - C_OEM_tot_us[u]
            - C_REP_tot_us[y, u]
            + R_RV_tot_us[y, u]
            - C_Peak_tot_us[u]
        )
    )

    # Cash flow
    @expression(model, Cash_flow_agg[y in append!([0], year_set)],
        (y == 0) ? 0.0 : R_Reward_agg_tot
    )

    # Cash flow
    @expression(model, Cash_flow_tot[y in append!([0], year_set)],
        sum(Cash_flow_us[u, y] for u in user_set)
        + Cash_flow_agg[y]
    )

    @expression(model, NPV_us[u in user_set],
        sum(
            Cash_flow_us[u, y] / ((1 + field(gen_data, "d_rate"))^y)
        for y in append!([0], year_set))
    )

    # Social welfare of the entire aggregation
    @expression(model, SW,
        sum(NPV_us) + R_Reward_agg_NPV
    )

    # Social welfare of the users
    @expression(model, SW_us,
        SW - NPV_agg
    )

    # Other expression

     # Power bought (-) or supplied (+) to the public market
    @expression(model, P_public_us[u=user_set, t=time_set],
        P_public_P_us[u, t] - P_public_N_us[u, t]
    )

     # Power bought (-) or supplied (+) to the microgrid market
    @expression(model, P_micro_us[u=user_set, t=time_set],
        P_micro_P_us[u, t] - P_micro_N_us[u, t]
    )

    # Dispatch of each user in each time step: value is positive when power is supplied to external markets
    @expression(model, P_tot_agg[t=time_set],
        sum(P_micro_P_us[u, t] - P_micro_N_us[u, t] + P_public_P_us[u, t]
            - P_public_N_us[u, t] for u in user_set)
    )

    # Total converters dispatch when supplying to the grid
    @expression(model, P_conv_P_tot_us[u=user_set, t=time_set],
        sum(P_conv_P_us[u, c, t] for c in asset_names(users_data[u], CONV))
    )

    # Total converters dispatch when absorbing from the grid
    @expression(model, P_conv_N_tot_us[u=user_set, t=time_set],
        sum(P_conv_N_us[u, c, t] for c in asset_names(users_data[u], CONV))
    )

    # Total converters dispatch by user
    @expression(model, P_conv_tot_us[u=user_set, t=time_set],
        P_conv_P_tot_us[u, t] - P_conv_N_tot_us[u, t]
    )

    # Total converters dispatch by user and type of component
    @expression(model, P_conv_us[u=user_set, c=asset_names(users_data[u], CONV), t=time_set],
        P_conv_P_us[u, c, t] - P_conv_N_us[u, c, t]
    )

    # Total converters dispatch
    @expression(model, P_conv_tot_agg[t=time_set],
        sum(P_conv_tot_us[u, t] for u in user_set)
    )

    # Total energy available in the batteries
    @expression(model, E_batt_tot_us[u=user_set, t=time_set],
        sum(E_batt_us[u, b, t] for b in asset_names(users_data[u], BATT))
    )

    ## Constraints

    ## Inequality constraints

    # Set the renewable energy dispatch to be no greater than the actual available energy
    @constraint(model,
        con_us_ren_dispatch[u in user_set, t in time_set],
        P_ren_us[u, t] <= sum(GenericAffExpr{Float64,VariableRef}[
            profile_component(users_data[u], r, "ren_pu")[t] * x_us[u, r]
            for r in asset_names(users_data[u], REN)])
    )

    # Set the maximum hourly dispatch of converters not to exceed their capacity
    @constraint(model,
        con_us_converter_capacity[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
        P_conv_P_us[u, c, t] + P_conv_N_us[u, c, t] <= x_us[u, c]
    )


    # Set the maximum hourly dispatch of converters not to exceed the C-rate of the battery in discharge
    @constraint(model,
        con_us_converter_capacity_crate_dch[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
        P_conv_P_us[u, c, t] <= 
            x_us[u, field_component(users_data[u], c, "corr_asset")] * field_component(users_data[u], field_component(users_data[u], c, "corr_asset"), "max_C_dch")
    )


    # Set the maximum hourly dispatch of converters not to exceed the C-rate of the battery in charge
    @constraint(model,
        con_us_converter_capacity_crate_ch[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
        P_conv_N_us[u, c, t] <= 
            x_us[u, field_component(users_data[u], c, "corr_asset")] * field_component(users_data[u], field_component(users_data[u], c, "corr_asset"), "max_C_ch")
    )



    # Set the minimum level of the energy stored in the battery to be proportional to the capacity
    @constraint(model,
        con_us_min_E_batt[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
        E_batt_us[u, b, t] >= x_us[u, b] * field_component(users_data[u], b, "min_SOC")
    )

    # Set the maximum level of the energy stored in the battery to be proportional to the capacity
    @constraint(model,
        con_us_max_E_batt[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
        E_batt_us[u, b, t] <= x_us[u, b] * field_component(users_data[u], b, "max_SOC")
    )

    ## Equality constraints

    # Set the electrical balance at the user system
    @constraint(model,
        con_us_balance[u in user_set, t in time_set],
        P_public_P_us[u, t] - P_public_N_us[u, t] + P_micro_P_us[u, t] - P_micro_N_us[u, t]
        + sum(GenericAffExpr{Float64,VariableRef}[
            P_conv_N_us[u, c, t] - P_conv_P_us[u, c, t] for c in asset_names(users_data[u], CONV)])
        - P_ren_us[u, t]
        ==
        - sum(Float64[profile_component(users_data[u], l, "load")[t] for l in asset_names(users_data[u], LOAD)])
    )

    # Set the balance at each battery system
    @constraint(model,
        con_us_bat_balance[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
        E_batt_us[u, b, t] - E_batt_us[u, b, pre(t, time_set)] +  # Difference between the energy level in the battery. Note that in the case of the first time step, the last id is used
        + profile(market_data, "time_res")[t] * P_conv_P_us[u, field_component(users_data[u], b, "corr_asset"), t]/(
            sqrt(field_component(users_data[u], b, "eta"))*field_component(users_data[u], field_component(users_data[u], b, "corr_asset"), "eta"))  # Contribution of the converter when supplying power to AC
        - profile(market_data, "time_res")[t] * P_conv_N_us[u, field_component(users_data[u], b, "corr_asset"), t]*(
            sqrt(field_component(users_data[u], b, "eta"))*field_component(users_data[u], field_component(users_data[u], b, "corr_asset"), "eta"))  # Contribution of the converter when absorbing power from AC
        == 0
    )

    # Set the flows within the microgrid to have sum equal to zero
    @constraint(model,
        con_micro_balance[t in time_set],
        sum(P_micro_P_us[u, t] - P_micro_N_us[u, t]
            for u in user_set) == 0
    )

    #Set the objective of maximizing the profit of the aggregator
    # @objective(model, Max, model[:NPV_agg]/output_divider)
    @objective(model, Max, model[:SW])

    return model
end


"""
    output_results_EC(data, model, output_file, output_plot_user, model_user, user_set, NPV_us_NOA)

Function to save the results in a file, print the plots and output on commandline
"""
function output_results_EC(data, model::Model, output_file,
    output_plot_user, model_user::Model;
    user_set::Vector = Vector(),
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
     time_set = init_step:final_step
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
    else
        _NPV_shapley_agg = value(model[:NPV_shapley_agg])
        economics_aggregator = DataFrames.DataFrame(
            vcat(
                [[_NPV_agg]],
                [[_NPV_shapley_agg]],
                [[sum(_R_Energy_tot_us)]],
                [[_SW]],
                [[_SW_us]],
                [[SW_us_NOA]],
                [[100*(_SW - SW_us_NOA)/abs(SW_us_NOA)]],
                [[100*(_SW_us - SW_us_NOA)/abs(SW_us_NOA)]],
                [[_R_Reward_agg_tot]]
            ),
                map(Symbol, vcat("annualized_profits (AP^A)", "Shapley value agg",
                    "energy_revenues (\\sum R^M_t)",
                    "Social welfare (SW)", "Social welfare users (SW^U)",
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
    elseif !haskey(model.obj_dict, :NPV_shapley_agg)
        _NPV_shapley_us = value.(model[:NPV_shapley_us])
        economics_users = DataFrames.DataFrame(
            vcat(
                [[u for u in user_set]],
                [[users_data[u].user_name for u in user_set]],
                # [_guaranteed_discount[:].data],
                [[_NPV_us[u] for u in user_set]],
                [_NPV_shapley_us[:].data],
                # [[NPV_us_NOA[u] + _guaranteed_discount[u] * abs.(NPV_us_NOA[u])
                #     for u in user_set]],
                [[NPV_us_NOA[u] for u in user_set]],
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
                #[[((a in device_names(users_data[u])) ? _C_OEM_us[u, a] : missing) for u in user_set] for a in asset_set_unique]
            ),
            map(Symbol, vcat("User_id (i)", "User_name", # "Discount tariff (\\rho_k)",
                "NPV_user (AP^U_i)", "Shapley granted value", # "Guaranteed NPV_user",
                "NPV_user_NOA (AP^{U,NOA}_i)", "AP discount w.r.t. NOA [%]",
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
    else
        _NPV_shapley_us = value.(model[:NPV_shapley_us])
        _NPV_shapley_us_with_agg = value.(model[:NPV_shapley_us_with_agg])
        economics_users = DataFrames.DataFrame(
            vcat(
                [[u for u in user_set]],
                [[users_data[u].user_name for u in user_set]],
                #[_guaranteed_discount[:].data],
                [[_NPV_us[u] for u in user_set]],
                [_NPV_shapley_us[:].data],
                [_NPV_shapley_us_with_agg[:].data],
                #[[NPV_us_NOA[u] + _guaranteed_discount[u] * abs.(NPV_us_NOA[u]) for u in user_set]],
                [[NPV_us_NOA[u] for u in user_set]],
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
            map(Symbol, vcat("User_id (i)", "User_name", # "Discount tariff (\\rho_k)",
                "NPV_user (AP^U_i)", "Shapley granted value",
                "Shapley granted value with agg",
                # "Guaranteed NPV_user",
                "NPV_user_NOA (AP^{U,NOA}_i)", "AP discount w.r.t. NOA [%]",
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