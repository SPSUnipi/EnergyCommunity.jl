![CI](https://github.com/SPSUnipi/EnergyCommunity.jl/actions/workflows/CI.yml/badge.svg)
[![Docs dev](https://img.shields.io/badge/docs-latest-blue.svg)](https://spsunipi.github.io/EnergyCommunity.jl/dev/)
[![Docs stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://spsunipi.github.io/EnergyCommunity.jl/stable/)

# EnergyCommunity.jl
Optimization of Energy Communities becomes easy with EnergyCommunity.jl!

The package allows to describe any Energy Community using a readable configuration file using yaml format and a simple execution.
EnergyCommunity.jl then creates a mathematical optimization model using [JuMP.jl](https://jump.dev/JuMP.jl/stable/) and solves it using any optimization solver compatible with JuMP.jl. The JuMP mathematical model is also editable and customized.

See the following example to understand how to use the package.

## Example

The following example describes how to install and execute a simple Energy Community model.

### Installation

```julia
julia> import Pkg

julia> Pkg.add("EnergyCommunity")  # EnergyCommunity package

julia> Pkg.add("JuMP")  # The optimization package

julia> Pkg.add("HiGHS")  # Open-source solver to solve the optimization problem

julia> Pkg.add("Plots")  # Plotting package
```

### Execution

After the installation, you can run a simple example as follows:

```julia
using EnergyCommunity
using HiGHS, Plots, JuMP

# create a sample Energy Community model input files in folder "data"
create_example_data("data")

# define input configuration (available in the package)
input_file = "./data/energy_community_model.yml"

# define pattern of plot by user: the "{:s}" will be filled with the name of the user
output_plot_combined = "outputs/Img/plot_user_{:s}_EC.png"

# create the Energy Community model in Cooperation mode GroupCO()
ECModel = ModelEC(input_file, EnergyCommunity.GroupCO(), HiGHS.Optimizer)

# build the model
build_model!(ECModel)

# optimize the model
optimize!(ECModel)

# create some plots
plot(ECModel, output_plot_combined)
```


# Folder structure
```
├── docs
│   └── ...
├── examples
│   └── ...
├── LICENSE
├── Project.toml
├── README.md
├── run_cloud
│   └── ...
├── src
│   ├── aggregated_non_cooperative.jl
│   ├── base_model.jl
│   ├── cooperative.jl
│   ├── data
│   │   └── default
│   │       ├── energy_community_model_flexibility.yml
│   │       ├── energy_community_model_heat.yml
│   │       ├── energy_community_model_thermal.yml
│   │       ├── energy_community_model.yml
│   │       ├── flexibility_resource.csv
│   │       ├── input_heating_cooling.csv
│   │       ├── input_resource.csv
│   │       └── market_data.csv
│   ├── stochastic
│   │       ├── base_model.jl < ---- new
│   │       └── cooperative.jl <.--- new
│   ├── ECModel_definitions.jl
|   |── ECModel_utils.jl <---- NEW
│   ├── ECModel.jl
│   ├── EnergyCommunity.jl
│   ├── Games_jl_interface.jl
│   ├── non_cooperative.jl
│   └── utils.jl
├── StochFile
│   ├── base_model.jl
│   ├── cooperative.jl
│   ├── ECModel_definitions(DONE).jl
│   ├── ECModel(TBD).jl <------ NEWS
```
Qui sopra ho inserito funzioni polimorfiche che risolvono a runtime il tipodi EC e gestiscono l'estrazione dei dati automaticamente. In particolare, ora lo stesso codice funziona su EC di tipo diverso grazie al dynamyc dispatch a runtime e non a "tempo di compilazione" (ammesso in julia si possa parlare di tempo di compilazione).

Ho aggiunto anche `extract_declared_values` con la logica preesistente: io uso una logica diversa nel mio codice, potrebbe non funzionare.

Da gestire il dispatch tra stocastico e deterministico, ma vediamo quale delle due versioni ci piace.
```
│   ├── energy_community_model.yml
│   ├── input_resource.csv
│   ├── main.jl
│   ├── market_data.csv
│   ├── market_data_no_penalties.csv
│   ├── pem_extraction.jl <---- OK
│   ├── point_Scen_eps_sampler.jl <---- OK
```
Le condizioni dentro l'if `second_stage == true` e il ramo `else` sono identici. Secondo me si può collassare a un if first stage - else.

Nel mio codice la logica è totalmente cambiata, per ora lascerei la tua versione per semplicità (la mia è più complicata e non ne vale la pena).

Propongo di inserire dentro `src` una cartella `scenarios` per chiarezza.
```
│   ├── print_functions.jl
│   ├── README.txt
│   ├── scenario_definition.jl
```
Ristrutturato in `scenario_definition_FS.jl` dimmi che ne pensi. È più pronto alle estensioni con facilità.
```
│   └── utils(DONE).jl
└── test
    ├── ...
    └── ...
    ```