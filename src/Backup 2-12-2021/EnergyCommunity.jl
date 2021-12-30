module EnergyCommunity

    using ExportAll
    using Formatting
    using JuMP
    using Plots
    using DataFrames
    using Parameters
    import CSV
    import Gurobi
    import XLSX
    using FileIO
    import YAML
    
    # additional usefull functions i.e. main type definitions and read data
    include("utils.jl")  
    
    # functions to calculate the shared energy among users
    include("energy_shares.jl")  
    
    # Main functions to build and print the model of the system where each user is on its own, thus no EC
    include("non_cooperative.jl")
    
    # Functions to build and print the model of the system in the EC configuration
    include("cooperative_EC.jl")
    
    # Function to plot the Sankey diagrams (energy shares by user)
    include("CreateSankeyDiagram.jl")

    # include the abstract types for encapsuling the method
    include("ECModel.jl")

    @exportAll()
end # module
