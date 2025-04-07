using EnergyCommunity, JuMP, Plots
using Test, FileIO, HiGHS, MathOptInterface, TheoryOfGames, YAML
using ReferenceTests

# needed to avoid problems with qt when plotting
ENV["GKSwstype"]="nul"

const MOI = MathOptInterface

# TODO add a test for the case of flexibility

# EC groups to test
EC_GROUPS = [GroupCO(), GroupNC(), GroupANC()]

OPTIMIZER = optimizer_with_attributes(
    HiGHS.Optimizer, "ipm_optimality_tolerance"=>1e-6, "mip_rel_gap"=>1e-3
)
ATOL = 1.
RTOL = 1e-3

input_tests = Dict(
    "base_case"=>joinpath(@__DIR__, "./data/energy_community_model.yml"),
    "thermal_case"=>joinpath(@__DIR__, "./data/energy_community_model_thermal.yml"),
    "flexibility_case"=>joinpath(@__DIR__, "./data/energy_community_model_flexibility.yml"),
    "heat_case"=>joinpath(@__DIR__, "./data/energy_community_model_heat.yml"),
)


include("tests.jl")

@testset "Create example data" begin
    folder = joinpath(@__DIR__, "./data")
    create_example_data(folder, config_name="default")
    for input_file in values(input_tests)
        @test isfile(input_file)
    end
end

@testset "Optimization tests" begin

    # Loop over input files
    for (name, input_file) in input_tests

        @testset "Input file: $name" begin
            # Loop over group types
            for group in EC_GROUPS

                full_test_name = "group_$name"

                @testset "Group $(string(group))" begin
                    _base_test(full_test_name, input_file, group, OPTIMIZER)
                end
            end
        end
    end
end

@testset "TheoryOfGames.jl interaction" begin

    test_name_tog = "base_case"
    input_file = input_tests[test_name_tog]
    
    @testset "Utility callback test" begin
        for base_group in [GroupNC(), GroupANC()]
            for no_aggregator_group in [GroupNC(), GroupANC()]
                full_test_name = "utility_$(test_name_tog)_$(string(no_aggregator_group))"
                _utility_callback_test(
                    full_test_name, input_file, OPTIMIZER, base_group;
                    no_aggregator_group=no_aggregator_group
                )
            end
        end
    end
        
    @testset "Least profitable group callback test" begin
        # base case of the simulation
        base_group = GroupNC()
        for no_aggregator_group in [GroupNC(), GroupANC()]
            full_test_name = "least_profitable_$(test_name_tog)_$(string(no_aggregator_group))"
            _least_profitable_callback_test(
                full_test_name, input_file, OPTIMIZER, base_group;
                no_aggregator_group=no_aggregator_group
            )
        end
    end
        
    @testset "TheoryOfGames.jl - Shapley" begin
        # base case of the simulation
        base_group = GroupNC()
        for no_aggregator_group in [GroupNC(), GroupANC()]  # exclude CO as base case
            full_test_name = "shapley_$(test_name_tog)_$(string(no_aggregator_group))"
            _profit_distribution_Games_jl_test(
                full_test_name, input_file, EnumMode, base_group, shapley_value, OPTIMIZER;
                no_aggregator_group=no_aggregator_group
            )
        end
    end

end
