# accepted technologies
ACCEPTED_TECHS = ["load", "renewable", "converter", "thermal", "storage"]
"""
    build_base_model!(ECModel::AbstractEC, optimizer)

Creates the base optimization model for all the EC models

## Arguments

* `ECModel`: EC model object
* `optimizer`: optimizer object; any optimizer from JuMP
* `use_notations`: boolean; if true, the model will be created using the direct mode to create the JuMP model

## Returns

It returns the ECModel object with the base model created
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
            - sum(Float64[profile_component(users_data[u], l, "e_load")[t] for l in asset_names(users_data[u], LOAD)]) # Minimum demand
        ) * TOL_BOUNDS
    )

    # Overestimation of the power exchanged by each POD when buying from the external market bu each user
    @expression(model_user, P_N_us_overestimate[u in user_set, t in time_set],
        max(0,
            sum(Float64[profile_component(users_data[u], l, "e_load")[t] for l in asset_names(users_data[u], LOAD)])
                # Maximum demand
            + sum(Float64[field_component(users_data[u], c, "max_capacity") 
                for c in asset_names(users_data[u], CONV)])  # Maximum capacity of the converters
        ) * TOL_BOUNDS
    )

    # Overestimation of the power exchanged by each POD, be it when buying or selling by each user
    @expression(model_user, P_us_overestimate[u in user_set, t in time_set],
        max(P_P_us_overestimate[u, t], P_N_us_overestimate[u, t])  # Max between the maximum values calculated previously
    )

    # Overestimation of the thermal power exchanged by each "user" when uploading to the "Thermal Grid" by each user
    @expression(model_user, P_P_us_overestimate_th[u in user_set, t in time_set],
        max(0,
            # sum(Float64[field_component(users_data[u], g, "max_capacity") 
            #     for g in asset_names(users_data[u], THER)]) # Maximum capacity of thermal generator
            # + sum(Float64[field_component(users_data[u], r, "max_capacity")*profile_component(users_data[u], r, "ren_pu")[t] 
            #       for r = asset_names(users_data[u], REN)]) # Maximum dispatch of renewable assets as solar panels
            + sum(Float64[field_component(users_data[u], g, "max_capacity")*field_component(users_data[u], g, "max_technical")
                for g = asset_names(users_data[u], THER)]) #Maximum dispatch of the fuel-fired generators
            - sum(Float64[profile_component(users_data[u], l, "t_load")[t] for l in asset_names(users_data[u], LOAD)]) # Minimum demand
        ) * TOL_BOUNDS
    )

    # Overestimation of the thermal power exchanged by each "user" when downloading from the "Thermal Grid" by each user
    @expression(model_user, P_N_us_overestimate_th[u in user_set, t in time_set],
        max(0,
            sum(Float64[profile_component(users_data[u], l, "t_load")[t] for l in asset_names(users_data[u], LOAD)])
                # Maximum thermal demand
            + sum(Float64[field_component(users_data[u], g, "max_capacity") 
                for g in asset_names(users_data[u], THER)])  # Maximum capacity of thermal generator
            + sum(Float64[field_component(users_data[u], s, "max_capacity") 
                for s in asset_names(users_data[u], STOR)])  # Maximum capacity of thermal storage
        ) * TOL_BOUNDS
    )

    ## Variable definition
    
    # Energy stored in the battery
    @variable(model_user, 
        0 <= E_batt_us[u=user_set, b=asset_names(users_data[u], STOR), t=time_set] 
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
    # Energy stored in the thermal storage
    @variable(model_user,
        0 <= E_tes_us[u=user_set, s=asset_names(users_data[u], STOR), t=time_set] 
            <= field_component(users_data[u], s, "max_capacity"))
    # Thermal Power of the heat pump
    @variable(model_user,
        0 <= P_hp_T[u=user_set, g=asset_names(users_data[u], THER), t=time_set] 
            <= field_component(users_data[u], g, "max_capacity"))
    # Total dispatch of the user, positive when uploading to public th grid
    @variable(model_user,
        0 <= P_P_us_th[u=user_set, t in time_set]
            <= P_P_us_overestimate_th[u, t])
    # Total dispatch of the user, positive when downloading from public th grid
    @variable(model_user,
        0 <= P_N_us_th[u=user_set, t in time_set]
            <= P_N_us_overestimate_th[u, t])
    # Mass flow of fuel in the thermal generator as boiler        
    @variable(model_user, 
        0 <= m_fuel[u=user_set, g=asset_names(users_data[u], THER), t=time_set] 
            <= field_component(users_data[u], g, "max_capacity"))               

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

    #     # Total energy available in the batteries
    #     @expression(model, E_batt_tot_us[u=user_set, t=time_set],
    #     sum(E_batt_us[u, b, t] for b in asset_names(users_data[u], THER))
    # )

    # Total thermal power given by heat pumps
    @expression(model, P_hp_T_tot[u=user_set, t=time_set],
        sum(P_hp_T[u, g, t] for g in asset_names(users_data[u], THER))
    )

    # Electrical power for thermal use of heat pump in heating mode by each pump and user
    @expression(model_user, P_el_heat[u in user_set, t in time_set],
        sum(P_hp_T[u, g, t]/field_component(users_data[u], g, "COP") for g in asset_names(users_data[u],THER))
    )

    # Energy Efficiency Ratio of the heat pump in cooling mode by each pump and user
    @expression(model_user, EER[t in time_set],
    field_component(users_data[u], g,"EER_nom")[t]* (1 - field_component(users_data[u], g,"alpha")*(profile_component(users_data[u], g,"T_ext")[t]
    - field_component(users_data[u], g,"T_ref")[t]))
    )

    # Electrical power for thermal use of heat pump in cooling mode by each pump and user
    @expression(model_user, P_el_cool[u in user_set, t in time_set],
        sum(P_hp_T[u, g, t]/EER[t] 
        for g in asset_names(users_data[u],THER))
    )

    # Total energy available in the thermal storage
    @expression(model, E_tes_tot_us[u=user_set, t=time_set],
    sum(E_tes_us[u, s, t] for s in asset_names(users_data[u], STOR))
    )

    # Unheated zone Temperature of each tes and user
    @expression(model_user, T_u[u in user_set, s in asset_names(users_data[u],STOR), t in time_set],
        (profile_component(users_data[u], s,"T_int")[t])
        - field_component(users_data[u], s,"b_tr_x")*(profile_component(users_data[u], s, "T_int")[t]
        - profile_component(users_data[u], s,"T_ext")[t]) 
    )

    # Heat Energy losses in Thermal Storage by each tes and user
    @expression(model_user, Tes_heat_loss[u in user_set, s in asset_names(users_data[u],STOR), t  in time_set],
        field_component(users_data[u], s, "k")*E_tes_us[u, s, pre(t, time_set)]*(profile_component(users_data[u], s, "T_ref")[t] - T_u[u, s, t])
    )

    # Capacity Energy losses in Thermal Storage by each tes and user (if the energy stored is greater than the maximum capacity, and DHN is not available)
    @expression(model_user, Tes_capacity_loss[u in user_set, s in asset_names(users_data[u], STOR), t in time_set], 
        max(0, E_tes_us[u, s, pre(t, time_set)]
        + (P_hp_T[u, g, t] + P_boil_us[u, g, t]) * profile(market_data, "time_res")[t]
        - field_component(users_data[u], s, "max_capacity"))
    )

    # Total energy losses in the storage by each user
    @expression(model_user, Tes_total_loss[u in user_set, t in time_set], 
        sum(Tes_heat_loss[u, s, t] + Tes_capacity_loss[u, s, t] for s in asset_names(users_data[u], STOR))
    )

    # Thermal power for use of boiler by each boiler and user
    @expression(model_user, P_boil_us[u in user_set, t in time_set],
        sum(field_component(users_data[u], g, "eta") * P_fuel[u, g, t] 
        for g in asset_names(users_data[u], THER))
    )

    # Fuel power for use of boiler by each boiler and user
    @expression(model_user, P_fuel[u in user_set, t in time_set], 
        sum(profile_component(users_data[u], g,"m_fuel")[t] * field_component(users_data[u], g, "PCI") 
        for g in asset_names(users_data[u], THER))
    )

    ## Economic Expressions

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
                Float64[profile_component(users_data[u], l, "e_load")[t]
                for l in asset_names(users_data[u], LOAD)]))  # economic flow with the market
    )

    # Energy revenues by user
    @expression(model_user, R_Energy_tot_us[u in user_set],
        sum(R_Energy_us[u, t] for t in time_set)  # sum of revenues by user
    )

    # # Economic balance of the aggregation with respect to the public market in every hour
    # @expression(model, R_Energy_agg_time[t in time_set],
    #     sum(R_Energy_us[u, t] for u in user_set)
    # )

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

    # Heat loss cost for each user by user
    @expression(model_user, C_heat_loss[u in user_set, t in time_set],
    profile(market_data, "time_res")[t] *
    (
        # If user is connected to the DHN, heat loss cost, from tes energy losses, is calculated with heat_tariff
        users_data[u]["DHN"]["connected"] ? 
            sum(Tes_total_loss[u, s, t] for s in asset_names(users_data[u], STOR), init=0) * users_data[u]["DHN"]["heat_tariff"]
            :
            # If user is NOT connected to the DHN
            (
                length(asset_names(users_data[u], STOR)) > 0 ?  
                    # If user has a TES, Energy loss is given by Tes_total_loss multiplied by fuel price
                    sum(Tes_total_loss[u, s, t] for s in asset_names(users_data[u], STOR)) *
                    (
                        length(asset_names(users_data[u], BOIL)) > 0 ?  
                            field_component(users_data[u], "boil", "fuel_price") / field_component(users_data[u], "boil", "eta")  # If use gas (boiler)
                            :
                            profile(market_data, "energy_weight")[t] * field_component(users_data[u], "hp", "buy_price") / field_component(users_data[u], "hp", "COP")  # If use electricity (heat pump)
                    )
                    :
                    # If user has NOT a TES, Energy loss is given by thermal component's oversizing compared to thermal load
                    sum(
                        max(
                            0, 
                            (P_hp_T[u, g, t] + P_boil_us[u, g, t]) - profile_component(users_data[u], "t_load", "value")[t] / profile(market_data, "time_res")[t]
                        ) *
                        (
                            g in asset_names(users_data[u], BOIL) ?
                                field_component(users_data[u], g, "fuel_price") / field_component(users_data[u], g, "eta")  # Boiler: use fuel_price and eta
                                :
                                profile(market_data, "energy_weight")[t] * field_component(users_data[u], g, "buy_price") / field_component(users_data[u], g, "COP")   # Heat pump: use buy_price and COP
                        )
                        for g in asset_names(users_data[u], THER)
                    )
            )
    )
)

    # CASH FLOW
    # Cash flow of each user
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
    @constraint(model_user, con_us_min_E_batt[u in user_set, b in asset_names(users_data[u], THER), t in time_set],
        x_us[u, b] * field_component(users_data[u], b, "min_SOC") - E_batt_us[u, b, t] <= 0
    )

    # Set the maximum level of the energy stored in the battery to be proportional to the capacity
    @constraint(model_user, con_us_max_E_batt[u in user_set, b in asset_names(users_data[u], THER), t in time_set],
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
        P_gen_us[u, g, t] - z_gen_us[u, g, t] * field_component(users_data[u], g, "nom_capacity") * field_component(users_data[u], g, "max_technical") <= 0
    )

    # Set the maximum level of the energy stored in the storage to be proportional to the capacity
    @constraint(model,
        con_us_max_tes[u in user_set, s in asset_names(users_data[u], STOR), t in time_set],
        E_tes_us[u, s, t] <= x_us[u, s]
    )  
    # Set the maximun dispatch of the heat pump 
    @constraint(model,
        con_us_max_hp[u in user_set, g in asset_names(users_data[u], THER), t in time_set],
        P_hp_T[u, g, t] <= x_us[u, g]
    )  

    ## Equality constraints

    # Set the thermal balance at each storage system
    @constraint(model,
        con_us_tes_balance[u in user_set, l in asset_names(users_data[u], LOAD), t in time_set],
        E_tes_us[u, field_component(users_data[u], l, "corr_storage"), t] - E_tes_us[u,field_component(users_data[u], l, "corr_storage") , pre(t, time_set)]  # Difference between the energy level in the storage. Note that in the case of the first time step, the last id is used
        == 
        profile(market_data, "time_res")[t] * P_hp_T[u, field_component(users_data[u], l, "corr_asset"), t]
        - profile(market_data, "time_res")[t] * profile_component(users_data[u],l, "t_load")[t]
        - Tes_heat_loss[u,field_component(users_data[u], l, "corr_storage"),t]*profile(market_data, "time_res")[t]
    ) 

    # Set the electrical balance at the user system
    @constraint(model_user,
        con_us_balance[u in user_set, t in time_set],
        P_N_us[u, t] - P_P_us[u, t]
        + sum(P_gen_us[u, g, t] for g in asset_names(users_data[u], THER))
        + sum(GenericAffExpr{Float64,VariableRef}[
            P_conv_P_us[u, c, t] - P_conv_N_us[u, c, t] for c in asset_names(users_data[u], CONV)])
        + P_ren_us[u, t]
        ==
        sum(Float64[profile_component(users_data[u], l, "e_load")[t] for l in asset_names(users_data[u], LOAD)])
    )

    # Set the balance at each battery system
    @constraint(model_user,
        con_us_bat_balance[u in user_set, b in asset_names(users_data[u], THER), t in time_set],
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

Function to retrieve the market profile of each user,
according to their market type (e.g. commercial, domestic, etc.)

## Arguments

* `ECModel`: EC model object
* `u_name`: user name
* `profile_name`: profile name

## Returns

It returns the vector of data corresponding to the profile of the user according to the market type
"""
function market_profile_by_user(ECModel::AbstractEC, u_name, profile_name)
    user_tariff_name = field(ECModel.users_data[u_name],"tariff_name")
    #This line allow to check if a tariff_name provided for any user is present in the market dictionary
    market_data_type = field(ECModel.market_data, user_tariff_name,"Missing market type definition '$user_tariff_name'")
    return profile(ECModel.market_data[user_tariff_name], profile_name)
