using StochasticPrograms#master
using JuMP
using Base.Threads
using DataStructures
using LinearAlgebra
using Parameters
using Distributions
using Random
using JLD2
using FileIO
using PointEstimateMethod
using YAML
using DataFrames
using CSV
using XLSX
using Formatting
# Useful package to built plot
using Makie
using CairoMakie
using ColorSchemes
using StochasticPrograms

import CPLEX

#Random.seed!(123) # Setting the seed
include("src/EnergyCommunity.jl")
# additional usefull functions i.e. main type definitions and read data
# include("utils.jl") 

# Data extraction
file_name = "./src/stochastic/stoch_data/energy_community_model.yml"
data = read_input(file_name)

(gen_data,
  users_data,
  market_data) = explode_data(data)

n_users = length(user_names(gen_data, users_data))
init_step = field(gen_data, "init_step")
final_step = field(gen_data, "final_step")
n_steps = final_step - init_step + 1
project_lifetime = field(gen_data, "project_lifetime")
peak_categories = profile(market_data, "peak_categories")

# Set definitions
user_set = user_names(gen_data, users_data)
year_set = 1:project_lifetime
time_set = 1:n_steps
peak_set = unique(peak_categories)

# # Define the scenario
# include("scenario_definition.jl")

# # EC model definition
# include("ECModel_definitions.jl")

# # include the abstract types for encapsuling the method
# include("ECModel.jl")

# # Include the samplers for long period uncertainty
# include("pem_extraction.jl")

# # Include the functions used to print results
# include("print_functions.jl")

################################# PRIMA FASE ###############################################

# Number of scenarios to be extracted
scen_s_sample = field(gen_data, "n_s")
scen_eps_sample = field(gen_data, "n_eps")
n_scen_sample = scen_s_sample * scen_eps_sample

isdet = false
if scen_eps_sample == 1 && scen_s_sample == 1
  isdet = true
end

scen_s_set = 1:scen_s_sample
scen_eps_set = 1:scen_eps_sample

# Standard deviation associated with load and renewable production in long period uncertainty

sigma_load = 0.3

mean_pv = 1.0
sigma_pv = 0.1

mean_wind = 0.95
sigma_wind = 0.15

# Extract Uncertain Variable
unc_var = field(gen_data, "uncertain_var")

# Extraction of the point used to sample the distributions associated to the long period uncertainty
(point_s_load,
  point_s_pv,
  point_s_wind,
  scen_probability) = pem_extraction(scen_s_sample, 
                        sigma_load, 
                        mean_pv,
                        sigma_pv,
                        mean_wind,
                        sigma_wind,
                        unc_var)

# Include the sampler for distributions associated to short period uncertainty and a function to generate scenarios (new version: sample the normalized distributions)

# include("point_Scen_eps_sampler.jl")

# To define an empty stochastic model we have to declare previously the scenarios

# OUTPUT: sampled_scenarios: array containing all the scenarios created for the first phase
#         point_eps_load_sampled: extracted points for the normalized distributions associated with load demand
#         point_eps_ren_sampled: extracted points for the normalized distributions associated with renewable production

sampled_scenarios = scenarios_generator(data,
                              point_s_load,
                              point_s_pv,
                              point_s_wind,
                              scen_s_sample,
                              scen_eps_sample,
                              unc_var,
                              point_probability=scen_probability,
                              first_stage=true,
                              deterministic=isdet)

# Print load and renewable production generated
load_ren_data = Dict( u => DataFrames.DataFrame(
      vcat(
          [[t for t in time_set]],
          [[sampled_scenarios[scen].Load[u][t] for t in time_set] for scen = 1:n_scen_sample],
          [[has_asset(users_data[u], REN) ? sampled_scenarios[scen].Ren[u][r][t] : 0.0 for t in time_set] for r in asset_names(users_data[u], REN) for scen = 1:n_scen_sample]
      ),
      map(Symbol, vcat("Time step",
          ["load_demand_($(convert_scen(scen_s_sample,scen_eps_sample,scen)[1]),$(convert_scen(scen_s_sample,scen_eps_sample,scen)[2]))" for scen = 1:n_scen_sample],
          ["$r renewable production_($(convert_scen(scen_s_sample,scen_eps_sample,scen)[1]),$(convert_scen(scen_s_sample,scen_eps_sample,scen)[2]))" for r in asset_names(users_data[u], REN) for scen = 1:n_scen_sample]
          )
      )
  )
  for u in user_set
  )

