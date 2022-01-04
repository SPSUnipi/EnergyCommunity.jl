"Return main data elements of the dataset of the ECModel: general parameters, users data and market data"
function explode_data(ECModel::AbstractEC)
    return general(ECModel.data), users(ECModel.data), market(ECModel.data)
end


"Set the EC group type"
function set_group_type!(ECModel::AbstractEC, group::AbstractGroup)
    ECModel.group_type = group
end

"Build the mathematical problem for the EC"
function build_model!(ECModel::AbstractEC)

    # build the model
    build_model!(ECModel.group_type, ECModel, ECModel.optimizer)

    # return the model
    return ECModel
end

"Abstract build function model for generic EnergyCommunity model"
function build_model!(group_type::AbstractGroup, ECModel::AbstractEC, optimizer)

    # the build model for the NC/ANC case is eqvuivalent to the base model
    build_base_model!(ECModel, optimizer)

    # add the NC/ANC-specific model
    build_specific_model!(group_type, ECModel)

    # set objective
    set_objective!(group_type, ECModel)

    # return the model
    return ECModel
end


"Solve the optimization problem for the EC"
function optimize_model!(ECModel::AbstractEC)
    optimize!(ECModel.model)
    ECModel.results = jump_to_dict(ECModel.model)
    return ECModel
end


"Output results for the NC configuration"
function output_results(ECModel::AbstractEC,
    output_file::AbstractString, output_file_plot::AbstractString,
    ::Union{GroupNC, GroupANC}; user_set::Vector = Vector())
    return output_results_NC(ECModel.data, ECModel.results_NC, 
            output_file, output_file_plot, user_set=user_set)
end

"Output results for the EC configuration"
function output_results(ECModel::AbstractEC,
    output_file::AbstractString, output_file_plot::AbstractString,
    ::GroupCO; user_set::Vector = Vector())
    return output_results_EC(ECModel.data, ECModel.results,
            output_file, output_file_plot, ECModel.results_NC, user_set=user_set)
end



"""
    save(ECModel::AbstractEC, output_file::AbstractString)
Function to save the results and the model to the hard drive
"""
function save(ECModel::AbstractEC, output_file::AbstractString)
    save_model = Dict(
        "data"=> ECModel.data,
        "user_set"=>ECModel.user_set,
        "group_type"=>string(typeof(ECModel.group_type)),
        "results"=>ECModel.results
    )
    FileIO.save(ECModel.data, output_file)
end

"""
    load(ECModel::AbstractEC, output_file::AbstractString)
Function to save the results and the model to the hard drive
"""
function load(ECModel::AbstractEC, output_file::AbstractString)

    ## load raw data and preliminary checks
    raw_data = FileIO.load(output_file)

    # check if file contains the data of the ECModel
    for k_val in ["data", "user_set", "group_type", "results"]
        if k_val ∉ keys(raw_data)
            throw(ArgumentError("File $output_file not a valid ECModel: missing keyword $k_val"))
        end
    end

    # check if the group_type is compatible with the available instances
    if !any([string(g) == raw_data["group_type"] for g in subtypes(AbstractGroup)])
        throw(ArgumentError("File $output_file not a valid EC group type"))
    end

    ## load data
    ECModel.data = raw_data["data"]
    ECModel.gen_data = general(ECModel.data)
    ECModel.market_data = market(ECModel.data)
    ECModel.users_data = users(ECModel.data)

    # load user_set available from configuration file
    user_set_from_user_list = collect(keys(ECModel.users_data))

    ## load user_set
    ECModel.user_set = unique(get(raw_data, "user_set", user_set_from_user_list))

    if isempty(ECModel.user_set)  # check if user_set is not empty
        throw(Error("user_set in configuration file $output_file is empty"))
    else  # check if all user_set names are available in the config
        diffset = setdiff(Set(ECModel.user_set), Set(user_set_from_user_list))  # elements of user_set not in the config
        if !isempty(diffset) #check that all user_set elements are in the list
            throw(Error("user_set in configuration file $output_file is empty: missing elements $(collect(diffset))"))
        end
    end


    # load group_type
    ECModel.group_type = eval(Meta.parse(raw_data["group_type"] * "()"))

    ECModel.model = Model()  # JuMP model not initialized
    ECModel.results = raw_data["results"]
    
    return ECModel
end


"""

Function to verify the data loaded from the disk
"""
function _verify_data(data::Dict)


end


"""

Function to verify the users data loaded from the disk
"""
function _verify_users_data(users_data::Dict)
    # check non-empty users data
    if isempty(users_data)
        throw(ArgumentError("Input users data are empty"))
    end

    # loop over each user to check whether the names of the assets
    # are in the accepted list
    for (user_name, u_data) in users_data
        # loop for every technology
        if u_data isa AbstractDict
            for (tech_name, tech_value) in u_data
                # check if keyword "type" is in the list
                if "type" ∉ tech_value
                    throw(ArgumentError("Type of technology not specified for technology name $tech_name of user $user_name"))
                end
                if tech_value["type"] ∉ ACCEPTED_TECHS
                    throw(ArgumentError("Type of technology $(tech_value["type"]) not in the available techs 
                        for user $user_name and technology name $tech_name"))
                end
            end
        end
    end

end

"""

Function to plot the EC model
"""
function Plots.plot(ECModel::ModelEC, output_plot_file::AbstractString="")
    Plots.plot(ECModel.group_type, ECModel, output_plot_file)
end


"""
Function to print a summary of the results of the model.
The function dispatches the execution to the appropriate function depending on the Aggregation type of the EC
"""
function print_summary(ECModel::AbstractEC; kwargs...)
    print_summary(ECModel.group_type, ECModel, kwargs...)
end


"""
Function to save a summary of the results of the model.
The function dispatches the execution to the appropriate function depending on the Aggregation type of the EC
"""
function save_summary(ECModel::AbstractEC, output_file::AbstractString; kwargs...)

    # set user_set into kwargs by externak kwargs or deafault user_set of ECModel
    kwargs_dict = Dict{Symbol, Any}(kwargs)
    # if user_set not in the inputs, add it
    if :user_set ∉ keys(kwargs_dict)
        kwargs_dict[:user_set] = ECModel.user_set
    end
    
    # get list of DataFrames to save
    output_list = prepare_summary(ECModel.group_type, ECModel; kwargs_dict...)

    # create parent dirs as needed
    mkpath(dirname(output_file))

    # Write XLSX table
    XLSX.openxlsx(output_file, mode="w") do xf
        # write the dataframe calculated before as an excel file

        if !isempty(output_list)
            #Rename first empty sheet to design_users amd write the corresponding DataFrame
            xs = xf[1]
            XLSX.rename!(xs, output_list[1][1])
            XLSX.writetable!(xs, DataFrames.eachcol(output_list[1][2]),
                DataFrames.names(output_list[1][2]))
        
            # add all the others sheets
            for i = 2:length(output_list)
                xs = XLSX.addsheet!(xf, output_list[i][1])
                XLSX.writetable!(xs, DataFrames.eachcol(output_list[i][2]),
                    DataFrames.names(output_list[i][2]))
            end
        end
    end
end