end

"""
    get_dhn_data(ECModel::AbstractEC, u_name)

Function to retrieve district heating network (DHN) data for a user.
If the user is connected to the DHN, it returns both the DHN data and the corresponding heat exchanger data.
If the user is not connected, it returns the user's local heating components.

## Arguments

* `ECModel`: EC model object
* `u_name`: user name

## Returns

It returns a dictionary containing DHN data and heat exchanger data if the user is connected.
Otherwise, it returns the user's local heating components.
"""
function get_dhn_data(ECModel::AbstractEC, u_name)
    user_data = ECModel.users_data[u_name]
    
    if haskey(user_data, "DHN") && user_data["DHN"]["connected"]
        return Dict(
            "DHN_data" => user_data["DHN"],  # District heating network data, if present
            "ECU_data" => get(user_data, "ECU", Dict())  # Heat exchanger data
        )
    else
        return Dict(
            "local_heating_assets" => filter(p -> p.second["type"] == "thermal" || p.first == "tes", user_data)
        )  # Return local heating assets if not connected to DHN
    end
end

"""
    calculate_demand(ECModel::AbstractEC)

Function to calculate the demand by user

## Arguments

* `ECModel`: EC model object

## Returns

It returns the demand by user and the whole EC as a DenseAxisArray
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

    data_e_load = Float64[sum(sum(
                profile_component(users_data[u], l, "e_load") .* time_res .* energy_weight)
                for l in asset_names(users_data[u], LOAD)
            ) for u in user_set]

    # sum of the electrical load power by user and EC
    demand_us_EC = JuMP.Containers.DenseAxisArray(
        [sum(data_e_load); data_e_load],
        user_set_EC
    )

    return demand_us_EC
end

"""
    calculate_production(ECModel::AbstractEC)

