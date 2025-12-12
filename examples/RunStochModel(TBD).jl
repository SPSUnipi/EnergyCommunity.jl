#using StochasticPrograms#master
#using JuMP
#using Base.Threads
#using DataStructures
#using LinearAlgebra
#using Parameters
#using Distributions
#using Random
#using JLD2
#using FileIO
#using PointEstimateMethod
#using YAML
#using DataFrames
#using CSV
#using XLSX
#using Formatting
# Useful package to built plot
#using Makie
#using CairoMakie
#using ColorSchemes
#using StochasticPrograms

#import CPLEX

# # Run this script from EnergyCommunity.jl root!!!
# using Pkg
# Pkg.activate("examples")

using EnergyCommunity, JuMP
using HiGHS, Plots

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

# Initialize the empty non-cooperative version of a EC

EC_NonCooperative = StochasticEC(file_name,GroupNC(),CPLEX.Optimizer,sampled_scenarios,scen_s_sample,scen_eps_sample)

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

print_first_stage(output_file_NC * ".xlsx",EC_NonCooperative)
save(output_file_NC * ".jld2", EC_NonCooperative)

# get the number of installed resource by users
x_NC_fixed = EC_NonCooperative.results[:x_us].data

# add the installed capacity of the entire EC
x_tot_NC = calculate_x_tot(EC_NonCooperative)

#Free memory
EC_NonCooperative = StochasticEC();

GC.gc() # garbage collector

# Initialize the cooperative version of a EC

EC_Cooperative = StochasticEC(file_name,GroupCO(),CPLEX.Optimizer,sampled_scenarios,scen_s_sample,scen_eps_sample)

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
print_first_stage(output_file_CO * ".xlsx",EC_Cooperative)
save(output_file_CO * ".jld2", EC_Cooperative)
# get the number of installed resource by users
x_CO_fixed = EC_Cooperative.results[:x_us].data

# Plot some useful image of the installed capacity
colors = Makie.wong_colors()

# add the installed capacity of the entire EC
x_tot_CO = calculate_x_tot(EC_Cooperative)

plot_resource("installed_capacity1_($scen_s_sample,$scen_eps_sample).png",["PV","wind"],users_data,x_tot_CO,x_tot_NC,colors[1:2]) # renewable asset
plot_resource("installed_capacity_($scen_s_sample,$scen_eps_sample).png",["batt"],users_data,x_tot_CO,x_tot_NC,[colors[3]]) #battery