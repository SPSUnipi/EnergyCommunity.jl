"""
    to_utility_callback_by_subgroup(ECModel::AbstractEC; BaseUtility::AbstractDict=Dict())

Function that returns a callback function that quantifies the benefit of a given subgroup of users
The returned function utility_func accepts as arguments an AbstractVector of users and
returns the benefit with respect to the base case of the users optimized independently

Parameters
----------
ECModel : AbstractEC
    Cooperative EC Model of the EC to study.
    When the model is not cooperative an error is thrown.
BaseUtility : AbstractDict (optional empty)
    Base case utility for each user.
    When not provided, an equivalent NonCooperative model is created and the corresponding
    utilities by user are used as reference case.

Return
------
utility_callback_by_subgroup : Function
    Function that accepts as input an AbstractVector (or Set) of users and returns
    as output the benefit of the specified community
"""
function to_utility_callback_by_subgroup(ECModel::AbstractEC; BaseUtility::AbstractDict=Dict())

    if typeof(ECModel.group_type) <: AbstractGroupNC
        # When a Non Cooperative method is given, no benefits are generated for the community
        let ret_value = ret_value
            return (uset) -> 0.0
        end
    end

    if isempty(BaseUtility)
        # if the reference utility is empty, then calculated it as a NonCooperative model

        # create NonCooperative model
        NCModel = ModelEC(ECModel, GroupNC())

        # build the model with the updated set of users
        build_model!(NCModel)

        # optimize the model
        optimize!(NCModel)

        # update base utility
        BaseUtility = objective_by_user(NCModel)
    end

    # create a backup of the model and work on it
    let ecm_copy = ModelEC(ECModel, GroupCO()), BaseUtility=BaseUtility

        # general implementation of utility_callback_by_subgroup
        function utility_callback_by_subgroup(user_set_callback; BaseUtility=BaseUtility)

            user_set_no_EC = setdiff(user_set_callback, [EC_CODE])

            # check if the EC is in the list and if at least two users are in the set
            if ((EC_CODE in user_set_callback) && length(user_set_no_EC) > 1)
                # if it is in the code, then execute the normal model

                # change the set of the EC
                set_user_set!(ecm_copy, user_set_no_EC)

                # build the model with the updated set of users
                build_model!(ecm_copy)

                # optimize the model
                optimize!(ecm_copy)

                # get base utility by base model
                base_utility = sum(Float64[
                    BaseUtility[uname] for uname in user_set_no_EC
                ])

                # coalition benefit
                utility_coal = objective_function(ecm_copy) - base_utility

                # return the coalition benefit
                return utility_coal
            else
                # otherwise return the null return value as
                # when the aggregator is not available, then no benefit
                # can be achieved                

                return 0.0
            end
        end

        return utility_callback_by_subgroup
    end
end



