
# User power model

## User's goal

### Net Present Value

The Net Present Value ``NPV_j`` of each user ``j`` accounts for the cash flows for every year ``y \in Y``, where ``Y`` is the set of years in the planning horizon, accounting for net revenues ``R_{j,y}`` by exchanging energy with the grid, investment costs ``I_{j,y}``, peak charges ``PP_{j,y}``, operating costs ``OP_{j,y}``, replacement costs ``{RP}_{j,y}``, and residual value ``{RV}_{j,y}`` at the end of the project, discounted at rate ``r``:

```math
\mathrm{NPV}_j = \sum_{y \in Y} \frac{ R_{j,y} - I_{j,y} - OF_{j,y} - OV_{j,y} - PP_{j,y} - RP_{j,y} + RV_{j,y} }{(1+r)^y}
```

### Net Revenues of energy flow with the grid

The net revenues are proportional to the energy withdrawn from the grid ``P^{U-}_{j,t}``, the energy injected into the grid ``P^{U+}_{j,t}``, and the consumption ``P^L_{j,t}`` to the main grid, weighted by the respective prices ``{\pi}^{+}_{j,t}``, ``{\pi}^{-}_{j,t}``, and excise ``{\pi}^{ex}_{j,t}`` at each time period ``t \in T``, where ``t`` is the set of time periods in the planning horizon, and scaled by the time resolution ``\Delta_t`` and the weighting factor ``m^T_t`` of each period to account for the use of representative days:

```math
R_{j,y} = \sum_{t \in T} m^T_t \Delta_t \left( {\pi}^{+}_{j,t}P^U_{j,t,+} - {\pi}^{-}_{j,t}P^U_{j,t,-} - {\pi}^{ex}_{j,t}P^L_{j,t} \right)
```

### Investment Costs

Investment charges are incurred only at the beginning of the project (``y = 0``) and account for the all assets ``A_j`` owned by the user ``j``. The cost of each asset ``a \in A_j`` is proportional to the nominal capacity ``x_{a,j}`` of that asset and the per-unit cost ``c^I_{a,j}``:

```math
I_{j,0} = \sum_{a\in A_j} c^I_{a,j} x_{a,j}, \qquad I_{j,y}=0 \;\; \forall y>0
```

### Fixed Operating costs

Yearly fixed operating costs ``OP_{j,y}`` include costs proportional the nominal capacity ``x_{a,j}`` of each asset by per-unit cost factor ``c^M_{a,j}``. Fixed operating costs do not apply to fuel-fired generators ``A^G_j``, as their maintenance charges are proportional to the number of dispatched hours and accounted for in the variable operating costs.

```math
OF_{j,y} = \sum_{a\in A_j} x_{a,j} c^M_{a,j} \quad \forall a \in A_j / A^G_j
```

### Variable Operating costs (fuel-fired assets)

Variable operating costs ``OV_{j,y}`` account for the fuel costs and maintenance charges related to the operation of fuel-fired generators ``A^G_j`` and fuel-fired boilers ``A^{boil}_j`` owned by user ``j``. The fuel consumption ``F_{j,g,t}`` of each generator ``g \in A^G_j`` at time ``t`` is multiplied by the fuel cost ``{\pi}^F_{j,g}`` and scaled by the weighting factor ``m^T_t`` of each period to account for the use of representative days. The maintenance costs of generators are proportional to the number of hours the units have been dispatched and the per-unit maintenance cost ``c^M_{g,j}``. The fuel costs of boilers ``o \in A^{boil}_j`` are proportional to the thermal power output ``P^{boil}_{j,o,t}``, the fuel price ``{\pi}^F_{j,o}``, and inversely proportional to the product of the lower heating value ``{PCI}_{j,o}`` and efficiency ``{\eta}_{j,o}`` of the boiler:

```math
OV_{j,y} = \sum_{t\in T} m^T_t \left[\sum_{g \in A^G_j} ( \pi^F_{j,g} F_{j,g,t} + \Delta_t c^M_{g,j} s_{j,g,t}) + \sum_{o \in A^{boil}_j} \Delta_t {\pi}^F_{j,o} \dfrac{P^{boil}_{j,o,t}}{PCI_{j,o} {\eta}_{j,o}}  \right]
```

### Peak Power Charges

The peak-power charges ``{PP}_{j,y}`` describes charges related to the nominal capacity of the connection to the grid, that are modelled proportional the maximum peak power at the POD ``P^{U,max}_{j,w}`` and the per-unit cost ``c^P_{j,w}`` for each representative peak period ``w \in W``, where ``W`` is the set of peak periods, scaled by the weighting factor ``m^W_w`` of each period to account for the use of representative days:

```math
{PP}_{j,y} = \sum_{w\in W} m^W_w \, c^P_{j,w} \, P^{U,\max}_{j,w}
```

### Replacement Costs

The replacement charges ``RP_{j,y}`` describe the costs for replacing assets during the project. When an asset ``a \in A_j`` reaches its end of life ``N^Y_{a,j}``, that is `` {mod}(y, N^Y_{a,j}) = 0 ``, the asset is replaced thus leading to additional expences. The replacement costs are modelled proportional the nominal capacity ``x_{a,j}`` of each asset by per-unit cost factor ``c^I_{a,j}``, as for the investment costs:

```math
RP_{j,y} = \begin{cases}
\displaystyle
\sum_{a\in A_j} x_{a,j} c^I_{a,j},
& \text{if } \mathrm{mod}(y, N^Y_{a,j}) = 0 \\
0, & \text{otherwise}
\end{cases}
```

### Residual Value

Finally, the residual value ``RV_{j,y}`` accounts for the remaining value of assets at the end of the project (``y = |Y|``); for all other years ``RV_{j,y} = 0``. For each asset ``a \in A_j``, if the asset has not reached its end of life ``N^Y_{a,j}``, a fraction of the investment cost proportional to the remaining useful life is considered.

```math
RV_{j,|Y|} = \sum_{a\in A_j} x_{a,j} c^I_{a,j} \frac{ N^Y_{a,j} - \mathrm{mod}(|Y|-1, N^Y_{a,j}) }{N^Y_{a,j}}
```

## Power Balance

The energy balance of the energy system at each user ``j`` and time ``t`` is guaranted by the following equation:

```math
P^{U+}_{j,t} - P^{U-}_{j,t} + \sum_{c\in A^C_j}(P^{c-}_{j,t} - P^{c+}_{j,t}) - P^R_{j,t} + \sum_{g \in A^G_j}P^g_{j,t} + \sum_{d \in A^D_j}P^{\text{adj}}_{j,d,t} + \sum_{h \in A^{HP}_j}P^{HP,el}_{j,h,t} = - \sum_{f \in A^F_j} P^L_{j,f,t}
```

where:
- ``P^{U+/U-}_{j,t,+}`` is the power injected (+) into or withdrawn (-) from the grid by user ``j`` at time ``t`` measured at the Point of Delivery (PoD);
- ``P^{c-/c+}_{j,t}`` is the discharging power of converter ``c``;
- ``P^R_{j,t}`` is the total renewable generation;
- ``P^g_{j,t}`` is the power generated by fuel-fired generator ``g``;
- ``P^{\text{adj}}_{j,d,t}`` is the net power exchanged by adjustable load ``d``;
- ``P^{HP}_{j,h,t}`` is the power consumed by heat pump ``h`` whose modelling is described in the section of thermal model;
- ``P^L_{j,t}`` is the power consumption of user ``j`` at time ``t``.
- ``A^{C/G/R/D/F}_j`` is the set of converters (C), fuel-fired generators (G), renewable assets (R) and dispatchable (D) and fixed (F) loads owned by user ``j``;

## Peak Power Definition

