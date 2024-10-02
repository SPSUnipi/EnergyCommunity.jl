# accepted technologies
ACCEPTED_TECHS = ["load", "renewable", "battery", "converter", "thermal"]

"""
    build_base_model!(ECModel::AbstractEC, optimizer)

Creates the base optimization model for all the EC models

# Arguments
'''
data: structure of data
'''
"""

function build_base_model!(ECModel::AbstractEC, optimizer; use_notations=false)

    TOL_BOUNDS = 1.05

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
    year_set_0 = 0:project_lifetime
    time_set = 1:n_steps
    peak_categories = profile(gen_data, "peak_categories")
    peak_set = unique(peak_categories)


    ## Model definition

    # Definition of JuMP model
    ECModel.model = (use_notations ? direct_model(optimizer) : Model(optimizer))
    model_user = ECModel.model

    # Overestimation of the power exchanged by each POD when selling to the external market by each user
    @expression(model_user, P_P_us_overestimate[u in user_set, t in time_set],
        max(0,
            sum(Float64[field_component(users_data[u], c, "max_capacity") 
                for c in asset_names(users_data[u], CONV)]) # Maximum capacity of the converters
            + sum(Float64[field_component(users_data[u], r, "max_capacity")*profile_component(users_data[u], r, "ren_pu")[t] 
                for r = asset_names(users_data[u], REN)]) # Maximum dispatch of renewable assets
            + sum(Float64[field_component(users_data[u], g, "max_capacity")*field_component(users_data[u], g, "max_technical")
                for g = asset_names(users_data[u], THER)]) #Maximum dispatch of the fuel-fired generators
            - sum(Float64[profile_component(users_data[u], l, "load")[t] for l in asset_names(users_data[u], LOAD)])  # Minimum demand
        ) * TOL_BOUNDS
    )

    # Overestimation of the power exchanged by each POD when buying from the external market bu each user
    @expression(model_user, P_N_us_overestimate[u in user_set, t in time_set],
        max(0,
            sum(Float64[profile_component(users_data[u], l, "load")[t] for l in asset_names(users_data[u], LOAD)])
                # Maximum demand
            + sum(Float64[field_component(users_data[u], c, "max_capacity") 
                for c in asset_names(users_data[u], CONV)])  # Maximum capacity of the converters
        ) * TOL_BOUNDS
    )

    # Overestimation of the power exchanged by each POD, be it when buying or selling by each user
    @expression(model_user, P_us_overestimate[u in user_set, t in time_set],
        max(P_P_us_overestimate[u, t], P_N_us_overestimate[u, t])  # Max between the maximum values calculated previously
    )


    ## Variable definition
    
    # Definition of variables for the Energy Community load
    @variable(model_user, P_shf[j in user_set, t in time_set] >= 0)
    @variable(model_user, P_adj[j in user_set, t in time_set] >= 0)
    @variable(model_user, P_fix[j in user_set, t in time_set] >= 0)
                
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
    #Dispatch of fuel-fired generator
    @variable(model_user, 
        0 <= P_gen_us[u=user_set, g=asset_names(users_data[u], THER), time_set] 
            <= field_component(users_data[u], g, "max_capacity"))
    # Number of generators plants used by a user in each time step t
    @variable(model_user,
        0 <= z_gen_us[u=user_set, g=asset_names(users_data[u], THER), time_set]
            <= field_component(users_data[u], g, "max_capacity")/field_component(users_data[u], g, "nom_capacity"))
    # Maximum dispatch of the user for every peak period
    @variable(model_user,
        0 <= P_max_us[u=user_set, w in peak_set]
            <= maximum(P_us_overestimate[u, t] for t in time_set if peak_categories[t] == w))
    # Total dispatch of the user, positive when supplying to public grid
    @variable(model_user,
        0 <= P_P_us[u=user_set, t in time_set]
            <= P_P_us_overestimate[u, t])
    # Total dispatch of the user, positive when absorbing from public grid
    @variable(model_user,
        0 <= P_N_us[u=user_set, t in time_set]
            <= P_N_us_overestimate[u, t])
    # Design of assets of the user
    @variable(model_user,
        0 <= n_us[u=user_set, a=device_names(users_data[u])]
            <= field_component(users_data[u], a, "max_capacity"))

    # Set integer capacity
    for u in user_set
        for a in device_names(users_data[u])
            if (has_component(users_data[u], a, "modularity") && field_component(users_data[u], a, "modularity") == true)
                set_integer(n_us[u,a])
                # It should be always true that if the component has a modularity, then a nominal capacity should be available
                set_upper_bound(n_us[u,a], field_component(users_data[u], a, "max_capacity")/field_component(users_data[u], a, "nom_capacity"))

                # For thermal units, set z_gen_us as integer
                if asset_type(users_data[u], a) == THER
                    set_integer.(z_gen_us[u,a,:])
                end
            end
        end
    end

    # Total design of assets of the user
    @expression(model_user, x_us[u=user_set, a=device_names(users_data[u])],
        (has_component(users_data[u], a, "modularity") && field_component(users_data[u], a, "modularity") == true) ?
            n_us[u,a] * field_component(users_data[u], a, "nom_capacity")  : n_us[u,a]
    )

    ## Expressions

    # New equations for overall load of the system
    @expression(model_user, P_L[j in user_set, t in time_set],
    P_shf[j,t] + P_adj[j,t] + P_fix[j,t]
    )

    # CAPEX by user and asset
    @expression(model_user, CAPEX_us[u in user_set, a in device_names(users_data[u])],
        x_us[u,a]*field_component(users_data[u], a, "CAPEX_lin")  # Capacity of the asset times specific investment costs
    )

    @expression(model_user, CAPEX_tot_us[u in user_set],
        sum(CAPEX_us[u, a] for a in device_names(users_data[u])) # sum of CAPEX by asset for the same user
    )  # CAPEX by user

    @expression(model_user, C_OEM_us[u in user_set, a in device_names(users_data[u])],
        x_us[u,a]*field_component(users_data[u], a, "OEM_lin")  # Capacity of the asset times specific operating costs
        + (  # Add OEM of thermal generators
            asset_type(users_data[u], a) == THER
            ? sum(
                profile(ECModel.gen_data,"energy_weight")[t] * profile(ECModel.gen_data, "time_res")[t] * z_gen_us[u,a,t]
                for t in time_set
            ) * field_component(users_data[u], a, "nom_capacity") * field_component(users_data[u], a, "OEM_com")
            : 0.0
        )
    )  # Maintenance cost by user and asset

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
        market_profile_by_user(ECModel,u,"peak_weight")[w] * market_profile_by_user(ECModel,u, "peak_tariff")[w] * P_max_us[u, w]
        # Peak tariff times the maximum connection usage times the discretization of the period
    )

    # Total peak tariff cost by user
    @expression(model_user, C_Peak_tot_us[u in user_set],
        sum(C_Peak_us[u, w] for w in peak_set)  # Sum of peak costs
    ) 

    # Revenues of each user in non-cooperative approach
    @expression(model_user, R_Energy_us[u in user_set, t in time_set],
        profile(ECModel.gen_data,"energy_weight")[t] * profile(ECModel.gen_data, "time_res")[t] * (market_profile_by_user(ECModel,u, "sell_price")[t]*P_P_us[u,t]
            - market_profile_by_user(ECModel,u,"buy_price")[t] * P_N_us[u,t] 
            - market_profile_by_user(ECModel,u,"consumption_price")[t] * sum(
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

    # Costs arising from the use of fuel-fired generators by users and asset
    @expression(model_user, C_gen_us[u in user_set, g=asset_names(users_data[u], THER), t in time_set],
        profile(ECModel.gen_data,"energy_weight")[t] * profile(ECModel.gen_data, "time_res")[t] *
        (
            z_gen_us[u,g,t] * field_component(users_data[u], g, "nom_capacity") *
                field_component(users_data[u], g, "fuel_price") *
                field_component(users_data[u], g, "inter_map")
            + P_gen_us[u,g,t] * field_component(users_data[u], g, "fuel_price") * 
                field_component(users_data[u], g, "slope_map")
            )
    )

    # Energy revenues by user by asset
    @expression(model_user, C_gen_tot_us_asset[u in user_set, g=asset_names(users_data[u], THER)],
        sum(C_gen_us[u, g, t] for t in time_set)  # sum of revenues by user
    )

    # Total costs arising from the use of fuel-fired generators by users
    @expression(model_user, C_gen_tot_us[u in user_set],
        sum(C_gen_tot_us_asset[u,g] for g  in asset_names(users_data[u], THER))
    )

    # Cash flow
    @expression(model_user, Cash_flow_us[y in year_set_0, u in user_set],
        (y == 0) ? 0 - CAPEX_tot_us[u] : 
            (R_Energy_tot_us[u]
            - C_gen_tot_us[u]
            - C_Peak_tot_us[u] 
            - C_OEM_tot_us[u] 
            - C_REP_tot_us[y, u] 
            + R_RV_tot_us[y, u])
    )

    # Annualized profits by the user; the sum of this function is the objective function
    @expression(model_user, NPV_us[u in user_set],
        sum(
            Cash_flow_us[y, u] / ((1 + field(gen_data, "d_rate"))^y)
        for y in year_set_0)
    )

    # Power flow by user POD
    @expression(model_user, P_us[u = user_set, t = time_set],
        P_P_us[u, t] - P_N_us[u, t]
    )

    # Total converter dispatch: positive when supplying to AC
    @expression(model_user, P_conv_us[u=user_set, c=asset_names(users_data[u], CONV), t=time_set],
        P_conv_P_us[u, c, t] - P_conv_N_us[u, c, t]
    )

    ## Inequality constraints

    # Set that the hourly dispatch cannot go beyond the maximum dispatch of the corresponding peak power period
    @constraint(model_user, con_us_max_P_user[u = user_set, t = time_set],
        - P_max_us[u, profile(gen_data, "peak_categories")[t]] + P_P_us[u, t] + P_N_us[u, t] <= 0
    )

    # Set the renewabl energy dispatch to be no greater than the actual available energy
    @constraint(model_user, con_us_ren_dispatch[u in user_set, t in time_set],
        - sum(profile_component(users_data[u], r, "ren_pu")[t] * x_us[u, r]
            for r in asset_names(users_data[u], REN))
        + P_ren_us[u, t] <= 0
    )

    # Set the maximum hourly dispatch of converters not to exceed their capacity
    @constraint(model_user, con_us_converter_capacity[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
        - x_us[u, c] + P_conv_P_us[u, c, t] + P_conv_N_us[u, c, t] <= 0
    )


    # Set the maximum hourly dispatch of converters not to exceed the C-rate of the battery in discharge
    @constraint(model_user, con_us_converter_capacity_crate_dch[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
        P_conv_P_us[u, c, t] <= 
            x_us[u, field_component(users_data[u], c, "corr_asset")] * field_component(users_data[u], field_component(users_data[u], c, "corr_asset"), "max_C_dch")
    )


    # Set the maximum hourly dispatch of converters not to exceed the C-rate of the battery in charge
    @constraint(model_user, con_us_converter_capacity_crate_ch[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
        P_conv_N_us[u, c, t] <= 
            x_us[u, field_component(users_data[u], c, "corr_asset")] * field_component(users_data[u], field_component(users_data[u], c, "corr_asset"), "max_C_ch")
    )


    # Set the minimum level of the energy stored in the battery to be proportional to the capacity
    @constraint(model_user, con_us_min_E_batt[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
        x_us[u, b] * field_component(users_data[u], b, "min_SOC") - E_batt_us[u, b, t] <= 0
    )

    # Set the maximum level of the energy stored in the battery to be proportional to the capacity
    @constraint(model_user, con_us_max_E_batt[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
        - x_us[u, b] * field_component(users_data[u], b, "max_SOC") + E_batt_us[u, b, t] <= 0
    )

    # Set that the number of working generator plants cannot exceed the number of generator plants installed
    @constraint(model_user, con_us_gen_on[u in user_set, g=asset_names(users_data[u], THER), t in time_set],
        z_gen_us[u, g, t] <= n_us[u, g]
    )

    # Set the minimum dispatch of the thermal generator
    @constraint(model_user, con_us_gen_min_disp[u in user_set, g=asset_names(users_data[u], THER), t in time_set],
        P_gen_us[u, g, t] - z_gen_us[u, g, t] * field_component(users_data[u], g, "nom_capacity") * field_component(users_data[u], g, "min_technical") >= 0
    )

    # Set the maximum dispatch of the thermal generator
    @constraint(model_user, con_us_gen_max_disp[u in user_set, g=asset_names(users_data[u], THER), t in time_set],
        P_gen_us[u, g, t] - z_gen_us[u, g, t] * field_component(users_data[u], g, "nom_capacity") * field_component(users_data[u], g, "max_technical") <= 0)

    ## Equality constraints

    # Set the electrical balance at the user system
    @constraint(model_user,
        con_us_balance[u in user_set, t in time_set],
        P_N_us[u, t] - P_P_us[u, t]
        + sum(P_gen_us[u, g, t] for g in asset_names(users_data[u], THER))
        + sum(GenericAffExpr{Float64,VariableRef}[
            P_conv_P_us[u, c, t] - P_conv_N_us[u, c, t] for c in asset_names(users_data[u], CONV)])
        + P_ren_us[u, t]
        ==
        sum(Float64[profile_component(users_data[u], l, "load")[t] for l in asset_names(users_data[u], LOAD)])
    )

    # Set the balance at each battery system
    @constraint(model_user,
        con_us_bat_balance[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
        #E_batt_us[u, b, t] - E_batt_us[u, b, if (t>1) t-1 else final_step end]  # Difference between the energy level in the battery. Note that in the case of the first time step, the last id is used
        E_batt_us[u, b, t] - E_batt_us[u, b, pre(t, time_set)]  # Difference between the energy level in the battery. Note that in the case of the first time step, the last id is used
        + profile(gen_data, "time_res")[t] * P_conv_P_us[u, field_component(users_data[u], b, "corr_asset"), t]/(
            sqrt(field_component(users_data[u], b, "eta"))*field_component(users_data[u], field_component(users_data[u], b, "corr_asset"), "eta"))  # Contribution of the converter when supplying power to AC
        - profile(gen_data, "time_res")[t] * P_conv_N_us[u, field_component(users_data[u], b, "corr_asset"), t]*(
            sqrt(field_component(users_data[u], b, "eta"))*field_component(users_data[u], field_component(users_data[u], b, "corr_asset"), "eta"))  # Contribution of the converter when absorbing power from AC
        == 0
    )
    
    return ECModel
end

"""
    market_profile_by_user(ECModel::AbstractEC, u_name, profile_name)

Function to calculate the profile of each users related to their market type (e.g. commercial, non_commercial)
Outputs
-------
profile
    Profile object corresponding to the target profile name and user

"""

function market_profile_by_user(ECModel::AbstractEC, u_name, profile_name)
    user_tariff_name = field(ECModel.users_data[u_name],"tariff_name")
    #This line allow to check if a tariff_name provided for any user is present in the market dictionary
    market_data_type = field(ECModel.market_data, user_tariff_name,"Missing market type definition '$user_tariff_name'")
    return profile(ECModel.market_data[user_tariff_name], profile_name)
end

"""
    calculate_demand(ECModel::AbstractEC)

Function to calculate the demand by user
Outputs
-------
demand_us_EC : DenseAxisArray
    DenseAxisArray representing the demand by the EC and each user

"""

function calculate_demand(ECModel::AbstractEC)

    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)

    # users set
    users_data = ECModel.users_data

    # time step resolution
    time_res = profile(ECModel.gen_data, "time_res")
    energy_weight = profile(ECModel.gen_data,"energy_weight")

    data_load = Float64[sum(sum(
                profile_component(users_data[u], l, "load") .* time_res .* energy_weight)
                for l in asset_names(users_data[u], LOAD)
            ) for u in user_set]

    # sum of the load power by user and EC
    demand_us_EC = JuMP.Containers.DenseAxisArray(
        [sum(data_load); data_load],
        user_set_EC
    )

    return demand_us_EC
end

"""
    calculate_production(ECModel::AbstractEC)

Function to calculate the energy production by user
Outputs
-------
production_us_EC : DenseAxisArray
    DenseAxisArray representing the production by the EC and each user

"""
function calculate_production(ECModel::AbstractEC)

    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)

    gen_data = ECModel.gen_data
    users_data = ECModel.users_data

    # get time set
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    time_set = 1:n_steps

    # time step resolution
    time_res = profile(gen_data, "time_res")
    energy_weight = profile(gen_data, "energy_weight")

    _P_ren = ECModel.results[:P_ren_us]
    _P_gen = ECModel.results[:P_gen_us]

    data_production_ren = Float64[
        has_asset(users_data[u], REN) ? sum(_P_ren[u, :] .* time_res .* energy_weight) : 0.0
        for u in user_set
    ]

    data_production_gen = Float64[ !has_asset(users_data[u], THER) ? 0.0 : sum(time_res[t] * energy_weight[t] * _P_gen[u, g, t] 
                for g in asset_names(users_data[u], THER) for t in time_set
            ) for u in user_set
        ]

    data_production = data_production_ren + data_production_gen

    # sum of the load power by user and EC
    production_us_EC = JuMP.Containers.DenseAxisArray(
        [sum(data_production); data_production],
        user_set_EC
    )

    return production_us_EC
end


"""
    calculate_production_shares(ECModel::AbstractEC; per_unit::Bool=true)

Calculate energy ratio by energy production resource for a generic group
Output is normalized with respect to the demand when per_unit is true
'''
# Outputs
frac : DenseAxisArray
    DenseAxisArray describing the share of energy production by
    energy resource by user and the entire system,
    normalized with respect to the demand of the corresponding group

'''
"""
function calculate_production_shares(ECModel::AbstractEC; per_unit::Bool=true)

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

    # list of all assets
    ren_set_unique = unique([name for u in user_set for name in asset_names(users_data[u], REN)])

    _P_tot_us = ECModel.results[:P_us]  # power dispatch of users - users mode
    _P_ren_us = ECModel.results[:P_ren_us]  # Ren production dispatch of users - users mode
    _P_gen_us = ECModel.results[:P_gen_us]  # Production of thermal generators of users - users mode
    _x_us = ECModel.results[:x_us]  # Installed capacity by user

    # time step resolution
    time_res = profile(ECModel.gen_data, "time_res")
    energy_weight = profile(ECModel.gen_data,"energy_weight")

    # Available renewable production
    _P_ren_available = JuMP.Containers.DenseAxisArray(
        [sum(Float64[
            !has_asset(users_data[u], r) ? 0.0 : profile_component(users_data[u], r, "ren_pu")[t] * _x_us[u,r]
                for r in asset_names(users_data[u], REN)
        ]) for u in user_set, t in time_set],
        user_set, time_set
    )

    # Calculate total energy fraction at EC level for every renewable resource
    frac_tot = JuMP.Containers.DenseAxisArray(
        [(sum(!has_asset(users_data[u], t_ren) ? 0.0 : sum(
                Float64[
                    _P_ren_us[u,t] <= 0.0 ? 0.0 : _P_ren_us[u,t] * sum(
                        Float64[profile_component(users_data[u], r, "ren_pu")[t] * _x_us[u,r]
                        for r in asset_names(users_data[u], REN) if r == t_ren]
                    ) / _P_ren_available[u, t] * time_res[t] * energy_weight[t]
                    for t in time_set
            ]) for u in user_set
            ))
        for t_ren in ren_set_unique],
        ren_set_unique
    )

    # fraction of energy production by user and EC
    frac = JuMP.Containers.DenseAxisArray(
        Float64[
            frac_tot.data';
            Float64[!has_asset(users_data[u], t_ren) ? 0.0 : sum(
                Float64[
                    _P_ren_us[u,t] <= 0.0 ? 0.0 : _P_ren_us[u,t] * sum(Float64[
                        profile_component(users_data[u], r, "ren_pu")[t] * _x_us[u,r]
                            for r in asset_names(users_data[u], REN) if r == t_ren
                    ]) / _P_ren_available[u,t] * time_res[t] * energy_weight[t]
                    for t in time_set
                ])
                for u in user_set, t_ren in ren_set_unique
            ]
        ],
        user_set_EC, ren_set_unique
    )

    # normalize output if perunit is required
    if per_unit

        # calculate the demand by EC and user
        demand_EC_us = calculate_demand(ECModel)

        # create auxiliary DenseAxisArray to perform the division
        
        # update value
        frac = JuMP.Containers.DenseAxisArray(
                frac.data ./ demand_EC_us.data,
            user_set_EC, ren_set_unique)
        
    end

    return frac
end


"""
    calculate_self_production(ECModel::AbstractEC; per_unit::Bool=true, only_shared::Bool=false)

Calculate the self production for each user.
Output is normalized with respect to the demand when per_unit is true

'''
Outputs
-------
shared_en_frac : DenseAxisArray
    Shared energy for each user and the aggregation
'''
"""
function calculate_self_production(ECModel::AbstractEC; per_unit::Bool=true, only_shared::Bool=false)

    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)
    users_data = ECModel.users_data

    gen_data = ECModel.gen_data
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1

    # Set definitions
    time_set = 1:n_steps

    # time step resolution
    time_res = profile(ECModel.gen_data, "time_res")
    energy_weight = profile(ECModel.gen_data,"energy_weight")

    _P_us = ECModel.results[:P_us]  # power dispatch of users - users mode
    _P_ren_us = ECModel.results[:P_ren_us]  # renewable production by user
    _P_gen_us = ECModel.results[:P_gen_us]  # renewable production by user by asset

    # total thermal production by user only
    _tot_P_gen_us = JuMP.Containers.DenseAxisArray(
        Float64[ !has_asset(users_data[u], THER) ? 0.0 : sum(time_res[t] * energy_weight[t] * _P_gen_us[u, g, t] 
                for g in asset_names(users_data[u], THER) for t in time_set
            ) for u in user_set],
        user_set
    )

    # self consumption by user only
    shared_en_us = JuMP.Containers.DenseAxisArray(
        Float64[sum(time_res .* energy_weight .* max.(
                0.0, _P_ren_us[u, :] - max.(_P_us[u, :], 0.0)
            )) +  _tot_P_gen_us[u] 
            for u in user_set],
        user_set
    )

    # self consumption by user and EC
    shared_en_frac = JuMP.Containers.DenseAxisArray(
        [
            sum(shared_en_us);
            shared_en_us.data
        ],
        user_set_EC
    )

    # normalize output if perunit is required
    if per_unit

        # calculate the demand by EC and user
        demand_EC_us = calculate_demand(ECModel)
        
        # update value
        shared_en_frac = shared_en_frac ./ demand_EC_us

    end

    return shared_en_frac
end



"""
    calculate_self_consumption(ECModel::AbstractEC; per_unit::Bool=true)

Calculate the demand that each user meets using its own sources, or self consumption.
Output is normalized with respect to the demand when per_unit is true

'''
Outputs
-------
shared_cons_frac : DenseAxisArray
    Shared consumption for each user and the aggregation
'''
"""
function calculate_self_consumption(ECModel::AbstractEC; per_unit::Bool=true)

    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)

    users_data = ECModel.users_data

    _P_us = ECModel.results[:P_us]  # power dispatch of users - users mode

    # time step resolution
    time_res = profile(ECModel.gen_data, "time_res")
    energy_weight = profile(ECModel.gen_data,"energy_weight")

    # self consumption by user only
    shared_cons_us = JuMP.Containers.DenseAxisArray(
        Float64[sum(time_res .* energy_weight .* max.(0.0, 
                sum(profile_component(users_data[u], l, "load") for l in asset_names(users_data[u], LOAD)) 
                + min.(_P_us[u, :], 0.0)
            )) for u in user_set],
        user_set
    )

    # self consumption by user and EC
    shared_cons = JuMP.Containers.DenseAxisArray(
        Float64[
            sum(shared_cons_us);
            shared_cons_us.data
        ],
        user_set_EC
    )

    # normalize output if perunit is required
    if per_unit

        # calculate the demand by EC and user
        demand_EC_us = calculate_demand(ECModel)
        
        # update value
        shared_cons = shared_cons ./ demand_EC_us

    end

    return shared_cons
end
