"""
    to_utility_callback_by_subgroup(ECModel::AbstractEC, base_group_type::AbstractGroup)

Function that returns a callback function that quantifies the benefit of a given subgroup of users
The returned function utility_func accepts as arguments an AbstractVector of users and
returns the benefit with respect to the base case of the users optimized independently

Parameters
----------
ECModel : AbstractEC
    Cooperative EC Model of the EC to study.
    When the model is not cooperative an error is thrown.
base_group_type : AbstractGroup
    Type of the base case to consider
no_aggregator_group : AbstractGroup (otional, default NonCooperative)
    EC group type for when no aggregator is considered

Return
------
utility_callback_by_subgroup : Function
    Function that accepts as input an AbstractVector (or Set) of users and returns
    as output the benefit of the specified community
"""
function to_utility_callback_by_subgroup(
        ECModel::AbstractEC, base_group_type::AbstractGroup;
        no_aggregator_group::AbstractGroup=GroupNC(),
        kwargs...
    )

    ecm_copy=deepcopy(ECModel)
    base_model=ModelEC(ECModel, base_group_type)

    objective_callback_EC = to_objective_callback_by_subgroup(ECModel, no_aggregator_group=no_aggregator_group)
    objective_callback_base = to_objective_callback_by_subgroup(base_model)


    # create a backup of the model and work on it
    let objective_callback_EC=objective_callback_EC, objective_callback_base=objective_callback_base

        # general implementation of utility_callback_by_subgroup
        function utility_callback_by_subgroup(user_set_callback)
            return objective_callback_EC(user_set_callback) - objective_callback_base(user_set_callback)
        end

        return utility_callback_by_subgroup
    end
end


"""
build_base_utility!(ECModel::AbstractEC, base_group::AbstractGroupNC)

When in the CO case the NC model is used as base case,
then this function builds the corresponding constraint

"""
function build_base_utility!(ECModel::AbstractEC, base_group::AbstractGroupNC)
    
    # create and optimize base model
    base_model = ModelEC(ECModel, base_group)
    build_model!(base_model)
    optimize!(base_model)

    # obtain objectives by users
    obj_users = objective_by_user(base_model)
    
    coalition_status = ECModel.model[:coalition_status]

    # define expression of BaseUtility
    @expression(ECModel.model, BaseUtility,
        sum(obj_users[u]*coalition_status[u] for u in ECModel.user_set)
    )

    return BaseUtility
end


"""
build_base_utility!(ECModel::AbstractEC, base_group::AbstractGroupANC)

When in the CO case the ANC model is used as base case,
then this function builds the corresponding constraint

"""
function build_base_utility!(ECModel::AbstractEC, base_group::AbstractGroupANC)
    
    # create and optimize base model
    base_model = ModelEC(ECModel, base_group)
    build_model!(base_model)
    optimize!(base_model)

    # obtain objectives by users
    obj_users = objective_by_user(base_model)

    # get main parameters
    gen_data = ECModel.gen_data
    users_data = ECModel.users_data
    market_data = ECModel.market_data

    n_users = length(users_data)
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    project_lifetime = field(gen_data, "project_lifetime")
    peak_categories = profile(market_data, "peak_categories")

    # Set definitions

    user_set = ECModel.user_set
    year_set = 1:project_lifetime
    year_set_0 = 0:project_lifetime
    time_set = 1:n_steps
    peak_set = unique(peak_categories)

    # define expression of BaseUtility
    @variable(ECModel.model, P_shared_agg_base[t in time_set] >= 0)

    coalition_status = ECModel.model[:coalition_status]
    _P_P_us_base = base_model.results[:P_P_us]
    _P_N_us_base = base_model.results[:P_N_us]

    # Shared energy shall be no greather than the available production
    @constraint(ECModel.model, con_max_P_shared_base[t in time_set],
    P_shared_agg_base[t] <= sum(coalition_status[u] * _P_P_us_base[u, t] for u in user_set)
    )

    # Shared energy shall be no greather than the available consumption
    @constraint(ECModel.model, con_max_N_shared_base[t in time_set],
    P_shared_agg_base[t] <= sum(coalition_status[u] * _P_N_us_base[u, t] for u in user_set)
    )

    # Reward awarded to the subcoalition at each time step
    @expression(ECModel.model, R_Reward_tot_coal,
        sum(GenericAffExpr{Float64,VariableRef}[
                profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] *
                    profile(market_data, "reward_price")[t] * P_shared_agg_base[t]
            for t in time_set
        ])
    )

    # Total reward awarded to the aggregator in NPV terms
    @expression(ECModel.model, R_Reward_agg_NPV_base,
        R_Reward_tot_coal * sum(1 / ((1 + field(gen_data, "d_rate"))^y) for y in year_set)
    )

    # define expression of BaseUtility
    @expression(ECModel.model, BaseUtility,
        sum(obj_users[u]*coalition_status[u] for u in ECModel.user_set) + R_Reward_agg_NPV_base
    )

    return BaseUtility
