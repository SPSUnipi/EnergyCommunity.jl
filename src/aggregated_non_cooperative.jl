"""

Set the ANC-specific model for the EC
"""
function build_specific_model!(::AbstractGroupANC, ECModel::AbstractEC)
    return build_specific_model!(GroupNC(), ECModel)
end


"""
    Function to set the objective function of the model of the Aggregated-Non-Cooperative model
"""
function set_objective!(::AbstractGroupANC, ECModel::AbstractEC)
    return set_objective!(GroupNC(), ECModel)
end

"""
Function to return the objective function by user in the Aggregated Non Cooperative case
"""
function objective_by_user(::AbstractGroupANC, ECModel::AbstractEC; add_EC=true)
    return objective_by_user(GroupCO(), ECModel; add_EC=add_EC)
end



""" 
    print_summary(::AbstractGroupANC, ECModel::AbstractEC)
Function to print the main results of the model
"""
function print_summary(::AbstractGroupANC, ECModel::AbstractEC; base_case::AbstractEC=ModelEC())
    print_summary(GroupCO(), ECModel; base_case=base_case)
end


"""

Function to plot the results of the Aggregated non cooperative configuration
"""
function Plots.plot(::AbstractGroupANC, ECModel::AbstractEC, output_plot_file::AbstractString;
    user_set::AbstractVector = Vector(), line_width = 2.0)
    Plots.plot(GroupCO(), ECModel, output_plot_file, user_set=user_set, line_width=line_width)
end


"""
    prepare_summary(::AbstractGroupANC, ECModel::AbstractEC;
        user_set::Vector=Vector())

Save base excel file with a summary of the results for the Aggregated Non Cooperative case
"""
function prepare_summary(::AbstractGroupANC, ECModel::AbstractEC; user_set::AbstractVector)
    return prepare_summary(GroupCO(), ECModel; user_set=user_set)
end


"""
    calculate_grid_import(::AbstractGroupANC, ECModel::AbstractEC; per_unit::Bool=true)

Calculate grid usage for the Aggregated Non Cooperative case.
Output is normalized with respect to the demand when per_unit is true
'''
Outputs
-------
grid_frac : DenseAxisArray
    Reliance on the grid demand for each user and the aggregation
'''
"""
function calculate_grid_import(::AbstractGroupANC, ECModel::AbstractEC; per_unit::Bool=true)
    return calculate_grid_import(GroupCO(), ECModel; per_unit=per_unit)
end


"""
    calculate_grid_export(::AbstractGroupANC, ECModel::AbstractEC; per_unit::Bool=true)

Calculate grid export for the Aggregated Non Cooperative case.
Output is normalized with respect to the demand when per_unit is true
'''
Outputs
-------
grid_frac : DenseAxisArray
    Reliance on the grid demand for each user and the aggregation
'''
"""
function calculate_grid_export(::AbstractGroupANC, ECModel::AbstractEC; per_unit::Bool=true)
    return calculate_grid_export(GroupCO(), ECModel; per_unit=per_unit)
end

"""
    calculate_shared_production(::AbstractGroupANC, ECModel::AbstractEC; per_unit::Bool=true, only_shared::Bool=false)

Calculate the shared produced energy for the Aggregated Non Cooperative case.
In this case, there can be shared energy between users, not only self production.
When only_shared is false, also self production is considered, otherwise only shared energy.
Shared energy means energy that is shared between 
Output is normalized with respect to the demand when per_unit is true

'''
Outputs
-------
shared_en_frac : DenseAxisArray
    Shared energy for each user and the aggregation
'''
"""
function calculate_shared_production(::AbstractGroupANC, ECModel::AbstractEC; per_unit::Bool=true, only_shared::Bool=false)
    return calculate_shared_production(GroupCO(), ECModel; per_unit=per_unit, only_shared=only_shared)
end

"""
    calculate_shared_consumption(::AbstractGroupANC, ECModel::AbstractEC; per_unit::Bool=true, only_shared::Bool=false)

Calculate the demand that each user meets using its own sources or other users for the Aggregated Non Cooperative case.
In this case, there can be shared energy, non only self consumption.
When only_shared is false, also self consumption is considered, otherwise only shared energy.
Shared energy means energy that is shared between 
Output is normalized with respect to the demand when per_unit is true

'''
Outputs
-------
shared_cons_frac : DenseAxisArray
    Shared consumption for each user and the aggregation
'''
"""
function calculate_shared_consumption(::AbstractGroupANC, ECModel::AbstractEC; per_unit::Bool=true, only_shared::Bool=false)
    return calculate_shared_consumption(GroupCO(), ECModel; per_unit=per_unit, only_shared=only_shared)    
end

