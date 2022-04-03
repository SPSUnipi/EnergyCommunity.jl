"""
    to_utility_callback_by_subgroup(ECModel::AbstractEC, BaseUtility::AbstractDict=Dict())

Function that returns a function that quantifies the benefit of a given subgroup of users
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
function to_utility_callback_by_subgroup(ECModel::AbstractEC, BaseUtility::AbstractDict=Dict())

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
    let ecm_copy = deepcopy(ECModel), BaseUtility=BaseUtility

        # general implementation of utility_callback_by_subgroup
        function utility_callback_by_subgroup(user_set_callback)

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