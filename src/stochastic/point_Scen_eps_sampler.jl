""" Sampler for distribution associated to short period uncertainty
	
Sampler function

INPUT: users data: dictionary containing all the user data information

OUTPUT: point_load_demand: sampled point from the normalized distribution associated with load demand
        point_ren_production: sampled point from the normalized distribution associated with renewable production

"""
function Scenario_eps_Point_Sampler(data_user, uncertain_var; deterministic::Bool = false)

    point_load_demand = Dict{String,Array{Float64}}() # extracted point for each user
    point_ren_production = Dict{String,Dict{String,Array{Float64}}}() # extracted point for each user and asset

    n_step = length(profile_component(data_user["user1"], "load", "load") )
    user_set = keys(data_user)
    time_set = 1:n_step

    for u in user_set

        if deterministic == true
            array_n_load = ones(n_step)
            point_load_demand[u] = array_n_load

            point_ren_production[u] = Dict{String,Array{Float64}}()
            for name = asset_names(data_user[u], REN)
                point_ren = ones(n_step)
                get!(point_ren_production[u],name,point_ren)
            end
        else
            if uncertain_var == "L" # We are considering uncertainties on load demand
        
                # Calculate the normalized std for load
                std_n_load = (profile_component(data_user[u], "load", "std"))./profile_component(data_user[u], "load", "load") 

                # We are supposing that to have a day-ahead uncertainty and a short-term uncertainty (in first approximation, considered equal)
                std_st_load = std_n_load

                # Define load distribution for short period uncertainty
                load_distribution = MvNormal(ones(n_step), std_st_load)
                
                # Load extraction
                array_n_load = broadcast(abs, rand(load_distribution))

                # Control when the extracted point are < 0
                for t in time_set
                    if array_n_load[t] < 0
                        array_n_load[t] = 0
                    end
                end

                # New load demand of user u in the specific scenario s considered
                point_load_demand[u] = array_n_load

                # Add deterministic renewable production
                point_ren_production[u] = Dict{String,Array{Float64}}()
                for name = asset_names(data_user[u], REN)
                    point_ren = ones(n_step)
                    get!(point_ren_production[u],name,point_ren)
                end

            else # We are considering uncertainties on renewable production

                # Add deterministic load 
                array_n_load = ones(n_step)
                point_load_demand[u] = array_n_load
            
                point_ren_production[u] = Dict{String,Array{Float64}}()
                for name = asset_names(data_user[u], REN)

                    if ( name == "PV" && uncertain_var == "P" ) || ( name == "wind" && uncertain_var == "W" ) # Add uncertainties on desired variable

                        # We are supposing that to have a day-ahead uncertainty and a short-term uncertainty (in first approximation, considered equal)
                        std_st_ren = profile_component(data_user[u], name, "std")

                        # Define load distribution for short period uncertainty
                        ren_distribution = MvNormal(ones(n_step), std_st_ren)

                        # Renewable extraction
                        point_ren = broadcast(abs, rand(ren_distribution))

                        # Control to set 0 the extracted production when initial renewable production was 0 or when the extracted point are < 0
                        for t in time_set
                            if profile_component(data_user[u], name, "ren_pu")[t] == 0 || point_ren[t] < 0
                                point_ren[t] = 0
                            end
                        end
                    else
                        point_ren = ones(n_step) # No uncertainties to consider
                    end
                    # Fill with extracted points
                    get!(point_ren_production[u],name,point_ren)
                end
            end
        end
    end
    return (point_load_demand,point_ren_production)
end

""" Scenarios generator function

INPUT: data: dictionary containing all the data information
       point_s_load: extracted point for long period uncertainty distribution in load demand
       point_s_ren: extracted point for long period uncertainty distribution in renewable production
       n_scen_s: number of scenarios s to generate
       n_scen_eps: number of scenarios eps to generate
       first_stage: boolean value to know if we are in the first stage
       second_stage: boolean value to know if we are in the second stage

OUTPUT: sampled_scenarios: array with the generated scenarios
"""

