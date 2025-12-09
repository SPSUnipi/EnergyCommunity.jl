using Distributions
# Function used to sample the load and renewable distributions for long period uncertainty using the Point Estimate Method

# scen_s_sample = number of scenarios s
# sigma_load = standard deviation associated to load distribution
# sigma_ren = standard deviation associated to renewable prouction distribution

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