For each user ``j`` and window `w`, the peak-power ``P^{U,\max}_{j,w}`` is defined as the maximum power withdrawn or injected from the grid ``P^U_{j,t,-}`` over all time periods ``t`` in the representative peak-period window ``T_w``:

```math
P^{U,\max}_{j,w} \ge \max\left(P^{U+}_{j,t},\, P^{U-}_{j,t}\right) \quad \forall t \in T_w
```

In linear form, the max is implemented with the following two constraints:

- ``P^{U,max}_{j,w} \ge P^U_{j,t,+}, \quad \forall t \in T_w``
- ``P^{U,max}_{j,w} \ge P^U_{j,t,-}, \quad \forall t \in T_w``

## Renewable Generation Limit

For each user ``j`` and time step ``t``, the total renewable generation ``P^R_{j,t}`` is limited by the set ``A^R_j`` of renewable assets, their nominal capacity ``x_{r,j}`` that is a variable optimized by the algorithm and the per-unit renewable production ``p^r_{j,t}``:

```math
P^R_{j,t} \le \sum_{r\in A^R_j} p^r_{j,t}\, x_{r,j}
```

## Battery and Converter Constraints

Each battery ``b \in A^B_j`` owned by user ``j``, where ``A^B_j`` is the set of storage assets owned by user ``j``, must have a corresponding converter ``c(b) \in A^C_j``, where ``A^C_j`` is the set of converters owned by user ``j``. The converter ``c(b)`` is used to charge and discharge the battery ``b``. 

For battery ``b \in A^B_j`` owned by user ``j``, the energy ``E_{j,b,t}`` stored in the battery is regulated by the following equation, where ``P^{c(b)+}_{j,t}`` is the charging power of the converter ``c(b)``, ``P^{c(b)-}_{j,t}`` is the discharging power of the converter ``c(b)``, and ``{\eta}_b`` is the round-trip efficiency of the battery ``b``.

```math
E_{j,b,t} = E_{j,b,t-1} - \Delta_t \frac{P^{c(b)+}_{j,t}}{\eta_b} + \Delta_t \eta_b P^{c(b)-}_{j, t}
``` 

Maximum and minimum energy limits apply:

```math
\beta^{min}_{b,j} x_{b,j} \le E_{j,b,t} \le \beta^{max}_{b,j} x_{b,j}
```

Power limits on the converter ``c`` apply as follows, where ``x_{c,j}`` is the nominal power capacity of the converter ``c`` owned by user ``j``:

- Maximum charging ``P^{c+}_{j,t} \le x_{c,j}``
- Maximum discharging ``P^{c-}_{j,t} \le x_{c,j}``


## Modular units

Units where modularity option is enabled are modelled by introducing integer variables ``n_{a,j}`` representing the number of installed modules of type ``A^M_j`` and constraints linking the total capacity to the number of modules and the capacity per module. ``n_{a,j}`` is an integer variable representing the number of modules of asset ``a`` owned by user ``j``, and `` \overline{S}^a_j `` is the capacity per module.