end


"""
build_no_agg_utility!(ECModel::AbstractEC, no_aggregator_group::AbstractGroupANC)

When in the CO case the ANC model is used as reference case for when the aggregator is not in the group,
then this function builds the corresponding constraint

"""
function build_no_agg_utility!(ECModel::AbstractEC, no_aggregator_group::AbstractGroupANC)
    
    # create and optimize base model
    base_model = ModelEC(ECModel, no_aggregator_group)
    build_model!(base_model)
    optimize!(base_model)

    # obtain objectives by users
    obj_users = objective_by_user(base_model)

    # get main parameters
    gen_data = ECModel.gen_data
    users_data = ECModel.users_data
    market_data = ECModel.market_data

    n_users = length(users_data)
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1
    project_lifetime = field(gen_data, "project_lifetime")
    peak_categories = profile(market_data, "peak_categories")

    # Set definitions

    user_set = ECModel.user_set
    year_set = 1:project_lifetime
    year_set_0 = 0:project_lifetime
    time_set = 1:n_steps
    peak_set = unique(peak_categories)

    # define expression of BaseUtility
    @variable(ECModel.model, P_shared_noagg_agg[t in time_set] >= 0)

    coalition_status = ECModel.model[:coalition_status]
    _P_P_us_base = base_model.results[:P_P_us]
    _P_N_us_base = base_model.results[:P_N_us]

    # Shared energy shall be no greather than the available production
    @constraint(ECModel.model, con_max_P_shared_noagg[t in time_set],
        P_shared_noagg_agg[t] <= sum(coalition_status[u] * _P_P_us_base[u, t] for u in user_set)
    )

    # Shared energy shall be no greather than the available consumption
    @constraint(ECModel.model, con_max_N_shared_noagg[t in time_set],
        P_shared_noagg_agg[t] <= sum(coalition_status[u] * _P_N_us_base[u, t] for u in user_set)
    )

    # Shared energy in ANC mode shall non-zero only when the aggregator is not selected
    @constraint(ECModel.model, con_max_shared_WHENNC_noagg[t in time_set],
        P_shared_noagg_agg[t] <= (1 - coalition_status[EC_CODE]) * min(sum(_P_N_us_base[:, t]), sum(_P_P_us_base[:, t]))
    )

    # Reward awarded to the subcoalition at each time step
    @expression(ECModel.model, R_Reward_tot_coal_noagg,
        sum(GenericAffExpr{Float64,VariableRef}[
                profile(market_data, "energy_weight")[t] * profile(market_data, "time_res")[t] *
                    profile(market_data, "reward_price")[t] * P_shared_noagg_agg[t]
            for t in time_set
        ])
    )

    # Total reward awarded to the aggregator in NPV terms
    @expression(ECModel.model, R_Reward_agg_NPV_noagg,
        R_Reward_tot_coal_noagg * sum(1 / ((1 + field(gen_data, "d_rate"))^y) for y in year_set)
    )

    # update social welfare value
    add_to_expression!(ECModel.model[:SW], R_Reward_agg_NPV_noagg)

    return ECModel.model[:SW]
