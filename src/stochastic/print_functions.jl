using Makie
using CairoMakie

"""
PRINT FILE, containin all the functions to store results in the first,second and third stage
""" 

"""
    print_first_stage(output_file::String, ECModel::StochasticEC)

    Print all the information of the first stochastic optimization
"""
function print_first_stage(output_file::String,
        ECModel::StochasticEC)

    users_data = ECModel.users_data
    gen_data = ECModel.gen_data
    market_data = ECModel.market_data

    user_set = ECModel.user_set
    user_set_EC = vcat(EC_CODE, user_set)
    n_users = length(user_set)

    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1

    project_lifetime = field(gen_data, "project_lifetime")
    year_set = 1:project_lifetime
    time_set = 1:n_steps

    energy_weight = profile(market_data, "energy_weight")[1]
    time_res = profile(market_data, "time_res")[1]

    d_model = ECModel.deterministic_model # JuMP model

    scenarios = ECModel.scenarios

    set_asset = unique([name for u in user_set for name in device_names(users_data[u])])

    # get general data solutions
    gap = MOI.get(d_model,MOI.RelativeGap())*100
    _solve_time = solve_time(d_model)
    _termination_status = Int(termination_status(d_model))
    _n_scen_s = ECModel.n_scen_s
    _n_scen_eps = ECModel.n_scen_eps

    _n_scen = _n_scen_s * _n_scen_eps
    # get the installed capacities for users and EC
    _x_us_EC = calculate_x_tot(ECModel)

    # get the total load demand in the scenarios considered
    load_demand = calculate_demand(ECModel)

    # subscript label (used in the results array)
    num_sub = Array{String}(undef,_n_scen)
    for i = 1:_n_scen
        if i<10
            num_sub[i] = string(Char(0x02080+i))
        else
            first_n = (i - mod(i,10))/10
            second_n = mod(i,10)
            num_sub[i] = Char(0x02080+first_n)*Char(0x02080+second_n)
        end
    end

    info_solution = DataFrames.DataFrame(configuration = name(get_group_type(ECModel)),
                        comp_time = _solve_time, 
                        exit_flag=_termination_status, 
                        primal_gap = gap,
                        n_scen_s = _n_scen_s,
                        n_scen_eps = _n_scen_eps,
                        obj_value = sum(ECModel.results[Symbol("SW"*num_sub[scen])] * probability(scenarios[scen]) for scen = 1:_n_scen))
    
    design_users = DataFrames.DataFrame(
        vcat(
            [[u for u in user_set_EC]],
            [[(u == EC_CODE) ? _x_us_EC[u, a] : 
                (a in device_names(users_data[u])) ? _x_us_EC[u, a] * field_component(users_data[u], a, "nom_capacity") : missing
                    for u in user_set_EC]
                        for a in set_asset]
        ),
        map(Symbol, vcat("User id", ["x_us_$a (x^{$a,U})" for a in set_asset]))
    )

    info_scenarios = DataFrames.DataFrame(
        vcat(
            [[convert_scen(_n_scen_s,_n_scen_eps,scen)[1] for scen = 1:_n_scen]],
            [[convert_scen(_n_scen_s,_n_scen_eps,scen)[2] for scen = 1:_n_scen]],
            [[probability(scenarios[scen]) for scen = 1:_n_scen]],
            [[ECModel.results[Symbol("SW"*num_sub[scen])] for scen = 1:_n_scen]],
            [[(get_group_type(ECModel) == GroupCO()) ? sum(ECModel.results[Symbol("P_shared_agg"*num_sub[scen])]) * time_res * energy_weight : missing for scen = 1:_n_scen]],
            [[(get_group_type(ECModel) == GroupCO()) ? sum(ECModel.results[Symbol("P_sq_P_agg"*num_sub[scen])]) * time_res * energy_weight : missing for scen = 1:_n_scen]],
            [[(get_group_type(ECModel) == GroupCO()) ? sum(ECModel.results[Symbol("P_sq_N_agg"*num_sub[scen])]) * time_res * energy_weight : missing for scen = 1:_n_scen]]
        ),
        map(Symbol, vcat("Scenario s","Scenario epsilon", "Scenario probability", "SW Scenario", "tot_P_shared", "tot_sq_P_agg","tot_sq_N_agg"))
    )

    economic_data = DataFrames.DataFrame(
        vcat(
            [[u for u in user_set]],
            [[ECModel.results[:CAPEX_tot_us][u] for u in user_set]],
            [[ECModel.results[:C_OEM_tot_us][u] for u in user_set]],
            [[ECModel.results[:C_REP_tot_us][y,u] for u in user_set] for y in year_set],
            [[ECModel.results[:R_RV_tot_us][y,u] for u in user_set] for y in year_set],
            [[ECModel.results[Symbol("R_Energy_tot_us" * num_sub[scen])].data[u] for u = 1:n_users] for scen = 1:_n_scen],
            [[ECModel.results[Symbol("C_gen_tot_us" * num_sub[scen])].data[u] for u = 1:n_users] for scen = 1:_n_scen],
            [[(get_group_type(ECModel) == GroupCO()) ? ECModel.results[Symbol("C_sq_tot_agg" * num_sub[scen])]/n_users :
                ECModel.results[Symbol("C_sq_tot_us" * num_sub[scen])].data[u] for u = 1:n_users] 
                    for scen = 1:_n_scen],
            [[(get_group_type(ECModel) == GroupCO()) ? ECModel.results[Symbol("R_Reward_agg_NPV" * num_sub[scen])]/n_users : missing for u = 1:n_users] for scen = 1:_n_scen],
            [[ECModel.results[Symbol("C_Peak_tot_us" * num_sub[scen])].data[u] for u = 1:n_users] for scen = 1:_n_scen]
        ),
        map(Symbol, vcat("User id",
                "CAPEX_tot_us",
                "C_OEM_tot_us",
                ["C_REP_tot_us_year_$y" for y in year_set],
                ["R_RV_tot_us_year_$y" for y in year_set],
                ["R_Energy_tot_us_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen],
                ["C_gen_tot_us_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen],
                ["C_Sq_tot_us_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen],
                ["R_reward_agg_NPV_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen],
                ["C_peak_tot_us_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen]
            )
        )
    )
    
    if ECModel.group_type == GroupNC() # Non Cooperative version
        forecast_dispatch = DataFrames.DataFrame(
            vcat(
                [[u for u in user_set]],
                [[sum(ECModel.results[:P_us_dec_P].data,dims=3)[u,scen] * time_res * energy_weight for u = 1:n_users] for scen = 1:_n_scen_s],
                [[sum(ECModel.results[:P_us_dec_N].data,dims=3)[u,scen] * time_res * energy_weight for u = 1:n_users] for scen = 1:_n_scen_s]
            ),
            map(Symbol, vcat("User id",
                    ["P_dec_P_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen_s],
                    ["P_dec_N_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen_s]
                )
            )
        )
    else
        forecast_dispatch = DataFrames.DataFrame(
            vcat(
                [[s for s = 1:_n_scen_s]],
                [[sum(ECModel.results[Symbol("P_agg_dec_P")].data,dims=2)[scen] * time_res * energy_weight for scen = 1:_n_scen_s]],
                [[sum(ECModel.results[Symbol("P_agg_dec_N")].data,dims=2)[scen] * time_res * energy_weight for scen = 1:_n_scen_s]]
            ),
            map(Symbol, vcat("Scenario s","P_dec_P","P_dec_N"
                )
            )
        )
    end

    energy_dispatch = DataFrames.DataFrame(
        vcat(
            [[u for u in user_set]],
            [[load_demand[scen][u] for u in user_set] for scen = 1:_n_scen],
            [[sum(ECModel.results[Symbol("P_P_us" * num_sub[scen])][u,t] for t in time_set) * time_res * energy_weight for u in user_set] for scen = 1:_n_scen],
            [[sum(ECModel.results[Symbol("P_N_us" * num_sub[scen])][u,t] for t in time_set) * time_res * energy_weight for u in user_set] for scen = 1:_n_scen],
            [[(get_group_type(ECModel) == GroupNC()) ? sum(ECModel.results[Symbol("P_sq_P_us" * num_sub[scen])][u,t] for t in time_set) * time_res * energy_weight : missing for u in user_set] for scen = 1:_n_scen],
            [[(get_group_type(ECModel) == GroupNC()) ? sum(ECModel.results[Symbol("P_sq_N_us" * num_sub[scen])][u,t] for t in time_set) * time_res * energy_weight : missing for u in user_set] for scen = 1:_n_scen],
            [[sum(ECModel.results[Symbol("P_ren_us" * num_sub[scen])][u,t] for t in time_set) * time_res * energy_weight for u in user_set] for scen = 1:_n_scen],
            [[(has_asset(users_data[u], THER)) ?  sum(ECModel.results[Symbol("P_gen_us" * num_sub[scen])][u,g,t] for t in time_set for g in asset_names(users_data[u],THER)) * time_res * energy_weight : missing
                for u in user_set] 
                    for scen = 1:_n_scen],
            [[(has_asset(users_data[u], CONV)) ?  sum(ECModel.results[Symbol("P_conv_P_us" * num_sub[scen])][u,c,t] for t in time_set for c in asset_names(users_data[u],CONV)) * time_res * energy_weight : missing
                    for u in user_set] 
                        for scen = 1:_n_scen],
            [[(has_asset(users_data[u], CONV)) ?  sum(ECModel.results[Symbol("P_conv_N_us" * num_sub[scen])][u,c,t] for t in time_set for c in asset_names(users_data[u],CONV)) * time_res * energy_weight : missing
                    for u in user_set] 
                        for scen = 1:_n_scen]
            
        ),
        map(Symbol, vcat("User id",
            ["load_demand_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen],
            ["P_P_us_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen],
            ["P_N_us_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen],
            ["P_sq_P_us_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen],
            ["P_sq_N_us_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen],
            ["P_ren_us_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen],
            ["P_gen_us_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen],
            ["P_conv_P_us_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen],
            ["P_conv_N_us_($(convert_scen(_n_scen_s,_n_scen_eps,scen)[1]),$(convert_scen(_n_scen_s,_n_scen_eps,scen)[2]))" for scen = 1:_n_scen]
            )
        )
    )

    XLSX.openxlsx(output_file, mode="w") do xf

        xs = xf[1]
        XLSX.rename!(xs, "info solution")
        XLSX.writetable!(xs, collect(DataFrames.eachcol(info_solution)),
            DataFrames.names(info_solution))
            
        xs = XLSX.addsheet!(xf, "design users") 
        XLSX.writetable!(xs, collect(DataFrames.eachcol(design_users)),
        DataFrames.names(design_users))

        xs = XLSX.addsheet!(xf, "info scenarios") 
        XLSX.writetable!(xs, collect(DataFrames.eachcol(info_scenarios)),
        DataFrames.names(info_scenarios))

        xs = XLSX.addsheet!(xf, "economic data") 
        XLSX.writetable!(xs, collect(DataFrames.eachcol(economic_data)),
        DataFrames.names(economic_data))

        xs = XLSX.addsheet!(xf, "forecast dispatch") 
        XLSX.writetable!(xs, collect(DataFrames.eachcol(forecast_dispatch)),
        DataFrames.names(forecast_dispatch))

        xs = XLSX.addsheet!(xf, "energy dispatch") 
        XLSX.writetable!(xs, collect(DataFrames.eachcol(energy_dispatch)),
        DataFrames.names(energy_dispatch))
    end
end

"""
    print_second_stage(output_file::String, ECModel::StochasticEC, declared_P, declared_N)

    Print the forecast dispatch found in the second stage in each scenario s
"""
function print_second_stage(output_file::String,
    data,
    declared_P, 
    declared_N,
    point_load,
    point_pv,
    point_wind,
    configuration)

    users_data = users(data)
    gen_data = general(data)

    # Set definitions
    user_set = user_names(gen_data, users_data)
    user_set_EC = vcat(EC_CODE, user_set)
    n_users = length(user_set)

    init_step = field(gen_data, "init_step")
    final_step = field(gen_data, "final_step")
    n_steps = final_step - init_step + 1

    project_lifetime = field(gen_data, "project_lifetime")
    year_set = 1:project_lifetime
    time_set = 1:n_steps

    n_repetition = length(declared_P)

    info_scenario = DataFrames.DataFrame(
        vcat(
            [[rep for rep = 1:n_repetition]],
            [[point_load[rep] for rep = 1:n_repetition]],
            [[point_pv[rep] for rep = 1:n_repetition]],
            [[point_wind[rep] for rep = 1:n_repetition]],
            [[declared_P[rep] for rep = 1:n_repetition]],
            [[declared_N[rep] for rep = 1:n_repetition]]
        ),
        map(Symbol,vcat(
            "Scenario s",
            "Point load",
            "Point PV",
            "Point wind",
            "P_dec_P",
            "P_dec_N"
        ))
    )

    XLSX.openxlsx(output_file, mode="w") do xf

        xs = xf[1]
        XLSX.rename!(xs, "info scenarios")
        XLSX.writetable!(xs, collect(DataFrames.eachcol(info_scenario)),
            DataFrames.names(info_scenario))
    end
end

"""
    print_third_stage(output_file::String, ...)

    Print the main results found in the third stage in each scenario s
"""

function print_third_stage(output_file::String,
    n_rep::Int,
    rep_time::Float64,
    SW::Array{Float64},
    R_energy::Array{Float64},
    C_gen::Array{Float64},
    C_sq::Array{Float64},
    C_peak::Array{Float64},
    load_demand::Array{Float64},
    P_P::Array{Float64},
    P_N::Array{Float64},
    P_sq_P::Array{Float64},
    P_sq_N::Array{Float64},
    P_ren::Array{Float64},
    P_gen::Array{Float64},
    P_conv_P::Array{Float64},
    P_conv_N::Array{Float64},
    configuration;
    R_reward::Array{Float64} = Array{Float64}(undef,0),
    P_Shared::Array{Float64} = Array{Float64}(undef,0))

    info_solution = DataFrames.DataFrame(n_rep = n_rep,
                        comp_time = rep_time,
                        obj_value = mean(SW))
    
    economic_data = DataFrames.DataFrame(
        vcat(
            [[rep for rep = 1:n_rep]],
            [[SW[rep] for rep = 1:n_rep]],
            [[R_energy[rep] for rep = 1:n_rep]],
            [[C_gen[rep] for rep = 1:n_rep]],
            [[C_sq[rep] for rep = 1:n_rep]],
            [[C_peak[rep] for rep = 1:n_rep]],
            [[(configuration == GroupCO()) ? R_reward[rep] : missing for rep = 1:n_rep]]
        ),
        map(Symbol, vcat("Repetition",
                "SW",
                "R_energy",
                "C_gen",
                "C_sq",
                "C_peak",
                "Reward_agg"
                )
            )
        )

    dispatch_data = DataFrames.DataFrame(
        vcat(
            [[rep for rep = 1:n_rep]],
            [[load_demand[rep] for rep = 1:n_rep]],
            [[P_P[rep] for rep = 1:n_rep]],
            [[P_N[rep] for rep = 1:n_rep]],
            [[P_sq_P[rep] for rep = 1:n_rep]],
            [[P_sq_N[rep] for rep = 1:n_rep]],
            [[P_ren[rep] for rep = 1:n_rep]],
            [[P_gen[rep] for rep = 1:n_rep]],
            [[P_conv_P[rep] for rep = 1:n_rep]],
            [[P_conv_N[rep] for rep = 1:n_rep]],
            [[(configuration == GroupCO()) ? P_Shared[rep] : missing for rep = 1:n_rep]]
        ),
        map(Symbol, vcat("Repetition",
                "load",
                "P_P",
                "P_N",
                "P_sq_P",
                "P_sq_N",
                "P_ren",
                "P_gen",
                "P_conv_P",
                "P_conv_N",
                "P_sh"
                )
            )
        )

    XLSX.openxlsx(output_file, mode="w") do xf

    xs = xf[1]
    XLSX.rename!(xs, "info solution")
    XLSX.writetable!(xs, collect(DataFrames.eachcol(info_solution)),
        DataFrames.names(info_solution))

    xs = XLSX.addsheet!(xf, "economic data")
    XLSX.writetable!(xs, collect(DataFrames.eachcol(economic_data)), DataFrames.names(economic_data))

    xs = XLSX.addsheet!(xf, "dispatch data")
    XLSX.writetable!(xs, collect(DataFrames.eachcol(dispatch_data)), DataFrames.names(dispatch_data))
    end
end

"""
    plot_resource(output_file::String, asset, ..)

    Plot the installed capacity by each user and community for the resources in asset
"""
function plot_resource(
    output_file::String,
    asset::Array{String},
    users_data,
    x_CO,
    x_NC,
    colors
    )

    user_set = collect(keys(users_data))
    n_users = length(user_set)
    n_resource = length(asset)

    max_installed_us_CO = maximum((has_asset(users_data[u], a)) ? x_CO[u,a] : 0.0 for u in user_set for a in asset)
    max_installed_us_NC = maximum((has_asset(users_data[u], a)) ? x_NC[u,a] : 0.0 for u in user_set for a in asset)
    max_installed_us = max(max_installed_us_CO,max_installed_us_NC)

    # Create the grid for the plot
    f = CairoMakie.Figure(resolution = (1500, 400))

    gEC = f[1,1] = GridLayout()
    gusers = f[1,2:n_users+1] = GridLayout()
    gLegend = f[1,n_users+2] = GridLayout()

    # adding barplot for EC
    axEC = Axis(gEC[1,1],
        ylabel = "Capacity [kW]",
        xticks = (1:2, ["CO","NC"]))
    
    Label(gEC[1,1,Top()], "Community", valign = :bottom, font = :bold, padding = (0, 0, 5, 0))

    for j = 1:n_resource
        barplot!(axEC, [1,2], [x_CO[EC_CODE, asset[j]],x_NC[EC_CODE, asset[j]]],
            gap = 0.05,
            label = asset[j],
            color = colors[j])
    end

    hidexdecorations!(axEC, ticks=false, ticklabels=false)

    CairoMakie.ylims!(axEC, low = 0)

    # adding barplot for users

    ylimus = (0, max_installed_us + 20);
    for i = 1:n_users
        if i ==1
            axUs = Axis(gusers[1,i],
                ylabel = "Capacity [kW]",
                xticks = (1:2, ["CO","NC"]))
            CairoMakie.ylims!(axUs, ylimus)
        else
            axUs = Axis(gusers[1,i],
                xticks = (1:2, ["CO","NC"]),
                yticklabelsvisible = false,
                yticksvisible = false)
            CairoMakie.ylims!(axUs, ylimus)
        end
        user = user_set[i]

        hidexdecorations!(axUs, ticks=false, ticklabels=false)

        Label(gusers[1,i,Top()], user, valign = :bottom, font = :bold, padding = (0, 0, 5, 0))

        for j = 1:n_resource
            installed_CO_NC = (has_asset(users_data[user], asset[j])) ? [x_CO[user, asset[j]],x_NC[user, asset[j]]] : [0.0,0.0]
            barplot!(axUs, [1,2], installed_CO_NC,
                gap = 0.05,
                color = colors[j])
        end
    end

    Legend(gLegend[1,1], axEC, framevisible = false)

    asset_string = ""
    for j = 1:n_resource
        asset_string = asset_string * asset[j] * "_"
    end
    asset_output_file = asset_string * output_file

    save(asset_output_file, f)
end
    
"""
    plot_declared_dispatch(output_file::String, ..)

    Plot the declared dispatch of the community in all the risimulations
    
    There will be two plots, one describing the total declared energy by the community (P and N), order by P_dec_P and
    one showing the corresponding point_s extracted for load demand and renewable dispatch
"""
function plot_declared_dispatch(
    output_file::String,
    P_dec_P,
    P_dec_N,
    point_s_load,
    point_s_pv,
    point_s_wind
    )

    n_rep = length(P_dec_P)

    rep_set = 1:n_rep

    # Create the grid for the plot

    f = Figure(resolution = (1000, 1000))

    gscen = f[1:2,1] = GridLayout()
    glegend = f[1:2,1] = GridLayout()

    p = sortperm( P_dec_P )

    # Declared energy plot
    axscenario = Axis(gscen[1,1],
    ylabel = "[kW]",
    xlabel = "Risimulation")

    Label(gscen[1,1,Top()], "Forecast dispatch", valign = :bottom, font = :bold, padding = (0, 0, 5, 0))

    # add the declared amount of energy supplied to the grid
    lines!(axscenario, rep_set, P_dec_P[ p ],
        label = "P_dec_P")

    lines!(axscenario, rep_set, P_dec_N[ p ],
        label = "P_dec_N")

    Legend(glegend[1,1], axscenario, framevisible = false)

     # Point s plot
     axscenario = Axis(gscen[2,1],
     ylabel = "Weight",
     xlabel = "Risimulation")
 
    Label(gscen[2,1,Top()], "Points scenarios s", valign = :bottom, font = :bold, padding = (0, 0, 5, 0))
 
    # add the extracted point s in each repetition
    lines!(axscenario, rep_set, point_s_load[ p ],
         label = "Point load demand")
 
    lines!(axscenario, rep_set, point_s_pv[ p ],
         label = "Point PV dispatch")

    lines!(axscenario, rep_set, point_s_wind[ p ],
         label = "Point wind dispatch")
 
    Legend(glegend[2,1], axscenario, framevisible = false)

    save(output_file,f)
end

"""
    plot_normalized_cost_third_stage(output_file::String, ..)

    Plot the costs of the comunity in each scenario s
"""
function plot_log_cost_third_stage(
    output_file::String,
    SW,
    R_rev,
    C_gen,
    C_sq,
    C_peak,
    n_scen_s::Int,
    prob_scen,
    configuration;
    Reward_agg = Array{Array}(undef,0)
    )

    colors = Makie.wong_colors()
    f = Figure(resolution = (1800, 800))

    gmain = f[1:2,1] = GridLayout()
    gscen = f[1:2,2:Int(n_scen_s/2)+1] = GridLayout()
    glegend = f[1:2,Int(n_scen_s/2)+2] = GridLayout()

    SC_tot = 0.0
    C_rev_tot = 0.0
    C_gen_tot = 0.0
    C_sq_tot = 0.0
    C_peak_tot = 0.0
    Reward_agg_tot = 0.0

    max_SC = - mean(SW[n_scen_s]) /1000
    if max_SC < 600
        pers_y_ticks = [10,20,40,100,200,300,400,600]
    else
        pers_y_ticks = [10,20,40,100,200,300,500,700]
    end

    for s = 1:n_scen_s
        if s <= n_scen_s/2
            row = 1
            col = s
        else
            row = 2
            col = s - Int(n_scen_s/2)
        end

        if configuration == GroupCO()
            SC = - mean(SW[s]) /20 /1000  # Also divided by project_lifetime
            _C_Rev = - mean(R_rev[s]) /1000
            _C_gen = mean(C_gen[s]) /1000
            _C_sq = mean(C_sq[s]) /1000
            _C_peak = mean(C_peak[s]) /1000
            _Reward_agg = mean(Reward_agg[s]) /1000

            SC_tot = SC_tot + SC * prob_scen[s]
            C_rev_tot = C_rev_tot + _C_Rev * prob_scen[s]
            C_gen_tot = C_gen_tot + _C_gen * prob_scen[s]
            C_sq_tot = C_sq_tot + _C_sq * prob_scen[s]
            C_peak_tot = C_peak_tot + _C_peak * prob_scen[s]
            Reward_agg_tot = Reward_agg_tot + _Reward_agg * prob_scen[s]

            if col == 1
                axscenario = Axis(gscen[row,col],
                    yscale = Makie.pseudolog10,
                    yticks = pers_y_ticks,
                    ylabel = "Yearly cost [k€] (log10 scale)",
                    xticks = (1:6),
                    xticksvisible = false)
            else
                axscenario = Axis(gscen[row,col],
                    yscale = Makie.pseudolog10,
                    yticks = pers_y_ticks,
                    yticklabelsvisible = false,
                    yticksvisible = false,
                    xticks = (1:6),
                    xticksvisible = false)
            end

            barplot!(axscenario, [i for i = 1:6], [SC,_C_Rev,_C_gen,_C_sq,_C_peak,_Reward_agg],
                gap = 0.05,
                color = colors[1:6])

            elements = [PolyElement(polycolor = colors[i]) for i in 1:6]
            
            legend = ["SC","C_Rev","C_Gen","C_Sq","C_Peak","Reward_agg"]
        else
            SC = - mean(SW[s]) /20 /1000  # Also divided by project_lifetime
            _C_Rev = - mean(R_rev[s]) /1000
            _C_gen = mean(C_gen[s]) /1000
            _C_sq = mean(C_sq[s]) /1000
            _C_peak = mean(C_peak[s]) /1000

            SC_tot = SC_tot + SC * prob_scen[s]
            C_rev_tot = C_rev_tot + _C_Rev * prob_scen[s]
            C_gen_tot = C_gen_tot + _C_gen * prob_scen[s]
            C_sq_tot = C_sq_tot + _C_sq * prob_scen[s]
            C_peak_tot = C_peak_tot + _C_peak * prob_scen[s]

            if col == 1
                axscenario = Axis(gscen[row,col],
                    yscale = Makie.pseudolog10,
                    yticks = pers_y_ticks,
                    ylabel = "Yearly cost [k€] (log10 scale)",
                    xticks = (1:5),
                    xticksvisible = false)
            else
                axscenario = Axis(gscen[row,col],
                    yscale = Makie.pseudolog10,
                    yticks = pers_y_ticks,
                    yticklabelsvisible = false,
                    yticksvisible = false,
                    xticks = (1:5),
                    xticksvisible = false)
            end
            
            barplot!(axscenario, [i for i = 1:5], [SC,_C_Rev,_C_gen,_C_sq,_C_peak],
                gap = 0.05,
                color = colors[1:5])

            elements = [PolyElement(polycolor = colors[i]) for i in 1:5]

            legend = ["SC","C_Rev","C_Gen","C_Sq","C_Peak"]
        end

        hidexdecorations!(axscenario)

        CairoMakie.ylims!(axscenario, (0,pers_y_ticks[length(pers_y_ticks)]))
        
        Label(gscen[row,col,Top()], "Scenario $s", valign = :bottom, font = :bold, padding = (0, 0, 5, 0))

        if s == n_scen_s
            Legend(glegend[1,1], elements, legend, framevisible = false)
        end
    end

    if configuration == GroupCO()
        axmain = Axis(gmain[1,1],
            ylabel = "[M€]",
            xticks = (1:6),
            xticksvisible = false)

        barplot!(axmain, [i for i = 1:6], [SC_tot, C_rev_tot, C_gen_tot, C_sq_tot, C_peak_tot, Reward_agg_tot],
            gap = 0.05,
            color = colors[1:6])
    else
        axmain = Axis(gmain[1,1],
            ylabel = "[M€]",
            xticks = (1:5),
            xticksvisible = false)

        barplot!(axmain, [i for i = 1:5], [SC_tot, C_rev_tot, C_gen_tot, C_sq_tot, C_peak_tot],
            gap = 0.05,
            color = colors[1:5])
    end

    hidexdecorations!(axmain)

    CairoMakie.ylims!(axmain, low = 0)

    Label(gmain[1,1,Top()], "Final costs", valign = :bottom, font = :bold, padding = (0, 0, 5, 0))

    save(output_file,f)
end

"""
    histogram_all_SC(output_file::String, ..)

    Plot the histogram of all the social cost obtained
"""
function  histogram_all_SC(
    output_file::String,
    SC
    )

    colors = colorschemes[:tab10]
    
    f = Figure(resolution = (1800, 500))

    axfig = Axis(f[1,1:10], title = "Distribution of social cost in risimulations",
        xlabel = "SC [M€]",
        ylabel = "Frequency")
    
    axleg = f[1,11] = GridLayout()

    hist!(axfig, SC/1000/1000, strokewidth = 1, strokecolor = :black)

    save(output_file, f)
end

"""
    plot_energy_flows_third_stage(output_file::String, ..)

    Plot the total flow of energy inside the comunity in each scenario s
"""
function plot_log_energy_flows_third_stage(
    output_file::String,
    load,
    P_P, 
    P_N, 
    P_ren,
    P_gen, 
    P_conv_P,
    n_scen_s::Int,
    configuration;
    P_shared = Array{Array}(undef,0)
    )

    colors = Makie.wong_colors()
    f = CairoMakie.Figure(resolution = (1800, 800))

    gscen = f[1:2,1:Int(n_scen_s/2)] = GridLayout()
    glegend = f[1:2,Int(n_scen_s/2)+1] = GridLayout()

    for s = 1:n_scen_s
        if s <= n_scen_s/2
            row = 1
            col = s
        else
            row = 2
            col = s - Int(n_scen_s/2)
        end

        if configuration == GroupCO()
            load_mean = mean(load[s])/1000
            P_P_norm = mean(P_P[s])/1000
            P_N_norm = mean(P_N[s])/1000
            P_ren_norm = mean(P_ren[s])/1000
            P_gen_norm = mean(P_gen[s])/1000
            P_conv_P_norm = mean(P_conv_P[s])/1000
            P_shared_norm = mean(P_shared[s])/1000

            if col == 1
                axscenario = Axis(gscen[row,col],
                    yscale = Makie.pseudolog10,
                    yticks = [50,200,500,1000,2000,4000],
                    ylabel = "Energy Flows [MW] (log10 scale)",
                    xticks = (1:7),
                    xticksvisible = false)
            else
                axscenario = Axis(gscen[row,col],
                    yscale = Makie.pseudolog10,
                    yticks = [50,200,500,1000,2000,4000],
                    yticklabelsvisible = false,
                    yticksvisible = false,
                    xticks = (1:7),
                    xticksvisible = false)
            end

            barplot!(axscenario, [i for i = 1:7], [load_mean,P_P_norm,P_N_norm,P_ren_norm,P_gen_norm,P_conv_P_norm,P_shared_norm],
                gap = 0.05,
                color = colors[1:7])

            elements = [PolyElement(polycolor = colors[i]) for i in 1:7]
            
            legend = ["Load","P_P","P_N","P_ren","P_gen","P_conv","P_shared"]
        else
            load_mean = mean(load[s])/1000
            P_P_norm = mean(P_P[s])/1000
            P_N_norm = mean(P_N[s])/1000
            P_ren_norm = mean(P_ren[s])/1000
            P_gen_norm = mean(P_gen[s])/1000
            P_conv_P_norm = mean(P_conv_P[s])/1000
            
            if col == 1
                axscenario = Axis(gscen[row,col],
                    yscale = Makie.pseudolog10,
                    yticks = [50,200,500,1000,2000,4000],
                    ylabel = "Energy Flows [MW] (log10 scale)",
                    xticks = (1:6),
                    xticksvisible = false)
            else
                axscenario = Axis(gscen[row,col],
                    yscale = Makie.pseudolog10,
                    yticks = [50,200,500,1000,2000,4000],
                    yticklabelsvisible = false,
                    yticksvisible = false,
                    xticks = (1:6),
                    xticksvisible = false)
            end
            
            barplot!(axscenario, [i for i = 1:6], [load_mean,P_P_norm,P_N_norm,P_ren_norm,P_gen_norm,P_conv_P_norm],
                gap = 0.05,
                color = colors[1:6])

            elements = [PolyElement(polycolor = colors[i]) for i in 1:6]

            legend = ["Load","P_P","P_N","P_ren","P_gen","P_conv"]
        end
        hidexdecorations!(axscenario)

        CairoMakie.ylims!(axscenario, (0,4000))
        
        Label(gscen[row,col,Top()], "Scenario $s", valign = :bottom, font = :bold, padding = (0, 0, 5, 0))

        if s == n_scen_s
            Legend(glegend[1,1], elements, legend, framevisible = false)
        end
    end

    save(output_file,f)
end

function print_load_demand(
    output_file::String,
    load_demand,
    user_set,
    n_time_step::Int,
    )

    colors = colorschemes[:tab10]
    time_set = 1:n_time_step

    # Create the grid for the plot

    f = Figure(resolution = (1800, 800))

    gscen = f[1:2,1:Int(length(user_set))] = GridLayout()

    for u=1:length(user_set)

        if u <= length(user_set)/2
            row = 1
            col = u
        else
            row = 2
            col = u - Int(length(user_set)/2)
        end

        # adding barplot for EC
        axuser = Axis(gscen[row,col],
            ylabel = "[kW]",
            xlabel = "Time steps")

        Label(gscen[row,col,Top()], "Load $u", valign = :bottom, font = :bold, padding = (0, 0, 5, 0))

        user = user_set[u]

        # add the declared amount of energy supplied to the grid
        lines!(axuser, time_set, dict2array(load_demand[user],n_time_step),
            color = colors[u])
    end

    save(output_file,f)
end    

function print_renewable_production(
    output_file::String,
    users_data,
    renewable_production,
    asset,
    user_set,
    n_time_step::Int,
    )

    colors = colorschemes[:tab10]
    time_set = 1:n_time_step

    # Create the grid for the plot

    f = Figure(resolution = (1800, 800))

    gscen = f[1:2,1:Int(length(user_set))] = GridLayout()

    for u=1:length(user_set)

        if u <= length(user_set)/2
            row = 1
            col = u
        else
            row = 2
            col = u - Int(length(user_set)/2)
        end

        # adding barplot for EC
        axuser = Axis(gscen[row,col],
            ylabel = "[kW]",
            xlabel = "Time steps")

        Label(gscen[row,col,Top()], "Production $asset $u", valign = :bottom, font = :bold, padding = (0, 0, 5, 0))

        user = user_set[u]

        # add the declared amount of energy supplied to the grid
        lines!(axuser, time_set, has_asset(users_data[user],asset) ? dict2array(renewable_production[user][asset],n_time_step) : zeros(n_time_step),
            color = colors[u])
    end

    save(output_file,f)
end