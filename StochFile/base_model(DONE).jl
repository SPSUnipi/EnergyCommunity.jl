# accepted technologies
ACCEPTED_TECHS = ["load", "renewable", "battery", "converter", "thermal"]

"""
    build_base_model!(ECModel::AbstractEC, optimizer)
Creates the non cooperative version of the model with the possibility of fixing the number of installed resources and the declared energy dispatch
# Arguments
'''
data: structure of data
control_first_risimulation: boolean value, if true we have to fix the installed resource
x_fixed: value of the resource to be fixed
control_MC: boolean value, if true we have to fix the declared dispatch of the users
'''
"""
function build_base_model!(ECModel::AbstractEC, optimizer; 
    use_notations=false, 
    control_first_risimulation=false,
    x_fixed=Dict{Tuple{String, String}, Float64}(),
    control_MC=false,
    P_dec_P_fixed=JuMP.Containers.DenseAxisArray([],[]),
    P_dec_N_fixed=JuMP.Containers.DenseAxisArray([],[]))

    TOL_BOUNDS = 1.05

    # get main parameters
    gen_data = ECModel.gen_data
    users_data = ECModel.users_data
    market_data = ECModel.market_data
    n_scen_s = ECModel.n_scen_s
    n_scen_eps = ECModel.n_scen_eps

    n_users = length(users_data)
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    project_lifetime = field(gen_data, "project_lifetime")
    peak_categories = profile(market_data, "peak_categories")

    # Set definitions

    user_set = ECModel.user_set
    year_set = 1:project_lifetime
    year_set_0 = 0:project_lifetime
    time_set = 1:n_steps
    peak_set = unique(peak_categories)
    scen_s_set = 1:n_scen_s

    ## Model definition

    # Definition of JuMP model
    #ECModel.model = (use_notations ? direct_model(optimizer) : Model(optimizer))
    model_user = ECModel.model

    @first_stage model_user = begin
        @decision(model_user, 0 <= x_us[u=user_set, a=device_names(users_data[u])] <= field_component(users_data[u], a, "max_capacity")/field_component(users_data[u], a, "nom_capacity"), Int)  # Number of base plants installed by each user
        @decision(model_user, 0 <= P_us_dec_P[user_set, scen_s_set, time_set]) # Supposed dispatch of each user, positive when supplying to public grid
        @decision(model_user, 0 <= P_us_dec_N[user_set, scen_s_set, time_set]) # Supposed dispatch of each user, positive when absorbing from public grid

        ## Expressions
        ## Some of the expressions are annotated as decisions due to limit of StochasticPrograms

        # CAPEX by user and asset
        @expression(model_user, CAPEX_us[u in user_set, a in device_names(users_data[u])],
             x_us[u,a]*field_component(users_data[u], a, "CAPEX_lin")*field_component(users_data[u], a, "nom_capacity") 
        )

        @decision(model_user, CAPEX_tot_us[u in user_set])  # CAPEX by user

        @constraint(model_user, con_CAPEX_tot_us[u in user_set],
            CAPEX_tot_us[u] == sum(DecisionAffExpr{Float64}[CAPEX_us[u, a] for a in device_names(users_data[u])]) # sum of CAPEX by asset for the same user
        )

        @expression(model_user, C_OEM_us[u in user_set, a in asset_names_ex(users_data[u],[THER,LOAD])],
            x_us[u,a]*field_component(users_data[u], a, "OEM_lin")*field_component(users_data[u], a, "nom_capacity")  # Capacity of the asset times specific operating costs
        )  # Maintenance cost by asset exluding thermal generation

        # Maintenance cost by asset
        @decision(model_user, C_OEM_tot_us[u in user_set])

        @constraint(model_user, con_OEM_tot_us[u in user_set],
            C_OEM_tot_us[u] == sum(DecisionAffExpr{Float64}[C_OEM_us[u, a] for a in asset_names_ex(users_data[u],[THER,LOAD])]) # sum of C_OEM by asset for the same user
        )

        # Replacement cost by year, user and asset
        @expression(model_user, C_REP_us[y in year_set, u in user_set, a in device_names(users_data[u])],
            (mod(y, field_component(users_data[u], a, "lifetime_y")) == 0 && y != project_lifetime) ? CAPEX_us[u, a] 
                : 0.0
        )

        # Replacement cost by year and user
        @decision(model_user, C_REP_tot_us[y in year_set, u in user_set])

        @constraint(model_user, con_C_REP_tot_us[y in year_set, u in user_set],
            C_REP_tot_us[y,u] == sum(DecisionAffExpr{Float64}[C_REP_us[y, u, a] for a in device_names(users_data[u])])
        )

        # Recovery cost by year, user and asset: null except for the last year
        @expression(model_user, C_RV_us[y in year_set, u in user_set, a in device_names(users_data[u])],
            (y == project_lifetime && mod(y, field_component(users_data[u], a, "lifetime_y")) != 0) ? CAPEX_us[u, a] *
                (1.0 - mod(y, field_component(users_data[u], a, "lifetime_y"))/ field_component(users_data[u], a, "lifetime_y")) 
                : 0.0
        )

        # Replacement cost by year and user
        @decision(model_user, R_RV_tot_us[y in year_set, u in user_set])

        @constraint(model_user, con_R_RV_tot_us[y in year_set, u in user_set],
            R_RV_tot_us[y,u] == sum(DecisionAffExpr{Float64}[C_RV_us[y, u, a] for a in device_names(users_data[u])])
        )

        if control_first_risimulation == true # if we are in the risimulation of scenarios s, we have to fix the number of installed plants
            #@constraint(model_user, con_fixed_x_us[u=user_set, a=device_names(users_data[u])],
            #    x_us[u,a] == x_fixed[u,a])
            for u in user_set
                for a in device_names(users_data[u])
                    fix( x_us[u,a] , x_fixed[u,a] )
                end
            end
        end

        if control_MC == true # if we are in the risimulation of scenarios eps, we have to fix the declared dispatch of the user
            #@constraint(model_user, con_fixed_P_dec_P[u=user_set, s=scen_s_set, t=time_set],
            #    P_us_dec_P[u,s,t] == P_dec_P_fixed[u,s,t])

            #@constraint(model_user, con_fixed_P_dec_N[u=user_set, s=scen_s_set, t=time_set],
            #    P_us_dec_N[u,s,t] == P_dec_N_fixed[u,s,t])

            for u in user_set
                for s in scen_s_set
                    for t in time_set
                        fix( P_us_dec_P[u,s,t] , P_dec_P_fixed[u,s,t] )
                        fix( P_us_dec_N[u,s,t] , P_dec_N_fixed[u,s,t] )
                    end
                end
            end
        end

        @objective(model_user, Max, 0 * sum(sum(x_us[u,a] for a in device_names(users_data[u])) for u in user_set)) # no objective value in first stage
    end
    @second_stage model_user = begin
        
        @known(model_user, x_us, P_us_dec_P, P_us_dec_N, CAPEX_tot_us, C_OEM_tot_us, C_REP_tot_us, R_RV_tot_us)
        #Introduction of the uncertainties, in this moment considered on the load demand and renewable production
		@uncertain scen_s scen_eps peak_tariff buy_price consumption_price sell_price penalty_price Load Ren from Scenario_Load_Renewable

        # Overestimation of the power exchanged by each POD when selling to the external market by each user
        @expression(model_user, P_P_us_overestimate[u in user_set, t in time_set],
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
        @expression(model_user, P_N_us_overestimate[u in user_set, t in time_set],
            max(0,
                Load[u][t]
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
        @recourse(model_user, 
            0 <= E_batt_us[u=user_set, b=asset_names(users_data[u], BATT), t=time_set] 
                <= field_component(users_data[u], b, "max_capacity"))
        # Converter dispatch positive when supplying to AC
        @recourse(model_user, 0 <= 
            P_conv_P_us[u=user_set, c=asset_names(users_data[u], CONV), time_set] 
                <= field_component(users_data[u], c, "max_capacity"))
        # Converter dispatch positive when absorbing from AC
        @recourse(model_user,
            0 <= P_conv_N_us[u=user_set, c=asset_names(users_data[u], CONV), time_set] 
                <= field_component(users_data[u], c, "max_capacity"))
        # Dispath of renewable assets
        @recourse(model_user,
            0 <= P_ren_us[u=user_set, time_set]
                <= sum(Float64[field_component(users_data[u], r, "max_capacity") for r in asset_names(users_data[u], REN)]))
        #Dispatch of fuel-fired generator
        @recourse(model_user, 
            0 <= P_gen_us[u=user_set, g=asset_names(users_data[u], THER), time_set] 
                <= field_component(users_data[u], g, "max_capacity"))
        # Maximum dispatch of the user for every peak period
        @recourse(model_user,
            0 <= P_max_us[u=user_set, w in peak_set]
                <= maximum(P_us_overestimate[u, t] for t in time_set if peak_categories[t] == w))
        # Total dispatch of the user, positive when supplying to public grid
        @recourse(model_user,
            0 <= P_P_us[u=user_set, t in time_set]
                <= P_P_us_overestimate[u, t])
        # Total dispatch of the user, positive when absorbing from public grid
        @recourse(model_user,
            0 <= P_N_us[u=user_set, t in time_set]
                <= P_N_us_overestimate[u, t])
        
        # Number of generators plants used by a user in each time step t
        @recourse(model_user,
            0 <= z_gen_us[u=user_set, g=asset_names(users_data[u], THER), time_set]
                <= field_component(users_data[u], g, "max_capacity")/field_component(users_data[u], g, "nom_capacity"), Int)
		
        # Squilibrium of each user with respect to the energy supplied to the public grid
        @recourse(model_user, 0 <= P_sq_P_us[u=user_set, t=time_set])
        
        # Squilibrium of each user with respect to the energy absorbed from the public grid
        @recourse(model_user, 0 <= P_sq_N_us[u=user_set, t=time_set])

        ## Expressions

        # Peak tariff cost by user and peak period
        @expression(model_user, C_Peak_us[u in user_set, w in peak_set],
            profile(market_data, "peak_weight")[w] * peak_tariff[w] * P_max_us[u, w]
            # Peak tariff times the maximum connection usage times the discretization of the period
        )

        # Total peak tariff cost by user
        @expression(model_user, C_Peak_tot_us[u in user_set],
            sum(C_Peak_us[u, w] for w in peak_set)  # Sum of peak costs
        ) 

        # Revenues of each user in non-cooperative approach
        @expression(model_user, R_Energy_us[u in user_set, t in time_set],
            profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] * (sell_price[t]*P_P_us[u,t]
                - buy_price[t] * P_N_us[u,t] 
                - consumption_price[t] * Load[u][t])  # economic flow with the market
        )
        
        # Energy revenues by user
        @expression(model_user, R_Energy_tot_us[u in user_set],
            sum(R_Energy_us[u, t] for t in time_set)  # sum of revenues by user
        )

        # Costs arising from the use of fuel-fired generators by users and asset
        @expression(model_user, C_gen_us[u in user_set, g=asset_names(users_data[u], THER)],
            sum(profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] *(
                z_gen_us[u,g,t] * field_component(users_data[u], g, "nom_capacity") 
                    * (field_component(users_data[u], g, "fuel_price") * field_component(users_data[u], g, "inter_map") + field_component(users_data[u], g, "OEM_lin"))
                    + field_component(users_data[u], g, "fuel_price") * field_component(users_data[u], g, "slope_map") * P_gen_us[u,g,t])
                for t in time_set)
		)

        # Total costs arising from the use of fuel-fired generators by users ### ERROR with StochasticProgram in istantiation (BUG)
        @expression(model_user, C_gen_tot_us[u in user_set],
            sum(DecisionAffExpr{Float64}[C_gen_us[u,g] for g  in asset_names(users_data[u], THER)])
        )
        
        # Cost arising from the imbalance of energy by user in each time_step
        @expression(model_user, C_sq_us[u in user_set, t in time_set],
            profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] * (penalty_price[t] * P_sq_P_us[u,t] + penalty_price[t] * P_sq_N_us[u,t])
		)
        
        # Total cost arising from the imbalance of energy by user
        @expression(model_user, C_sq_tot_us[u in user_set],
            sum(C_sq_us[u,t] for t in time_set)
        )

        # Yearly revenue of the user
        #@expression(model_user, yearly_rev[u=user_set],
        #    R_Energy_tot_us[u] - C_OEM_tot_us[u]
        #)

        # Cash flow
        @expression(model_user, Cash_flow_us[y in year_set_0, u in user_set],
            (y == 0) ? 0 - CAPEX_tot_us[u] : 
                (R_Energy_tot_us[u] 
                - C_Peak_tot_us[u] 
                - C_OEM_tot_us[u] 
                - C_gen_tot_us[u]
                - C_sq_tot_us[u] 
                - C_REP_tot_us[y, u] 
                + R_RV_tot_us[y, u])
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
        #@expression(model_user, P_us[u = user_set, t = time_set],
        #    P_P_us[u, t] - P_N_us[u, t]
        #)

        # Total converter dispatch: positive when supplying to AC
        #@expression(model_user, P_conv_us[u=user_set, c=asset_names(users_data[u], CONV), t=time_set],
        #    P_conv_P_us[u, c, t] - P_conv_N_us[u, c, t]
        #)

        # Social welfare of the entire aggregation
        @expression(model_user, SW,
            sum(NPV_us)
        )

        ## Inequality constraints

        # Set that the hourly dispatch cannot go beyond the maximum dispatch of the corresponding peak power period
        @constraint(model_user, con_us_max_P_user[u = user_set, t = time_set],
            - P_max_us[u, profile(market_data, "peak_categories")[t]] + P_P_us[u, t] + P_N_us[u, t] <= 0
        )

        # Set the renewable energy dispatch to be no greater than the actual available energy
        @constraint(model_user, con_us_ren_dispatch[u in user_set, t in time_set],
            - sum(Ren[u][r][t] * x_us[u, r] * field_component(users_data[u], r, "nom_capacity") for r in asset_names(users_data[u], REN))
            + P_ren_us[u, t] <= 0
        )

        # Set the maximum hourly dispatch of converters not to exceed their capacity
        @constraint(model_user, con_us_converter_capacity[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
            - x_us[u, c] * field_component(users_data[u], c, "nom_capacity") + P_conv_P_us[u, c, t] + P_conv_N_us[u, c, t] <= 0
        )


        # Set the maximum hourly dispatch of converters not to exceed the C-rate of the battery in discharge
        @constraint(model_user, con_us_converter_capacity_crate_dch[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
            P_conv_P_us[u, c, t] <= 
                x_us[u, field_component(users_data[u], c, "corr_asset")] * field_component(users_data[u], field_component(users_data[u], c, "corr_asset"), "nom_capacity")
                * field_component(users_data[u], field_component(users_data[u], c, "corr_asset"), "max_C_dch")
        )


        # Set the maximum hourly dispatch of converters not to exceed the C-rate of the battery in charge
        @constraint(model_user, con_us_converter_capacity_crate_ch[u in user_set, c in asset_names(users_data[u], CONV), t in time_set],
            P_conv_N_us[u, c, t] <= 
                x_us[u, field_component(users_data[u], c, "corr_asset")] * field_component(users_data[u], field_component(users_data[u], c, "corr_asset"), "nom_capacity")
                * field_component(users_data[u], field_component(users_data[u], c, "corr_asset"), "max_C_ch")
        )


        # Set the minimum level of the energy stored in the battery to be proportional to the capacity
        @constraint(model_user, con_us_min_E_batt[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
            x_us[u, b] * field_component(users_data[u], b, "nom_capacity") * field_component(users_data[u], b, "min_SOC") - E_batt_us[u, b, t] <= 0
        )

        # Set the maximum level of the energy stored in the battery to be proportional to the capacity
        @constraint(model_user, con_us_max_E_batt[u in user_set, b in asset_names(users_data[u], BATT), t in time_set],
            - x_us[u, b] * field_component(users_data[u], b, "nom_capacity") * field_component(users_data[u], b, "max_SOC") + E_batt_us[u, b, t] <= 0
        )
        
        # Set that the number of working generator plants cannot exceed the number of generator plants installed
        @constraint(model_user, con_us_gen_on[u in user_set, g=asset_names(users_data[u], THER), t in time_set],
			z_gen_us[u, g, t] <= x_us[u, g]
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
        @constraint(model_user, con_us_balance[u in user_set, t in time_set],
            P_P_us[u, t] - P_N_us[u, t]
            - sum(P_gen_us[u, g, t] for g in asset_names(users_data[u], THER))
            + sum(P_conv_N_us[u, c, t] - P_conv_P_us[u, c, t] for c in asset_names(users_data[u], CONV))
            - P_ren_us[u, t]
            == - Load[u][t]
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

        @constraint(model_user, con_us_sq_balance[u in user_set, t in time_set],
		    P_N_us[u, t] - P_P_us[u, t] == P_us_dec_N[u,scen_s,t] - P_us_dec_P[u,scen_s,t] - P_sq_P_us[u,t] + P_sq_N_us[u,t]
		)

        @objective(model_user, Max, sum(NPV_us[u] for u in user_set))
    
    end
    
    set_optimizer(model_user,optimizer)

    ECModel.deterministic_model = DEP(model_user)
    
    return ECModel
end

"""
    calculate_demand(ECModel::AbstractEC,scenarios::Array{Scenario_Load_Renewable, 1},control_stoch::Bool)
Function to calculate the demand by user in each scenario
Outputs
-------
demand_us_EC : Array{DenseAxisArray}
    DenseAxisArray representing the demand by the EC and each user in each scenario
"""

function calculate_demand(ECModel::AbstractEC)

    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)
    n_users = length(user_set)

    n_scen_s = ECModel.n_scen_s
    n_scen_eps = ECModel.n_scen_eps
    n_scen = n_scen_s * n_scen_eps

    scenarios = ECModel.scenarios

    # get the number of time_step

    gen_data = ECModel.gen_data
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    time_set = 1:n_steps

    # time step resolution
    time_res = profile(ECModel.market_data, "time_res")
    energy_weight = profile(ECModel.market_data, "energy_weight")

    # array with sum of the load power by user and EC in each scenario
    demand_us_EC = Array{Any}(undef,n_scen)

    for i = 1:n_scen
        data_load = Array{Float64}(undef,n_users) # total load by user in the specific scenario considered
        for u = 1:n_users
            user = user_set[u]
            data_load[u] = Float64[sum(scenarios[i].Load[user][t] .* time_res[t] .* energy_weight[t]
                for t in time_set)][1]
        end
        demand_us_EC[i] = JuMP.Containers.DenseAxisArray(
                [sum(data_load); data_load],
                user_set_EC
            )
    end

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
function calculate_production(ECModel::AbstractEC,control_stoch::Bool)

    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)

    # users set
    users_data = ECModel.users_data

    # get number of scenarios if the model is stochastich
    if control_stoch == true
        n_scen_s = ECModel.n_scen_s
        n_scen_eps = ECModel.n_scen_eps
        n_scen = n_scen_s * n_scen_eps
    else
        n_scen = 1
    end

    # time step resolution
    time_res = profile(ECModel.market_data, "time_res")
    energy_weight = profile(ECModel.market_data, "energy_weight")

    # Array with sum of the renewable production by user and EC in each scenario
    production_us_EC = Array{Any}(undef,n_scen)

    for i = 1:n_scen
        # Extraction of renewable production by user based on the scenario considered
        _P_ren = value.(ECModel.model[2,:P_ren_us],i)

        data_production = Float64[
            has_asset(users_data[u], REN) ? sum(_P_ren[u, :] .* time_res .* energy_weight) : 0.0
            for u in user_set
        ]

        production_us_EC[i] = JuMP.Containers.DenseAxisArray(
            [sum(data_production); data_production],
            user_set_EC
        )
    end

    return production_us_EC
end

"""
    calculate_production_shares(ECModel::AbstractEC,scenarios::Array{Scenario_Load_Renewable, 1},control_stoch::Bool; per_unit::Bool=true)
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
function calculate_production_shares(ECModel::AbstractEC,scenarios::Array{Scenario_Load_Renewable, 1},control_stoch::Bool; per_unit::Bool=true)

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

    # time step resolution
    time_res = profile(ECModel.market_data, "time_res")
    energy_weight = profile(ECModel.market_data, "energy_weight")

    # get number of scenarios if the model is stochastich
    if control_stoch == true
        n_scen_s = ECModel.n_scen_s
        n_scen_eps = ECModel.n_scen_eps
        n_scen = n_scen_s * n_scen_eps
    else
        n_scen = 1
    end

    # Array to store fraction of energy production by user and EC in each scenario
    frac = Array{Any}(undef,n_scen)

    for i = 1:n_scen
        _P_ren_us = value.(ECModel.model[2,:P_ren_us],i)  # Ren production dispatch of users - users mode
        _x_us = value.(ECModel.model[1,:x_us]) # Installed capacity by user

        # Available renewable production
        _P_ren_available = JuMP.Containers.DenseAxisArray(
            [sum(Float64[
                !has_asset(users_data[u], r) ? 0.0 : scenarios[i].Ren[u][r][t] * _x_us[u,r] * field_component(users_data[u], r, "nom_capacity")
                    for r in asset_names(users_data[u], REN)
            ]) for u in user_set, t in time_set],
            user_set, time_set
        )

        # Calculate total energy fraction at EC level for every renewable resource
        frac_tot = JuMP.Containers.DenseAxisArray(
            [(sum(!has_asset(users_data[u], t_ren) ? 0.0 : sum(
                    Float64[
                        _P_ren_us[u,t] <= 0.0 ? 0.0 : _P_ren_us[u,t] * sum(
                            Float64[scenarios[i].Ren[u][r][t] * _x_us[u,r] * field_component(users_data[u], r, "nom_capacity")
                            for r in asset_names(users_data[u], REN) if r == t_ren]
                        ) / _P_ren_available[u, t] * time_res[t] * energy_weight[t]
                        for t in time_set
                ]) for u in user_set
                ))
            for t_ren in ren_set_unique],
            ren_set_unique
        )

        # fraction of energy production by user and EC
        frac[i] = JuMP.Containers.DenseAxisArray(
            Float64[
                frac_tot.data';
                Float64[!has_asset(users_data[u], t_ren) ? 0.0 : sum(
                    Float64[
                        _P_ren_us[u,t] <= 0.0 ? 0.0 : _P_ren_us[u,t] * sum(Float64[
                            scenarios[i].Ren[u][r][t] * _x_us[u,r] * field_component(users_data[u], r, "nom_capacity")
                                for r in asset_names(users_data[u], REN) if r == t_ren
                        ]) / _P_ren_available[u,t] * time_res[t] * energy_weight[t]
                        for t in time_set
                    ])
                    for u in user_set, t_ren in ren_set_unique
                ]
            ],
            user_set_EC, ren_set_unique
        )
    end
    
    # normalize output if perunit is required
    if per_unit

        # calculate the demand by EC and user
        demand_EC_us = calculate_demand(ECModel,scenarios,control_stoch)

        # create auxiliary DenseAxisArray to perform the division
        
        # update value
        for i = 1:n_scen
            frac[i] = JuMP.Containers.DenseAxisArray(
                    frac[i].data ./ demand_EC_us[i].data,
                user_set_EC, ren_set_unique)
        end
            
    end

    return frac
end

"""
    calculate_self_production(ECModel::AbstractEC,scenarios::Array{Scenario_Load_Renewable, 1},control_stoch::Bool; per_unit::Bool=true)
Calculate the self production for each user.
Output is normalized with respect to the demand when per_unit is true
'''
Outputs
-------
shared_en_frac : DenseAxisArray
    Shared energy for each user and the aggregation
'''
"""
function calculate_self_production(ECModel::AbstractEC,scenarios::Array{Scenario_Load_Renewable, 1},control_stoch::Bool; per_unit::Bool=true)

    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)

    # time step resolution
    time_res = profile(ECModel.market_data, "time_res")
    energy_weight = profile(ECModel.market_data, "energy_weight")

    # get the number of time_step
    gen_data = ECModel.gen_data
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    time_set = 1:n_steps

    # get number of scenarios if the model is stochastich
    if control_stoch == true
        n_scen_s = ECModel.n_scen_s
        n_scen_eps = ECModel.n_scen_eps
        n_scen = n_scen_s * n_scen_eps
    else
        n_scen = 1
    end

    # Array containing self consumption by user and EC in each scenario
    shared_en_frac = Array{Any}(undef,n_scen)

    for i = 1:n_scen

        # power dispatch of users - users mode
        _P_P_us = value.(ECModel.model[2,:P_P_us],i)
        _P_N_us = value.(ECModel.model[2,:P_N_us],i)

        _P_us = JuMP.Containers.DenseAxisArray(
                _P_P_us.data - _P_N_us.data,
                user_set, time_set)

        _P_ren_us = value.(ECModel.model[2,:P_ren_us],i)  # Ren production dispatch of users - users mode
        _x_us = value.(ECModel.model[1,:x_us]) # Installed capacity by user
        
        # self consumption by user only
        shared_en_us = JuMP.Containers.DenseAxisArray(
            Float64[sum(time_res .* energy_weight .* max.(
                    0.0, _P_ren_us[u, :] - max.(_P_us[u, :], 0.0)
                )) for u in user_set],
            user_set
        )

        # self consumption by user and EC
        shared_en_frac[i] = JuMP.Containers.DenseAxisArray(
            [sum(shared_en_us); shared_en_us.data],
            user_set_EC
        )
    end

    # normalize output if perunit is required
    if per_unit

        # calculate the demand by EC and user
        demand_EC_us = calculate_demand(ECModel,scenarios,control_stoch)
        
        # update value
        for i = 1:n_scen
            shared_en_frac[i] = shared_en_frac[i] ./ demand_EC_us[i]
        end
    end

    return shared_en_frac
end

"""
    calculate_self_consumption(ECModel::AbstractEC,scenarios::Array{Scenario_Load_Renewable, 1},control_stoch::Bool; per_unit::Bool=true)
Calculate the demand that each user meets using its own sources, or self consumption.
Output is normalized with respect to the demand when per_unit is true
'''
Outputs
-------
shared_cons_frac : DenseAxisArray
    Shared consumption for each user and the aggregation
'''
"""
function calculate_self_consumption(ECModel::AbstractEC,scenarios::Array{Scenario_Load_Renewable, 1},control_stoch::Bool; per_unit::Bool=true)

    # get user set
    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)

    users_data = ECModel.users_data

    # time step resolution
    time_res = profile(ECModel.market_data, "time_res")
    energy_weight = profile(ECModel.market_data, "energy_weight")

    # get the number of time_step
    gen_data = ECModel.gen_data
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    time_set = 1:n_steps

    # get number of scenarios if the model is stochastich
    if control_stoch == true
        n_scen_s = ECModel.n_scen_s
        n_scen_eps = ECModel.n_scen_eps
        n_scen = n_scen_s * n_scen_eps
    else
        n_scen = 1
    end

    # Array containing self consumption by user and EC in each scenario
    shared_cons= Array{Any}(undef,n_scen)

    for i = 1:n_scen

        # power dispatch of users - users mode
        _P_P_us = value.(ECModel.model[2,:P_P_us],i)
        _P_N_us = value.(ECModel.model[2,:P_N_us],i)

        _P_us = JuMP.Containers.DenseAxisArray(
                _P_P_us.data - _P_N_us.data,
                user_set, time_set)
        
        # self consumption by user only
        shared_cons_us = JuMP.Containers.DenseAxisArray(
            Float64[sum(time_res[t] * energy_weight[t] * 
                        max.(0.0, scenarios[i].Load[u][t] + min.(_P_us[u, t], 0.0))
                    for t in time_set) 
                for u in user_set],
            user_set
        )

        # self consumption by user and EC
        shared_cons[i] = JuMP.Containers.DenseAxisArray(
            Float64[sum(shared_cons_us); shared_cons_us.data],
            user_set_EC
        )
    end

    # normalize output if perunit is required
    if per_unit

        # calculate the demand by EC and user
        demand_EC_us = calculate_demand(ECModel,scenarios,control_stoch)
        
        # update value
        for i = 1:n_scen
            shared_cons[i] = shared_cons[i] ./ demand_EC_us[i]
        end
    end

    return shared_cons
end

function get_scenario_data_model(ECModel::AbstractEC, data_name::String)
    set_label = collect(keys(ECModel.results))

    index = findall( x -> occursin(data_name, x), set_label)

    set_data = set_label[index]

    data_extracted = Array{Any}(undef,length(index))

    for scen = 1:length(index)
        # Scenario index are subscript, so to find them we have to use relative Unicode
        pos = findall( x -> occursin(Char(0x02080+scen), x), set_data) # find the position of the scenario scen in set_data
        label = set_data[pos][1] # label = data_name\_scen

        data_extracted[scen] = value.(ECModel.results[label])
    end

    return data_extracted

end

"""
    calculate_x_tot(ECModel::AbstractEC)
Function to calculate the total capacity installed by user in the EC
Outputs
-------
x_us_EC :
    SparseAxisArray representing the total installed capacity of resources by each user and the total EC
"""
function calculate_x_tot(ECModel::AbstractEC)
    
    x_us_EC = ECModel.results["x_us"]

    users_data = ECModel.users_data

    # get user set
    user_set = ECModel.user_set

    set_asset = unique([name for u in user_set for name in device_names(users_data[u])])

    for asset in set_asset
        tot_installed = sum(has_asset(users_data[u], asset) ? x_us_EC[u,asset] * field_component(users_data[u], asset, "nom_capacity") : 0.0 for u in user_set)
        x_us_EC[EC_CODE,asset] = tot_installed
    end

    return x_us_EC
end
