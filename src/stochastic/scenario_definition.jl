
"""
    @define_scenario Scenario_Load_Renewable

Define a custom scenario type for stochastic energy community optimization.

This macro from the `StochasticPrograms.jl` package creates a scenario structure that encapsulates
all uncertain parameters in the stochastic optimization problem, including market prices, load demand,
and renewable production profiles.

# Scenario Fields
- `scen_s::Int`: Long-term scenario index
- `scen_eps::Int`: Short-term (epsilon) scenario index
- `peak_tariff::Dict{String, Float64}`: Peak demand tariff for each peak period
- `buy_price::Dict{Int, Float64}`: Energy purchase price from grid at each time step
- `consumption_price::Dict{Int, Float64}`: Energy consumption price at each time step
- `sell_price::Dict{Int, Float64}`: Energy selling price to grid at each time step
- `penalty_price::Dict{Int, Float64}`: Penalty price for imbalances at each time step
- `Load::Dict{String, Dict{Int, Float64}}`: Load demand for each user at each time step
- `Ren::Dict{String, Dict{String, Dict{Int, Float64}}}`: Renewable production for each user, asset, and time step

# Macro Methods

## `@zero`
Defines the zero scenario (default/empty scenario) used as initialization.

Returns a `Scenario_Load_Renewable` with default values (scenario indices = 1, empty dictionaries).

## `@expectation`
Defines how to compute the expected scenario given a collection of scenarios with probabilities.

Computes weighted averages of all scenario attributes based on their probabilities:
- Market prices: ``E[price_t] = \\sum_s p_s \\cdot price_{s,t}``
- Load demand: ``E[Load_{u,t}] = \\sum_s p_s \\cdot Load_{u,s,t}``
- Renewable production: ``E[Ren_{u,a,t}] = \\sum_s p_s \\cdot Ren_{u,a,s,t}``

where ``p_s`` is the probability of scenario ``s``.

# Usage

The macro automatically generates:
- A constructor for creating scenario instances
- Methods for computing expected scenarios
- Integration with `StochasticPrograms.jl` framework

"""
# Scenario definition
@define_scenario Scenario_Load_Renewable = begin
	scen_s::Int
	scen_eps::Int
	peak_tariff::Dict{String, Float64}
	buy_price::Dict{Int,Float64}
	consumption_price::Dict{Int,Float64}
	sell_price::Dict{Int,Float64}
	penalty_price::Dict{Int,Float64}
	Load::Dict{String,Dict{Int,Float64}} # load_demand of each user per each scenario (s,eps)
	Ren::Dict{String,Dict{String,Dict{Int,Float64}}} # renewable production of each users plant per each scenario (s,eps)		
	

	@zero begin
		return Scenario_Load_Renewable(
			1, # scen_s
			1, # scen_eps
			Dict{String, Float64}(), # peak_tariff
			Dict{Int,Float64}(), # buy_price
			Dict{Int,Float64}(), # consumption_price
			Dict{Int,Float64}(), # sell_price
			Dict{Int,Float64}(), # penalty_price
			Dict{String,Dict{Int,Float64}}(), # Load
			Dict{String,Dict{String,Dict{Int,Float64}}}(), # Ren
		)
	end
	
	@expectation begin
		p_t = Dict{String, Float64}()
		b_V = Dict{Int,Float64}()
		b_F = Dict{Int,Float64}()
		s_p = Dict{Int,Float64}()
		p_p = Dict{Int,Float64}()
		p   = Dict(u => Dict{Int,Float64}() for u in user_set)
		q   = Dict(u => Dict{String,Dict{Int,Float64}}() for u in user_set)

		length_scenarios = length(scenarios)

		utils = [Dict{Int,Float64}() for _ in 1:length_scenarios+1] #variable used to store values

		# Dictionary of time-indexed attributes
		time_attributes = [
			(:buy_price, b_V),
			(:consumption_price, b_F),
			(:sell_price, s_p),
			(:penalty_price, p_p),
		]

		@inbounds for t in time_set
			for (attribute, scenario_attribute) in time_attributes
				get!(scenario_attribute, t, sum([probability(sc)*(getfield(sc, attribute)[t]) for sc in scenarios]))
			end
			get!(utils[1],t,0)
		end
		
		@inbounds for peak in peak_set
			get!(p_t,peak,sum(probability(sc)*sc.peak_tariff[peak] for sc in scenarios))
		end
		
		@inbounds for u in user_set
			count = 1
			for sc in scenarios #primo ciclo per calcolare il carico atteso
				count += + 1
				prob_scen = probability(sc)
				load_scen = sc.Load[u]
				utils2 = Dict{Int,Float64}() #variable used to store values
				@inbounds for n in time_set
						utils2[n] = prob_scen*load_scen[n]
				end
				utils[count] = merge(+,utils[count-1],utils2)
			end
			p[u] = utils[length_scenarios+1]
			for name = asset_names(users_data[u], REN)
				temp1 = [Dict{Int,Float64}() for _ in 1:length_scenarios+1]
				@inbounds for n in time_set
					get!(temp1[1],n,0)
				end
				count2 = 1
				for sc in scenarios
					count2 = count2 + 1
					temp2 = Dict{Int,Float64}() # temporary dictionary to store the expected scenario for renewable production of each asset "name"
					ren_scen_ass = sc.Ren[u][name]
					prob_scen = probability(sc)
					@inbounds for n in time_set
						temp2[n] = prob_scen*ren_scen_ass[n]
					end
				temp1[count2] = merge(+,temp1[count2-1],temp2)
				end
				get!(q[u],name,	temp1[length_scenarios+1])
			end
		end
		return Scenario_Load_Renewable(1, 1, p_t, b_V, b_F, s_p, p_p, p, q) 
	end
end
