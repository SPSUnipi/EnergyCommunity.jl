#==============================================================================
# ACCESSOR FUNCTIONS - Dynamic dispatch for AbstractEC
# Provide uniform access to fields regardless of concrete type (ModelEC vs StochasticEC)
# NOTE: With the new flat structure, both types have identical field access patterns
==============================================================================#

# --- GETTERS ---

"""
    data(m::AbstractEC)

Get the data dictionary from the model.
"""
get_data(m::AbstractEC) = m.data

"""
    gen_data(m::AbstractEC)

Get the general data dictionary from the model.
"""
get_gen_data(m::AbstractEC) = m.gen_data

"""
    market_data(m::AbstractEC)

Get the market data dictionary from the model.
"""
get_market_data(m::AbstractEC) = m.market_data

"""
    users_data(m::AbstractEC)

Get the users data dictionary from the model.
"""
get_users_data(m::AbstractEC) = m.users_data

"""
    jump_model(m::AbstractEC)

Get the JuMP/StochasticProgram model from the model.
For ModelEC, returns a JuMP Model.
For StochasticEC, returns a StochasticProgram.
"""
get_jump_model(m::AbstractEC) = m.model

"""
    optimizer(m::AbstractEC)

Get the optimizer from the model.
"""
get_optimizer(m::AbstractEC) = m.optimizer

"""
    results(m::AbstractEC)

Get the results dictionary from the model.
"""
get_results(m::AbstractEC) = m.results

# Stochastic-specific getters
"""
    stoch_model(m::StochasticEC)

Alias for jump_model(m) for StochasticEC (returns the StochasticProgram).
"""
get_stoch_model(m::StochasticEC) = m.model

"""
    scenarios(m::StochasticEC)

Get the scenarios vector (only for StochasticEC).
"""
get_scenarios(m::StochasticEC) = m.scenarios

"""
    n_scen_s(m::StochasticEC)

Get the number of long-term scenarios (only for StochasticEC).
"""
get_n_scen_s(m::StochasticEC) = m.n_scen_s

"""
    n_scen_eps(m::StochasticEC)

Get the number of short-term scenarios (only for StochasticEC).
"""
get_n_scen_eps(m::StochasticEC) = m.n_scen_eps

# --- SETTERS ---

"""
    set_optimizer!(m::AbstractEC, opt)

Set the optimizer for the model.
"""
set_optimizer!(m::AbstractEC, opt) = (m.optimizer = opt)

"""
    set_results!(m::AbstractEC, res::Dict)

Set the results dictionary for the model.
"""
set_results!(m::AbstractEC, res::Dict) = (m.results = res)

"""
    set_jump_model!(m::AbstractEC, jm)

Set the JuMP/StochasticProgram model.
"""
set_jump_model!(m::AbstractEC, jm) = (m.model = jm)

# Stochastic-specific setters
"""
    set_stoch_model!(m::StochasticEC, sm::StochasticProgram)

Alias for set_jump_model! for StochasticEC.
"""
set_stoch_model!(m::StochasticEC, sm::StochasticProgram) = (m.model = sm)

"""
    set_scenarios!(m::StochasticEC, scen::Vector{Scenario_Load_Renewable})

Set the scenarios vector (only for StochasticEC).
"""
set_scenarios!(m::StochasticEC, scen::Vector{Scenario_Load_Renewable}) = (m.scenarios = scen)

"""
    set_n_scen_s!(m::StochasticEC, n::Int)

Set the number of long-term scenarios (only for StochasticEC).
"""
set_n_scen_s!(m::StochasticEC, n::Int) = (m.n_scen_s = n)

"""
    set_n_scen_eps!(m::StochasticEC, n::Int)

Set the number of short-term scenarios (only for StochasticEC).
"""
set_n_scen_eps!(m::StochasticEC, n::Int) = (m.n_scen_eps = n)