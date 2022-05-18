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

end

function _utility_callback_test(input_file, optimizer, group_type)

    ## Initialization
    ECModel = ModelEC(input_file, EnergyCommunity.GroupCO(), optimizer)

    callback = to_utility_callback_by_subgroup(ECModel, group_type)

    dist_base = callback([EC_CODE, get_user_set(ECModel)[1]])

    @test dist_base ≈ 0.0 atol=1e-6

    dist_base = callback([EC_CODE; get_user_set(ECModel)])

    @test !isnothing(dist_base)

end

function _least_profitable_callback_test(input_file, optimizer)

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
    callback = to_least_profitable_coalition_callback(ECModel)

    # test to identify the least profitable coalition of the profit distribution test_coal
    # expected value are tested below
    least_profitable_coalition, coalition_benefit, min_surplus = callback(test_coal)

    @test Set(least_profitable_coalition) == Set(["user1", "user3"])
    @test coalition_benefit ≈ 9404.77 atol=1
    @test min_surplus ≈ -1280.42 atol=1

end

function _profit_distribution_Games_jl_test(input_file, games_mode, group_type, distribution_function, optimizer, kwargs...)

    ## Initialization
    ## Model CO
    ECModel = ModelEC(input_file, EnergyCommunity.GroupCO(), optimizer)
    
    mode = games_mode(ECModel, group_type)

    calc_solution = distribution_function(mode, kwargs...)

    path_solution = (
        string(@__DIR__) * 
        "/refs/games/" * 
        string(distribution_function) * "/" 
        * string(games_mode) * "/"
        * string(group_type) * ".yml"
    )
    
    if isfile(path_solution)
        # if the file exists run tests
        proven_solution = YAML.load_file(path_solution)
        
        @test Set(keys(calc_solution)) == Set(keys(proven_solution))
        @test all(isapprox(calc_solution[k] - proven_solution[k], 0.0, atol=1e-4) for k in keys(proven_solution))
    else
        # otherwise create the tests
        mkpath(dirname(path_solution))

        YAML.write_file(path_solution, calc_solution)
        @warn("Preloaded solution not found, then it has been created")
    end

end