XLSX.openxlsx("generated_load_ren.xlsx", mode="w") do xf

      for u in user_set
          xs = XLSX.addsheet!(xf, "user $u")
          XLSX.writetable!(xs, collect(DataFrames.eachcol(load_ren_data[u])), DataFrames.names(load_ren_data[u]))
      end
  end

# add the base modelling for Energy Communities (Non Cooperative NC version)
# include("base_model.jl")

# # Functions to build the Cooperative CO model
# include("cooperative.jl")

# Initialize the empty non-cooperative version of a EC

EC_NonCooperative = ModelEC(file_name,GroupNC(),CPLEX.Optimizer,sampled_scenarios,scen_s_sample,scen_eps_sample)

# Build the NC model

build_base_model!(EC_NonCooperative,CPLEX.Optimizer)

# set the technical paraters for the NC optimization
time_lim = 60 * 60 * 10  # max time in second
primal_gap = 1e-2 # primal gap (1e-4 = 1%)
n_threads = 64 # number of threads to be used

set_parameters_ECmodel!(EC_NonCooperative,primal_gap,time_lim,n_threads,1)

optimize_deterministic_ECmodel(EC_NonCooperative) # optimize the deterministic equivalent version and store the results

# save the data of the first stage model
output_file_NC = "first_stage_output_NC_($scen_s_sample,$scen_eps_sample)"
save_first_stage_model(EC_NonCooperative,output_file_NC)

# get the number of installed resource by users
x_NC_fixed = EC_NonCooperative.results["x_us"].data

# add the installed capacity of the entire EC
x_tot_NC = calculate_x_tot(EC_NonCooperative)

#Free memory
EC_NonCooperative = ModelEC();

GC.gc() # garbage collector

# Initialize the cooperative version of a EC

EC_Cooperative = ModelEC(file_name,GroupCO(),CPLEX.Optimizer,sampled_scenarios,scen_s_sample,scen_eps_sample)

# Build the CO model

build_specific_model!(GroupCO(),EC_Cooperative,CPLEX.Optimizer)

# set the technical parameters for the CO optimization
time_lim = 60 * 60 * 24 # max time in second
primal_gap = 1e-2 # primal gap (1e-4 = 1%)
n_threads = 64 # number of threads to be used

set_parameters_ECmodel!(EC_Cooperative,primal_gap,time_lim,n_threads,1)

optimize_deterministic_ECmodel(EC_Cooperative) # optimize the deterministic equivalent version and store the results

# save the data of the first stage model
output_file_CO = "first_stage_output_CO_($scen_s_sample,$scen_eps_sample)"
save_first_stage_model(EC_Cooperative,output_file_CO)

# get the number of installed resource by users
x_CO_fixed = EC_Cooperative.results["x_us"].data

# Plot some useful image of the installed capacity
colors = Makie.wong_colors()

# add the installed capacity of the entire EC
x_tot_CO = calculate_x_tot(EC_Cooperative)

plot_resource("installed_capacity1_($scen_s_sample,$scen_eps_sample).png",["PV","wind"],user_set,x_tot_CO,x_tot_NC,colors[1:2]) # renewable asset
plot_resource("installed_capacity_($scen_s_sample,$scen_eps_sample).png",["batt"],user_set,x_tot_CO,x_tot_NC,[colors[3]]) #battery

#Free memory
EC_Cooperative = ModelEC();

GC.gc() # garbage collector

################################# FINE PRIMA FASE ###############################################

################################# SECONDA FASE ###############################################

n_repeat = 10 # number of new repetition for the risimulation

# Initialize the new point used to sample the distributions associated to the long period uncertainty to 1
point_s_load_ris = ones(n_repeat) 
point_s_pv_ris = ones(n_repeat) * mean_pv
point_s_wind_ris = ones(n_repeat) * mean_wind

# For the moment we are considering that the scenarios s affects separately the load demand, the PV production or the wind production
if field(gen_data, "uncertain_var") == "L"
  # Definition of the distributions from which the sigma_s will be extracted to multiply the average scenario
  Distribution_load = truncated(Normal(1.0,sigma_load), 0.0, +Inf) # Load distribution 
  point_s_load_ris = rand( Distribution_load , n_repeat )
  emp_mean = mean(point_s_load_ris)
  point_s_load_ris = point_s_load_ris/emp_mean # Normalize on 1