end


"""
build_no_agg_utility!(ECModel::AbstractEC, no_aggregator_group::AbstractGroupNC)

When the NC case is the reference value when no aggregator is available,
then no changes in the model are required

"""
function build_no_agg_utility!(ECModel::AbstractEC, no_aggregator_group::AbstractGroupNC)
    return ECModel.model[:SW]
end


"""
build_no_agg_utility!(ECModel::AbstractEC, no_aggregator_group::Any)

Not implemented case

"""
function build_no_agg_utility!(ECModel::AbstractEC, no_aggregator_group::Any)
    return throw(ArgumentError("Argument $(string(no_aggregator_group)) not valid"))
end


"""
build_base_utility!(ECModel::AbstractEC, no_aggregator_group::AbstractGroupANC)

When in the CO case the ANC model is used as reference case for when the aggregator is not in the group,
then this function builds the corresponding constraint

"""
function build_base_utility!(ECModel::AbstractEC, kwargs...)
    return throw(ArgumentError("Model type $(string(typeof(no_aggregator_group))) not implemented"))
end


"""
build_least_profitable!(ECModel::AbstractEC; no_aggregator_group::AbstractGroup=GroupNC(), add_EC=true)

Function to build the model to identify the least profitable coalition
"""
function build_least_profitable!(
        ECModel::AbstractEC, base_group::AbstractGroup;
        no_aggregator_group::AbstractGroup=GroupNC(),
        add_EC=true,
        relax_combinatorial=false,
        use_notations=false,
    )
    
    # list of variables to modify
    list_vars = [:E_batt_us, :P_conv_P_us, :P_conv_N_us, :P_ren_us, :P_max_us, :P_P_us, :P_N_us, :x_us]
    # list of constraints to modify
    list_cons = [:con_us_balance]
    # list of expressions to modify
    list_exprs = []  # [:R_Energy_us]

    # get main parameters
    gen_data = ECModel.gen_data
    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1

    # Set definitions
    time_set = 1:n_steps

    # build model
    build_model!(ECModel; use_notations=use_notations)

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
    @variable(
        ECModel.model,
        coalition_status[user_set_EC],
        set = (relax_combinatorial==false ? MOI.ZeroOne() : MOI.Semicontinuous(0.0, 1.0)),
    )
    

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

    # change expressions constantss
    for expr in list_exprs
        build_nullify_expr_by_binary!(ECModel.model[expr], coalition_status)
    end

    # remove the grand coalition from the analysis
    @constraint(ECModel.model, exclude_grand_coalition,
        sum(coalition_status) <= length(user_set_EC) - 1
    )

    # assure at least a user to be in the coalition
    @constraint(ECModel.model, exclude_null_coalition,
        sum(coalition_status) >= 1.0
    )

    # test_coalition = ["EC", "user1", "user2", "user3", "user4"]

    # # remove keep only selected users
    # @constraint(ECModel.model, keep_grand_coalition[i=user_set_EC],
    #     coalition_status[i] == ((i in test_coalition) ? 1.0 : 0.0)
    # )

    # change expression of SW
    for u in ECModel.user_set
        # get the constant value
        coeff = constant(ECModel.model[:NPV_us][u])
        
        # change expression to add the constant only when the corresponding binary is enabled
        add_to_expression!(ECModel.model[:SW], coeff * coalition_status[u] - coeff)
        add_to_expression!(ECModel.model[:NPV_us][u], coeff * coalition_status[u] - coeff)
    end

    # define expression of BaseUtility
    BaseUtility = build_base_utility!(ECModel, base_group)

    # update social welfare to account for the expected output when no aggregator is included
    SW = build_no_agg_utility!(ECModel, no_aggregator_group)

    # definition of the minimum surplus
    @expression(ECModel.model, coalition_benefit,
        SW - BaseUtility
    )

    # Force shared energy to zero when aggregator is not selected
    @constraint(ECModel.model, con_max_shared[t in time_set],
        ECModel.model[:P_shared_agg][t] <= coalition_status[EC_CODE] * min(
                sum(upper_bound.(ECModel.model[:P_N_us][:, t])),
                sum(upper_bound.(ECModel.model[:P_P_us][:, t]))
            )
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

"Get variables related to the user u_name for a DenseAxisArray"
function get_subproblem_vars_by_user(var::Containers.DenseAxisArray{T}, u_name) where T <: VariableRef
    list_axes = axes(var)

    if length(list_axes) == 1
        return T[var[u_name]]
    else
        return vec(T[var[k...] for k in Iterators.product([u_name], list_axes[2:end]...)])
    end
end

"Get variables related to the user u_name for a SparseAxisArray"
function get_subproblem_vars_by_user(var::Containers.SparseAxisArray{T}, u_name) where T <: VariableRef
    key_set = eachindex(var)
    
    return T[var[k...] for k in key_set if k[1] == u_name]
end

"Get annotations for Benders decomposition"
function get_annotations(ECModel::AbstractEC)
    variable_annotations = Dict{Int, Vector{VariableRef}}()
    
    # Master problem
    variable_annotations[0] = [
        vec(ECModel.model[:coalition_status].data);  # coaliion status
        vec(ECModel.model[:P_shared_agg].data);  # shared energy
        vec(ECModel.model[:P_agg].data);  # dispatch of the aggregation
        ECModel.model[:NPV_agg];  # obj value of the coalition
        vec(ECModel.model[:P_P_us].data);  # energy supplied by users
        vec(ECModel.model[:P_N_us].data);  # energy bought by users
    ]

    # variables by users: one subproblem for every user
    list_user_vars = [:E_batt_us, :P_conv_P_us, :P_conv_N_us, :P_ren_us, :P_max_us, :x_us]
    for (u_id, u_name) in enumerate(get_user_set(ECModel))
        variable_annotations[u_id] = vcat([
            get_subproblem_vars_by_user(ECModel.model[var], u_name) for var in list_user_vars
        ]...)
    end

    # # Master problem: only binaries
    # variable_annotations[0] = vec(ECModel.model[:coalition_status].data)  #coalition status (binaries)

    # # Lower problem: all the rest
    # list_sub_vars = [
    #     :P_P_us, :P_N_us, :P_agg, :P_shared_agg, :E_batt_us, :P_conv_P_us, :P_conv_N_us, :P_ren_us, :P_max_us, :x_us
    # ]
    # variable_annotations[1] = [
    #     ECModel.model[:NPV_agg];  # obj value of the coalition
    #     vcat([vec(collect(values(ECModel.model[var_symb].data))) for var_symb in list_sub_vars]...);
    # ]

    return variable_annotations
end

"General fallback"
function add_notations!(ECModel::AbstractEC, ::Any)
    @warn "Annotations not supported for the current solver; annotations are ignored"
    return
end

try

    """
        Add notations for CPLEX backend
    """
    function add_notations!(ECModel::AbstractEC, ::Type{CPLEX.Optimizer})

        model = ECModel.model

        variable_classification = get_annotations(ECModel)

        num_variables = sum(length(it) for it in values(variable_classification))
        if num_variables != JuMP.num_variables(model)
            @warn "Annotation for $num_variables out of the total $(JuMP.num_variables(model)) variables"
        end
        indices, annotations = CPLEX.CPXINT[], CPLEX.CPXLONG[]
        for (key, value) in variable_classification
            indices_value = map(x->CPLEX.CPXINT(x.index.value-1), value)
            append!(indices, indices_value)
            append!(annotations, fill(CPLEX.CPXLONG(CPLEX.CPX_BENDERS_MASTERVALUE + key), length(indices_value)))
        end
        cplex = JuMP.backend(model)
        index_p = Ref{CPLEX.CPXINT}()
        CPLEX.CPXnewlongannotation(
            cplex.env,
            cplex.lp,
            CPLEX.CPX_BENDERS_ANNOTATION,
            CPLEX.CPX_BENDERS_MASTERVALUE,
        )
        CPLEX.CPXgetlongannotationindex(
            cplex.env,
            cplex.lp,
            CPLEX.CPX_BENDERS_ANNOTATION,
            index_p,
        )
        CPLEX.CPXsetlongannotations(
            cplex.env,
            cplex.lp,
            index_p[],
            CPLEX.CPX_ANNOTATIONOBJ_COL,
            length(indices),
            indices,
            annotations,
        )
        return
    end
catch e
    @warn "Notation by CPLEX are not enabled"
end


"""
    to_least_profitable_coalition_callback(ECModel::AbstractEC, base_group::AbstractGroup=GroupNC(); no_aggregator_group::AbstractGroup=GroupNC())

Function that returns a callback function that, given as input a profit distribution scheme,
returns the coalition that has the least benefit in remaining in the grand coalition.
The returned function least_profitable_coalition_callback accepts an AbstractDict as argument
that specifies the profit distribution by user that is used to compute the least benefit procedure.

Parameters
----------
ECModel : AbstractEC
    Cooperative EC Model of the EC to study.
    When the model is not cooperative an error is thrown.
base_group : AbstractGroup (optional, default GroupNC())
    Base group with respect the benefit is calculated.
no_aggregator_group : AbstractGroup (optional, default GroupNC())
    Type of aggregation group of the community when no aggregator is available
    When not provided, an equivalent NonCooperative model is created and the corresponding
    utilities by user are used as reference case.
number_of_solutions : (optional, default 1)
    Number of solutions to be returned at every iteration
    number_of_solutions <= 0: all solutions are returned
    number_of_solutions >= 1: specific number of solutions are returned
relax_combinatorial : (optional, default false)
    When true, the full least profitable coalition MILP problem is relaxed to continuous,
    in the combinatorial part
direct_model : (optional, default false)
    When true the JuMP model is direct
callback_solution : Dict (optional, default empty)
    Dictionary of callbacks depending on the termination status of the optimization.
    Keys shall be of type JuMP.TerminationStatusCode, and outputs a function with as argument a ModelEC

Return
------
least_profitable_coalition_callback : Function
    Function that accepts as input an AbstractDict representing the benefit distribution
    by user
"""
function to_least_profitable_coalition_callback(
        ECModel::AbstractEC,
        base_group::AbstractGroup;
        no_aggregator_group::AbstractGroup=GroupNC(),
        optimizer=nothing,
        raw_outputs=false,
        number_of_solutions=1,
        relax_combinatorial=false,
        use_notations=false,
        callback_solution=Dict(),
        kwargs...
    )

    if typeof(ECModel.group_type) <: AbstractGroupNC
        # When a Non Cooperative method is given, no benefits are generated for the community
        throw(ArgumentError("Expected a Cooperative Community as input"))
        return nothing
    end

    # create a bakup of the model to work with
    ecm_copy = ModelEC(ECModel; optimizer=optimizer)

    # build the model in the backup variable ecm_copy
    build_least_profitable!(
        ecm_copy,
        base_group;
        no_aggregator_group=no_aggregator_group,
        add_EC=true,
        relax_combinatorial=relax_combinatorial,
        use_notations=use_notations,
    )

    if use_notations
        if isnothing(optimizer)
            @error "Customer optimizer shall be specified when notations are enabled"
        end

        optimizer_constructor = (isa(optimizer, MOI.OptimizerWithAttributes) ? optimizer.optimizer_constructor : optimizer)

        add_notations!(ecm_copy, optimizer_constructor)
    end

    # create a backup of the model and work on it
    let ecm_copy=ecm_copy, number_of_solutions=number_of_solutions, callback_solution=callback_solution

        # general implementation of utility_callback_by_subgroup
        """
            least_profitable_coalition_callback(profit_distribution)
        Callback function that, given a profit distribution scheme by user,
        returns the worst coalition and its total benefit with respect to base case

        Parameters
        ----------
        profit_distribution : AbstractDict
            Dictionary of profit distribution by user
        modify_solver_options : Vector{Pair} (optional)
            Vector of the pairs of solver options to set or modify

        Returns
        -------
        least_profitable_coalition : Vector{NamedTuple}
            Vector of NamedTuple with the components of the coalition leading to the worst benefit,
            given the current distribution scheme.
            Each NamedTuple has the following fields of the vector entry o:
            - least_profitable_coalition_status: vector specifying whether each user 
              belongs (1) or not (0) to the worst coalition
            - least_profitable_coalition: members of the worst coalition, for result o
            - coalition_benefit: benefit of the coalition, for result o
            - min_surplus: minimum surplus of the coalition, for result o

        """
        function least_profitable_coalition_callback(
                profit_distribution;
                modify_solver_options::Vector=[],
                kwargs...
            )
            
            # change the profit distribution
            set_least_profitable_profit!(ecm_copy, profit_distribution)

            # change solver attributes
            for opt in modify_solver_options
                set_optimizer_attribute(ecm_copy.model, opt.first, opt.second)
            end

            # optimize the problem
            optimize!(ecm_copy)

            # postprocess result by termination status
            t_status = termination_status(EC_CODE)
            if t_status in keys(callback_solution)
                callback_solution[t_status](ecm_copy)
            end

            user_set_tot = axes(ecm_copy.results[:profit_distribution])[1]

            # number of results of the current iteration
            n_results = result_count(ecm_copy)
            # number of outputs to return
            n_outputs = (number_of_solutions <= 0) ? n_results : number_of_solutions

            output_data = Vector{NamedTuple}(undef, n_outputs)

            for o = 1:n_outputs

                # get the coalition status
                coalition_status = value.(ecm_copy.model[:coalition_status], result=o)

                # define the set of the least profitable coalition
                least_profitable_coalition = [
                    u for u in user_set_tot if coalition_status[u] >= 0.5
                ]

                # get the benefit of the coalition
                coalition_benefit = value(ecm_copy.model[:coalition_benefit], result=o)

                # get minimum surplus of the coalition
                min_surplus = objective_value(ecm_copy.model, result=o)

                output_data[o] = (
                    least_profitable_coalition_status=coalition_status,
                    least_profitable_coalition=least_profitable_coalition,
                    coalition_benefit=coalition_benefit,
                    min_surplus=min_surplus,
                )

            end
            
            return output_data
        end

        if raw_outputs
            return least_profitable_coalition_callback, ecm_copy
        else
            return least_profitable_coalition_callback
        end
    end
end


"""
    IterMode(ECModel::AbstractEC, base_group_type::AbstractGroup)

Function to create the IterMode item for the Games.jl package 
"""
function Games.IterMode(
        ECModel::AbstractEC,
        base_group_type::AbstractGroup; 
        no_aggregator_type::AbstractGroup=GroupNC(),
        optimizer=nothing,
        number_of_solutions=0,
        use_notations=false,
        kwargs...
    )
    utility_callback = to_utility_callback_by_subgroup(ECModel, base_group_type; no_aggregator_type=no_aggregator_type, kwargs...)
    worst_coalition_callback = to_least_profitable_coalition_callback(ECModel, base_group_type; no_aggregator_type=no_aggregator_type, optimizer=optimizer, number_of_solutions=number_of_solutions, use_notations=use_notations, kwargs...)

    robust_mode = Games.IterMode([EC_CODE; ECModel.user_set], utility_callback, worst_coalition_callback)

    return robust_mode
end


"""
    EnumMode(ECModel::AbstractEC)

Function to create the EnumMode item for the Games.jl package 
"""
function Games.EnumMode(ECModel::AbstractEC, base_group::AbstractGroup; verbose::Bool=true, kwargs...)
    utility_callback = to_utility_callback_by_subgroup(ECModel, base_group; kwargs...)

    enum_mode = Games.EnumMode([EC_CODE; ECModel.user_set], utility_callback; verbose=verbose)

    return enum_mode
end