using EnergyCommunity
using Documenter
using Literate
using Test

# Deactivate Plots display output on server
ENV["GKSwstype"] = "100"

const _EXAMPLE_DIR = joinpath(@__DIR__, "src", "examples")

"""
    _include_sandbox(filename)
Include the `filename` in a temporary module that acts as a sandbox. (Ensuring
no constants or functions leak into other files.)
"""
function _include_sandbox(filename)
    mod = @eval module $(gensym()) end
    return Base.include(mod, filename)
end

function _file_list(full_dir, relative_dir, extension)
    return map(
        file -> joinpath(relative_dir, file),
        filter(file -> endswith(file, extension), sort(readdir(full_dir))),
    )
end

function link_example(content)
    edit_url = match(r"EditURL = \"(.+?)\"", content)[1]
    footer = match(r"^(---\n\n\*This page was generated using)"m, content)[1]
    content = replace(
        content, footer => "!!! info\n    [View this file on Github]($(edit_url)).\n\n" * footer
    )
    return content
end

function literate_directory(dir)
    rm.(_file_list(dir, dir, ".md"))
    for filename in _file_list(dir, dir, ".jl")
        # `include` the file to test it before `#src` lines are removed. It is
        # in a testset to isolate local variables between files.
        @testset "$(filename)" begin
            _include_sandbox(filename)
        end
        Literate.markdown(
            filename,
            dir;
            documenter = true,
            postprocess = link_example
        )
    end
    return
end

literate_directory(_EXAMPLE_DIR)

examples = [
    "configurations",
    "plotting",
    "io",
    "theory_of_games"
    # "non_cooperative",
    # "aggregated_non_cooperative",
    # "cooperative",
]

makedocs(
    modules = [EnergyCommunity],
    doctest  = false,
    clean    = true,
    format   = Documenter.HTML(
        mathengine = Documenter.MathJax2(),
        collapselevel = 1,
        prettyurls = get(ENV, "CI", nothing) == "true",
        size_threshold_ignore = [
            "API reference.md",
        ]
    ),
    sitename = "EnergyCommunity.jl",
    authors  = "Davide Fioriti",
    pages   = [
        "Introduction" => [
            "index.md",
            "installation.md",
        ],
        "Examples" => [
            joinpath("examples", f * ".md")
            for f in examples
        ],
        "Optimization Model" => [
            "model/intro_model.md",
            "model/power_model.md",
            "model/energy_model.md",
            "model/community_model.md",
        ],
        "Fair reward allocations" => [
            "theory_of_games/fair_allocation.md",
            "theory_of_games/supported_allocations.md",
        ],
        "Configuration" => [
            "configuration.md",
        ],
        "API reference" => "API reference.md",
    ]
)

deploydocs(
    repo = "github.com/SPSUnipi/EnergyCommunity.jl.git",
    push_preview = true,
)