Function to calculate the energy production by user

## Arguments

* `ECModel`: EC model object

## Returns

It returns the production by user and the whole EC as a DenseAxisArray
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
    _P_hp = ECModel.results[:P_hp_T]

    data_production_ren = Float64[
        has_asset(users_data[u], REN) ? sum(_P_ren[u, :] .* time_res .* energy_weight) : 0.0
        for u in user_set
    ]

    data_production_gen = Float64[ !has_asset(users_data[u], THER) ? 0.0 : sum(time_res[t] * energy_weight[t] * _P_gen[u, g, t] 
                for g in asset_names(users_data[u], THER) for t in time_set
            ) for u in user_set
        ]

    data_production_hp = Float64[ !has_asset(users_data[u], THER) ? 0.0 : sum(time_res[t] * energy_weight[t] * _P_hp[u, g, t] 
                for g in asset_names(users_data[u], THER) for t in time_set
            ) for u in user_set
        ]

    data_production = data_production_ren + data_production_gen + data_production_hp

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
Output is normalized with respect to the demand when `per_unit` is true

## Arguments

* `ECModel`: EC model object
* `per_unit`: boolean; if true, the output is normalized with respect to the demand

## Returns

It returns a DenseAxisArray describing the share of energy production by 
energy resource by user and the entire system,
optionally normalized with respect to the demand of the corresponding group, when `per_unit` is true
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
    _E_tes_us = ECModel.results[:E_tes_us]  # Energy stored in the thermal storage
    _P_hp_T = ECModel.results[:P_hp_T]  # Thermal power of the heat pump

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
    calculate_self_production(ECModel::AbstractEC; per_unit::Bool=true)