elseif field(gen_data, "uncertain_var") == "P"
  Distribution_pv = truncated(Normal(mean_pv,sigma_pv), 0.0, +Inf) # PV production distribution
  point_s_pv_ris = rand( Distribution_pv , n_repeat )
  emp_mean = mean(point_s_pv_ris)
  point_s_pv_ris = point_s_pv_ris * mean_pv / emp_mean # Normalize on mean_pv
elseif field(gen_data, "uncertain_var") == "W"
  Distribution_wind = truncated(Normal(mean_wind,sigma_wind), 0.0, +Inf) # wind production distribution
  point_s_wind_ris = rand( Distribution_wind , n_repeat )
  emp_mean = mean(point_s_wind_ris)
  point_s_wind_ris = point_s_wind_ris * mean_wind / emp_mean # Normalize on mean_pv
end

# Arrays created to store the total energy declared by the community
tot_declared_P_CO_fixed = Array{Float64}(undef,n_repeat)
tot_declared_N_CO_fixed = Array{Float64}(undef,n_repeat)
tot_declared_P_NC_fixed = Array{Float64}(undef,n_repeat)
tot_declared_N_NC_fixed = Array{Float64}(undef,n_repeat)

# Economic data CO
SW_CO = Array{Float64}(undef,n_repeat)
R_ene_tot_CO = Array{Float64}(undef,n_repeat)
C_gen_tot_CO = Array{Float64}(undef,n_repeat)
C_sq_tot_CO = Array{Float64}(undef,n_repeat)
C_peak_tot_CO = Array{Float64}(undef,n_repeat)
R_rew_agg_CO = Array{Float64}(undef,n_repeat)

# Economic data NC
SW_NC = Array{Float64}(undef,n_repeat)
R_ene_tot_NC = Array{Float64}(undef,n_repeat)
C_gen_tot_NC = Array{Float64}(undef,n_repeat)
C_sq_tot_NC = Array{Float64}(undef,n_repeat)
C_peak_tot_NC = Array{Float64}(undef,n_repeat)

# Dispatch data NC
load_demand_CO = Array{Float64}(undef,n_repeat)
P_P_CO = Array{Float64}(undef,n_repeat)
P_N_CO = Array{Float64}(undef,n_repeat)
P_sq_P_CO = Array{Float64}(undef,n_repeat)
P_sq_N_CO = Array{Float64}(undef,n_repeat)
P_ren_CO = Array{Float64}(undef,n_repeat)
P_gen_CO = Array{Float64}(undef,n_repeat)
P_conv_P_CO = Array{Float64}(undef,n_repeat)
P_conv_N_CO = Array{Float64}(undef,n_repeat)
P_Shared_CO = Array{Float64}(undef,n_repeat)

# Dispatch data NC
load_demand_NC = Array{Float64}(undef,n_repeat)
P_P_NC = Array{Float64}(undef,n_repeat)
P_N_NC = Array{Float64}(undef,n_repeat)
P_sq_P_NC = Array{Float64}(undef,n_repeat)
P_sq_N_NC = Array{Float64}(undef,n_repeat)
P_ren_NC = Array{Float64}(undef,n_repeat)
P_gen_NC = Array{Float64}(undef,n_repeat)
P_conv_P_NC = Array{Float64}(undef,n_repeat)
P_conv_N_NC = Array{Float64}(undef,n_repeat)

# Dispatch data NC

# set the technical paraters for the optimization in the risimulated models
time_lim_sec_stage = 60 * 60 # max time in second
time_lim_third_stage = 60 * 5 # max time in second
primal_gap = 1e-4 # primal gap (1e-4 = 5%)
n_threads = 32 # number of threads to be used

# Evaluate time for the risimulation process
start_time = time()

