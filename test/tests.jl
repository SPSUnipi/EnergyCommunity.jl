function _base_test(input_file, group, optimizer)

    ## Parameters

    output_file_isolated = joinpath(@__DIR__, "./results/output_file_NC.xlsx")  # Output file - model users alone
    output_plot_isolated = joinpath(@__DIR__, "./results/Img/plot_user_{:s}_NC.png")  # Output png file of plot - model users alone

    output_file_combined = joinpath(@__DIR__, "./results/output_file_EC.xlsx")  # Output file - model Energy community
    output_plot_combined = joinpath(@__DIR__, "./results/Img/plot_user_{:s}_EC.png")  # Output png file of plot - model energy community

    output_plot_sankey_agg = joinpath(@__DIR__, "./results/Img/sankey_EC.png")  # Output plot of the sankey plot related to the aggregator case
    output_plot_sankey_noagg = joinpath(@__DIR__, "./results/Img/sankey_NC.png")  # Output plot of the sankey plot related to the no aggregator case


    ## Model CO

    ## Initialization

    # Read data from excel file
    ECModel = ModelEC(input_file, group, optimizer)

    # set_group_type!(ECModel, GroupNC())

    build_model!(ECModel)

    optimize!(ECModel)

    @test termination_status(ECModel) in [MOI.OPTIMAL, MOI.LOCALLY_SOLVED]

    plot(ECModel, output_plot_combined)

    print_summary(ECModel)

    save_summary(ECModel, output_file_combined)

    grid_shares_EC = calculate_grid_import(ECModel)
    energy_shares_EC = calculate_production_shares(ECModel)
    
    @test_reference "refs/sankeys/group_$(string(group)).png" plot_sankey(ECModel)

    @test_reference "refs/business_plan_plot/group_$(string(group)).png" business_plan_plot(ECModel)
end

function _utility_callback_test(input_file, optimizer, group_type; atol=ATOL, rtol=RTOL, kwargs...)

    ## Initialization
    ECModel = ModelEC(input_file, EnergyCommunity.GroupCO(), optimizer)

    callback = to_utility_callback_by_subgroup(ECModel, group_type; kwargs...)

    testing_coalitions = [
        [EC_CODE, get_user_set(ECModel)[1]],
        [EC_CODE; get_user_set(ECModel)],
        get_user_set(ECModel),
    ]

    dist_testing_coalitions = Dict(
        coal=>callback(coal) for coal in testing_coalitions
    )

    path_solution = (
        string(@__DIR__) * 
        "/refs/utility_callback/" * 
        string(group_type) * "__" * join([string(p.first) * "-" * string(p.second) for p in kwargs], "_") * ".yml"
    )
    
    if isfile(path_solution)
        # if the file exists run tests
        proven_solution = YAML.load_file(path_solution)

        @test Set(testing_coalitions) == Set(keys(proven_solution))
        for coal in keys(proven_solution)
            @test dist_testing_coalitions[coal] ≈ proven_solution[coal] atol=atol rtol=rtol
        end
    else
        # otherwise create the tests
        mkpath(dirname(path_solution))

        YAML.write_file(path_solution, dist_testing_coalitions)
        @warn("Preloaded solution not found, then it has been created")
    end

end

function _least_profitable_callback_test(input_file, optimizer, base_group; atol=ATOL, rtol=RTOL, no_aggregator_group=GroupNC())

    ## Initialization
    ## Model CO
    ECModel = ModelEC(input_file, EnergyCommunity.GroupCO(), optimizer)
    build_model!(ECModel)
    optimize!(ECModel)
    
    ## Model NC
    NCModel = ModelEC(input_file, EnergyCommunity.GroupNC(), optimizer)
    build_model!(NCModel)
    optimize!(NCModel)
    
    # total surplus
    total_surplus = objective_value(ECModel) - objective_value(NCModel)

    # test coalition distribution
    test_coal = Dict(EC_CODE=>0.0, "user1"=>total_surplus/2, "user2"=>total_surplus/2, "user3"=>0.0)

    # create callback
    callback = to_least_profitable_coalition_callback(ECModel, base_group; no_aggregator_group=no_aggregator_group)

    # test to identify the least profitable coalition of the profit distribution test_coal
    # expected value are tested below
    outdata = callback(test_coal)

    # get first output
    outdata = outdata[1]

    path_solution = (
        string(@__DIR__) * 
        "/refs/least_profitable_coalition/" * 
        string(base_group) * "/" 
        * string(no_aggregator_group) * ".yml"
    )
    
    if isfile(path_solution)
        # if the file exists run tests
        proven_solution = YAML.load_file(path_solution)

        
        @test Set(outdata.least_profitable_coalition) == Set(proven_solution["worst_coalition"])
        @test outdata.coalition_benefit ≈ proven_solution["coalition_benefit"] atol=atol rtol=rtol
        @test outdata.min_surplus ≈ proven_solution["min_surplus"] atol=atol rtol=rtol
    else
        # otherwise create the tests
        mkpath(dirname(path_solution))

        calc_solution = Dict(
            "worst_coalition"=>outdata.least_profitable_coalition,
            "coalition_benefit"=>outdata.coalition_benefit,
            "min_surplus"=>outdata.min_surplus,
        )

        YAML.write_file(path_solution, calc_solution)
        @warn("Preloaded solution not found, then it has been created")
    end

end

function _profit_distribution_Games_jl_test(input_file, games_mode, group_type, distribution_function, optimizer; atol=ATOL, rtol=RTOL, kwargs...)

    ## Initialization
    ## Model CO
    ECModel = ModelEC(input_file, EnergyCommunity.GroupCO(), optimizer)
    
    mode = games_mode(ECModel, group_type; kwargs...)

    calc_solution = distribution_function(mode)

    path_solution = (
        string(@__DIR__) * 
        "/refs/games/" * 
        string(distribution_function) * "/" 
        * string(games_mode) * "/"
        * string(group_type) * "__" * join([string(p.first) * "-" * string(p.second) for p in kwargs], "_") * ".yml"
    )
    
    if isfile(path_solution)
        # if the file exists run tests
        proven_solution = YAML.load_file(path_solution)
        
        @test Set(keys(calc_solution)) == Set(keys(proven_solution))
        @test all(isapprox(calc_solution[k] - proven_solution[k], 0.0; atol=atol, rtol=rtol) for k in keys(proven_solution))
    else
        # otherwise create the tests
        mkpath(dirname(path_solution))

        YAML.write_file(path_solution, calc_solution)
        @warn("Preloaded solution not found, then it has been created")
    end

end