"""
    calculate_energy_ratios(users_data, _P_ren_us, user_agg_set, agg_id, time_set, _P_tot_us, _x_us)

Calculate energy ratios
'''
# Outputs
- PV_frac
- PV_frac_tot
- wind_frac
- wind_frac_tot
'''
"""
function calculate_energy_ratios(users_data, user_agg_set, agg_id, time_set, _P_ren_us, _P_tot_us, _x_us)

    user_set = setdiff(user_agg_set, agg_id)

    # PV fraction of the aggregate case noagg
    PV_frac_tot =
        sum((length(users_data[u].asset_type) == 0 ||
            !any(a_type == REN for (name, a_type) in users_data[u].asset_type)) ? 0.0 :
            (_P_ren_us[u,t] <= 0) ? 0.0 :
                _P_ren_us[u,t] * sum(
                    Float64[users_data[u].ren_pu[pv][t] * _x_us[u,pv]
                    for pv in users_data[u].asset_names if occursin("pv", pv)]) / sum(
                        users_data[u].ren_pu[r][t] * _x_us[u,r]
                        for r in users_data[u].asset_names if users_data[u].asset_type[r] == REN
                )
            for u in user_set, t in time_set) / sum(users_data[u].load[t] for u in user_set, t in time_set)

    # fraction of PV production with respect to demand by user (agg) noagg case
    PV_frac = JuMP.Containers.DenseAxisArray(
        vcat(
            PV_frac_tot,
            [(length(users_data[u].asset_type) == 0 ||
                !any(a_type == REN for (name, a_type) in users_data[u].asset_type)) ? 0.0 :
                sum((_P_ren_us[u,t] <= 0) ? 0.0 :
                    _P_ren_us[u,t] * sum(
                        Float64[users_data[u].ren_pu[pv][t] * _x_us[u,pv]
                        for pv in users_data[u].asset_names if occursin("pv", pv)]) / sum(
                            users_data[u].ren_pu[r][t] * _x_us[u,r]
                            for r in users_data[u].asset_names if users_data[u].asset_type[r] == REN
                    )
                for t in time_set) / sum(users_data[u].load[t] for t in time_set) for u in user_set]
            )
        , user_agg_set)

    # wind fraction of the aggregate case noagg
    wind_frac_tot =
        sum((length(users_data[u].asset_type) == 0 ||
            !any(a_type == REN for (name, a_type) in users_data[u].asset_type)) ? 0.0 :
            (_P_ren_us[u,t] <= 0) ? 0.0 :
                _P_ren_us[u,t] * sum(
                    Float64[users_data[u].ren_pu[w][t] * _x_us[u,w]
                    for w in users_data[u].asset_names if occursin("wind", w)]) / sum(
                        users_data[u].ren_pu[r][t] * _x_us[u,r]
                        for r in users_data[u].asset_names if users_data[u].asset_type[r] == REN
                )
            for u in user_set, t in time_set) / sum(users_data[u].load[t] for u in user_set, t in time_set)

    # fraction of wind production with respect to demand by user (agg)noagg case
    wind_frac = JuMP.Containers.DenseAxisArray(
        vcat(
            wind_frac_tot,
            [(length(users_data[u].asset_type) == 0 ||
                    !any(a_type == REN for (name, a_type) in users_data[u].asset_type)) ? 0.0 :
                    sum((_P_ren_us[u,t] <= 0) ? 0.0 :
                        _P_ren_us[u,t] * sum(
                            Float64[users_data[u].ren_pu[pv][t] * _x_us[u,pv]
                            for pv in users_data[u].asset_names if occursin("wind", pv)]) / sum(
                                users_data[u].ren_pu[r][t] * _x_us[u,r]
                                for r in users_data[u].asset_names if users_data[u].asset_type[r] == REN
                        )
                    for t in time_set) / sum(users_data[u].load[t] for t in time_set) for u in user_set]
            ),
        user_agg_set)

    return PV_frac, wind_frac
end


"""
    calculate_grid_ratios_noagg(users_data, user_agg_set, agg_id, time_set, _P_tot_us_noagg)

Calculate energy ratios
'''
# Outputs
- grid_frac_noagg
- grid_frac_tot_noagg
'''
"""
function calculate_grid_ratios_noagg(users_data, user_agg_set, agg_id, time_set, _P_tot_us_noagg)

    user_set = setdiff(user_agg_set, agg_id)

    # fraction of grid resiliance of the aggregate case noagg
    grid_frac_tot_noagg = sum(max(-_P_tot_us_noagg[u,t], 0) for u in user_set, t in time_set)/
        sum(users_data[u].load[t] for u in user_set, t in time_set)

    # fraction of grid reliance with respect to demand by user noagg case
    grid_frac_noagg = JuMP.Containers.DenseAxisArray(
        vcat(
            grid_frac_tot_noagg,
            [sum(max(-_P_tot_us_noagg[u,t], 0) for t in time_set)/sum(users_data[u].load[t] for t in time_set)
                for u in user_set]
        ),
        user_agg_set
    )

    return grid_frac_noagg
