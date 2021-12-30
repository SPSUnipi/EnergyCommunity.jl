"""
    build_model_user(data)

Creates the model of the users alone

# Arguments
'''
data: structure of data
'''
"""
function build_model_NC(data, optimizer=optimizer_with_attributes(Gurobi.Optimizer))

    # get main parameters
    gen_data, users_data, market_data = explode_data(data)
    n_users = length(users_data)
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    project_lifetime = field(gen_data, "project_lifetime")
    peak_categories = profile(market_data, "peak_categories")

    # Set definitions

    user_set = user_names(gen_data, users_data)
    year_set = 1:project_lifetime
    time_set = init_step:final_step
    peak_set = unique(peak_categories)


    ## Model definition

    # Definition of JuMP model
    model_user = Model(optimizer)

    # Overestimation of the power exchanged by each POD when selling to the external market
    @expression(model_user, P_tot_P_overestimate[u in user_set],
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

    # Overestimation of the power exchanged by each POD when buying from the external market
    @expression(model_user, P_tot_N_overestimate[u in user_set],
        max(0,
            maximum(
                sum(Float64[profile_component(users_data[u], l, "load")[t] for l in asset_names(users_data[u], LOAD)])
                for t in time_set)  # Maximum demand
            + sum(Float64[field_component(users_data[u], c, "max_capacity") 
                for c in asset_names(users_data[u], CONV)])  # Maximum capacity of the converters
        )
    )

    # Overestimation of the power exchanged by each POD, be it when buying or selling
    @expression(model_user, P_tot_us_overestimate[u in user_set],
        max(P_tot_P_overestimate[u], P_tot_N_overestimate[u])  # Max between the maximum values calculated previously
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
            <= P_tot_us_overestimate[u])
    # Total dispatch of the user, positive when supplying to public grid
    @variable(model_user,
        0 <= P_tot_P_us[u=user_set, time_set]
            <= P_tot_P_overestimate[u])
    # Total dispatch of the user, positive when absorbing from public grid
    @variable(model_user,
        0 <= P_tot_N_us[u=user_set, time_set]
            <= P_tot_N_overestimate[u])
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
        profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] * (profile(market_data, "sell_price")[t]*P_tot_P_us[u,t]
            - profile(market_data, "buy_price")[t] * P_tot_N_us[u,t] 
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
    @expression(model_user, Cash_flow_us[y in append!([0], year_set), u in user_set],
        (y == 0) ? 0 - CAPEX_tot_us[u] : R_Energy_tot_us[u] - C_Peak_tot_us[u] - C_OEM_tot_us[u] - C_REP_tot_us[y, u] + R_RV_tot_us[y, u]
    )

    # Cash flow
    @expression(model_user, Cash_flow_tot[y in append!([0], year_set)],
        sum(Cash_flow_us[y, u] for u in user_set)
    )

    # Annualized profits by the user; the sum of this function is the objective function
    @expression(model_user, NPV_user[u in user_set],
        sum(
            (R_Energy_tot_us[u] # Costs related to the energy trading with the market
            - C_Peak_tot_us[u]  # Peak cost
            - C_OEM_tot_us[u]  # Maintenance cost
            - C_REP_tot_us[y, u]  # Replacement costs
            + R_RV_tot_us[y, u]  # Residual value
            ) / ((1 + field(gen_data, "d_rate"))^y)
            for y in year_set)
        - CAPEX_tot_us[u]  # Investment costs
    )  

    # Power flow by user POD
    @expression(model_user, P_tot_us[u = user_set, t = time_set],
        P_tot_P_us[u, t] - P_tot_N_us[u, t]
    )

    ## Inequality constraints

    # Set that the hourly dispatch cannot go beyond the maximum dispatch of the corresponding peak power period
    @constraint(model_user,
        con_us_max_P_user[u = user_set, t = time_set],
        - P_max_us[u, profile(market_data, "peak_categories")[t]] + P_tot_P_us[u, t] + P_tot_N_us[u, t] <= 0
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
        P_tot_P_us[u, t] - P_tot_N_us[u, t]
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


    ## Setting the objective

    # Setting the objective of maximizing the annual profits NPV_user
    @objective(model_user, Max, sum(NPV_user[u] for u in user_set))

    return model_user
end

"""
    output_results_NC(data, model_user, output_file, output_plot_user, user_set)

Function to plot the results of the user model
"""
function output_results_NC(data, model_user::Model,
    output_file, output_plot_user;
    user_set::Vector = Vector(), line_width=2.0)

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

    # reset the user_set if not specified
    if isempty(user_set)
        user_set = user_names(gen_data, users_data)
    end

    asset_set_unique = unique([name for u in user_set for name in asset_names(users_data[u])])

    ## Retrive results

    _x_us = value.(model_user[:x_us]) # Optimal size of the system
    _E_batt_us = value.(model_user[:E_batt_us])  # Energy stored in the battery
    _E_batt_tot_us = JuMP.Containers.DenseAxisArray([sum(Float64[_E_batt_us[u, b, t] for b in asset_names(users_data[u], BATT)]) for u in user_set, t in time_set], user_set, time_set)  # Total energy available in the batteries
    _P_conv_P_us = value.(model_user[:P_conv_P_us]) # Converter dispatch positive when supplying to AC
    _P_conv_P_tot_us = JuMP.Containers.DenseAxisArray([sum(Float64[_P_conv_P_us[u, c, t] for c in asset_names(users_data[u])  if asset_type(users_data[u], c) == CONV]) for u in user_set, t in time_set], user_set, time_set)  # Total converters dispatch when supplying to the grid
    _P_conv_N_us = value.(model_user[:P_conv_N_us])  # Converter dispatch positive when absorbing from AC
    _P_conv_N_tot_us = JuMP.Containers.DenseAxisArray([sum(Float64[_P_conv_N_us[u, c, t] for c in asset_names(users_data[u])  if asset_type(users_data[u], c) == CONV]) for u in user_set, t in time_set], user_set, time_set)  # Total converters dispatch when absorbing from the grid
    _P_conv_tot_us = JuMP.Containers.DenseAxisArray([_P_conv_P_tot_us[u, t] - _P_conv_N_tot_us[u, t] for u in user_set, t in time_set], user_set, time_set)  # Total converters dispatch
    _P_conv_us = JuMP.Containers.SparseAxisArray(Dict((u, c, t) => _P_conv_P_us[u, c, t] - _P_conv_N_us[u, c, t]  for u in user_set for c in asset_names(users_data[u])  if asset_type(users_data[u], c) == CONV for t in time_set))  # converter dispatch
    _P_ren_us = value.(model_user[:P_ren_us]) # Dispath of renewable assets
    _P_max_us = value.(model_user[:P_max_us])  # Maximum dispatch of the user for every peak period
    _P_tot_P_us = value.(model_user[:P_tot_P_us])  # Total dispatch of the user, positive when supplying to public grid
    _P_tot_N_us = value.(model_user[:P_tot_N_us])  # Total dispatch of the user, positive when absorbing from public grid
    _P_tot_us = value.(model_user[:P_tot_us])  # Total user dispatch

    _CAPEX_us = value.(model_user[:CAPEX_us])  # CAPEX by user and asset
    _CAPEX_tot_us = value.(model_user[:CAPEX_tot_us])  # Total CAPEX by user
    _C_OEM_us = value.(model_user[:C_OEM_us]) # Maintenance cost by user and asset
    _C_OEM_tot_us = value.(model_user[:C_OEM_tot_us]) # Total maintenance cost by asset
    _C_REP_us = value.(model_user[:C_REP_us])  # Replacement costs by user and asset
    _C_REP_tot_us = value.(model_user[:C_REP_tot_us])  # Total replacement costs by user
    _C_RV_us = value.(model_user[:C_RV_us])  # Residual value by user and asset
    _R_RV_tot_us = value.(model_user[:R_RV_tot_us])  # Residual value by user
    _yearly_rev = value.(model_user[:yearly_rev])  # yearly revenues by user
    _NPV_us = value.(model_user[:NPV_user])  # Annualized profits by the user
    _C_Peak_us = value.(model_user[:C_Peak_us])  # Peak tariff cost by user and peak period
    _C_Peak_tot_us = value.(model_user[:C_Peak_tot_us])  # Peak tariff cost by user
    _R_Energy_us = value.(model_user[:R_Energy_us])  # Energy revenues by user and time
    _R_Energy_tot_us = value.(model_user[:R_Energy_tot_us])  # Energy revenues by user

    # get corresponding maximum power of the aggregation
    _P_max_us_comb = JuMP.Containers.DenseAxisArray(
            [maximum(abs(sum(_P_tot_us[u, t] for u in user_set)) for t in time_set if peak_categories[t] == w)
                for w in peak_set]
        ,
        peak_set
    )
    
    design_users = DataFrames.DataFrame(
        vcat(
            [[u for u in user_set]],
            [[maximum(sum(Float64[profile_component(users_data[u], l, "load")[t]
                for l in asset_names(users_data[u]) if asset_type(users_data[u], l) == LOAD]) for t in time_set) for u in user_set]],
            [[sum(Float64[profile_component(users_data[u], l, "load")[t] * profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t]/1000
                for t in time_set for l in asset_names(users_data[u], LOAD)]) for u in user_set]],
            [[if (a in device_names(users_data[u])) _x_us[u, a] else missing end for u in user_set] for a in asset_set_unique]
        ),
        map(Symbol, vcat("User", "Peak demand [kW]", "Yearly Demand [MWh]", ["x_us_$a" for a in asset_set_unique]))
    )

    economics_users = DataFrames.DataFrame(
        vcat(
            [user_set],
            [[_NPV_us[u] for u in user_set]],
            [_CAPEX_tot_us[:].data],
            [_yearly_rev[:].data],
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
            map(Symbol, vcat("User_id", "NPV_user", "CAPEX_tot_us", "yearly_rev",
                "SDCF C_OEM_tot_us", "SDCF C_REP_tot_us", "SDCF R_RV_tot_us",
                "SDCF C_Peak_tot_us", "SDCF R_Energy_tot_us",
                ["CAPEX_us_$a" for a in asset_set_unique], ["C_OEM_us_$a" for a in asset_set_unique]))
    )

    peak_users = Dict(
        u=>DataFrames.DataFrame(
            vcat(
                [peak_set],
                [[_P_max_us[u, w] for w in peak_set]],
                [[_C_Peak_us[u, w] for w in peak_set]]
            ),
            map(Symbol, ["Peak_name", "P_max_us", "C_Peak_us"])
    ) for u in user_set)

    dispatch_users = Dict(
        u=>DataFrames.DataFrame(
            vcat(
                    [[t for t in time_set]],
                    [[sum(Float64[profile_component(users_data[u], l, "load")[t] for l in asset_names(users_data[u], LOAD)]) for t in time_set]],
                    [[_P_tot_us[u, t] for t in time_set]],
                    [[_P_tot_P_us[u, t] for t in time_set]],
                    [[_P_tot_N_us[u, t] for t in time_set]],
                    [[_P_ren_us[u, t] for t in time_set]],
                    [[_P_max_us[u, peak_categories[t]] for t in time_set]],
                    [[_P_conv_tot_us[u, t] for t in time_set]],
                    [[_P_conv_P_tot_us[u, t] for t in time_set]],
                    [[_P_conv_N_tot_us[u, t] for t in time_set]],
                    [[_E_batt_tot_us[u, t] for t in time_set]],
                    [[_P_conv_us[u, c, t] for t in time_set] for c in asset_names(users_data[u], CONV)],
                    [[_P_conv_P_us[u, c, t] for t in time_set] for c in asset_names(users_data[u], CONV)],
                    [[_P_conv_N_us[u, c, t] for t in time_set] for c in asset_names(users_data[u], CONV)],
                    [[_E_batt_us[u, b, t] for t in time_set] for b in asset_names(users_data[u], BATT)],
                    [[profile_component(users_data[u], r, "ren_pu")[t]*_x_us[u, r] for t in time_set] for r in asset_names(users_data[u], REN)]
                ),
            map(Symbol, vcat(
                    "time_step", "P_L_us", "P_tot_us", "P_tot_P_us", "P_tot_N_us", "P_ren_us", "P_max_us", "P_conv_us_tot", "P_conv_P_us_tot", "P_conv_N_us_tot", "E_batt_us_tot",
                    ["P_conv_us_$c" for c in asset_names(users_data[u], CONV)],
                    ["P_conv_P_us_$c" for c in asset_names(users_data[u], CONV)],
                    ["P_conv_N_us_$c" for c in asset_names(users_data[u], CONV)],
                    ["E_batt_us_$b" for b in asset_names(users_data[u], BATT)],
                    ["P_ren_us_$r" for r in asset_names(users_data[u], REN)]
                )
            )
        ) for u in user_set)

    # Write XLSX table
    XLSX.openxlsx(output_file, mode="w") do xf
        #Rename first empty sheet to design_users amd write the corresponding DataFrame
        xs = xf[1]
        XLSX.rename!(xs, "design_users")
        XLSX.writetable!(xs, collect(DataFrames.eachcol(design_users)), DataFrames.names(design_users))

        #Write DataFrame economics_users in a new sheed
        xs = XLSX.addsheet!(xf, "economics_users")
        XLSX.writetable!(xs, collect(DataFrames.eachcol(economics_users)), DataFrames.names(economics_users))

        for u = user_set

            #Write DataFrame peak_users related to user u in a new sheet
            xs = XLSX.addsheet!(xf, "peak_user$u")
            XLSX.writetable!(xs, collect(DataFrames.eachcol(peak_users[u])), DataFrames.names(peak_users[u]))

            #Write DataFrame dispatch_users related to user u in a new sheet
            xs = XLSX.addsheet!(xf, "dispatch_user$u")
            XLSX.writetable!(xs, collect(DataFrames.eachcol(dispatch_users[u])), DataFrames.names(dispatch_users[u]))
        end
    end

    ## Print general outputs
    printfmtln("\nRESULTS - AGGREGATOR")

    printf_code_user = string("{:<18s}: {: 7.2e}", join([", {: 7.2e}" for i in 1:length(user_set) if i > 1]))
    printf_code_description = string("{:<18s}: {:>9s}", join([", {:>9s}" for i in 1:length(user_set) if i > 1]))
    printf_code_energy_share = string("{:<18s}: ", join([if (a == asset_set_unique[1]) "{: 7.2e}" else ", {: 7.2e}" end for a in asset_set_unique]))

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

    printfmtln("\n\nEnergy flows")
    printfmtln(printf_code_description, "USER", [u for u in user_set]...)
    printfmtln(printf_code_user, "PtotPubP [MWh]",
        [sum(_P_tot_P_us[u, :]) for u in user_set]/1000...)
    printfmtln(printf_code_user, "PtotPubN [MWh]",
        [sum(_P_tot_N_us[u, :]) for u in user_set]/1000...)
    printfmtln(printf_code_user, "PconvP [MWh]",
        [sum(_P_conv_P_tot_us[u, t] for t in time_set) for u in user_set]/1000...)
    printfmtln(printf_code_user, "PconvN [MWh]",
        [sum(_P_conv_N_tot_us[u, t] for t in time_set) for u in user_set]/1000...)
    printfmtln(printf_code_user, "Pren [MWh]",
        [sum(_P_ren_us[u,:]) for u in user_set]/1000...)
    printfmtln(printf_code_user, "Load [MWh]",
        [sum(profile_component(users_data[u], l, "load")[t] for l in asset_names(users_data[u], LOAD) for t in time_set) for u in user_set]/1000...)

    ## Plots


    Plots.PlotlyBackend()
    pt = Array{Plots.Plot, 2}(undef, n_users, 3)
    lims_y_axis_dispatch = [(-30, 60),(-30, 60)]
    lims_y_axis_batteries = [(0, 120), (0, 120)]
    for (u_i, u_name) in enumerate(user_set)

        # Power dispatch plot
        pt[u_i, 1] = plot(time_set, [sum(Float64[profile_component(users_data[u_name], l, "load")[t] 
                                        for l in asset_names(users_data[u_name], LOAD)])
                                    for t in time_set],
                        label="Load", w=line_width, legend=:outerright)
        plot!(pt[u_i, 1], time_set, _P_tot_us[u_name, :].data, label="Grid", w=line_width)
        plot!(pt[u_i, 1], time_set, _P_conv_tot_us[u_name, :].data, label="Converters", w=line_width)
        plot!(pt[u_i, 1], time_set, _P_ren_us[u_name, :].data, label="Renewables", w=line_width)
        xaxis!("Time step [#]")
        yaxis!("Power [kW]")
        # ylims!(lims_y_axis_dispatch[u])

        # Battery status plot
        pt[u_i, 2] = plot(time_set, _E_batt_tot_us[u_name, :].data, label="Energy      ", w=line_width, legend=:outerright)
        xaxis!("Time step [#]")
        yaxis!("Energy [kWh]")
        # ylims!(lims_y_axis_batteries[u])

        pt[u_i,3] = plot(pt[u_i, 1], pt[u_i, 2], layout=(2,1))
        display(pt[u_i,3])

        png(pt[u_i,3], format(output_plot_user, u_name))
    end

    # plot_layout_x = Int(ceil(sqrt(n_users)))
    # plot_layout_y = Int(ceil(n_users/plot_layout_x))
    #
    # plot(pt..., layout=(plot_layout_x, plot_layout_y))
end
