# Supported fair allocation methods

## Supported fair allocation methods

All allocation methods supported by TheoryOfGames.jl are available in EnergyCommunity.jl. Some of the most relevant methods for energy communities include:

- **Shapley Value**: This method allocates benefits based on each participant's marginal contribution to all possible coalitions. It ensures that participants are rewarded fairly according to their contributions.
- **Nucleolus**: This method focuses on minimizing the maximum dissatisfaction among participants. It aims to find an allocation that is as fair as possible by reducing the largest grievances.
- **Fair Core**: This method ensures that no participant receives less than what they would get by acting alone. It guarantees that the allocation is stable and acceptable to all members.
- **Fair Least Core**: This method relaxes the core concept to allow for some level of dissatisfaction, aiming to find an allocation that is as fair as possible while still being feasible.

## Shapely Value

The Shapley Value is one of the most widely used methods for fair allocation in cooperative game theory. It provides a way to distribute the total benefit of a coalition among its members based on their individual contributions. The Shapley Value for each participant ``j`` is calculated as follows:

```math
\phi_j = \dfrac{1}{|I|} \sum{J \subseteq I}{\binom{|I|-1}{|J|}}^{-1} \left[ v(J) - v(J \setminus \{j\}) \right]
```

Where:
- ``\phi_j`` is the Shapley Value allocated to participant ``j``.
- ``v(J)`` is the characteristic function representing the benefit of coalition ``J``.
- ``|J|`` is the number of participants in coalition ``J``.
- ``|I|`` is the total number of participants in the grand coalition ``I``.
- ``\binom{|I|-1}{|J|}`` is the binomial coefficient representing the number of ways to choose ``|J|`` participants from ``|I|-1`` participants.

The Shapley Value ensures that each participant is rewarded fairly based on their contributions to all possible coalitions, making it a robust method for fair allocation in energy communities. However, it requires the evaluation of the characteristic function for all possible coalitions, which can be computationally intensive for large communities, unless efficient algorithms or approximations are employed.

## Nucleolus

The Nucleolus is another important method for fair allocation in cooperative game theory. It aims to find the unique allocation that lexicographically maximizes the satisfaction of the least satisfied group of participants in joining and staying into the whole community, thus ensuring that the allocation is as fair as possible. The Nucleolus is determined by solving a series of linear programming problems that focus on minimizing the largest excesses (dissatisfactions) of coalitions. The Nucleolus allocation ``\phi`` is found by iteratively solving the following optimization problem:

```math
\begin{array}{ll}
\max & \theta \\
\text{s.t.} & \sum_{j \in J} \phi_j - v(J) \ge \theta \quad \forall j \notin \Gamma \\
            & \sum_{j \in J} \phi_j - v(J) \ge \bar{\theta}_j \quad \forall j \in \Gamma \\
\end{array}
```

Where:
- ``\theta`` is the maximum dissatisfaction to be minimized in the current iteration.
- ``\bar{\theta}_j`` are the dissatisfaction levels fixed from previous iterations for coalitions already considered in previous iterations.
- ``\Gamma`` is the set of coalitions whose dissatisfaction levels have been fixed in previous iterations.

The Nucleolus ensures that the allocation is stable and acceptable to all members by minimizing the maximum dissatisfaction among participants. It is unique, however , it can be computationally intensive to compute, especially for large communities, as it requires solving multiple linear programming problems iteratively and calculate the function v(J) for all coalitions.

## Variance Core and Variance Least Core

The Variance Core and Variance Least Core are methods that ensure stability and fairness in the allocation of benefits among participants in a cooperative game.

The Variance Core distributes benefits to minimize the variance of redistribution, provided that that each participant and group of participats receive no less than the benefits they provide. In mathematical terms, Variance Core identifies the allocation that minimizes the variance of the allocations while satisfying the core constraints.

Let ``\phi`` be the allocation vector for all participants, Variance Core allocation is determined by solving the following optimization problem:

```math
\begin{array}{ll}
\min & \sum_{j \in I} \left( \phi_j - \dfrac{v(I)}{|I|} \right)^2 \\
\text{s.t.} & \sum_{j \in J} \phi_j - v(J) \ge 0 \quad \forall J \subseteq I \\ 
            & \sum_{j \in I} \phi_j = v(I)
\end{array}
```

Where:
- The objective function minimizes the variance of the allocations among participants, promoting fairness.
- The first constraint ensures that no coalition ``J`` receives less than its value.
- The second constraint ensures that the total allocation equals the total value of the grand coalition.

The Variance Least Core is a variation of the Variance Core that allows for a minimum satisfaction level ``\bar{\theta}`` for each coalition, where ``\bar{\theta}`` represents the minimum additional benefit that each coalition should receive beyond its standalone value. Its value is computed by executing the first iteration of the Nucleolus algorithm. The Variance Least Core allocation is determined by solving the following optimization problem:

```math
\begin{array}{ll}
\min & \sum_{j \in I} \left( \sum_{j \in J} \dfrac{\phi_j - \dfrac{v(I)}{|I|}}{|I|} \right)^2 \\
\text{s.t.} & \sum_{j \in J} \phi_j - v(J) \ge \bar{\theta} \quad \forall J \subseteq I \\
            & \sum_{j \in I} \phi_j = v(I)
\end{array}
```

Where:
- The objective function minimizes the variance of the allocations among participants, promoting fairness.
- The first constraint ensures that no coalition ``J`` receives less than its value plus the minimum satisfaction level ``\bar{\theta}``.
- The second constraint ensures that the total allocation equals the total value of the grand coalition.

Both the Variance Core and Variance Least Core aim to provide fair and stable allocations among participants, with the latter allowing for a degree of dissatisfaction to ensure feasibility in cases where the core may be empty.

In its form, the Variance Least Core is simpler than the Nucleolus, however, it still requires the evaluation of the characteristic function for all possible coalitions, which can be computationally intensive for large communities, unless efficient algorithms or approximations are employed. Alternative techniques adopting row-generation techniques are available in TheoryOfGames.jl to efficiently compute these allocations for larger games.

See more details about these allocation methods in the [TheoryOfGames.jl documentation](https://energycommunity-jl.org/TheoryOfGames.jl/stable/) and the original references:

- D. Fioriti, G. Bigi, A. Frangioni, M. Passacantando and D. Poli, "Fair Least Core: Efficient, Stable and Unique Game-Theoretic Reward Allocation in Energy Communities by Row-Generation," in IEEE Transactions on Energy Markets, Policy and Regulation, vol. 3, no. 2, pp. 170-181, June 2025, [doi: 10.1109/TEMPR.2024.3495237](https://doi.org/10.1109/TEMPR.2024.3495237).
