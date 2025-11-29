"""
    build_specific_model!(ECModel::AbstractEC, optimizer)
Creates the cooperative version of the model with the possibility of fixing the number of installed resources and the declared energy dispatch
# Arguments
'''
data: structure of data

'''
"""

function build_specific_model!(::AbstractGroupCO, ECModel::AbstractEC,optimizer;
    control_first_risimulation=false,
    x_fixed=Dict{Tuple{String, String}, Float64}(),
    control_MC=false,
    P_dec_P_fixed=JuMP.Containers.DenseAxisArray([],[]),
    P_dec_N_fixed=JuMP.Containers.DenseAxisArray([],[]))

    #is_optimized(ECModel_NC) # control for the NCmodel to be optimized
    
    TOL_BOUNDS = 1.05

    # get main parameters
    gen_data = ECModel.gen_data
    users_data = ECModel.users_data
    market_data = ECModel.market_data
    n_scen_s = ECModel.n_scen_s
    n_scen_eps = ECModel.n_scen_eps
    n_scen = n_scen_s * n_scen_eps

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
    scen_s_set = 1:n_scen_s

    # Set definition when optional value is not included
    user_set = ECModel.user_set

    sigma = 1.0

    # get NC data

    #s = "NPV_us" # variable name in NC model for users profits
    #NPV_NC = get_scenario_data_model(ECModelNC,s)
    #NPV_NC_user_set = Array{Any}(undef,n_scen)
    #SW_NC = Array{Float64}(undef,n_scen)
    #for scen = 1:n_scen
    #    NPV_NC_user_set[scen] = JuMP.Containers.DenseAxisArray([NPV_NC[scen].data[i] for i = 1:length(user_set)],user_set)
    #    SW_NC[scen] = sum(NPV_NC[scen])
    #end

    ## Model definition

    # Definition of JuMP model
    model = ECModel.model

    @first_stage model = begin
        @decision(model, 0 <= x_us[u=user_set, a=device_names(users_data[u])] <= field_component(users_data[u], a, "max_capacity")/field_component(users_data[u], a, "nom_capacity"), Int)  # Number of base plants installed by each user
        @decision(model, 0 <= P_agg_dec_P[scen_s_set, time_set]) # Supposed dispatch of each user, positive when supplying to public grid
        @decision(model, 0 <= P_agg_dec_N[scen_s_set, time_set]) # Supposed dispatch of each user, positive when absorbing from public grid

        ## Expressions
        ## Some of the expressions are annotated as decisions due to limit of StochasticPrograms

        # CAPEX by user and asset
        @expression(model, CAPEX_us[u in user_set, a in device_names(users_data[u])],
             x_us[u,a]*field_component(users_data[u], a, "CAPEX_lin")*field_component(users_data[u], a, "nom_capacity") 
        )

        @decision(model, CAPEX_tot_us[u in user_set])  # CAPEX by user

        @constraint(model, con_CAPEX_tot_us[u in user_set],
            CAPEX_tot_us[u] == sum(DecisionAffExpr{Float64}[CAPEX_us[u, a] for a in device_names(users_data[u])]) # sum of CAPEX by asset for the same user
        )

        @expression(model, C_OEM_us[u in user_set, a in asset_names_ex(users_data[u],[THER,LOAD])],
            x_us[u,a]*field_component(users_data[u], a, "OEM_lin")*field_component(users_data[u], a, "nom_capacity")  # Capacity of the asset times specific operating costs
        )  # Maintenance cost by asset exluding thermal generation

        # Maintenance cost by asset
        @decision(model, C_OEM_tot_us[u in user_set])

        @constraint(model, con_OEM_tot_us[u in user_set],
            C_OEM_tot_us[u] == sum(DecisionAffExpr{Float64}[C_OEM_us[u, a] for a in asset_names_ex(users_data[u],[THER,LOAD])]) # sum of C_OEM by asset for the same user
        )

        # Replacement cost by year, user and asset
        @expression(model, C_REP_us[y in year_set, u in user_set, a in device_names(users_data[u])],
            (mod(y, field_component(users_data[u], a, "lifetime_y")) == 0 && y != project_lifetime) ? CAPEX_us[u, a] 
                : 0.0
        )

        # Replacement cost by year and user
        @decision(model, C_REP_tot_us[y in year_set, u in user_set])

        @constraint(model, con_C_REP_tot_us[y in year_set, u in user_set],
            C_REP_tot_us[y,u] == sum(DecisionAffExpr{Float64}[C_REP_us[y, u, a] for a in device_names(users_data[u])])
        )

        # Recovery cost by year, user and asset: null except for the last year
        @expression(model, C_RV_us[y in year_set, u in user_set, a in device_names(users_data[u])],
            (y == project_lifetime && mod(y, field_component(users_data[u], a, "lifetime_y")) != 0) ? CAPEX_us[u, a] *
                ( field_component(users_data[u], a, "lifetime_y") - mod(y-1, field_component(users_data[u], a, "lifetime_y")) - 1.0 )
                / field_component(users_data[u], a, "lifetime_y")  
                : 0.0
        )

        # Replacement cost by year and user
        @decision(model, R_RV_tot_us[y in year_set, u in user_set])

        @constraint(model, con_R_RV_tot_us[y in year_set, u in user_set],
            R_RV_tot_us[y,u] == sum(DecisionAffExpr{Float64}[C_RV_us[y, u, a] for a in device_names(users_data[u])])
        )

        if control_first_risimulation == true # if we are in the risimulation of scenarios s, we have to fix the number of installed plants
            #@constraint(model, con_fixed_x_us[u=user_set, a=device_names(users_data[u])],
            #    x_us[u,a] == x_fixed[u,a])

            for u in user_set
                for a in device_names(users_data[u])
                    fix( x_us[u,a] , x_fixed[u,a] )
                end
            end
        end

        if control_MC == true # if we are in the risimulation of scenarios eps, we have to fix the declared dispatch of the user
            #@constraint(model, con_fixed_P_dec_P[s=scen_s_set, t=time_set],
            #    P_agg_dec_P[s,t] == P_dec_P_fixed[s,t])

            #@constraint(model, con_fixed_P_dec_N[s=scen_s_set, t=time_set],
            #    P_agg_dec_N[s,t] == P_dec_N_fixed[s,t])

            
            for s in scen_s_set
                for t in time_set
                    fix( P_agg_dec_P[s,t] , P_dec_P_fixed[s,t] )
                    fix( P_agg_dec_N[s,t] , P_dec_N_fixed[s,t] )
                end
            end
            
        end

        @objective(model, Max, 0 * sum(sum(x_us[u,a] for a in device_names(users_data[u])) for u in user_set)) # no objective value in first stage
    end
    @second_stage model = begin

        @known(model, x_us, P_agg_dec_P, P_agg_dec_N, CAPEX_tot_us, C_OEM_tot_us, C_REP_tot_us, R_RV_tot_us)
        #Introduction of the uncertainties, in this moment considered on the load demand and renewable production
		@uncertain scen_s scen_eps peak_tariff buy_price consumption_price sell_price penalty_price Load Ren from Scenario_Load_Renewable

        # Expression used to identify the actual scenario in a sequential way
			@expression(model, Scenario,
            scen_eps+(scen_s-1)*n_scen_eps
        )

        # Overestimation of the power exchanged by each POD when selling to the external market by each user
        @expression(model, P_P_us_overestimate[u in user_set, t in time_set],
            max(0,
                sum(Float64[field_component(users_data[u], c, "max_capacity") 
                    for c in asset_names(users_data[u], CONV)]) # Maximum capacity of the converters
                + sum(Float64[field_component(users_data[u], r, "max_capacity")*Ren[u][r][t] 
                    for r = asset_names(users_data[u], REN)]) # Maximum dispatch of renewable assets
                + sum(Float64[field_component(users_data[u], g, "max_capacity")*field_component(users_data[u], g, "max_technical")
                    for g = asset_names(users_data[u], THER)]) #Maximum dispatch of the fuel-fired generators
                - Load[u][t]  # Minimum demand
            ) * TOL_BOUNDS
        )

        # Overestimation of the power exchanged by each POD when buying from the external market bu each user
        @expression(model, P_N_us_overestimate[u in user_set, t in time_set],
            max(0,
                Load[u][t]
                + sum(Float64[field_component(users_data[u], c, "max_capacity") 
                    for c in asset_names(users_data[u], CONV)])  # Maximum capacity of the converters
            ) * TOL_BOUNDS
        )

        # Overestimation of the power exchanged by each POD, be it when buying or selling by each user
        @expression(model, P_us_overestimate[u in user_set, t in time_set],
            max(P_P_us_overestimate[u, t], P_N_us_overestimate[u, t])  # Max between the maximum values calculated previously
        )

            # Overestimation of the power exchanged by each POD when selling to the external market
        @expression(model, P_P_agg_overestimate[t=time_set],
            sum(P_P_us_overestimate[u, t] for u in user_set)
        )

        # Overestimation of the power exchanged by each POD when selling to the external market
        @expression(model, P_N_agg_overestimate[t=time_set],
            sum(P_N_us_overestimate[u, t] for u in user_set)
        )


        ## Variable definition
        
        # Energy stored in the battery
        @recourse(model, 
            0 <= E_batt_us[u=user_set, b=asset_names(users_data[u], BATT), t=time_set] 
                <= field_component(users_data[u], b, "max_capacity"))
        # Converter dispatch positive when supplying to AC
        @recourse(model, 0 <= 
            P_conv_P_us[u=user_set, c=asset_names(users_data[u], CONV), time_set] 
                <= field_component(users_data[u], c, "max_capacity"))
        # Converter dispatch positive when absorbing from AC
        @recourse(model,
            0 <= P_conv_N_us[u=user_set, c=asset_names(users_data[u], CONV), time_set] 
                <= field_component(users_data[u], c, "max_capacity"))
        # Dispath of renewable assets
        @recourse(model,
            0 <= P_ren_us[u=user_set, time_set]
                <= sum(Float64[field_component(users_data[u], r, "max_capacity") for r in asset_names(users_data[u], REN)]))
        #Dispatch of fuel-fired generator
        @recourse(model, 
            0 <= P_gen_us[u=user_set, g=asset_names(users_data[u], THER), time_set] 
                <= field_component(users_data[u], g, "max_capacity"))
        # Maximum dispatch of the user for every peak period
        @recourse(model,
            0 <= P_max_us[u=user_set, w in peak_set]
                <= maximum(P_us_overestimate[u, t] for t in time_set if peak_categories[t] == w))
        # Total dispatch of the user, positive when supplying to public grid
        @recourse(model,
            0 <= P_P_us[u=user_set, t in time_set]
                <= P_P_us_overestimate[u, t])
        # Total dispatch of the user, positive when absorbing from public grid
        @recourse(model,
            0 <= P_N_us[u=user_set, t in time_set]
                <= P_N_us_overestimate[u, t])
                # Number of generators plants used by a user in each time step t
        @recourse(model,
            0 <= z_gen_us[u=user_set, g=asset_names(users_data[u], THER), time_set]
                <= field_component(users_data[u], g, "max_capacity")/field_component(users_data[u], g, "nom_capacity"), Int)
		# Squilibrium of each user with respect to the energy supplied to the public grid
        @recourse(model, 0 <= P_sq_P_agg[t=time_set])
        # Squilibrium of each user with respect to the energy absorbed from the public grid
        @recourse(model, 0 <= P_sq_N_agg[t=time_set])
        # Virtual shared energy by user
        @recourse(model, 0 <= P_shared_agg[t=time_set])
        @recourse(model, P_agg[t=time_set])  # Power supplied to the public market (positive when supplied, negative otherwise)
        # annualized profits of the aggregator
        #@recourse(model, NPV_agg >= 0)

        ## Expressions

        # Peak tariff cost by user and peak period
        @expression(model, C_Peak_us[u in user_set, w in peak_set],
            profile(market_data, "peak_weight")[w] * peak_tariff[w] * P_max_us[u, w]  # Peak tariff times the maximum connection usage times the discretization of the period
        )

        # Total peak tariff cost by user
        @expression(model, C_Peak_tot_us[u in user_set],
            sum(C_Peak_us[u, w] for w in peak_set)  # Sum of peak costs
        ) 

        # Revenues of each user in non-cooperative approach
        @expression(model, R_Energy_us[u in user_set, t in time_set],
            profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] * (sell_price[t]*P_P_us[u,t]
                - buy_price[t] * P_N_us[u,t] 
                - consumption_price[t] * Load[u][t])  # economic flow with the market
        )

        # Energy revenues by user
        @expression(model, R_Energy_tot_us[u in user_set],
            sum(R_Energy_us[u, t] for t in time_set)  # sum of revenues by user
        )

        # Costs arising from the use of fuel-fired generators by users and asset
        @expression(model, C_gen_us[u in user_set, g=asset_names(users_data[u], THER)],
            sum(profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] *(
                z_gen_us[u,g,t] * field_component(users_data[u], g, "nom_capacity") 
                    * (field_component(users_data[u], g, "fuel_price") * field_component(users_data[u], g, "inter_map") + field_component(users_data[u], g, "OEM_lin"))
                    + field_component(users_data[u], g, "fuel_price") * field_component(users_data[u], g, "slope_map") * P_gen_us[u,g,t])
                for t in time_set)
		)

        # Total costs arising from the use of fuel-fired generators by users ### ERROR with StochasticProgram in istantiation (BUG)
        @expression(model, C_gen_tot_us[u in user_set],
            sum(DecisionAffExpr{Float64}[C_gen_us[u,g] for g  in asset_names(users_data[u], THER)])
        )

        @expression(model, C_sq_agg[t in time_set],
            profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] * 
                ( penalty_price[t] * P_sq_P_agg[t] + penalty_price[t] * P_sq_N_agg[t])
		)

        @expression(model, C_sq_tot_agg,
            sum(C_sq_agg[t] for t in time_set)
        )

        # Total reward awarded to the community at each time step
        @expression(model, R_Reward_agg[t in time_set],
            profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] *
                profile(market_data, "reward_price")[t] * P_shared_agg[t]
        )

        # Total reward awarded to the community by year
        @expression(model, R_Reward_agg_tot,
            sum(R_Reward_agg[t] for t in time_set)
        )

        # Total reward awarded to the community in NPV terms
        @expression(model, R_Reward_agg_NPV,
            R_Reward_agg_tot * sum(1 / ((1 + field(gen_data, "d_rate"))^y) for y in year_set)
        )

        # Total cost arising from energy squilibrium
        @expression(model, C_sq_tot_period,
            C_sq_tot_agg * sum(1 / ((1 + field(gen_data, "d_rate"))^y) for y in year_set)
        )

         # Cash flow ### ERROR with StochasticProgram in istantiation (BUG)
        #@expression(model, Cash_flow_agg[y in year_set_0],
        #    (y == 0) ? 0.0 : R_Reward_agg_tot
        #)

        # Yearly revenue of the user
        #@expression(model, yearly_rev[u=user_set],
        #    R_Energy_tot_us[u] - C_OEM_tot_us[u]
        #)

        # Cash flow
        @expression(model, Cash_flow_us[y in year_set_0, u in user_set],
            (y == 0) ? 0 - CAPEX_tot_us[u] : 
                (R_Energy_tot_us[u] 
                - C_Peak_tot_us[u] 
                - C_OEM_tot_us[u] 
                - C_gen_tot_us[u] 
                - C_REP_tot_us[y, u] 
                + R_RV_tot_us[y, u])
        )

        # Cash flow
        @expression(model, Cash_flow_tot[y in year_set_0],
            sum(Cash_flow_us[y, u] for u in user_set)
            - ((y == 0) ? 0.0 : C_sq_tot_agg)
            + ((y == 0) ? 0.0 : R_Reward_agg_tot)
        )

        # Annualized profits by the user; the sum of this function is the objective function
        @expression(model, NPV_us[u in user_set],
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

        # Social welfare of the entire aggregation
        @expression(model, SW,
            sum(NPV_us) - C_sq_tot_period + R_Reward_agg_NPV
        )

        # Social welfare of the users
        #@expression(model, SW_us,
        #    SW - NPV_agg
        #)

        # Power flow by user POD
        @expression(model, P_us[u = user_set, t = time_set],
            P_P_us[u, t] - P_N_us[u, t]
        )

        # Total converter dispatch: positive when supplying to AC
        #@expression(model, P_conv_us[u=user_set, c=asset_names(users_data[u], CONV), t=time_set],
        #    P_conv_P_us[u, c, t] - P_conv_N_us[u, c, t]
        #)

        ## Inequality constraints

        # Annual profits of the aggregator limited by a fraction of the surplus of the users
        #@constraint(model, AP_agg_limit_sigma,
        #    NPV_agg - 0.2 * (SW_us - SW_NC[Scenario]) <= 0
        #)

        # Set that the hourly dispatch cannot go beyond the maximum dispatch of the corresponding peak power period
        @constraint(model, con_us_max_P_user[u = user_set, t = time_set],
            - P_max_us[u, profile(market_data, "peak_categories")[t]] + P_P_us[u, t] + P_N_us[u, t] <= 0
        )

        # Set the renewable energy dispatch to be no greater than the actual available energy
        @constraint(model, con_us_ren_dispatch[u in user_set, t in time_set],
            - sum(Ren[u][r][t] * x_us[u, r] * field_component(users_data[u], r, "nom_capacity") for r in asset_names(users_data[u], REN))
            + P_ren_us[u, t] <= 0
        )

        # Set the maximum hourly dispatch of converters not to exceed their capacity
        @constraint(model, con_us_converter_capacity[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
            - x_us[u, c] * field_component(users_data[u], c, "nom_capacity") + P_conv_P_us[u, c, t] + P_conv_N_us[u, c, t] <= 0
        )


        # Set the maximum hourly dispatch of converters not to exceed the C-rate of the battery in discharge
        @constraint(model, con_us_converter_capacity_crate_dch[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
            P_conv_P_us[u, c, t] <= 
                x_us[u, field_component(users_data[u], c, "corr_asset")] * field_component(users_data[u], field_component(users_data[u], c, "corr_asset"), "nom_capacity")
                * field_component(users_data[u], field_component(users_data[u], c, "corr_asset"), "max_C_dch")
        )


        # Set the maximum hourly dispatch of converters not to exceed the C-rate of the battery in charge
        @constraint(model, con_us_converter_capacity_crate_ch[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
            P_conv_N_us[u, c, t] <= 
                x_us[u, field_component(users_data[u], c, "corr_asset")] * field_component(users_data[u], field_component(users_data[u], c, "corr_asset"), "nom_capacity")
                * field_component(users_data[u], field_component(users_data[u], c, "corr_asset"), "max_C_ch")
        )


        # Set the minimum level of the energy stored in the battery to be proportional to the capacity
        @constraint(model, con_us_min_E_batt[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
            x_us[u, b] * field_component(users_data[u], b, "nom_capacity") * field_component(users_data[u], b, "min_SOC") - E_batt_us[u, b, t] <= 0
        )

        # Set the maximum level of the energy stored in the battery to be proportional to the capacity
        @constraint(model, con_us_max_E_batt[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
            - x_us[u, b] * field_component(users_data[u], b, "nom_capacity") * field_component(users_data[u], b, "max_SOC") + E_batt_us[u, b, t] <= 0
        )
        
        # Set that the number of working generator plants cannot exceed the number of generator plants installed
        @constraint(model, con_us_gen_on[u in user_set, g=asset_names(users_data[u], THER), t in time_set],
			z_gen_us[u, g, t] <= x_us[u, g]
		)

        # Set the minimum dispatch of the thermal generator
        @constraint(model, con_us_gen_min_disp[u in user_set, g=asset_names(users_data[u], THER), t in time_set],
    		P_gen_us[u, g, t] - z_gen_us[u, g, t] * field_component(users_data[u], g, "nom_capacity") * field_component(users_data[u], g, "min_technical") >= 0
    	)

        # Set the maximum dispatch of the thermal generator
        @constraint(model, con_us_gen_max_disp[u in user_set, g=asset_names(users_data[u], THER), t in time_set],
		    P_gen_us[u, g, t] - z_gen_us[u, g, t] * field_component(users_data[u], g, "nom_capacity") * field_component(users_data[u], g, "max_technical") <= 0)

        ## Equality constraints

        # Set the electrical balance at the user system
        @constraint(model, con_us_balance[u in user_set, t in time_set],
            P_P_us[u, t] - P_N_us[u, t]
            - sum(P_gen_us[u, g, t] for g in asset_names(users_data[u], THER))
            + sum(P_conv_N_us[u, c, t] - P_conv_P_us[u, c, t] for c in asset_names(users_data[u], CONV))
            - P_ren_us[u, t]
            == - Load[u][t]
        )

        # Set the balance at each battery system
        @constraint(model,
            con_us_bat_balance[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
            #E_batt_us[u, b, t] - E_batt_us[u, b, if (t>1) t-1 else final_step end]  # Difference between the energy level in the battery. Note that in the case of the first time step, the last id is used
            E_batt_us[u, b, t] - E_batt_us[u, b, pre(t, time_set)]  # Difference between the energy level in the battery. Note that in the case of the first time step, the last id is used
            + profile(market_data, "time_res")[t] * P_conv_P_us[u, field_component(users_data[u], b, "corr_asset"), t]/(
                sqrt(field_component(users_data[u], b, "eta"))*field_component(users_data[u], field_component(users_data[u], b, "corr_asset"), "eta"))  # Contribution of the converter when supplying power to AC
            - profile(market_data, "time_res")[t] * P_conv_N_us[u, field_component(users_data[u], b, "corr_asset"), t]*(
                sqrt(field_component(users_data[u], b, "eta"))*field_component(users_data[u], field_component(users_data[u], b, "corr_asset"), "eta"))  # Contribution of the converter when absorbing power from AC
            == 0
        )

        @constraint(model, con_agg_sq_balance[t in time_set],
            - P_agg[t] ==
                P_sq_N_agg[t] - P_sq_P_agg[t] 
                + P_agg_dec_N[scen_s,t] - P_agg_dec_P[scen_s,t]
		)
        
        # Set the commercial energy flows within the aggregate to have sum equal to zero
        @constraint(model, con_micro_balance[t in time_set],
            P_agg[t] == sum(P_us[u, t] for u in user_set)
        )

        # Max shared power: excess energy
        @constraint(model, con_max_shared_power_P[t in time_set],
            P_shared_agg[t] <= sum(P_P_us[u, t] for u in user_set)
        )

        # Max shared power: demand
        @constraint(model, con_max_shared_power_N[t in time_set],
            P_shared_agg[t] <= sum(P_N_us[u, t] for u in user_set)
        )

        @objective(model, Max, SW)
    
    end
    
    set_optimizer(model,optimizer)

    ECModel.deterministic_model = DEP(model)

    return ECModel
end

