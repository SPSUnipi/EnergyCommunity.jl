module EnergyCommunity

    using ExportAll
    using Format
    using JuMP
    using Plots
    using DataFrames
    using MathOptInterface
    using Base.Iterators
    using TheoryOfGames
    using StatsPlots
    # import ECharts
    import SankeyPlots
    import CSV
    import XLSX
    import FileIO
    import YAML
    import InteractiveUtils
    using StochasticPrograms
    
    try
        import CPLEX
    catch e
        @warn "CPLEX not loaded; features may be limited"
    end
    try
        import Gurobi
    catch e
        @warn "Gurobi not loaded; features may be limited"
    end

    const MOI = MathOptInterface
    
    # additional usefull functions i.e. main type definitions and read data
    include("utils.jl")  
    #### new include
    include("stochastic/point_Scen_eps_sampler.jl")

    include("stochastic/scenario_definition_FS.jl")
    include("stochastic/pem_extraction.jl")

    # EC model definition
    include("ECModel_definitions.jl")

    # add the base modelling for all Energy Communities
    include("base_model.jl")
    
    # Main functions to build and print the Non-Cooperative model
    include("non_cooperative.jl")
    
    # Functions to build and print the Cooperative CO model
    include("cooperative.jl")
    
    # Main functions to build and print the Aggregated Non Cooperative model
    include("aggregated_non_cooperative.jl")

    # include the abstract types for encapsuling the method
    include("ECModel.jl")

    # include the callbacks to be used in the TheoryOfGames package
    include("Games_jl_interface.jl")


    include("stochastic/nonCooperativeStoch.jl")
    include("stochastic/cooperativeStoch.jl")
    include("stochastic/print_functions.jl")


    @exportAll()
end # module