function scenarios_generator(
	data::Dict{Any, Any},
	point_s_load::Vector{Float64}, # extracted point for long period uncertainty distribution in load demand
	point_s_pv::Vector{Float64}, # extracted point for long period uncertainty distribution in PV production
    point_s_wind::Vector{Float64}, # extracted point for long period uncertainty distribution in wind production
	n_scen_s::Int, # number of scenarios s to generate
	n_scen_eps::Int, # number of scenarios eps to generate
    uncertain_var::String; # Uncertain var to consider
    point_probability::Vector{Float64} = Float64[], # probability of each point
	first_stage::Bool = false, # boolean value to know if we are in the first stage
    second_stage::Bool = false, # boolean value to know if we are in the second stage
    deterministic::Bool = false
)

    ## In this implementation, we consider uncertanties only on the uncertain_var under analyses.

    data_user = users(data)
	data_market = market(data)
    user_set = keys(data_user)


	if first_stage == true # we are in the first stage, thus we need to normally extract scenarios
		
        n_scen = n_scen_s*n_scen_eps # total number of scenarios

		# Array containing each scenario
		sampled_scenarios = Array{Scenario_Load_Renewable}(undef,n_scen)
		for scen = 1:n_scen
			sampled_scenarios[scen] = zero(Scenario_Load_Renewable) # initialize an empty scenario 
		end
		
		for s = 1:n_scen_s
            # Extract first day-ahead uncertainties which are common among different scenarios epsilon
            point_load_dayahead = Dict{String,Array{Float64}}() # dictionary used to store all the extracted point for day-ahead load demand
            point_ren_dayahead = Dict{String,Dict{String,Array{Float64}}}() # dictionary used to store all the extracted point for day-ahead renewable production
            (point_load_dayahead,point_ren_dayahead) = Scenario_eps_Point_Sampler(users(data),uncertain_var,deterministic=deterministic)

			for eps = 1:n_scen_eps
				scen = (s-1)*n_scen_eps+eps

                # we have now to evaluate the real value sampled for load and renewable production
                # It is evaluated as: mean_L * sigma^LT_s * sigma^DA_{s,d} * sigma^ST_{s,d,epsilon}
                load_demand = Dict{String,Dict{Int,Float64}}()
		        ren_production = Dict{String,Dict{String,Dict{Int,Float64}}}()

                # Extract now short-term uncertainties which are different among different scenarios epsilon
                point_load_shortterm = Dict{String,Array{Float64}}() # dictionary used to store all the extracted point for day-ahead load demand
                point_ren_shortterm = Dict{String,Dict{String,Array{Float64}}}() # dictionary used to store all the extracted point for day-ahead renewable production
                (point_load_shortterm,point_ren_shortterm) = Scenario_eps_Point_Sampler(users(data),uncertain_var,deterministic=deterministic)

                for u in user_set
                    # Fill the scenarios with extracted values
                    load_demand[u] = array2dict(( profile_component(data_user[u], "load", "load") * point_s_load[s] ) # Scenario s demand
                                                    .* point_load_dayahead[u] # Day-Ahead demand
                                                        .* point_load_shortterm[u] ) # Short-term demand
                    
                    ren_production[u] = Dict{String,Dict{Int,Float64}}()
                    for name = asset_names(data_user[u], REN)
                        if name == "PV"
                            temp = array2dict( ( profile_component(data_user[u], name, "ren_pu") * point_s_pv[s] ) # Scenario s production
                                                    .* point_ren_dayahead[u][name] # Day-Ahead production 
                                                        .* point_ren_shortterm[u][name] ) # Short-term
                        elseif name == "wind"
                            temp = array2dict( ( profile_component(data_user[u], name, "ren_pu") * point_s_wind[s] ) # Scenario s production
                                                    .* point_ren_dayahead[u][name] # Day-Ahead production 
                                                        .* point_ren_shortterm[u][name] ) # Short-term
                        else
                            throw( ArgumentError("Accepted renewable assets name are wind and PV") )
                        end
                        get!(ren_production[u],name,temp)
                    end
                end

				sampled_scenarios[scen] = Scenario_Load_Renewable(
					s,
					eps,
					profile(data_market, "peak_tariff"),
                    array2dict(profile(data_market, "buy_price")),
                    array2dict(profile(data_market, "consumption_price")),
                    array2dict(profile(data_market, "sell_price")),
                    array2dict(profile(data_market, "penalty_price")),
					load_demand,
					ren_production,
					probability = point_probability[s]/n_scen_eps)
			end
		end
		return sampled_scenarios
	elseif second_stage == true # building scenarios for the risimulation, now scen_s doesn't represent the number of scenarios s to be generated
		
		# Array containing each scenario (only one scenario s)
		sampled_scenarios = Array{Scenario_Load_Renewable}(undef,n_scen_eps)
		for scen = 1:n_scen_eps
			sampled_scenarios[scen] = zero(Scenario_Load_Renewable) # initialize an empty scenario 
		end

		s = n_scen_s # scenario s actually considered

        # Extract first day-ahead uncertainties which are common among different scenarios epsilon
        point_load_dayahead = Dict{String,Array{Float64}}() # dictionary used to store all the extracted point for day-ahead load demand
        point_ren_dayahead = Dict{String,Dict{String,Array{Float64}}}() # dictionary used to store all the extracted point for day-ahead renewable production
        (point_load_dayahead,point_ren_dayahead) = Scenario_eps_Point_Sampler(users(data), uncertain_var)

			for eps = 1:n_scen_eps
				scen = eps

                # Extract first short-term uncertainties which are different among different scenarios epsilon
                point_load_shortterm = Dict{String,Array{Float64}}() # dictionary used to store all the extracted point for day-ahead load demand
                point_ren_shortterm = Dict{String,Dict{String,Array{Float64}}}() # dictionary used to store all the extracted point for day-ahead renewable production
                (point_load_shortterm,point_ren_shortterm) = Scenario_eps_Point_Sampler(users(data), uncertain_var)

                # we have now to evaluate the real value sampled for load and renewable production
                load_demand = Dict{String,Dict{Int,Float64}}()
		        ren_production = Dict{String,Dict{String,Dict{Int,Float64}}}()

                for u in user_set
                    load_demand[u] = array2dict( ( profile_component(data_user[u], "load", "load") * point_s_load[s] ) # Scenario s demand
                                                        .* point_load_dayahead[u] # Day-Ahead demand
                                                            .* point_load_shortterm[u] ) # Short-term 
                    
                    ren_production[u] = Dict{String,Dict{Int,Float64}}()
                    for name = asset_names(data_user[u], REN)
                        if name == "PV"
                            temp = array2dict( ( profile_component(data_user[u], name, "ren_pu") * point_s_pv[s] ) # Scenario s production
                                                    .* point_ren_dayahead[u][name] # Day-Ahead production 
                                                        .* point_ren_shortterm[u][name] ) # Short-term
                        elseif name == "wind"
                            temp = array2dict( ( profile_component(data_user[u], name, "ren_pu") * point_s_wind[s] ) # Scenario s production
                                                    .* point_ren_dayahead[u][name] # Day-Ahead production 
                                                        .* point_ren_shortterm[u][name] ) # Short-term
                        else
                            throw( ArgumentError("Accepted renewable assets name are wind and PV") )
                        end
                        get!(ren_production[u],name,temp)
                    end
                end

				sampled_scenarios[scen] = Scenario_Load_Renewable(
					1,
					eps,
					profile(data_market, "peak_tariff"),
                    array2dict(profile(data_market, "buy_price")),
                    array2dict(profile(data_market, "consumption_price")),
                    array2dict(profile(data_market, "sell_price")),
                    array2dict(profile(data_market, "penalty_price")),
					load_demand,
					ren_production,
					probability = 1/n_scen_eps)
			end
		return sampled_scenarios
    else # we are in the third stage
        sampled_scenarios = Array{Scenario_Load_Renewable}(undef,n_scen_eps)
		for scen = 1:n_scen_eps
			sampled_scenarios[scen] = zero(Scenario_Load_Renewable) # initialize an empty scenario 
		end

        # Extract first day-ahead uncertainties which are common among different scenarios epsilon
        point_load_dayahead = Dict{String,Array{Float64}}() # dictionary used to store all the extracted point for day-ahead load demand
        point_ren_dayahead = Dict{String,Dict{String,Array{Float64}}}() # dictionary used to store all the extracted point for day-ahead renewable production
        (point_load_dayahead,point_ren_dayahead) = Scenario_eps_Point_Sampler(users(data), uncertain_var)

        s = n_scen_s # scenario s actually considered

        for eps = 1:n_scen_eps
            scen = eps

            # Extract first short-term uncertainties which are different among different scenarios epsilon
            point_load_shortterm = Dict{String,Array{Float64}}() # dictionary used to store all the extracted point for day-ahead load demand
            point_ren_shortterm = Dict{String,Dict{String,Array{Float64}}}() # dictionary used to store all the extracted point for day-ahead renewable production
            (point_load_shortterm,point_ren_shortterm) = Scenario_eps_Point_Sampler(users(data),uncertain_var)
            
            # we have now to evaluate the real value sampled for load and renewable production
            load_demand = Dict{String,Dict{Int,Float64}}()
            ren_production = Dict{String,Dict{String,Dict{Int,Float64}}}()

            for u in user_set
                load_demand[u] = array2dict( ( profile_component(data_user[u], "load", "load") * point_s_load[s] ) # Scenario s demand
                                                        .* point_load_dayahead[u] # Day-Ahead demand
                                                            .* point_load_shortterm[u] ) # Short-term
                
                ren_production[u] = Dict{String,Dict{Int,Float64}}()
                for name = asset_names(data_user[u], REN)
                    if name == "PV"
                        temp = array2dict( ( profile_component(data_user[u], name, "ren_pu") * point_s_pv[s] ) # Scenario s production
                                                .* point_ren_dayahead[u][name] # Day-Ahead production 
                                                    .* point_ren_shortterm[u][name] ) # Short-term
                    elseif name == "wind"
                        temp = array2dict( ( profile_component(data_user[u], name, "ren_pu") * point_s_wind[s] ) # Scenario s production
                                                .* point_ren_dayahead[u][name] # Day-Ahead production 
                                                    .* point_ren_shortterm[u][name] ) # Short-term
                    else
                        throw( ArgumentError("Accepted renewable assets name are wind and PV") )
                    end
                                                                                                    
                    get!(ren_production[u],name,temp)
                end
            end

            sampled_scenarios[scen] = Scenario_Load_Renewable(
                1,
                eps,
                profile(data_market, "peak_tariff"),
                array2dict(profile(data_market, "buy_price")),
                array2dict(profile(data_market, "consumption_price")),
                array2dict(profile(data_market, "sell_price")),
                array2dict(profile(data_market, "penalty_price")),
                load_demand,
                ren_production,
                probability = 1/n_scen_eps)
        end
        return sampled_scenarios
    end    
end