"""
finalize_results!(::AbstractGroupANC, ECModel::AbstractEC)

Function to finalize the results of the Aggregated Non Cooperative model after the execution

"""
function finalize_results!(::AbstractGroupANC, ECModel::AbstractEC)
    
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

    project_lifetime = field(gen_data, "project_lifetime")
    peak_categories = profile(market_data, "peak_categories")

    # Set definitions

    year_set = 1:project_lifetime
    year_set_0 = 0:project_lifetime
    time_set = 1:n_steps
    peak_set = unique(peak_categories)

    # Set definition when optional value is not included
    user_set = ECModel.user_set

    # Power of the aggregator
    ECModel.results[:P_agg] = JuMP.Containers.DenseAxisArray(
        [sum(ECModel.results[:P_us][:, t]) for t in time_set],
        time_set
    )

    # Shared power: the minimum between the supply and demand for each time step
    ECModel.results[:P_shared_agg] = JuMP.Containers.DenseAxisArray(
        [
            min(
                sum(ECModel.results[:P_P_us][:, t]),
                sum(ECModel.results[:P_N_us][:, t])
            )
        for t in time_set],
        time_set
    )

    # Total reward awarded to the community at each time step
    ECModel.results[:R_Reward_agg] = JuMP.Containers.DenseAxisArray(
        [
            profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] *
                profile(market_data, "reward_price")[t] * ECModel.results[:P_shared_agg][t]
        for t in time_set],
        time_set
    )

    # Total reward awarded to the community in a year
    ECModel.results[:R_Reward_agg_tot] = sum(ECModel.results[:R_Reward_agg])


    # Total reward awarded to the aggregator in NPV terms
    ECModel.results[:R_Reward_agg_NPV] = (
        ECModel.results[:R_Reward_agg_tot] * sum(1 / ((1 + field(gen_data, "d_rate"))^y) for y in year_set)
    )


    # Total reward awarded to the aggregator in NPV terms
    ECModel.results[:NPV_agg] = ECModel.results[:R_Reward_agg_NPV]

    
    # Cash flow
    ECModel.results[:Cash_flow_agg] = JuMP.Containers.DenseAxisArray(
        [(y == 0) ? 0.0 : ECModel.results[:R_Reward_agg_tot] for y in year_set_0],
        year_set_0
    )
    
    
    # Cash flow total
    ECModel.results[:Cash_flow_tot] = JuMP.Containers.DenseAxisArray(
        [
            ((y == 0) ? 0.0 : 
                sum(ECModel.results[:Cash_flow_us][y, :]) + ECModel.results[:Cash_flow_agg][y])
            for y in year_set_0
        ],
        year_set_0
    )
    
    # Social welfare of the users
    ECModel.results[:SW_us] = sum(ECModel.results[:NPV_us])

    # Social welfare of the entire aggregation
    ECModel.results[:SW] = ECModel.results[:SW_us] + ECModel.results[:NPV_agg]
    ECModel.results[:objective_value] = ECModel.results[:SW]

end


"""
    to_objective_callback_by_subgroup(::AbstractGroupANC, ECModel::AbstractEC)

Function that returns a callback function that quantifies the objective of a given subgroup of users
The returned function objective_func accepts as arguments an AbstractVector of users and
returns the objective of the aggregation for Aggregated Non Cooperative models

Parameters
----------
ECModel : AbstractEC
    Cooperative EC Model of the EC to study.
    When the model is not cooperative an error is thrown.

Return
------
objective_callback_by_subgroup : Function
    Function that accepts as input an AbstractVector (or Set) of users and returns
    as output the benefit of the specified community
"""
function to_objective_callback_by_subgroup(::AbstractGroupANC, ECModel::AbstractEC; kwargs...)

    # create a backup of the model and work on it
    ecm_copy = deepcopy(ECModel)

    # build the model with the updated set of users
    build_model!(ecm_copy)

    # optimize the model
    optimize!(ecm_copy)

    let ecm_copy=ecm_copy

        # general implementation of objective_callback_by_subgroup
        function objective_callback_by_subgroup(user_set_callback)

            user_set_no_EC = setdiff(user_set_callback, [EC_CODE])

            # check if at least one user is in the list
            if length(user_set_no_EC) > 0

                gen_data = ecm_copy.gen_data
                market_data = ecm_copy.market_data
            
                # get time set
                init_step = field(gen_data, "init_step")
                final_step = field(gen_data, "final_step")
                n_steps = final_step - init_step + 1
                time_set = 1:n_steps
            
                project_lifetime = field(gen_data, "project_lifetime")
            
                # Set definitions
            
                year_set = 1:project_lifetime

                # Shared power for the userset: the minimum between the supply and demand for each time step
                P_shared_coal = JuMP.Containers.DenseAxisArray(
                    [
                        min(
                            sum(ecm_copy.results[:P_P_us][u, t] for u in user_set_no_EC),
                            sum(ecm_copy.results[:P_N_us][u, t] for u in user_set_no_EC)
                        )
                    for t in time_set],
                    time_set
                )

                # Reward awarded to the subcoalition at each time step
                R_Reward_coal = JuMP.Containers.DenseAxisArray(
                    [
                        profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] *
                            profile(market_data, "reward_price")[t] * P_shared_coal[t]
                    for t in time_set],
                    time_set
                )

                # Total reward of the coalition
                R_Reward_tot_coal = sum(R_Reward_coal)

                # Total reward awarded to the aggregator in NPV terms
                R_Reward_agg_NPV = (
                    R_Reward_tot_coal * sum(1 / ((1 + field(gen_data, "d_rate"))^y) for y in year_set)
                )

                # objective of the users
                obj_users = objective_by_user(ecm_copy)

                # Total NPV
                NPV_ANC = sum(obj_users[u] for u in user_set_no_EC) + R_Reward_agg_NPV
                
                # return the objective
                return NPV_ANC
            else
                # otherwise return the null return value as
                # when the aggregator is not available, then no benefit
                # can be achieved                

                return 0.0
            end
        end

        return objective_callback_by_subgroup
    end
end