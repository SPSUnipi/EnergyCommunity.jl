using Distributions
"""
    pem_extraction(scen_s_sample::Int, sigma_load, mean_pv, sigma_pv, mean_wind, sigma_wind, uncertain_var)

Extract scenario points and probabilities using the Point Estimate Method (PEM) for long-term uncertainty.

This function applies the Point Estimate Method to sample from probability distributions representing
long-term uncertainty in load demand or renewable production. PEM provides a discrete approximation
of continuous distributions with a small number of representative points and associated probabilities.

# Arguments
- `scen_s_sample::Int`: Number of long-term scenarios (s) to generate
- `sigma_load::Float64`: Standard deviation of the normalized load demand distribution
- `mean_pv::Float64`: Mean value of the PV production multiplier
- `sigma_pv::Float64`: Standard deviation of the PV production distribution
- `mean_wind::Float64`: Mean value of the wind production multiplier
- `sigma_wind::Float64`: Standard deviation of the wind production distribution
- `uncertain_var::String`: Type of uncertain variable to consider:
  - `"L"`: Long-term uncertainty on load demand only
  - `"P"`: Long-term uncertainty on PV production only
  - `"W"`: Long-term uncertainty on wind production only

# Returns
A tuple `(point_load, point_pv, point_wind, scen_probability)` where:
- `point_load::Vector{Float64}`: Sampled load demand multipliers (length `scen_s_sample`)
- `point_pv::Vector{Float64}`: Sampled PV production multipliers (length `scen_s_sample`)
- `point_wind::Vector{Float64}`: Sampled wind production multipliers (length `scen_s_sample`)
- `scen_probability::Vector{Float64}`: Probability associated with each scenario (sums to 1.0)

# Distribution Details
- For load demand (`uncertain_var="L"`): Truncated Normal distribution ``N(1.0, σ_{load})`` with support ``[0, +∞)``
- For PV production (`uncertain_var="P"`): Truncated Normal distribution ``N(μ_{pv}, σ_{pv})`` with support ``[0, +∞)``
- For wind production (`uncertain_var="W"`): Truncated Normal distribution ``N(μ_{wind}, σ_{wind})`` with support ``[0, +∞)``

# Point Estimate Method
PEM approximates the moments of a random variable using a weighted sum of strategically chosen points.
For `scen_s_sample` scenarios, it selects points and weights that match the first `scen_s_sample` 
moments of the underlying distribution.

# Special Cases
- If `scen_s_sample = 1`: Returns deterministic values (load=1.0, pv=mean_pv, wind=mean_wind) with probability 1.0
- For uncertain variables: Only the specified variable has uncertainty; others are set to their mean values

# Errors

- Throws ArgumentError if uncertain_var is not "L", "P", or "W"

"""

function pem_extraction(scen_s_sample::Int, sigma_load, 
						mean_pv,
						sigma_pv,
						mean_wind,
						sigma_wind,
						uncertain_var)

	if scen_s_sample > 1 # More than a single scenario s to generate
		if uncertain_var == "L" # We are considering long uncertainties on load demand
			Distribution_load = truncated(Normal(1.0,sigma_load), 0.0, +Inf) # Load distribution
			pem_load = pem(Distribution_load,scen_s_sample) # Extracted point for load (with their probability)
			point_load = pem_load.x
			scen_probability = pem_load.p # probability associated to each extracted point from load distribution
			
			point_wind = ones(scen_s_sample) * mean_wind # No uncertainty on wind
			point_pv = ones(scen_s_sample) * mean_pv # No uncertainty on PV

		elseif uncertain_var == "P" # We are considering long uncertainties on PV
			Distribution_pv = truncated(Normal(mean_pv,sigma_pv), 0.0, +Inf) # Renewable production distribution
			pem_pv = pem(Distribution_pv,scen_s_sample) # Extracted point for PV
			point_pv = pem_pv.x
			scen_probability = pem_pv.p # probability associated to each extracted point from renewable distribution

			point_load = ones(scen_s_sample) # No uncertainty on load demand
			point_wind = ones(scen_s_sample) * mean_wind # No uncertainty on wind

		elseif uncertain_var == "W" # We are considering long uncertainties on wind
			Distribution_wind = truncated(Normal(mean_wind,sigma_wind), 0.0, +Inf) # Renewable production distribution
			pem_wind = pem(Distribution_wind,scen_s_sample) # Extracted point for PV
			point_wind = pem_wind.x
			scen_probability = pem_wind.p # probability associated to each extracted point from renewable distribution

			point_load = ones(scen_s_sample) # No uncertainty on load demand
			point_pv = ones(scen_s_sample) * mean_pv # No uncertainty on PV
		else
			throw( ArgumentError("The uncertain_var value must be R, P or W") )
		end
		
	else
		point_load = [1.0]
		point_pv = [mean_pv]
		point_wind = [mean_wind]

		scen_probability = [1.0]
	end

	return (point_load,point_pv,point_wind,scen_probability)
end