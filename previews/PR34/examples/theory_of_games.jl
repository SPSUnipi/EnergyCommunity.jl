# # Fair reward allocations
# This example showcase the capabilities of estimating fair reward allocations within energy communities using concepts from cooperative game theory. By leveraging on [TheoryOfGames.jl](https://github.com/SPSUnipi/theoryofgames.jl), the package provides functionalities to compute various allocation methods, such as the Variance (Least) Core, Shapley value, the Nucleolus, and more. These methods help in distributing the benefits of cooperation among the members of the energy community in a fair manner.
# In the following, we showcase how to set up an energy community optimization problem and compute fair reward allocations based on the results. More information are also available at:
# > - D. Fioriti, G. Bigi, A. Frangioni, M. Passacantando and D. Poli, "Fair Least Core: Efficient, Stable and Unique Game-Theoretic Reward Allocation in Energy Communities by Row-Generation," in IEEE Transactions on Energy Markets, Policy and Regulation, vol. 3, no. 2, pp. 170-181, June 2025, [doi: 10.1109/TEMPR.2024.3495237](https://doi.org/10.1109/TEMPR.2024.3495237).
# > - D. Fioriti, A. Frangioni, D. Poli, "Optimal sizing of energy communities with fair revenue sharing and exit clauses: Value, role and business model of aggregators and users," in Applied Energy, vol. 299, 2021, 117328,[doi: 10.1016/j.apenergy.2021.117328](https://doi.org/10.1016/j.apenergy.2021.117328)

# ## Initialization of the model

# Import the needed packages
using EnergyCommunity, JuMP, HiGHS
using TheoryOfGames
using DataFrames, StatsPlots

# Create a base Energy Community example in the data folder; use the default configuration.
folder = joinpath(@__DIR__, "data")
create_example_data(folder, config_name="default")

# Input file to load the structure of the energy community based on a yaml file.
input_file = joinpath(@__DIR__, "data/energy_community_model.yml");

# define optimizer and options
optimizer = optimizer_with_attributes(
    HiGHS.Optimizer,
    "log_to_console"=>false,  # suppress solver output
    "ipm_optimality_tolerance"=>1e-6,  # set optimality tolerance
)

# Define the Non Cooperative model
CO_Model = ModelEC(input_file, EnergyCommunity.GroupCO(), optimizer)

# ## Enumerative method for reward allocations
# Define the enumerative mode for cooperative games
enum_mode = EnumMode(
    CO_Model,
    EnergyCommunity.GroupNC(),  # Base group is the Non Cooperative group
    no_aggregator_type=EnergyCommunity.GroupNC(),  # when the aggregator is not in the community, use Non Cooperative group
)

# ### Shapley
# Calculate fair allocation using Shapley value
dst_sh = shapley_value(enum_mode)
dst_sh

# ### Nucleolus
# Calculate fair allocation using Nucleolus
dst_nuc = nucleolus(enum_mode, optimizer)
dst_nuc

# ### Variance Core
# Calculate fair allocation using Variance Core
dst_vc = var_in_core(enum_mode, optimizer)
dst_vc

# ### Variance Least Core
# Calculatefair allocation using Variance Least Core
dst_vlc = var_least_core(enum_mode, optimizer)
dst_vlc

# ## Verify stability of the allocations

# Check if the Shapley value is in the Core
sh_in_core = verify_in_core(dst_sh, enum_mode, optimizer)
println("Shapley value in Core: ", sh_in_core)

# Check if the Nucleolus is in the Core
nuc_in_core = verify_in_core(dst_nuc, enum_mode, optimizer)
println("Nucleolus in Core: ", nuc_in_core)

# Check if the Variance Core allocation is in the Core
vc_in_core = verify_in_core(dst_vc, enum_mode, optimizer)
println("Variance Core allocation in Core: ", vc_in_core)

# Check if the Variance Least Core allocation is in the Core
vlc_in_core = verify_in_core(dst_vlc, enum_mode, optimizer)
println("Variance Least Core allocation in Core: ", vlc_in_core)

# ## Compare reward allocations
# Create a DataFrame to compare the different allocations
df = DataFrame(
    Member = collect(keys(dst_sh)),
    Shapley = collect(values(dst_sh)),
    Nucleolus = collect(values(dst_nuc)),
    Variance_Core = collect(values(dst_vc)),
    Variance_Least_Core = collect(values(dst_vlc)),
)
println(df)

# Plot the comparison
groupedbar(
    df.Member,
    [df.Shapley df.Nucleolus df.Variance_Core df.Variance_Least_Core],
    label = ["Shapley" "Nucleolus" "Variance Core" "Variance Least Core"],
    title = "Comparison of Fair Reward Allocations",
    xlabel = "Community Members",
    ylabel = "Allocated Reward [€]",
    bar_position = :dodge,
)

# ## Iterative method for reward allocations
# For large energy communities, the enumerative method may become computationally expensive as it implies the calculation of the utility function for all possible coalitions. In such cases, an iterative method employing row-generation can be employed to estimate fair reward allocations more efficiently.
# This example showcases how to set up an iterative method for computing the Nucleolus allocation.

# Define the iterative mode for cooperative games
iter_mode = IterMode(
    CO_Model,
    EnergyCommunity.GroupNC(),  # Base group is the Non Cooperative group
    no_aggregator_type=EnergyCommunity.GroupNC(),  # when the aggregator is not in the community, use Non Cooperative group
    optimizer=optimizer,
)

# Calculate Variance Least Core with iterative method
dst_vlc_iter = var_least_core(iter_mode, optimizer)
dst_vlc_iter

# Compare the distributions from the enumerative and iterative methods
println("Difference between enumerative and iterative Variance Least Core allocations:")
for member in keys(dst_vlc)
    diff = dst_vlc[member] - dst_vlc_iter[member]
    println("Member: ", member, ", Absolute Difference [%]: ", 100*abs(diff)/dst_vlc[member])
end
