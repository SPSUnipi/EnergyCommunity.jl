# accepted technologies
ACCEPTED_TECHS = ["load", "t_load", "renewable", "battery", "converter", "thermal", "load_adj", "storage", "heat_pump", "boiler"]

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
            - sum(Float64[profile_component(users_data[u], l, "load")[t] for l in asset_names(users_data[u], LOAD)])  # Minimum fix demand
            + sum(Float64[profile_component(users_data[u], e, "max_supply")[t] for e in asset_names(users_data[u], LOAD_ADJ)])  # Maximum adjustable load
        ) * TOL_BOUNDS
    )

    # Overestimation of the power exchanged by each POD when buying from the external market by each user
    @expression(model_user, P_N_us_overestimate[u in user_set, t in time_set],
        max(0,
            sum(Float64[profile_component(users_data[u], l, "load")[t] for l in asset_names(users_data[u], LOAD)])
                # Maximum fix demand
            + sum(Float64[profile_component(users_data[u], e, "max_withdrawal")[t] for e in asset_names(users_data[u], LOAD_ADJ)])  # Maximum adjustable load
            + sum(Float64[field_component(users_data[u], c, "max_capacity") 
                for c in asset_names(users_data[u], CONV)])  # Maximum capacity of the converters
        ) * TOL_BOUNDS
    )

    # Overestimation of the power exchanged by each POD, be it when buying or selling by each user
    @expression(model_user, P_us_overestimate[u in user_set, t in time_set],
        max(P_P_us_overestimate[u, t], P_N_us_overestimate[u, t])  # Max between the maximum values calculated previously
    )

    ## Variable definition

    # Energy stored in the battery
    @variable(model_user, 
        0 <= E_batt_us[u=user_set, b=asset_names(users_data[u], BATT), t in time_set] 
            <= field_component(users_data[u], b, "max_capacity"))
    # Converter dispatch positive when supplying to AC
    @variable(model_user, 0 <= 
        P_conv_P_us[u=user_set, c=asset_names(users_data[u], CONV), t in time_set] 
            <= field_component(users_data[u], c, "max_capacity"))
    # Converter dispatch positive when absorbing from AC
    @variable(model_user,
        0 <= P_conv_N_us[u=user_set, c=asset_names(users_data[u], CONV), t in time_set] 
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
    # Adjusted positive power for single adjustable appliance by user when supplying to public grid
    @variable(model_user,
        0 <= P_adj_P_us[u=user_set, e=asset_names(users_data[u], LOAD_ADJ), t=time_set]
            <= profile_component(users_data[u], e, "max_supply")[t])
    # Adjusted positive power for single adjustable appliance by user when absorbing from public grid
    @variable(model_user,
        0 <= P_adj_N_us[u=user_set, e=asset_names(users_data[u], LOAD_ADJ), t=time_set]
            <= profile_component(users_data[u], e, "max_withdrawal")[t])
    # Adjusted energy for single adjustable appliance by user
    @variable(model_user,
        profile_component(users_data[u], e, "min_energy")[t] <= 
            E_adj_us[u=user_set, e=asset_names(users_data[u], LOAD_ADJ), t=time_set]
            <= profile_component(users_data[u], e, "max_energy")[t])
    # Volume of the thermal storage, in m3 or lt
    @variable(model_user,
        0 <= V_tes_us[u=user_set, s=asset_names(users_data[u], TES), t in time_set] 
            <= field_component(users_data[u], s, "max_capacity"))
    # Energy stored in the thermal storage, in MWh: use (-) if DeltaT_C[t] is positive
    @variable(model_user,
        field_component(users_data[u], s, "max_capacity") / 1000 * field_component(users_data[u], s, "cp") * delta_t_tes_lb(users_data, u, s, t) <= 
            E_tes_us[u=user_set, s=asset_names(users_data[u], TES), t in time_set] 
            <= field_component(users_data[u], s, "max_capacity") / 1000 * field_component(users_data[u], s, "cp") * delta_t_tes_ub(users_data, u, s, t))
    # Electrical Power of the heat pump
    @variable(model_user,
        0 <= P_el_hp[u in user_set, h=asset_names(users_data[u], HP), t in time_set] 
            <= field_component(users_data[u], h, "max_capacity"))
    # Power of each boiler by each user, always positive     
    @variable(model_user, 
        0 <= P_boil_us[u=user_set, o=asset_names(users_data[u], BOIL), t in time_set] 
            <= field_component(users_data[u], o, "max_capacity"))               

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
    #     @expression(model_user, E_batt_tot_us[u=user_set, t=time_set],
    #     sum(E_batt_us[u, b, t] for b in asset_names(users_data[u], BATT))
    # )

    # Real efficiency of heat pump, heating mode, conditions 1
    @expression(model_user, eta_II_c1_heat[u=user_set, h=asset_names(users_data[u], HP), t=time_set],
        sum(
            field_component(users_data[u], h, "COP_c1") /
                ((field_component(users_data[u], h, "T_c1") + 273.15 + 5) /
                (field_component(users_data[u], h, "T_h") - (field_component(users_data[u], h, "T_c1") + 5))
                    )
                for l in asset_names(users_data[u], T_LOAD)
        )
    )

    # Real efficiency of heat pump, heating mode, conditions 2
    @expression(model_user, eta_II_c2_heat[u=user_set, h=asset_names(users_data[u], HP), t=time_set],
        sum(
            field_component(users_data[u], h, "COP_c2") /
                ((field_component(users_data[u], h, "T_c2") + 273.15 + 5) /
                (field_component(users_data[u], h, "T_h") - (field_component(users_data[u], h, "T_c2") + 5))
                    )
                for l in asset_names(users_data[u], T_LOAD)
        )
    )

    # Real efficiency of heat pump, heating mode, x external conditions , time depending
    @expression(model_user, eta_II_cx_heat[u=user_set, h=asset_names(users_data[u], HP), t=time_set],
        sum(
            eta_II_c1_heat[u, h, t] + (eta_II_c2_heat[u, h, t] - eta_II_c1_heat[u, h, t]) *
                ((profile_component(users_data[u], h, "T_ext")[t] - field_component(users_data[u], h, "T_c1")) /
                (field_component(users_data[u], h, "T_c2") - field_component(users_data[u], h, "T_c1"))
                    )
                for l in asset_names(users_data[u], T_LOAD)
        )
    )

    # COP(Text) = η_II(Text) ⋅ COP_Carnot(Text)
    # COP value depending on T_ext
    @expression(model_user, COP_T[u=user_set, h=asset_names(users_data[u], HP), t=time_set],
        sum(
            eta_II_cx_heat[u, h, t] * (profile_component(users_data[u], h, "T_ext")[t] + 273.15 + 5) /
                (field_component(users_data[u], h, "T_h") - (profile_component(users_data[u], h, "T_ext")[t] + 5))
            for l in asset_names(users_data[u], T_LOAD)
        )
    )

    # Real efficiency of heat pump, cooling mode, conditions 1
    @expression(model_user, eta_II_h1_cool[u=user_set, h=asset_names(users_data[u], HP), t=time_set],
        sum(
            field_component(users_data[u], h, "EER_h1") /
                ((field_component(users_data[u], h, "T_h1") + 273.15 + 5) /
                ((field_component(users_data[u], h, "T_h1") + 5) - field_component(users_data[u], h, "T_c"))
                    )
                for l in asset_names(users_data[u], T_LOAD)
        )
    )

    # Real efficiency of heat pump, cooling mode, conditions 2
    @expression(model_user, eta_II_h2_cool[u=user_set, h=asset_names(users_data[u], HP), t=time_set],
        sum(
            field_component(users_data[u], h, "EER_h2") /
                ((field_component(users_data[u], h, "T_h2") + 273.15 + 5) /
                ((field_component(users_data[u], h, "T_h2") + 5) - field_component(users_data[u], h, "T_c"))
                    )
                for l in asset_names(users_data[u], T_LOAD)
        )
    )

    # Real efficiency of heat pump, cooling mode, x external conditions , time depending
    @expression(model_user, eta_II_hx_cool[u=user_set, h=asset_names(users_data[u], HP), t=time_set],
        sum(
            eta_II_h1_cool[u, h, t] + (eta_II_h2_cool[u, h, t] - eta_II_h1_cool[u, h, t]) *
                ((profile_component(users_data[u], h, "T_ext")[t] - field_component(users_data[u], h, "T_h1")) /
                (field_component(users_data[u], h, "T_h2") - field_component(users_data[u], h, "T_h1"))
                    )
                for l in asset_names(users_data[u], T_LOAD)
        )
    )

    # EER(Text) = η_II(Text) ⋅ EER_Carnot(text)
    # EER value depending on T_ext
    @expression(model_user, EER_T[u=user_set, h=asset_names(users_data[u], HP), t=time_set],
        sum(
             eta_II_hx_cool[u, h, t] * (profile_component(users_data[u], h, "T_ext")[t] + 273.15 + 5) /
                ((profile_component(users_data[u], h, "T_ext")[t] + 5) - field_component(users_data[u], h, "T_c"))
            for l in asset_names(users_data[u], T_LOAD)
        )
    )

    # Thermal power of heat pump in heating/cooling mode by each user
    @expression(model_user, P_hp_T[u in user_set, h in asset_names(users_data[u], HP), t in time_set],
        sum(
            P_el_hp[u, h, t] * (
                profile_component(users_data[u], l, "mode")[t] < - 0.5 ? - EER_T[u, h, t] : COP_T[u, h, t]
            )
            for l in asset_names(users_data[u], T_LOAD)
        )
    )

    # Total Thermal power that could give heat pumps by each user 
    @expression(model_user, P_hp_T_tot[u=user_set, h=asset_names(users_data[u], HP), t=time_set],
        sum(P_hp_T[u, h, t] for h in asset_names(users_data[u], HP))
    )

    # Alternative Total electrical power for thermal use of heat pump in heating/cooling mode by each user
    @expression(model_user, P_el_hp_tot[u=user_set, h=asset_names(users_data[u], HP), t=time_set],
        sum(P_el_hp[u, h, t] for h in asset_names(users_data[u], HP))
    )
    
    # Total energy available in the thermal storage
    @expression(model_user, E_tes_tot_us[u=user_set, s=asset_names(users_data[u], TES), t=time_set],
        sum(E_tes_us[u, s, t] for s in asset_names(users_data[u], TES))
    )

    # Unheated zone Temperature of each tes and user
    @expression(model_user, T_u[u=user_set, s=asset_names(users_data[u], TES), t=time_set],
        (profile_component(users_data[u], s, "T_int")[t]
        - field_component(users_data[u], s, "b_tr_x")*(profile_component(users_data[u], s, "T_int")[t]
        - profile_component(users_data[u], s, "T_ext")[t]))
    )

    # Heat Energy losses in Thermal Storage by each tes and user [KWh]
    @expression(model_user, Tes_heat_loss[u=user_set, s=asset_names(users_data[u], TES), t=time_set],
        field_component(users_data[u], s, "k") * E_tes_us[u, s, pre(t, time_set)]*(profile_component(users_data[u], s, "T_ref")[t] - T_u[u, s, t])
    )

    # Mass flow rate of Fuel for use of boiler by each user and asset [m3/s]
    @expression(model_user, m_fuel[u=user_set, o=asset_names(users_data[u], BOIL), t=time_set],
        sum(
            (P_boil_us[u, o, t] / (field_component(users_data[u], o, "PCI") * field_component(users_data[u], o, "eta") / 3600))
            for l in asset_names(users_data[u], T_LOAD)
        )
    )

    ## Economic Expressions

    # Total adjustable load dispatch for each appliance: positive when charging the vehicle (absorbing from the grid)
    @expression(model_user, P_adj_us[u=user_set, e=asset_names(users_data[u], LOAD_ADJ), t=time_set],
        P_adj_N_us[u, e, t] - P_adj_P_us[u, e, t]
    )

    # Total energy load by user and time step for adjustable load: positive when charging the vehicle
    @expression(model_user, P_adj_tot_us[u=user_set, t=time_set],
        sum(P_adj_us[u,e,t] for e in asset_names(users_data[u], LOAD_ADJ))
    )
    
    # Fixed power for single fixed appliance by user
    @expression(model_user, P_fix_us[u=user_set, f=asset_names(users_data[u], LOAD), t=time_set],
        profile_component(users_data[u], f, "load")[t])

    # Total energy load by user and time step for fixed load
    @expression(model_user, P_fix_tot_us[u=user_set, t=time_set],
        sum(P_fix_us[u,e,t] for e in asset_names(users_data[u], LOAD))
    )

    # Total energy load by user and time step
    @expression(model_user, P_L_tot_us[u=user_set, t=time_set],
        P_adj_tot_us[u,t] + P_fix_tot_us[u,t]
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

    # Recovery cost by year and user
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
    
    #TODO add the adjustable load costs (they are double counted as in P_N_us and P_L_tot_us)
    # Revenues of each user in non-cooperative approach
    @expression(model_user, R_Energy_us[u in user_set, t in time_set],
        profile(ECModel.gen_data,"energy_weight")[t] * profile(ECModel.gen_data, "time_res")[t] * (market_profile_by_user(ECModel,u, "sell_price")[t]*P_P_us[u,t]
            - market_profile_by_user(ECModel,u,"buy_price")[t] * P_N_us[u,t] 
            - market_profile_by_user(ECModel,u,"consumption_price")[t] * P_L_tot_us[u, t])
    )  # economic flow with the market

    # Energy revenues by user
    @expression(model_user, R_Energy_tot_us[u in user_set],
        sum(R_Energy_us[u, t] for t in time_set)  # sum of revenues by user
    )

    # # Economic balance of the aggregation with respect to the public market in every hour
    # @expression(model_user, R_Energy_agg_time[t in time_set],
    #     sum(R_Energy_us[u, t] for u in user_set)
    # )

    # Yearly revenue of the user
    @expression(model_user, yearly_rev[u=user_set],
        R_Energy_tot_us[u] - C_OEM_tot_us[u]
    )

    # Costs arising from the use of fuel-fired generators by users and asset for electricity production
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

    # Total costs arising from the use of fuel-fired generators by users and asset for electricity production
    @expression(model_user, C_gen_tot_us_asset[u in user_set, g=asset_names(users_data[u], THER)],
        sum(C_gen_us[u, g, t] for t in time_set) 
    )

    # Total costs arising from the use of fuel-fired generators by users
    @expression(model_user, C_gen_tot_us[u in user_set],
        sum(C_gen_tot_us_asset[u,g] for g  in asset_names(users_data[u], THER))
    )

    # Costs arising from the use of heat pumps by users and asset for thermal energy production
    @expression(model_user, C_hp_us[u in user_set, h = asset_names(users_data[u], HP), t in time_set],
        profile(ECModel.gen_data, "energy_weight")[t] * profile(ECModel.gen_data, "time_res")[t] *
        P_el_hp[u, h, t] * (market_profile_by_user(ECModel, u, "buy_price")[t] + market_profile_by_user(ECModel, u, "consumption_price")[t])
    )

    # Costs arising from the use of boilers by users and asset for thermal energy production
    @expression(model_user, C_boil_us[u in user_set, o=asset_names(users_data[u], BOIL), t in time_set],
        profile(ECModel.gen_data, "time_res")[t] *
        (m_fuel[u,o,t] * field_component(users_data[u], o,"fuel_price"))
    )
          
    # Costs arising from the thermal energy production by users and asset
    @expression(model_user, C_t_load_us[u in user_set, o=asset_names(users_data[u], BOIL), h=asset_names(users_data[u], HP), t in time_set],
        sum(
            C_boil_us[u, o, t] + C_hp_us[u, h, t]
            for l in asset_names(users_data[u], T_LOAD)
        )
    )

    # Total costs arising from the thermal energy production by users and asset
    @expression(model_user, C_t_load_tot_us_asset[u in user_set, o=asset_names(users_data[u], BOIL), h=asset_names(users_data[u], HP)],
        sum(C_t_load_us[u,o,h,t] for t in time_set)
    )

    # Total costs arising from the thermal energy production by users
    @expression(model_user, C_t_load_tot_us[u in user_set],
        sum(C_t_load_tot_us_asset[u,o,h] for o=asset_names(users_data[u], BOIL), h=asset_names(users_data[u], HP))
    )

    # CASH FLOW
    # Cash flow of each user
    @expression(model_user, Cash_flow_us[y in year_set_0, u in user_set],
        (y == 0) ? 0 - CAPEX_tot_us[u] : 
            (R_Energy_tot_us[u]
            - C_gen_tot_us[u]
            - C_t_load_tot_us[u]
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
        P_gen_us[u, g, t] - z_gen_us[u, g, t] * field_component(users_data[u], g, "nom_capacity") * field_component(users_data[u], g, "max_technical") <= 0
    )

    # Set the maximum level of the energy stored in the storage to be proportional to the capacity
    @constraint(model_user,
        con_us_max_tes[u in user_set, s=asset_names(users_data[u], TES), t in time_set],
        E_tes_us[u, s, t] <= x_us[u, s]
    )

    # Set the minimum level of the energy stored in the storage to be proportional to the capacity
    @constraint(model_user,
        con_us_min_tes[u in user_set, s=asset_names(users_data[u], TES), t in time_set],
        E_tes_us[u, s, t] + x_us[u, s] >= 0
    )

    # Set the maximun dispatch of the heat pump 
    @constraint(model_user,
        con_us_max_hp[u in user_set, h=asset_names(users_data[u], HP), t in time_set],
        P_el_hp[u, h, t] <= x_us[u, h]
    )

    # Set the maximun dispatch of the boiler
    @constraint(model_user,
        con_us_max_boil[u in user_set, o=asset_names(users_data[u], BOIL), t in time_set],
        P_boil_us[u, o, t] <= x_us[u, o]
    )

    # Set the thermal balance at the user system [kWh th]
    @constraint(model_user, 
        con_us_heat_balance[u in user_set, l in asset_names(users_data[u], T_LOAD), t in time_set],
        sum(GenericAffExpr{Float64,VariableRef}[
            #E_tes_us[u, s, t] - E_tes_us[u, s, pre(t, time_set)] + Tes_heat_loss[u, s, t] * profile(gen_data, "time_res")[t]
            E_tes_us[u, s, t] - E_tes_us[u, s, pre(t, time_set)] + Tes_heat_loss[u, s, t]
            for s in asset_names(users_data[u], TES) if s in field_component(users_data[u], l, "corr_asset")
        ]) # available tes energy
        + profile_component(users_data[u], l, "t_load")[t] * profile(gen_data, "time_res")[t] # thermal load
        == 
        sum(GenericAffExpr{Float64,VariableRef}[
            P_hp_T[u, h, t] * profile(gen_data, "time_res")[t] for h in asset_names(users_data[u], HP) if h in field_component(users_data[u], l, "corr_asset")
            ]) # hp energy supplied
        + sum(GenericAffExpr{Float64,VariableRef}[
            P_boil_us[u, o, t] * profile(gen_data, "time_res")[t] for o in asset_names(users_data[u], BOIL) if o in field_component(users_data[u], l, "corr_asset")
            ]) # boiler energy supplied
    )

    # Set the electrical balance at the user system [kW]
    @constraint(model_user,
        con_us_balance[u in user_set, t in time_set],
        P_N_us[u, t] - P_P_us[u, t]
        + sum(P_gen_us[u, g, t] for g in asset_names(users_data[u], THER))
        + sum(GenericAffExpr{Float64,VariableRef}[
            P_conv_P_us[u, c, t] - P_conv_N_us[u, c, t] for c in asset_names(users_data[u], CONV)])
        + P_ren_us[u, t]
        ==
        sum(P_L_tot_us[u, t])
    )

    # Set the balance at each battery system
    @constraint(model_user,
        con_us_bat_balance[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
        E_batt_us[u, b, t] - E_batt_us[u, b, pre(t, time_set)]  # Difference between the energy level in the battery. Note that in the case of the first time step, the last id is used
        + profile(gen_data, "time_res")[t] * P_conv_P_us[u, field_component(users_data[u], b, "corr_asset"), t]/(
            sqrt(field_component(users_data[u], b, "eta"))*field_component(users_data[u], field_component(users_data[u], b, "corr_asset"), "eta"))  # Contribution of the converter when supplying power to AC
        - profile(gen_data, "time_res")[t] * P_conv_N_us[u, field_component(users_data[u], b, "corr_asset"), t]*(
            sqrt(field_component(users_data[u], b, "eta"))*field_component(users_data[u], field_component(users_data[u], b, "corr_asset"), "eta"))  # Contribution of the converter when absorbing power from AC
        == 0
    )

    # Total energy balance for adjustable load
    @constraint(model_user,
        E_adj_us_balance[u=user_set, e in asset_names(users_data[u], LOAD_ADJ), t=time_set],
        E_adj_us[u, e, t] == 
            E_adj_us[u, e, pre(t, time_set)] 
            - profile(gen_data, "time_res")[t] * P_adj_P_us[u, e, t] / field_component(users_data[u], e, "eta_P")
            + profile(gen_data, "time_res")[t] * P_adj_N_us[u, e, t] * field_component(users_data[u], e, "eta_N")
            + profile_component(users_data[u], e, "energy_exchange")[t]
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

    data_load = Float64[sum(ECModel.results[:P_L_tot_us][u, :] .* time_res .* energy_weight) for u in user_set]

    # sum of the electrical load power by user and EC
    demand_us_EC = JuMP.Containers.DenseAxisArray(
        [sum(data_load); data_load],
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
    
    # total thermal generator production by user only
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
        Float64[sum(
            time_res .* energy_weight .* max.(
                0.0, 
                max.(ECModel.results[:P_L_tot_us][u, :].data, 0.0)
                + min.(_P_us[u, :], 0.0)
            )
            ) for u in user_set
        ],
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

"""
    calculate_th_demand(ECModel::AbstractEC)

Function to calculate the thermal demand by user

## Arguments

* `ECModel`: EC model object

## Returns

It returns the thermal demand by user /and the whole EC/ as a DenseAxisArray
"""
function calculate_th_demand(ECModel::AbstractEC)
    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)

    # users set
    users_data = ECModel.users_data

    # time step resolution
    time_res = profile(ECModel.gen_data, "time_res")
    energy_weight = profile(ECModel.gen_data,"energy_weight")

    data_t_load = Float64[sum(sum(
        profile_component(users_data[u], l, "t_load") .* time_res .* energy_weight)
        for l in asset_names(users_data[u], T_LOAD)
    ) for u in user_set]

    # sum of the electrical load power by user and EC
    th_demand_us_EC = JuMP.Containers.DenseAxisArray(
    [sum(data_t_load); data_t_load],
    user_set_EC
    )

    return th_demand_us_EC
end


"""
    calculate_th_production(ECModel::AbstractEC)

Function to calculate the thermal energy production by user

## Arguments

* `ECModel`: EC model object

## Returns

It returns the thermal production by user /and the whole EC/ as a DenseAxisArray
"""
function calculate_th_production(ECModel::AbstractEC)

    # get user set
    user_set = ECModel.user_set

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

    _P_hp = ECModel.results[:P_hp_T]
    _P_boil = ECModel.results[:P_boil_us]

    # TODO: check if correct way is the first one or the second one
    # total heat pump production by user only
    _tot_P_hp_us = JuMP.Containers.DenseAxisArray(
        Float64[!has_asset(users_data[u], HP) ? 0.0 :
            sum(time_res[t] * energy_weight[t] * get(_P_hp[u, h, t], 0.0)
                for h in asset_names(users_data[u], HP) for t in time_set)
        for u in user_set],
        user_set
    )

    # total boiler production by user only
    _tot_P_boil_us = JuMP.Containers.DenseAxisArray(
        Float64[!has_asset(users_data[u], BOIL) ? 0.0 :
            sum(time_res[t] * energy_weight[t] * get(_P_boil[u, o, t], 0.0)
                for o in asset_names(users_data[u], BOIL) for t in time_set)
        for u in user_set],
        user_set
    )

    # total heat pump production by the whole EC
    data_production_hp = Float64[
        !has_asset(users_data[u], HP) ? 0.0 :
            sum(time_res[t] * energy_weight[t] * get(_P_hp[u, h, t], 0.0)
                for h in asset_names(users_data[u], HP) for t in time_set)
        for u in user_set
    ]

    # total boiler production by the whole EC
    data_production_boil = Float64[
        !has_asset(users_data[u], BOIL) ? 0.0 :
            sum(time_res[t] * energy_weight[t] * get(_P_boil[u, o, t], 0.0)
                for o in asset_names(users_data[u], BOIL) for t in time_set)
        for u in user_set
    ]

    data_th_production = data_production_boil + data_production_hp

    # sum of thermal production power by user and EC
    th_production_us_EC = JuMP.Containers.DenseAxisArray(
        vcat(sum(data_th_production), data_th_production),
        user_set
    )

    return th_production_us_EC
end


"""
    calculate_tes_losses(ECModel::AbstractEC)

Function to calculate the thermal energy losses by thermal storage by user

## Arguments

* `ECModel`: EC model object

## Returns

It returns the thermal energy losses by user /and the whole EC/ as a DenseAxisArray
"""
function calculate_tes_losses(ECModel::AbstractEC)

    # get user set
    user_set = ECModel.user_set

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

    _Tes_heat_loss = ECModel.results[:Tes_heat_loss]

    # total thermal energy losses by the whole EC
    data_heat_losses = Float64[
        !has_asset(users_data[u], TES) ? 0.0 : sum(time_res[t] * energy_weight[t] * _Tes_heat_loss[u, s, t]
            for s in asset_names(users_data[u], TES) for t in time_set)
        for u in user_set
    ]

    data_tes_losses = data_heat_losses

    # sum of thermal energy storage losses by user and EC
    th_tes_losses_us_EC = JuMP.Containers.DenseAxisArray(
        vcat(sum(data_tes_losses), data_tes_losses), 
        user_set 
    )

    return th_tes_losses_us_EC
end

"""
    calculate_COP_T(ECModel::AbstractEC)

Function to calculate the characteristic values for a heat pump, in heating mode, by user

## Arguments

* `ECModel`: EC model object

## Returns

It returns the characteristic values for a heat pump, in heating mode, by user /and the whole EC/ as a DenseAxisArray
"""

function calculate_COP_T(ECModel::AbstractEC)

    user_set = ECModel.user_set
    users_data = ECModel.users_data

    gen_data = ECModel.gen_data
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    time_set = init_step:final_step

    # Complete list of all heat pump assets
    hp_assets = unique(vcat([asset_names(users_data[u], HP) for u in user_set]...))

    # Helper function
    function safe_value(expr, u, h, t)
        if has_asset(users_data[u], HP) && h in asset_names(users_data[u], HP)
            return value(expr[u, h, t])
        else
            return 0.0
        end
    end

    # Construction of the final result as a DenseAxisArray
    _T_cond_heat = JuMP.Containers.DenseAxisArray(
        [safe_value(ECModel.model[:T_cond_heat], u, h, t)
         for u in user_set, h in hp_assets, t in time_set],
        (user_set, hp_assets, time_set)
    )

    _T_evap_heat = JuMP.Containers.DenseAxisArray(
        [safe_value(ECModel.model[:T_evap_heat], u, h, t)
         for u in user_set, h in hp_assets, t in time_set],
        (user_set, hp_assets, time_set)
    )

    _COP_Carnot = JuMP.Containers.DenseAxisArray(
        [safe_value(ECModel.model[:COP_Carnot], u, h, t)
         for u in user_set, h in hp_assets, t in time_set],
        (user_set, hp_assets, time_set)
    )

    _eta_II_Id_heat = JuMP.Containers.DenseAxisArray(
        [safe_value(ECModel.model[:eta_II_Id_heat], u, h, t)
         for u in user_set, h in hp_assets, t in time_set],
        (user_set, hp_assets, time_set)
    )

    _eta_II_Re_heat = JuMP.Containers.DenseAxisArray(
        [safe_value(ECModel.model[:eta_II_Re_heat], u, h, t)
         for u in user_set, h in hp_assets, t in time_set],
        (user_set, hp_assets, time_set)
    )

    _COP_T = JuMP.Containers.DenseAxisArray(
        [safe_value(ECModel.model[:COP_T], u, h, t)
         for u in user_set, h in hp_assets, t in time_set],
        (user_set, hp_assets, time_set)
    )

    # Return the results as a tuple
    return (
        T_cond_heat = _T_cond_heat,
        T_evap_heat = _T_evap_heat,
        COP_Carnot = _COP_Carnot,
        eta_II_Id_heat = _eta_II_Id_heat,
        eta_II_Re_heat = _eta_II_Re_heat,
        COP_T = _COP_T,
    )

end

"""
    calculate_th_consumption(ECModel::AbstractEC)

Function to calculate the economic thermal energy consumption by user

## Arguments

* `ECModel`: EC model object

## Returns

It returns the thermal economic consumption by user /and the whole EC/ as a DenseAxisArray
"""
function calculate_th_consumption(ECModel::AbstractEC)

    # get user set
    user_set = ECModel.user_set

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


    _C_hp_us = ECModel.results[:C_hp_us]
    _C_boil_us = ECModel.results[:C_boil_us]


    # total heat pump consumption by user only
    _tot_C_hp_us = JuMP.Containers.DenseAxisArray(
        Float64[ !has_asset(users_data[u], HP) ? 0.0 : sum(_C_hp_us[u, h, t]
                for h in asset_names(users_data[u], HP) for t in time_set
            ) for u in user_set],
        user_set
    )

    # total boiler consumption by user only
    _tot_C_boil_us = JuMP.Containers.DenseAxisArray(
        Float64[!has_asset(users_data[u], BOIL) ? 0.0 : sum(_C_boil_us[u, o, t]
                for o in asset_names(users_data[u], BOIL) for t in time_set
            ) for u in user_set],
        user_set
    )

    data_th_consumption = _tot_C_hp_us + _tot_C_boil_us

    # sum of thermal consumption power by user and EC
    th_consumption_us_EC = JuMP.Containers.DenseAxisArray(
        vcat(sum(data_th_consumption), data_th_consumption),
        user_set
    )

    # Return the results as a tuple
    return (
        C_hp_us = _C_hp_us,
        C_boil_us = _C_boil_us,
    )

    # Return the total thermal consumption by user and EC
    return th_consumption_us_EC
end