end

"""
    calculate_grid_ratios_noagg(users_data, user_agg_set, agg_id, time_set, _P_tot_us_agg)

Calculate energy ratios
'''
# Outputs
- grid_frac_agg
- grid_frac_tot_agg
'''
"""
function calculate_grid_ratios_agg(users_data, user_agg_set, agg_id, time_set, _P_tot_us_agg)

    user_set = setdiff(user_agg_set, agg_id)

    # fraction of grid reliance with respect to demand of the aggregate agg case
    grid_frac_tot_agg = sum(max(-sum(_P_tot_us_agg[u,t] for u in user_set), 0) for t in time_set)/
        sum(users_data[u].load[t] for u in user_set, t in time_set)

    # fraction of grid reliance with respect to demand by user agg case
    grid_frac_agg = JuMP.Containers.DenseAxisArray(
        vcat(
            grid_frac_tot_agg,
            [sum(max(-_P_tot_us_agg[u,t], 0) for t in time_set)/
                sum(users_data[u].load[t] for t in time_set)
                for u in user_set]
        ),
        user_agg_set
    )

    return grid_frac_agg
end


"""
    calculate_shared_energy(users_data, user_agg_set, agg_id, time_set,
        _P_ren_us, _P_tot_us, shared_en_frac, shared_cons_frac)

Calculate the shared produced energy (en) and the shared consumption (cons) ratios

'''
# Outputs
- shared_en_frac_us_agg
- shared_en_tot_frac_agg
- shared_cons_frac_us_agg
- shared_cons_tot_frac_agg
'''
"""
function calculate_shared_energy_agg(users_data, user_agg_set, agg_id, time_set,
        _P_tot_us_agg, _P_ren_us_agg)

    # total sum of power sold by users in agg case
    _P_tot_P_sum_us_agg = JuMP.Containers.DenseAxisArray(
        [sum(max(_P_tot_us_agg[u,t], 0) for u in user_set) for t in time_set], time_set
    )
    # total sum of power bought by users in agg case
    _P_tot_N_sum_us_agg = JuMP.Containers.DenseAxisArray(
        [sum(max(-_P_tot_us_agg[u,t], 0) for u in user_set) for t in time_set], time_set
    )

    # fraction of shared energy with respect to total sold energy by users in the agg case
    shared_en_frac_agg = JuMP.Containers.DenseAxisArray(
        [(_P_tot_P_sum_us_agg[t] > 0) ? (_P_tot_P_sum_us_agg[t] - max(sum(_P_tot_us_agg[u,t] for u in user_set), 0)
            )/_P_tot_P_sum_us_agg[t] : 0.0 for t in time_set],
        time_set
    )

    # fraction of shared consumption with respect to total bought energy by users in the agg case
    shared_cons_frac_agg = JuMP.Containers.DenseAxisArray(
        [(_P_tot_N_sum_us_agg[t] > 0) ? (_P_tot_P_sum_us_agg[t] - max(sum(_P_tot_us_agg[u,t] for u in user_set), 0)
            )/_P_tot_N_sum_us_agg[t] : 0.0 for t in time_set],
        time_set
    )

    # fraction of energy share reliance with respect to demand by user aggnoagg case
    shared_en_tot_frac_agg = sum(
        (isempty(asset_names(users_data[u])) || isempty(asset_names(users_data[u], GENS))) ? 0.0 :
                shared_en_frac_agg[t] * max(_P_tot_us_agg[u, t], 0)
                    for u in user_set, t in time_set) /
                        sum(_P_ren_us_agg[u,t] for u in user_set, t in time_set)

    # fraction of energy share reliance with respect to demand by user aggnoagg case
    shared_en_frac_agg_tot = JuMP.Containers.DenseAxisArray(
        vcat(
            shared_en_tot_frac_agg,
            [(isempty(asset_names(users_data[u])) || isempty(asset_names(users_data[u], GENS))) ? 0.0 :
                    sum(shared_en_frac_agg[t] * max(_P_tot_us_agg[u, t], 0)
                        for t in time_set) / sum(_P_ren_us_agg[u,t] for t in time_set) for u in user_set]
        ), user_agg_set)

    # fraction of shared consumption reliance with respect to demand by user aggnoagg case
    shared_cons_tot_frac_agg = sum(shared_cons_frac_agg[t] * max(-_P_tot_us_agg[u, t], 0)
        for u in user_set, t in time_set) /
            sum(users_data[u].load[t] for u in user_set, t in time_set)

    # fraction of shared consumption reliance with respect to demand by user aggnoagg case
    shared_cons_frac_tot_agg = JuMP.Containers.DenseAxisArray(
        vcat(
            shared_cons_tot_frac_agg,
            [sum(shared_cons_frac_agg[t] * max(-_P_tot_us_agg[u, t], 0)
                for t in time_set) / sum(users_data[u].load[t] for t in time_set) for u in user_set]
        ), user_agg_set)

    return shared_en_frac_agg_tot, shared_cons_frac_tot_agg