Threads.@threads for r = 1:n_repeat
  println("Processing repetition number: ", r)

  # Creation of the array of scenarios (only one scenario s and same scenarios epsilon of the first optimization)
  sampled_scenarios_ris = scenarios_generator(data,
    point_s_load_ris,
    point_s_pv_ris,
    point_s_wind_ris,
    r, # actual repetition
    scen_eps_sample, # number of scenarios eps to sample
    unc_var, # Uncertain variable
    second_stage=true ) # bool value to declare that we are in the second stage

  EC_NonCooperative_second_stage = ModelEC(file_name,GroupNC(),CPLEX.Optimizer,sampled_scenarios_ris,1,scen_eps_sample)

  build_base_model!(EC_NonCooperative_second_stage,CPLEX.Optimizer,control_first_risimulation=true,x_fixed=x_NC_fixed)

  set_parameters_ECmodel!(EC_NonCooperative_second_stage,primal_gap,time_lim_sec_stage,n_threads)

  optimize_deterministic_ECmodel(EC_NonCooperative_second_stage) # optimize the deterministic equivalent version and store the results

  # Store declared energy by aggregator in each time step (to be used in the third stage optimization)
  declared_P_NC_fixed = value.(EC_NonCooperative_second_stage.deterministic_model[:P_us_dec_P])
  declared_N_NC_fixed = value.(EC_NonCooperative_second_stage.deterministic_model[:P_us_dec_N])

  # Store the total declared energy by aggregator (to be printed)
  tot_declared_P_NC_fixed[r] = sum(sum(declared_P_NC_fixed[u,1,t] for t in time_set) for u in user_set)
  tot_declared_N_NC_fixed[r] = sum(sum(declared_N_NC_fixed[u,1,t] for t in time_set) for u in user_set)

  #Free memory
  EC_NonCooperative_second_stage = ModelEC();

  GC.gc() # garbage collector

  # Initialize the cooperative version of a EC
  EC_Cooperative_second_stage = ModelEC(file_name,GroupCO(),CPLEX.Optimizer,sampled_scenarios_ris,1,scen_eps_sample)

  # Build the CO model

  build_specific_model!(GroupCO(),EC_Cooperative_second_stage,CPLEX.Optimizer, control_first_risimulation=true,x_fixed=x_CO_fixed)

  set_parameters_ECmodel!(EC_Cooperative_second_stage,primal_gap,time_lim_sec_stage,n_threads)

  optimize_deterministic_ECmodel(EC_Cooperative_second_stage) # optimize the deterministic equivalent version and store the results

  # Store declared energy by aggregator
  declared_P_CO_fixed = value.(EC_Cooperative_second_stage.deterministic_model[:P_agg_dec_P])
  declared_N_CO_fixed = value.(EC_Cooperative_second_stage.deterministic_model[:P_agg_dec_N])

  # Store the total declared energy by aggregator (to be printed)
  tot_declared_P_CO_fixed[r] = sum(declared_P_CO_fixed[1,t] for t in time_set)
  tot_declared_N_CO_fixed[r] = sum(declared_N_CO_fixed[1,t] for t in time_set)

  #Free memory
  EC_Cooperative_second_stage = ModelEC();

  GC.gc() # garbage collector

  ################################# FINE SECONDA FASE ###############################################

  ################################# TERZA FASE ######################################################

  # Final deterministic optimization on the same scenario s previously extracted and on a single scenario epsilon to be randomly extracted

  # Creation of scenario (only one scenario s and one scenario epsilon)

  sampled_scenario_thid_stage = scenarios_generator(data,
                                  point_s_load_ris,
                                  point_s_pv_ris,
                                  point_s_wind_ris,
                                  r,
                                  1,
                                  unc_var)

  # Initialize the empty non-cooperative version of a EC

  EC_NonCooperative_MC = ModelEC(file_name,GroupNC(),CPLEX.Optimizer,sampled_scenario_thid_stage,1,1)

  build_base_model!(EC_NonCooperative_MC,CPLEX.Optimizer,
    control_first_risimulation=true,
    x_fixed=x_NC_fixed,
    control_MC=true,
    P_dec_P_fixed=declared_P_NC_fixed,
    P_dec_N_fixed=declared_N_NC_fixed
  )

  set_parameters_ECmodel!(EC_NonCooperative_MC,primal_gap,time_lim_third_stage,n_threads)

  optimize_deterministic_ECmodel(EC_NonCooperative_MC) # optimize the deterministic equivalent version and store the results
  
  (SW_NC[r],
    R_ene_tot_NC[r],
    C_gen_tot_NC[r],
    C_sq_tot_NC[r],
    C_peak_tot_NC[r]) = extract_economic_values_NC(EC_NonCooperative_MC)

   (load_demand_NC[r],
    P_P_NC[r],
    P_N_NC[r],
    P_sq_P_NC[r],
    P_sq_N_NC[r],
    P_ren_NC[r],
    P_gen_NC[r],
    P_conv_P_NC[r],
    P_conv_N_NC[r]) = extract_dispatch_values_NC(EC_NonCooperative_MC)

  #Free memory
  EC_NonCooperative_MC = ModelEC();

  GC.gc() # garbage collector

  # Initialize the empty cooperative version of a EC

  EC_Cooperative_MC = ModelEC(file_name,GroupCO(),CPLEX.Optimizer,sampled_scenario_thid_stage,1,1)

  build_specific_model!(GroupCO(),EC_Cooperative_MC,CPLEX.Optimizer,
    control_first_risimulation=true,
    x_fixed=x_CO_fixed,
    control_MC=true,
    P_dec_P_fixed=declared_P_CO_fixed,
    P_dec_N_fixed=declared_N_CO_fixed
  )

  set_parameters_ECmodel!(EC_Cooperative_MC,primal_gap,time_lim_third_stage,n_threads)

  optimize_deterministic_ECmodel(EC_Cooperative_MC) # optimize the deterministic equivalent version and store the results

  (SW_CO[r],
  R_ene_tot_CO[r],
  C_gen_tot_CO[r],
  C_sq_tot_CO[r],
  C_peak_tot_CO[r],
  R_rew_agg_CO[r]) = extract_economic_values_CO(EC_Cooperative_MC)

  (load_demand_CO[r],
    P_P_CO[r],
    P_N_CO[r],
    P_sq_P_CO[r],
    P_sq_N_CO[r],
    P_ren_CO[r],
    P_gen_CO[r],
    P_conv_P_CO[r],
    P_conv_N_CO[r],
    P_Shared_CO[r]) = extract_dispatch_values_CO(EC_Cooperative_MC)

  #Free memory
  EC_Cooperative_MC = ModelEC();

  GC.gc() # garbage collector

