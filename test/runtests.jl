using EnergyCommunity, JuMP, Plots
using Test, FileIO, GLPK, HiGHS, MathOptInterface
using ReferenceTests

# needed to avoid problems with qt when plotting
ENV["GKSwstype"]="nul"

const MOI = MathOptInterface

# EC groups to test
const EC_GROUPS = [EnergyCommunity.GroupCO(), EnergyCommunity.GroupNC()]

input_file = joinpath(@__DIR__, "./data/energy_community_model.yml")  # Input file


include("tests.jl")

@testset "EnergyCommunity tests" begin

    # Loop over group types
    for group in EC_GROUPS

        @testset "Group $(string(group))" begin
            _base_test(input_file, group, HiGHS.Optimizer)
        end

    end

    @testset "Callback test" begin
        _callback_test(input_file, HiGHS.Optimizer)
    end

end
