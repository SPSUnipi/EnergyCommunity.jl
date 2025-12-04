# Fair benefit allocation

## Scope of fair allocation in energy communities

EnergyCommunity.jl also provides tools for fair allocation of benefits among participants in an energy community supported by Game Theory. Fair allocation is crucial to ensure that all members are motivated to form, stay and contribute to the community's success. The package implements several well-known methods for fair allocation, including the Shapley value, the nucleolus, FairCore and FairLeastCore, among others, thanks to its interface with [TheoryOfGames.jl](https://github.com/SPSUnipi/theoryofgames.jl). While the optimization model described in the previous sections focuses on minimizing the overall costs of the energy community, fair allocation methods ensure that the benefits derived from cost savings are distributed equitably among all participants. For more details, please refer to:

- D. Fioriti, A. Frangioni, D. Poli, "Optimal sizing of energy communities with fair revenue sharing and exit clauses: Value, role and business model of aggregators and users," in Applied Energy, vol. 299, 2021, 117328,[doi: 10.1016/j.apenergy.2021.117328](https://doi.org/10.1016/j.apenergy.2021.117328)
- D. Fioriti, G. Bigi, A. Frangioni, M. Passacantando and D. Poli, "Fair Least Core: Efficient, Stable and Unique Game-Theoretic Reward Allocation in Energy Communities by Row-Generation," in IEEE Transactions on Energy Markets, Policy and Regulation, vol. 3, no. 2, pp. 170-181, June 2025, [doi: 10.1109/TEMPR.2024.3495237](https://doi.org/10.1109/TEMPR.2024.3495237).

Let ``j \in I`` be the set of participants (also known as "grand coalition") in the energy community (including the aggregator ``A``), and let ``v(J)`` a generic function that describes the benefit of creating and participating in an energy community for any subgroup ``J \subseteq I`` of participants. The goal of fair allocation methods is to distribute the total benefit ``v(I)`` among all participants in a way that is considered fair according to specific criteria defined by each method. In other words, the goal is to find an allocation vector ``\phi_j \; , \; \forall j \in I`` where ``\sum_{j \in I} \phi_j = v(I)`` and each ``\phi_j`` represents the fair share of the benefit allocated to participant ``j``. In the following section, we describe examples of supported fair allocation methods.

## Benefit function

The benefit ``v(J)`` is typically calculated as the difference between the objective function ``{SW}^{{group}_{agg}}(J)`` obtained by a cooperative configuration (usually `CO`) and the value ``{SW}^{{group}_{base}}(J)`` obtained by a base configuration (typically `NC`). To account for the role of the aggregator, the behavior of the function depends on whether the aggregator ``A`` is part of the coalition ``J`` or not: when the aggregator is not included in the coalition, the benefit is calculated with respect to an alternative group ``{SW}^{{group}_{no-agg}}(J)`` (e.g., `NC` or `ANC`). Formally, the characteristic function ``v(J)`` is defined as follows:

```math
v(J) = \begin{cases}
    {SW}^{{group}_{agg}}(J) - {SW}^{{group}_{base}}(J) & "A" \in J \\
    {SW}^{{group}_{no-agg}}(J) - {SW}^{{group}_{base}}(J) & "A" \notin J
\end{cases}
```

In typical scenarios, the cooperative configuration is represented by `CO`, while the base configuration is `NC`. When a community is unable to create an EC with no external support, the alternative group without the aggregator can be represented by `NC` and the characteristic function simplifies to the following typical case:

```math
v(J) = \begin{cases}
    {SW}^{CO}(J) - {SW}^{NC}(J) & "A" \in J \\
    0 & "A" \notin J
\end{cases}
```

## Benefit versus users' payoff

As explained in the previous section, the benefit function ``v(J)`` quantifies the total advantage that a coalition of users ``J`` with respect to a base case allocation. Accordingly, the fair share of the benefit ``\phi_j`` allocated to participant ``j`` represents the portion of the total benefit ``v(I)`` that is fairly assigned to that participant **with respect to the base case configuration**.

Therefore, let's assume that each user ``j`` has a payoff ``\mathrm{NPV}^{base}_j`` in the base case configuration (e.g., `NC`). The total payoff for user ``j`` after fair allocation of the benefit is given by the sum of the base case payoff and the allocated fair share of the benefit:

```math
\mathrm{NPV}^{fair}_j = \mathrm{NPV}^{base}_j + \phi_j
```

Where:
- ``\mathrm{NPV}^{fair}_j`` is the total payoff for user ``j`` after fair allocation.
- ``\mathrm{NPV}^{base}_j`` is the payoff for user ``j`` in the base case configuration (usually `NC`).
