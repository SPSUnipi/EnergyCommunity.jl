

# Community Shared Energy and benefits

In cooperative and aggregated-non-cooperative ECs, users can share energy among each other, leading to potential cost savings and increased efficiency. The shared energy exchanged among users is modelled by introducing additional variables and constraints that regulate the energy flows within the community.

In mathematical terms, the shared energy benefits ``\mathrm{NPV}^{sh}`` in cooperative ECs and ``\mathrm{NPV}^{sh}_{NC}`` in aggregated-non-cooperative ECs are defined based on the discunted value of the yearly net benefit ``R^{sh}_y`` related to the energy shared.

```math
\mathrm{NPV}^{sh} = \sum_{y \in Y} \dfrac{ \sum R^{sh}_y }{(1+r)^y}
```

``R^{sh}_y`` is defined as proportional to the power ``P^{sh}_{j,t}`` that is procuded and consumed among members of the community; ``{\pi}^{sh}_{j,t}`` is the per-unit reward for every unit of energy shared. Quantities are scaled by the time resolution ``\Delta_t`` and weighted by factor ``m^T_t`` similalrly to other terms in the model.

```math
R^{sh}_y = \sum_{t \in T} m^T_t \Delta_t {\pi}^{sh}_{j,t} P^{sh}_{j,t}
```

The shared power ``P^{sh}_{j,t}`` for each user ``j`` and time ``t`` is limited by the surplus generation and demand measured at users' PoD:

```math
P^{sh}_{j,t} = \min \left\lbrace \sum_{j \in I} P^{U-}_{j,t} \; , \; \sum_{j \in I} P^{U-}_{j,t} \right\rbrace
```

In linear form, the min is implemented with the following two constraints:
- ``P^{sh}_{j,t} \le \sum_{j \in I} P^{U-}_{j,t}``
- ``P^{sh}_{j,t} \le \sum_{j \in I} P^{U-}_{j,t}``