```math
x_{a,j} = n_{a,j} \overline{S}^a_j` \quad \forall a \in A^M_j
```


## Fuel-Fired Generators

The dispatch of each fuel-fired generator ``g \in A^G_j`` owned by user ``j`` is regulated by unit-commitment constraints and require modularity option, that is the fuel-fired generators are of standardized nominal capacity ``\overline{S}^a_j``. Minimum and maximum power limitations apply. Accordingly, the generation ``P^g_{j,t}`` is limited by the number of dispatched units ``s_{j,g,t}`` as shown below:

```math
\beta^{min}_{j,g} \overline{S}^a_j x_{g,j} \le P^g_{j,t} \le \beta^{max}_{j,g} \overline{S}^a_j x_{g,j}
```

The number of dispatched units is limited by the number of installed units ``n_{g,j}``:

```math
s_{g,j} \le n_{g,j}
```

The fuel consumption ``F_{j,g,t}`` is proportional to the generated power ``P^g_{j,t}`` by the using a piece-wise linear function of slope ``c^{FS,g}_j`` and intercept ``c^{FI,g}_j``:

```math
F^g_{j,t} = c^{FS,g}_j P^g_{j,t} + \Delta c^{FI,g}_j s_{j,g,t}
```

## Adjustable loads

Adjustable loads represent appliances whose electrical consumption can be modulated in time within technical boundaries while still satisfying a mandatory **energy trajectory** over the planning horizon. Examples include electric vehicles (EVs) or flexible industrial processes. Adjustable loads do have power constraints and energy constraints. The latter ensures that the total energy consumed (or supplied) by the adjustable load over the planning horizon matches a predefined energy trajectory.

Each adjustable load ``d \in A^D_j`` among the adjustable loads ``A^D_j`` owned by the user ``j`` is indexed by can absorb (``P^{\text{adj},N}_{j,d,t}``) or supply (``P^{\text{adj},P}_{j,d,t}``) power in agreement to specific constraints, where ``\overline{P}^{\text{withdrawal}}_{j,d,t}`` and ``\overline{P}^{\text{supply}}_{j,d,t}`` are specific inputs (constants or time series) provided by the user. For simplicity, we denote ``P^{\text{adj}}_{j,d,t}`` the net power exchanged by the adjustable load ``d`` at time ``t``, defined as the difference between the power withdrawn and supplied.

```math
  0 \le P^{\text{adj},N}_{j,d,t} \le \overline{P}^{\text{withdrawal}}_{j,d,t}\\
  0 \le P^{\text{adj},P}_{j,d,t} \le \overline{P}^{\text{supply}}_{j,d,t}\\
  P^{\text{adj}}_{j,d,t} = P^{\text{adj},N}_{j,d,t} - P^{\text{adj},P}_{j,d,t}
```

The energy trajectory is regulated by the exogenous energy inflow ``{\xi}_{j,d,t}`` (positive for charging and negative for discharging) that defines the net energy flows to the component. The energy stored in the adjustable load ``E^{\text{adj}}_{j,d,t}`` at each time ``t`` is modelled as follows, where ``\eta^P_{j,d}`` and ``\eta^N_{j,d}`` are the efficiencies related to power supply and withdrawal.

```math
  E^{\text{adj}}_{j,d,t} = E^{\text{adj}}_{j,d,t-1} - \Delta_t \frac{P^{\text{adj},P}_{j,d,t}}{\eta^P_{j,d}} + \Delta_t P^{\text{adj},N}_{j,d,t}\,\eta^N_{j,d} + {\xi}_{j,d,t}
```

Maximum and minimum energy limits also apply:

```math
  \underline{E}^{\text{adj}}_{j,d,t} \le E^{\text{adj}}_{j,d,t} \le \overline{E}^{\text{adj}}_{j,d,t}
```

This component can be used to model both energy storage systems (e.g., EV batteries) and flexible loads with specific energy requirements. For example, a charging station for Electric Vehicles can be modelled as an adjustable load where power and energy limits are non-zero when vehicles are connected to the recharging station, and the energy trajectory ``{\xi}_{j,d,t}`` corresponds to the required state of charge by a specific time (e.g., departure time). In particular, when an EV with a given state of charge connects to the station, ``{\xi}_{j,d,t}`` in that time step can be positive and match that value, signaling the additional state of charge that is being connected. Conversely, when an EV leaves the station, the station is deprived of energy and thus ``{\xi}_{j,d,t}`` becomes negative. Energy limits are adapted accordingly to model the total minimum and maximum state of charge of all EVs connected to the station at each time ``t``.

## Deferrable loads (not implemented yet)

Deferrable loads represent loads that can be shifted in time within certain limits but must be fully served within a specified time window. Examples include certain industrial processes or household appliances like washing machines.

> Not implemented yet.