end

"""
    calculate_shared_energy_abs_agg(users_data, user_set, time_set,
        _P_ren_us, _P_tot_us, shared_en_frac, shared_cons_frac)

Calculate the absolute shared produced energy (en), the shared consumption (cons) and self consumption (self cons)

'''
# Outputs
- shared_en_frac_us_agg
- shared_en_tot_frac_agg
- shared_cons_frac_us_agg
- shared_cons_tot_frac_agg
- self_cons_frac_us_agg
- self_cons_tot_frac_agg
'''
"""
function calculate_shared_energy_abs_agg(users_data, user_set, time_set,
        _P_tot_us_agg, _P_ren_us_agg)

    _P_tot_P_sum_us_agg = JuMP.Containers.DenseAxisArray(
        [sum(max(_P_tot_us_agg[u,t], 0) for u in user_set) for t in time_set], time_set
    )
    # total sum of power bought by users in agg case
    _P_tot_N_sum_us_agg = JuMP.Containers.DenseAxisArray(
        [sum(max(-_P_tot_us_agg[u,t], 0) for u in user_set) for t in time_set], time_set
    )

    # fraction of shared energy with respect to total sold energy by users in the agg case
    shared_en_frac_agg = JuMP.Containers.DenseAxisArray(
        [(_P_tot_P_sum_us_agg[t] > 0) ? (_P_tot_P_sum_us_agg[t] - max(sum(_P_tot_us_agg[u,t] for u in user_set), 0)
            )/_P_tot_P_sum_us_agg[t] : 0.0 for t in time_set],
        time_set
    )

    # fraction of shared consumption with respect to total bought energy by users in the agg case
    shared_cons_frac_agg = JuMP.Containers.DenseAxisArray(
        [(_P_tot_N_sum_us_agg[t] > 0) ? (_P_tot_P_sum_us_agg[t] - max(sum(_P_tot_us_agg[u,t] for u in user_set), 0)
            )/_P_tot_N_sum_us_agg[t] : 0.0 for t in time_set],
        time_set
    )

    # energy share reliance with respect to demand by user aggnoagg case
    shared_en_us_agg = JuMP.Containers.DenseAxisArray([
        (isempty(asset_names(users_data[u])) || isempty(asset_names(users_data[u], GENS))) ? 0.0 :
                sum(shared_en_frac_agg[t] * max(_P_tot_us_agg[u, t], 0)
                    for t in time_set) for u in user_set]
        , user_set)

    # energy share reliance with respect to demand by user aggnoagg case
    shared_en_tot_agg = sum(
        (isempty(asset_names(users_data[u])) || isempty(asset_names(users_data[u], GENS))) ? 0.0 :
                shared_en_frac_agg[t] * max(_P_tot_us_agg[u, t], 0)
                    for u in user_set, t in time_set)

    # shared consumption reliance with respect to demand by user aggnoagg case
    shared_cons_us_agg = JuMP.Containers.DenseAxisArray([
            sum(shared_cons_frac_agg[t] * max(-_P_tot_us_agg[u, t], 0)
                for t in time_set) for u in user_set]
        , user_set)

    # shared consumption reliance with respect to demand by user aggnoagg case
    shared_cons_tot_agg = sum(shared_cons_frac_agg[t] * max(-_P_tot_us_agg[u, t], 0)
                for u in user_set, t in time_set)

    return shared_en_us_agg, shared_en_tot_agg, shared_cons_us_agg, shared_cons_tot_agg,
        shared_en_frac_agg, shared_cons_frac_agg
end