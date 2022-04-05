using Plots, SankeyPlots

## Sankey diagram info agg
function createSankeyDiagram(_P_tot_us_agg, shared_cons_frac_agg, shared_en_frac_agg, user_set, user_set_desc)
    name_units = vcat("Market buy", [user_set_desc[u] * " prod." for u in user_set]...,
        "Community", "Market sell", [user_set_desc[u] * " cons." for u in user_set]...)
    # name_units = vcat("", ["" for u in user_set]...,
    #     "", "", ["" for u in user_set]...)
    source_sank = Int[]
    target_sank = Int[]
    value_sank = Float64[]

    market_id_from = 1
    market_id_to = length(user_set) + 3
    community_id = length(user_set) + 2
    user_id_from(x) = x + 1
    user_id_to(x) = x + length(user_set) + 3

    node_layer = Dict(vcat(
        [id => 1 for id in 1:(length(user_set)+1)],
        community_id => 2,
        market_id_to => 3,
        [id => 3 for id in (market_id_to+1):length(name_units)]))

    order_list = Dict(id => id +1 for id in 1:length(name_units) if market_id_to != id)
    push!(order_list, length(name_units)=>market_id_to)

    #calculate produced energy and energy sold to the market by user
    for (u_i, u_name) in enumerate(user_set)
        # demand from the market
        demand_market = sum(max(-_P_tot_us_agg[u_name,t], 0) * (1 - shared_cons_frac_agg[t]) for t in time_set)
        if demand_market > 0.001
            append!(source_sank, market_id_from)
            append!(target_sank, user_id_to(u_i))
            append!(value_sank, demand_market)
        end

        # production to the market
        prod_market = sum(max(_P_tot_us_agg[u_name,t], 0) * (1 - shared_en_frac_agg[t]) for t in time_set)
        if prod_market > 0.001
            append!(source_sank, user_id_from(u_i))
            append!(target_sank, market_id_to)
            append!(value_sank, prod_market)
        end

        # shared energy
        shared_en = sum(max(_P_tot_us_agg[u_name,t], 0) * shared_en_frac_agg[t] for t in time_set)
        if shared_en > 0.001
            append!(source_sank, user_id_from(u_i))
            append!(target_sank, community_id)
            append!(value_sank, shared_en)
        end

        # shared consumption
        shared_cons = sum(max(-_P_tot_us_agg[u_name,t], 0) * shared_cons_frac_agg[t] for t in time_set)
        if shared_cons > 0.001
            append!(source_sank, community_id)
            append!(target_sank, user_id_to(u_i))
            append!(value_sank, shared_cons)
        end
        
        # self consumption
        self_cons = sum(sum(Float64[
                profile_component(users_data[u_name], l, "load")[t] for l in asset_names(users_data[u_name], LOAD)
            ]) 
            - max(-_P_tot_us_agg[u_name,t], 0) for t in time_set)
        if self_cons > 0.001
            append!(source_sank, user_id_from(u_i))
            append!(target_sank, user_id_to(u_i))
            append!(value_sank, self_cons)
        end
    end

    value_sank = value_sank/sum(profile_component(users_data[u], l, "load")[t] 
        for u in user_set for l in asset_names(users_data[u], LOAD) for t in time_set)

    # s = sankey(name_units, source_sank.-1, target_sank.-1, value_sank)  # ECharts style
    market_color = palette(:rainbow)[2]
    community_color = palette(:rainbow)[5]
    users_colors = palette(:default)
    tot_colors = vcat([market_color],users_colors[1:length(user_set)],[community_color],
        [market_color],users_colors[1:length(user_set)])

    # Check and remove the ids that do not appear in the lists
    no_shows = []
    for i=1:length(name_units)
        if !((i in source_sank) || (i in target_sank))
            append!(no_shows, i)
        end
    end
    if !isempty(no_shows)
        upd_index(data_idx, no_shows) = map((x) -> x - sum(x .> no_shows), data_idx)
        upd_index!(data_idx, no_shows) = map!((x) -> x - sum(x .> no_shows), data_idx, data_idx)
        # map!((x) -> x - sum(x .> no_shows), source_sank, source_sank)
        # map!((x) -> x - sum(x .> no_shows), target_sank, target_sank)
        upd_index!(source_sank, no_shows)
        upd_index!(target_sank, no_shows)
        deleteat!(name_units, no_shows)
        deleteat!(tot_colors, no_shows)
        filter(x->!(x.first in no_shows), node_layer)
        filter(x->!(x.first in no_shows), order_list)
        for k in keys(node_layer)
            node_layer[k - sum(node_layer[k] .> no_shows)]
        end
        node_layer = Dict(upd_index(k, no_shows) => node_layer[k] for k in keys(node_layer))
        order_list = Dict(upd_index(k, no_shows) => upd_index(order_list[k], no_shows) for k in keys(order_list))
    end

    data_sort = sortslices(hcat(source_sank, target_sank, value_sank),
        dims=1,by=x->(x[1],x[2]),rev=false)
    _source_sank = convert.(Int, data_sort[:, 1])
    _target_sank = convert.(Int, data_sort[:, 2])
    _value_sank = data_sort[:, 3]

    sank_agg = DataFrame(source_sank=_source_sank,
        target_sank=_target_sank,
        value_sank=_value_sank)

    s = sankey(_source_sank, _target_sank, _value_sank;
        node_labels=name_units,
        node_colors=tot_colors,
        edge_color=:gradient,
        compact=true,
        label_size=15,
        opt_layer_assign=node_layer,
        opt_node_order=order_list
        )  # SankeyPlots style
    s, sank_agg
end