"""
build_least_profitable!(ECModel::AbstractEC; add_EC=true)

Function to build the model to identify the least profitable coalition
"""
function build_least_profitable!(ECModel::AbstractEC, BaseUtility; add_EC=true)
    
    # list of variables to modify
    list_vars = [:E_batt_us, :P_conv_P_us, :P_conv_N_us, :P_ren_us, :P_max_us, :P_P_us, :P_N_us, :x_us]
    # list of constraints to modify
    list_cons = [:con_us_balance]
    # list of expressions to modify
    list_exprs = []  # [:R_Energy_us]

    # build model
    build_model!(ECModel)

    # create list of users including EC if edd_EC is enabled
    user_set_EC = ECModel.user_set
    if add_EC
        user_set_EC = unique([EC_CODE; user_set_EC])
    end

    function build_nullify_var_by_binary!(m::Model, var::Containers.DenseAxisArray{T}, binary_var) where T <: VariableRef
        list_axes = axes(var)
        key_set = product(list_axes...)

        # the first index of each key_set must belong to user_set
        @constraint(m, [k=key_set], var[k...] <= upper_bound(var[k...]) * binary_var[k[1]])
    end

    function build_nullify_var_by_binary!(m::Model, var::Containers.SparseAxisArray{T}, binary_var) where T <: VariableRef
        key_set = eachindex(var)
        
        # the first index of each key_set must belong to user_set
        @constraint(m, [k in key_set], var[k...] <= upper_bound(var[k...]) * binary_var[k[1]])
    end

    function build_nullify_con_by_binary!(con::Containers.DenseAxisArray{T}, binary_var) where T <: ConstraintRef
        list_axes = axes(con)
        key_set = product(list_axes...)

        for k in key_set
            # get the rhs
            coeff = normalized_rhs(con[k...])
            # change that rhs to coefficient for the binary variable with opposite sign
            # since it change position
            set_normalized_coefficient(con[k...], binary_var[k[1]], -coeff)
            # reset the coefficient for the constraint
            set_normalized_rhs(con[k...], 0.0)
        end
    end

    function build_nullify_expr_by_binary!(expr::Containers.DenseAxisArray{T}, binary_var) where T <: AffExpr
        list_axes = axes(expr)
        key_set = product(list_axes...)

        for k in key_set
            # get the constant value
            coeff = constant(expr[k...])

            # change expression to add the constant only when the corresponding binary is enabled
            add_to_expression!(expr[k...], coeff * binary_var[k[1]] - coeff)
        end
    end

    # create binary variable that identifies the status of what users are considered
    @variable(ECModel.model, coalition_status[user_set_EC], Bin)
    # auxiliary variable used to fix the profit distribution using the fix function
    @expression(ECModel.model, profit_distribution[user_set_EC], 0.0)

    # set constraint to set variables to zero when user not selected
    for var in list_vars
        build_nullify_var_by_binary!(ECModel.model, ECModel.model[var], coalition_status)
    end

    # change constraint for non-zero equality constraints
    for con in list_cons
        build_nullify_con_by_binary!(ECModel.model[con], coalition_status)
    end

    # # change expressions constantss
    # for expr in list_exprs
    #     build_nullify_expr_by_binary!(ECModel.model[expr], coalition_status)
    # end

    # # remove the grand coalition from the analysis
    # @constraint(ECModel.model, exclude_grand_coalition,
    #     sum(coalition_status) <= length(ECModel.user_set) - 1
    # )

    # # remove keep only selected users
    # @constraint(ECModel.model, exclude_grand_coalition[i=["EC",  "user2"]],
    # coalition_status[i] <= 0.0
    # )

    # # remove keep only selected users
    # @constraint(ECModel.model, keep_grand_coalition[i=["user3"]],
    #     coalition_status[i] >= 1.0
    # )

    # # change expression of SW
    # for u in ECModel.user_set
    #     # get the constant value
    #     coeff = constant(ECModel.model[:NPV_us][u])
    #     println("NPV_us coeff $u: ", coeff)
    #     # change expression to add the constant only when the corresponding binary is enabled
    #     add_to_expression!(ECModel.model[:SW], coeff * coalition_status[u] - coeff)
    #     add_to_expression!(ECModel.model[:NPV_us][u], coeff * coalition_status[u] - coeff)
    # end

    # define expression of BaseUtility
    @expression(ECModel.model, BaseUtility[u in user_set_EC],
        BaseUtility[u]
    )

    # definition of the minimum surplus
    @expression(ECModel.model, coalition_benefit,
        ECModel.model[:SW] - sum(BaseUtility[u]*coalition_status[u] for u in user_set_EC)
    )

    # change objective to the minimum surplus
    @objective(ECModel.model, Min, sum(profit_distribution[u]*coalition_status[u] for u in user_set_EC) - coalition_benefit)

end


