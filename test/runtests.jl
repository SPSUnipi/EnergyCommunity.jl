using EnergyCommunity, JuMP, Plots
using Test, FileIO, HiGHS, MathOptInterface, Games, YAML
using ReferenceTests

# needed to avoid problems with qt when plotting
ENV["GKSwstype"]="nul"

const MOI = MathOptInterface

# EC groups to test
EC_GROUPS = [EnergyCommunity.GroupCO(), EnergyCommunity.GroupNC(), EnergyCommunity.GroupANC()]

OPTIMIZER = HiGHS.Optimizer
ATOL = 1.
RTOL = 1e-3

input_file = joinpath(@__DIR__, "./data/energy_community_model.yml")  # Input file


include("tests.jl")

@testset "Optimization tests" begin

    # Loop over group types
    for group in EC_GROUPS

        @testset "Group $(string(group))" begin
            _base_test(input_file, group, OPTIMIZER)
        end

    end

end

@testset "Games.jl interaction" begin
    
    @testset "Utility callback test" begin
        for base_group in [EnergyCommunity.GroupNC(), EnergyCommunity.GroupANC()]
            for no_aggregator_group in [EnergyCommunity.GroupNC(), EnergyCommunity.GroupANC()]
                _utility_callback_test(input_file, OPTIMIZER, base_group; no_aggregator_group=no_aggregator_group)
            end
        end
    end
        
    @testset "Least profitable group callback test" begin
        # base case of the simulation
        base_group = GroupNC()
        for no_aggregator_group in [GroupNC(), GroupANC()]
            _least_profitable_callback_test(input_file, OPTIMIZER, base_group; no_aggregator_group=no_aggregator_group)
        end
    end
        
    @testset "Games.jl - Shapley" begin
        # base case of the simulation
        base_group = GroupNC()
        for no_aggregator_group in [GroupNC(), GroupANC()]  # exclude CO as base case
            _profit_distribution_Games_jl_test(input_file, EnumMode, base_group, shapley_value, OPTIMIZER; no_aggregator_group=no_aggregator_group)
        end
    end

end
