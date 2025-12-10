# # Optimizing different configurations
# This example aims to shocase the use of EnergyCommunity.jl to optimize the different configurations of energy communities supported by the tool, namely:
# - Non Cooperative (NC)
# - Aggregated Non Cooperative (ANC)
# - Cooperative (CO)

# The energy community considered in this example consists of 3 users, where:
# * all users can install PV system
# * only the first user cannot install batteries, whereas the others can
# * the third user can install also wind turbines

# The example is based on a subset of users taken from the following article, yet for a subset of users.
# > D. Fioriti, A. Frangioni, D. Poli, "Optimal sizing of energy communities with fair revenue sharing and exit clauses: Value, role and business model of aggregators and users," in Applied Energy, vol. 299, 2021, 117328,[doi: 10.1016/j.apenergy.2021.117328](https://doi.org/10.1016/j.apenergy.2021.117328)

# ## Cooperative (CO) Energy Community

# ### Initialization

# Import the needed packages
using EnergyCommunity, JuMP
using HiGHS, Plots

# Create a base Energy Community example in the data folder; use the default configuration.
folder = joinpath(@__DIR__, "data")
create_example_data(folder, config_name="default")

# Input file to load the structure of the energy community based on a yaml file.
input_file = joinpath(@__DIR__, "data/energy_community_model.yml");

# define optimizer and options
optimizer = optimizer_with_attributes(HiGHS.Optimizer, "ipm_optimality_tolerance"=>1e-6)

# ### Create, build and optimize the model

# Define the Cooperative model
CO_Model = ModelEC(input_file, EnergyCommunity.GroupCO(), optimizer)

# Build the mathematical model
build_model!(CO_Model)

# Optimize the model
optimize!(CO_Model)

# ### Results

# get objective value in M€
obj_CO = objective_value(CO_Model)/1e6
obj_CO

# optionally, print summary of the results
print_summary(CO_Model)

# moreover, obtain the business plan as DataFrame
business_plan(CO_Model)

# ## Non Cooperative (NC) Energy Community

# ### Initialization
# Given that the initialization is the same as for the CO model, we can reuse the input file and the optimizer defined above. So we can directly move to the model creation.

# ### Create, build and optimize the model
# Define the Non Cooperative model
NC_Model = ModelEC(input_file, EnergyCommunity.GroupNC(), optimizer)

# Build the mathematical model
build_model!(NC_Model)

# Optimize the model
optimize!(NC_Model)

# ### Results
# get objective value in M€
obj_NC = objective_value(NC_Model)/1e6
obj_NC

# ## Aggregated Non Cooperative (ANC) Energy Community
# ### Initialization
# Given that the initialization is the same as for the CO model, we can reuse the input file and the optimizer defined above. So we can directly move to the model creation. In this case, we showcase a different approach to define the ANC model by passing directly the configuration name to the `ModelEC` constructor.

# ### Create, build and optimize the model
# Define the Aggregated Non Cooperative model
ANC_Model = ModelEC(CO_Model, GroupANC())

# Build the mathematical model
build_model!(ANC_Model)

# Optimize the model
optimize!(ANC_Model)

# ### Results
# get objective value in M€
obj_ANC = objective_value(ANC_Model)/1e6
obj_ANC

# ## Comparison of the results
# Finally, we can compare the results obtained from the three different configurations of energy communities.

println("Objective value CO Model [M€]: ", obj_CO)
println("Objective value NC Model [M€]: ", obj_NC)
println("Objective value ANC Model [M€]: ", obj_ANC)
# As expected, the Cooperative model provides the best objective value, followed by the Aggregated Non Cooperative model, and finally the Non Cooperative model. This showcases the benefits of cooperation within energy communities.
# We can do that also with a plot:
bar(
    ["CO Model", "ANC Model", "NC Model"],
    [obj_CO, obj_ANC, obj_NC],
    title="Comparison of Objective Values",
    ylabel="Objective Value [M€]",
    ylims=[-1.3, -1.1],
    legend=false,
)