"""
set_least_profitable_profit!(ECModel::AbstractEC, profit_distribution)

Function to set the profit distribution of the least profitable problem

Parameters
----------
ECModel : ModelEC
    Model of the community
profit_distribution : AbstractDict
    Profit distribution per user
"""
function set_least_profitable_profit!(ECModel::AbstractEC, profit_distribution)

    coalition_status = ECModel.model[:coalition_status]  # coalition_status variable
    pre_profit_distribution = ECModel.model[:profit_distribution]  # current profit distribution
    dist_set = axes(pre_profit_distribution)[1]
    for i in dist_set
        coeff = coefficient(objective_function(ECModel.model), coalition_status[i])
        
        # change the objective value
        set_objective_coefficient(ECModel.model, coalition_status[i], coeff + profit_distribution[i] - pre_profit_distribution[i])
        # change the current profit distribution stored in the model
        pre_profit_distribution[i] = profit_distribution[i]
    end
end




"""
    to_least_profitable_coalition_callback(ECModel::AbstractEC; BaseUtility::AbstractDict=Dict())

Function that returns a callback function that, given as input a profit distribution scheme,
returns the coalition that has the least benefit in remaining in the grand coalition.
The returned function least_profitable_coalition_callback accepts an AbstractDict as argument
that specifies the profit distribution by user that is used to compute the least benefit procedure.

Parameters
----------
ECModel : AbstractEC
    Cooperative EC Model of the EC to study.
    When the model is not cooperative an error is thrown.
BaseUtility : AbstractDict (optional empty)
    Base case utility for each user.
    When not provided, an equivalent NonCooperative model is created and the corresponding
    utilities by user are used as reference case.

Return
------
least_profitable_coalition_callback : Function
    Function that accepts as input an AbstractDict representing the benefit distribution
    by user
"""
function to_least_profitable_coalition_callback(ECModel::AbstractEC; BaseUtility::AbstractDict=Dict())

    if typeof(ECModel.group_type) <: AbstractGroupNC
        # When a Non Cooperative method is given, no benefits are generated for the community
        throw(ArgumentError("Expected a Cooperative Community as input"))
        return nothing
    end

    if isempty(BaseUtility)
        # if the reference utility is empty, then calculated it as a NonCooperative model

        # create NonCooperative model
        NCModel = ModelEC(ECModel, GroupNC())

        # build the model with the updated set of users
        build_model!(NCModel)

        # optimize the model
        optimize!(NCModel)

        # update base utility
        BaseUtility = objective_by_user(NCModel)
    end

    # create the model to work with
    ecm_copy = ModelEC(ECModel, GroupCO())
    build_least_profitable!(ecm_copy, BaseUtility)

    # create a backup of the model and work on it
    let ecm_copy = ecm_copy

        # general implementation of utility_callback_by_subgroup
        """
            least_profitable_coalition_callback(profit_distribution)
        Callback function that, given a profit distribution scheme by user,
        returns the worst coalition and its total benefit with respect to base case

        Parameters
        ----------
        profit_distribution : AbstractDict
            Dictionary of profit distribution by user

        Returns
        -------
        least_profitable_coalition : AbstractVector
            Vector of the components of the coalition leading to the worst benefit,
            given the current distribution scheme
        coalition_benefit : Number
            Total benefit of the least_profitable_coalition with respect to base case,
            described by the argument BaseUtility

        """
        function least_profitable_coalition_callback(profit_distribution)
            
            # change the profit distribution
            set_least_profitable_profit!(ecm_copy, profit_distribution)

            # optimize the problem
            optimize!(ecm_copy)

            user_set_tot = axes(ecm_copy.results[:profit_distribution])[1]

            # define the set of the least profitable coalition
            least_profitable_coalition = [
                u for u in user_set_tot if ecm_copy.results[:coalition_status][u] >= 0.5
            ]

            # get the benefit of the coalition
            coalition_benefit = ecm_copy.results[:coalition_benefit]

            # get minimum surplus of the coalition
            min_surplus = objective_value(ecm_copy)
            
            return least_profitable_coalition, coalition_benefit, min_surplus
        end

        return least_profitable_coalition_callback, ecm_copy
    end
end