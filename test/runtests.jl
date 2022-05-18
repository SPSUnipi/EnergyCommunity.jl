using EnergyCommunity, JuMP, Plots
using Test, FileIO, GLPK, HiGHS, MathOptInterface, Games, YAML
using ReferenceTests

# needed to avoid problems with qt when plotting
ENV["GKSwstype"]="nul"

const MOI = MathOptInterface

# EC groups to test
const EC_GROUPS = [EnergyCommunity.GroupCO(), EnergyCommunity.GroupNC(), EnergyCommunity.GroupANC()]

const OPTIMIZER = HiGHS.Optimizer

input_file = joinpath(@__DIR__, "./data/energy_community_model.yml")  # Input file


include("tests.jl")

# @testset "EnergyCommunity tests" begin

#     # Loop over group types
#     for group in EC_GROUPS

#         @testset "Group $(string(group))" begin
#             _base_test(input_file, group, OPTIMIZER)
#         end

#     end

# end

@testset "Games.jl interaction" begin
    
    @testset "Utility callback test" begin
        for group in EC_GROUPS
            _utility_callback_test(input_file, OPTIMIZER, group)
        end
    end
        
    @testset "Least profitable group callback test" begin
        _least_profitable_callback_test(input_file, OPTIMIZER)
    end
        
    @testset "Games.jl - Shapley" begin
        for group in [GroupNC(), GroupANC()]  # exclude CO as base case
            _profit_distribution_Games_jl_test(input_file, EnumMode, group, shapley_value, OPTIMIZER)
        end
    end

end