end

end_time = time()

# SECOND STAGE PRINT DATA

# Print forecast dispatch obtained
output_file_dec_NC = "forecast_dispatch_NC_($scen_s_sample,$scen_eps_sample)"
print_second_stage(output_file_dec_NC * ".xlsx", data, 
                      tot_declared_P_NC_fixed, 
                      tot_declared_N_NC_fixed, 
                      point_s_load_ris, 
                      point_s_pv_ris,
                      point_s_wind_ris,
                      GroupNC())

output_file_dec_CO = "forecast_dispatch_CO_($scen_s_sample,$scen_eps_sample)"
print_second_stage(output_file_dec_CO * ".xlsx", data, 
                      tot_declared_P_CO_fixed, 
                      tot_declared_N_CO_fixed, 
                      point_s_load_ris, 
                      point_s_pv_ris,
                      point_s_wind_ris,
                      GroupCO())

# Plot forecast dispatch obtained
plot_declared_dispatch(output_file_dec_NC * ".png", tot_declared_P_NC_fixed, tot_declared_N_NC_fixed, point_s_load_ris, point_s_pv_ris, point_s_wind_ris) 
plot_declared_dispatch(output_file_dec_CO * ".png", tot_declared_P_CO_fixed, tot_declared_N_CO_fixed, point_s_load_ris, point_s_pv_ris, point_s_wind_ris) 

# THIRD STAGE PRINT DATA

output_file_ts_NC = "third_stage_output_NC_($scen_s_sample,$scen_eps_sample).xlsx"

print_third_stage(output_file_ts_NC, n_repeat, start_time - end_time, # general data
  SW_NC, R_ene_tot_NC, C_gen_tot_NC, C_sq_tot_NC, C_peak_tot_NC, # economic data
  load_demand_NC, P_P_NC, P_N_NC, P_sq_P_NC, P_sq_N_NC, P_ren_NC, P_gen_NC, P_conv_P_NC, P_conv_N_NC, # dispatch data
  GroupNC() # configuration 
  )

output_file_ts_CO = "third_stage_output_CO_($scen_s_sample,$scen_eps_sample).xlsx"

print_third_stage(output_file_ts_CO, n_repeat, start_time - end_time, # general data
  SW_CO, R_ene_tot_CO, C_gen_tot_CO, C_sq_tot_CO, C_peak_tot_CO, # economic data
  load_demand_CO, P_P_CO, P_N_CO, P_sq_P_CO, P_sq_N_CO, P_ren_CO, P_gen_CO, P_conv_P_CO, P_conv_N_CO, # dispatch data
  GroupCO(), # configuration
  R_reward = R_rew_agg_CO, P_Shared = P_Shared_CO # only CO data
  )

# Plot data third stage

# Plot distribution of Social cost over simulation in the CO version
histogram_all_SC("CO_histogram_SC_($scen_s_sample,$scen_eps_sample).png",-SW_CO)