"""
    Scenario_eps_Point_Sampler(data_user, uncertain_var; deterministic::Bool = false)

Sample points from the distribution associated with short-term (epsilon scenario) uncertainty.

This function generates random samples for load demand and renewable production based on the 
specified uncertainty variable. The samples are normalized multiplicative factors applied to 
the base profiles.

# Arguments
- `data_user::Dict`: Dictionary containing user data with load and renewable generation profiles
- `uncertain_var::String`: Type of uncertain variable to consider:
  - `"L"`: Uncertainty on load demand only
  - `"P"`: Uncertainty on PV production only
  - `"W"`: Uncertainty on wind production only
- `deterministic::Bool=false`: If `true`, returns deterministic samples (all ones) instead of random samples

# Returns
A tuple `(point_load_demand, point_ren_production)` where:
- `point_load_demand::Dict{String, Array{Float64}}`: Normalized load demand multipliers for each user
- `point_ren_production::Dict{String, Dict{String, Array{Float64}}}`: Normalized renewable production 
  multipliers for each user and renewable asset

# Sampling Details
- Samples are drawn from a multivariate normal distribution with mean 1 and standard deviation 
  derived from the profile data
- Negative samples are set to zero
- For renewable production, samples are set to zero when the base profile is zero
- When `uncertain_var="L"`, renewable production is deterministic (ones)
- When `uncertain_var` is `"P"` or `"W"`, load demand is deterministic and only the specified 
  renewable source has uncertainty
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

"""
    scenarios_generator(data, point_s_load, point_s_pv, point_s_wind, n_scen_s, n_scen_eps, uncertain_var; 
                       point_probability=Float64[], first_stage=false, second_stage=false, deterministic=false)

Generate scenarios combining long-term and short-term uncertainties for stochastic optimization.

This function creates a hierarchical scenario tree where each long-term scenario (s) branches into 
multiple short-term scenarios (ε). The scenarios include load demand and renewable production profiles 
affected by three levels of uncertainty: long-term, day-ahead, and short-term.

# Arguments
- `data::Dict{Any, Any}`: Dictionary containing all user, market, and general data
- `point_s_load::Vector{Float64}`: Sampled points for long-term load demand uncertainty (one per scenario s)
- `point_s_pv::Vector{Float64}`: Sampled points for long-term PV production uncertainty (one per scenario s)
- `point_s_wind::Vector{Float64}`: Sampled points for long-term wind production uncertainty (one per scenario s)
- `n_scen_s::Int`: Number of long-term scenarios (s) to generate
- `n_scen_eps::Int`: Number of short-term scenarios (ε) per long-term scenario
- `uncertain_var::String`: Type of uncertain variable to consider (`"L"`, `"P"`, or `"W"`)

# Keyword Arguments
- `point_probability::Vector{Float64}=Float64[]`: Probability of each long-term scenario s
- `first_stage::Bool=false`: If `true`, generates scenarios for first-stage optimization
- `second_stage::Bool=false`: If `true`, generates scenarios for second-stage (given a fixed s)
- `deterministic::Bool=false`: If `true`, uses deterministic day-ahead and short-term uncertainties

# Returns
- `sampled_scenarios::Array{Scenario_Load_Renewable}`: Array of generated scenarios

# Scenario Structure
The function operates in three modes:

1. **First Stage** (`first_stage=true`): 
   - Generates `n_scen_s × n_scen_eps` scenarios
   - Each scenario combines long-term, day-ahead, and short-term uncertainties
   - Probability of scenario (s,ε) is `point_probability[s] / n_scen_eps`

2. **Second Stage** (`second_stage=true`):
   - Generates `n_scen_eps` scenarios for a fixed long-term scenario s (passed as `n_scen_s`)
   - Day-ahead uncertainty is sampled once and shared across all ε scenarios
   - Each ε scenario has independent short-term uncertainty
   - Equal probability `1/n_scen_eps` for each scenario

3. **Third Stage** (default):
   - Similar to second stage but used for out-of-sample validation
   - Generates `n_scen_eps` scenarios with independent short-term uncertainties

# Uncertainty Levels
For each user and time step, the realized value is computed as:
```
load_demand[u,t] = mean_load[u,t] × σ_LT[s] × σ_DA[u,t] × σ_ST[u,t,ε]
ren_production[u,asset,t] = mean_ren[u,asset,t] × σ_LT[s] × σ_DA[u,asset,t] × σ_ST[u,asset,t,ε]
```
where:
- `σ_LT`: Long-term uncertainty (scenario s)
- `σ_DA`: Day-ahead uncertainty (common within scenario s)
- `σ_ST`: Short-term uncertainty (specific to scenario ε)

# Example
```julia
# First stage: generate complete scenario tree
scenarios = scenarios_generator(
    data, point_s_load, point_s_pv, point_s_wind, 
    10, 5, "L", 
    point_probability=probs, 
    first_stage=true
)

# Second stage: generate scenarios for a specific s=3
scenarios_eps = scenarios_generator(
    data, point_s_load, point_s_pv, point_s_wind,
    3, 100, "L",
    second_stage=true
)
```
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
