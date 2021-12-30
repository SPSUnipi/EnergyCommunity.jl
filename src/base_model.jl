# accepted technologies
ACCEPTED_TECHS = ["load", "renewable", "battery", "converter"]

"""
    build_base_model!(ECModel::AbstractEC, optimizer)

Creates the base optimization model for all the EC models

# Arguments
'''
data: structure of data
'''
"""
function build_base_model!(ECModel::AbstractEC, optimizer)

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

    user_set = user_names(gen_data, users_data)
    year_set = 1:project_lifetime
    year_set_0 = 0:project_lifetime
    time_set = init_step:final_step
    peak_set = unique(peak_categories)


    ## Model definition

    # Definition of JuMP model
    ECModel.model = Model(optimizer)
    model_user = ECModel.model

    # Overestimation of the power exchanged by each POD when selling to the external market by each user
    @expression(model_user, P_P_us_overestimate[u in user_set],
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

    # Overestimation of the power exchanged by each POD when buying from the external market bu each user
    @expression(model_user, P_N_us_overestimate[u in user_set],
        max(0,
            maximum(
                sum(Float64[profile_component(users_data[u], l, "load")[t] for l in asset_names(users_data[u], LOAD)])
                for t in time_set)  # Maximum demand
            + sum(Float64[field_component(users_data[u], c, "max_capacity") 
                for c in asset_names(users_data[u], CONV)])  # Maximum capacity of the converters
        )
    )

    # Overestimation of the power exchanged by each POD, be it when buying or selling by each user
    @expression(model_user, P_us_overestimate[u in user_set],
        max(P_P_us_overestimate[u], P_N_us_overestimate[u])  # Max between the maximum values calculated previously
    )


    ## Variable definition
    
    # Energy stored in the battery
    @variable(model_user, 
        0 <= E_batt_us[u=user_set, b=asset_names(users_data[u], BATT), t=time_set] 
            <= field_component(users_data[u], b, "max_capacity"))
    # Converter dispatch positive when supplying to AC
    @variable(model_user, 0 <= 
        P_conv_P_us[u=user_set, c=asset_names(users_data[u], CONV), time_set] 
            <= field_component(users_data[u], c, "max_capacity"))
    # Converter dispatch positive when absorbing from AC
    @variable(model_user,
        0 <= P_conv_N_us[u=user_set, c=asset_names(users_data[u], CONV), time_set] 
            <= field_component(users_data[u], c, "max_capacity"))
    # Dispath of renewable assets
    @variable(model_user,
        0 <= P_ren_us[u=user_set, time_set]
            <= sum(Float64[field_component(users_data[u], r, "max_capacity") for r in asset_names(users_data[u], REN)]))
    # Maximum dispatch of the user for every peak period
    @variable(model_user,
        0 <= P_max_us[u=user_set, peak_set]
            <= P_us_overestimate[u])
    # Total dispatch of the user, positive when supplying to public grid
    @variable(model_user,
        0 <= P_P_us[u=user_set, time_set]
            <= P_P_us_overestimate[u])
    # Total dispatch of the user, positive when absorbing from public grid
    @variable(model_user,
        0 <= P_N_us[u=user_set, time_set]
            <= P_N_us_overestimate[u])
    # Design of assets of the user
    @variable(model_user,
        0 <= x_us[u=user_set, a=device_names(users_data[u])]
            <= field_component(users_data[u], a, "max_capacity"))

    ## Expressions

    # CAPEX by user and asset
    @expression(model_user, CAPEX_us[u in user_set, a in device_names(users_data[u])],
        x_us[u,a]*field_component(users_data[u], a, "CAPEX_lin")  # Capacity of the asset times specific investment costs
    )

    @expression(model_user, CAPEX_tot_us[u in user_set],
        sum(CAPEX_us[u, a] for a in device_names(users_data[u])) # sum of CAPEX by asset for the same user
    )  # CAPEX by user

    @expression(model_user, C_OEM_us[u in user_set, a in device_names(users_data[u])],
        x_us[u,a]*field_component(users_data[u], a, "OEM_lin")  # Capacity of the asset times specific operating costs
    )  # Maintenance cost by asset

    # Maintenance cost by asset
    @expression(model_user, C_OEM_tot_us[u in user_set],
        sum(C_OEM_us[u, a] for a in device_names(users_data[u]))  # sum of C_OEM by asset for the same user
    )

    # Replacement cost by year, user and asset
    @expression(model_user, C_REP_us[y in year_set, u in user_set, a in device_names(users_data[u])],
        (mod(y, field_component(users_data[u], a, "lifetime_y")) == 0 && y != project_lifetime) ? CAPEX_us[u, a] : 0.0
    )

    # Replacement cost by year and user
    @expression(model_user, C_REP_tot_us[y in year_set, u in user_set],
        sum(C_REP_us[y, u, a] for a in device_names(users_data[u]))
    )

    # Recovery cost by year, user and asset: null except for the last year
    @expression(model_user, C_RV_us[y in year_set, u in user_set, a in device_names(users_data[u])],
        (y == project_lifetime && mod(y, field_component(users_data[u], a, "lifetime_y")) != 0) ? CAPEX_us[u, a] *
            (1.0 - mod(y, field_component(users_data[u], a, "lifetime_y"))/ field_component(users_data[u], a, "lifetime_y")) : 0.0
    )

    # Replacement cost by year and user
    @expression(model_user, R_RV_tot_us[y in year_set, u in user_set],
        sum(C_RV_us[y, u, a] for a in device_names(users_data[u]))
    )

    # Peak tariff cost by user and peak period
    @expression(model_user, C_Peak_us[u in user_set, w in peak_set],
        profile(market_data, "peak_weight")[w] * profile(market_data, "peak_tariff")[w] * P_max_us[u, w]
        # Peak tariff times the maximum connection usage times the discretization of the period
    )

    # Total peak tariff cost by user
    @expression(model_user, C_Peak_tot_us[u in user_set],
        sum(C_Peak_us[u, w] for w in peak_set)  # Sum of peak costs
    ) 

    # Revenues of each user in non-cooperative approach
    @expression(model_user, R_Energy_us[u in user_set, t in time_set],
        profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] * (profile(market_data, "sell_price")[t]*P_P_us[u,t]
            - profile(market_data, "buy_price")[t] * P_N_us[u,t] 
            - profile(market_data, "consumption_price")[t] * sum(
                Float64[profile_component(users_data[u], l, "load")[t]
                for l in asset_names(users_data[u], LOAD)]))  # economic flow with the market
    )

    # Energy revenues by user
    @expression(model_user, R_Energy_tot_us[u in user_set],
        sum(R_Energy_us[u, t] for t in time_set)  # sum of revenues by user
    )

    # Yearly revenue of the user
    @expression(model_user, yearly_rev[u=user_set],
        R_Energy_tot_us[u] - C_OEM_tot_us[u]
    )

    # Cash flow
    @expression(model_user, Cash_flow_us[y in year_set_0, u in user_set],
        (y == 0) ? 0 - CAPEX_tot_us[u] : (R_Energy_tot_us[u] - C_Peak_tot_us[u] - C_OEM_tot_us[u] - C_REP_tot_us[y, u] + R_RV_tot_us[y, u])
    )

    # Annualized profits by the user; the sum of this function is the objective function
    @expression(model_user, NPV_us[u in user_set],
        sum(
            Cash_flow_us[y, u] / ((1 + field(gen_data, "d_rate"))^y)
        for y in year_set_0)
        # sum(
        #     (R_Energy_tot_us[u] # Costs related to the energy trading with the market
        #     - C_Peak_tot_us[u]  # Peak cost
        #     - C_OEM_tot_us[u]  # Maintenance cost
        #     - C_REP_tot_us[y, u]  # Replacement costs
        #     + R_RV_tot_us[y, u]  # Residual value
        #     ) / ((1 + field(gen_data, "d_rate"))^y)
        #     for y in year_set)
        # - CAPEX_tot_us[u]  # Investment costs
    )  

    # Power flow by user POD
    @expression(model_user, P_us[u = user_set, t = time_set],
        P_P_us[u, t] - P_N_us[u, t]
    )

    # Total converter dispatch: positive when supplying to AC
    @expression(model_user, P_conv_us[u=user_set, c=asset_names(users_data[u], CONV), t=time_set],
        P_conv_P_us[u, c, t] - P_conv_P_us[u, c, t]
    )

    ## Inequality constraints

    # Set that the hourly dispatch cannot go beyond the maximum dispatch of the corresponding peak power period
    @constraint(model_user,
        con_us_max_P_user[u = user_set, t = time_set],
        - P_max_us[u, profile(market_data, "peak_categories")[t]] + P_P_us[u, t] + P_N_us[u, t] <= 0
    )

    # Set the renewabl energy dispatch to be no greater than the actual available energy
    @constraint(model_user,
        con_us_ren_dispatch[u in user_set, t in time_set],
        - sum(profile_component(users_data[u], r, "ren_pu")[t] * x_us[u, r] 
            for r in asset_names(users_data[u], REN))
        + P_ren_us[u, t] <= 0
    )

    # Set the maximum hourly dispatch of converters not to exceed their capacity
    @constraint(model_user,
        con_us_converter_capacity[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
        - x_us[u, c] + P_conv_P_us[u, c, t] + P_conv_N_us[u, c, t] <= 0
    )


    # Set the maximum hourly dispatch of converters not to exceed the C-rate of the battery in discharge
    @constraint(model_user,
        con_us_converter_capacity_crate_dch[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
        P_conv_P_us[u, c, t] <= 
            x_us[u, field_component(users_data[u], c, "corr_asset")] * field_component(users_data[u], field_component(users_data[u], c, "corr_asset"), "max_C_dch")
    )


    # Set the maximum hourly dispatch of converters not to exceed the C-rate of the battery in charge
    @constraint(model_user,
        con_us_converter_capacity_crate_ch[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
        P_conv_N_us[u, c, t] <= 
            x_us[u, field_component(users_data[u], c, "corr_asset")] * field_component(users_data[u], field_component(users_data[u], c, "corr_asset"), "max_C_ch")
    )


    # Set the minimum level of the energy stored in the battery to be proportional to the capacity
    @constraint(model_user,
        con_us_min_E_batt[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
        x_us[u, b] * field_component(users_data[u], b, "min_SOC") - E_batt_us[u, b, t] <= 0
    )

    # Set the maximum level of the energy stored in the battery to be proportional to the capacity
    @constraint(model_user,
        con_us_max_E_batt[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
        - x_us[u, b] * field_component(users_data[u], b, "max_SOC") + E_batt_us[u, b, t] <= 0
    )

    ## Equality constraints

    # Set the electrical balance at the user system
    @constraint(model_user,
        con_us_balance[u in user_set, t in time_set],
        P_P_us[u, t] - P_N_us[u, t]
        + sum(GenericAffExpr{Float64,VariableRef}[
            P_conv_N_us[u, c, t] - P_conv_P_us[u, c, t] for c in asset_names(users_data[u], CONV)])
        - P_ren_us[u, t]
        ==
        - sum(Float64[profile_component(users_data[u], l, "load")[t] for l in asset_names(users_data[u], LOAD)])
    )

    # Set the balance at each battery system
    @constraint(model_user,
        con_us_bat_balance[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
        #E_batt_us[u, b, t] - E_batt_us[u, b, if (t>1) t-1 else final_step end]  # Difference between the energy level in the battery. Note that in the case of the first time step, the last id is used
        E_batt_us[u, b, t] - E_batt_us[u, b, pre(t, time_set)]  # Difference between the energy level in the battery. Note that in the case of the first time step, the last id is used
        + profile(market_data, "time_res")[t] * P_conv_P_us[u, field_component(users_data[u], b, "corr_asset"), t]/(
            sqrt(field_component(users_data[u], b, "eta"))*field_component(users_data[u], field_component(users_data[u], b, "corr_asset"), "eta"))  # Contribution of the converter when supplying power to AC
        - profile(market_data, "time_res")[t] * P_conv_N_us[u, field_component(users_data[u], b, "corr_asset"), t]*(
            sqrt(field_component(users_data[u], b, "eta"))*field_component(users_data[u], field_component(users_data[u], b, "corr_asset"), "eta"))  # Contribution of the converter when absorbing power from AC
        == 0
    )
    
    return ECModel
end