Calculate the self production for each user.
Output is normalized with respect to the demand when `per_unit` is true

## Arguments

* `ECModel`: EC model object
* `per_unit`: boolean; if true, the output is normalized with respect to the demand

## Returns

It returns a DenseAxisArray describing the self production for each user and the aggregation, optionally normalized with respect to the demand of the corresponding group, when `per_unit` is true
"""
function calculate_self_production(ECModel::AbstractEC; per_unit::Bool=true)

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
    _P_gen_us = ECModel.results[:P_gen_us]  # thermal generators production by user
    _P_hp_T = ECModel.results[:P_hp_T]  # thermal power of the heat pump
    _E_tes_us = ECModel.results[:E_tes_us]  # energy stored in the thermal storage

    # total thermal production by user only
    _tot_P_gen_us = JuMP.Containers.DenseAxisArray(
        Float64[ !has_asset(users_data[u], THER) ? 0.0 : sum(time_res[t] * energy_weight[t] * _P_gen_us[u, g, t] 
                for g in asset_names(users_data[u], THER) for t in time_set
            ) for u in user_set],
        user_set
    )

    # total heat pump production by user only
    _tot_P_hp_us = JuMP.Containers.DenseAxisArray(
        Float64[ !has_asset(users_data[u], THER) ? 0.0 : sum(time_res[t] * energy_weight[t] * _P_hp_T[u, g, t] 
                for g in asset_names(users_data[u], THER) for t in time_set
            ) for u in user_set],
        user_set
    )

    # self consumption by user only
    shared_en_us = JuMP.Containers.DenseAxisArray(
        Float64[sum(time_res .* energy_weight .* max.(
                0.0, _P_ren_us[u, :] - max.(_P_us[u, :], 0.0)
            )) +  _tot_P_gen_us[u] + _tot_P_hp_us[u]
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
Output is normalized with respect to the demand when `per_unit` is true

## Arguments

* `ECModel`: EC model object
* `per_unit`: boolean; if true, the output is normalized with respect to the demand

## Returns

It returns a DenseAxisArray describing the self consumption for each user and the aggregation, optionally normalized with respect to the demand of the corresponding group, when `per_unit` is true
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
                sum(profile_component(users_data[u], l, "e_load") for l in asset_names(users_data[u], LOAD)) 
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
