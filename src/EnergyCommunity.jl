module EnergyCommunity

    using ExportAll
    using Formatting
    using JuMP
    using Plots
    using DataFrames
    using MathOptInterface
    using Base.Iterators
    # import ECharts
    import SankeyPlots
    import CSV
    import XLSX
    import FileIO
    import YAML

    const MOI = MathOptInterface
    
    # additional usefull functions i.e. main type definitions and read data
    include("utils.jl")  

    # EC model definition
    include("ECModel_definitions.jl")
    
    # functions to calculate the shared energy among users
    include("energy_shares.jl")  

    # add the base modelling for all Energy Communities
    include("base_model.jl")
    
    # Main functions to build and print the model of the system where each user is on its own, thus no EC
    include("non_cooperative.jl")
    
    # Functions to build and print the model of the system in the EC configuration
    include("cooperative_EC.jl")

    # include the abstract types for encapsuling the method
    include("ECModel.jl")

    # include the callbacks to be used in the Games package
    include("Games_jl_interface.jl")

    @exportAll()
end # module
