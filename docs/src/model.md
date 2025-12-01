# Mathematical Model

The optimization model implemented in EnergyCommunity.jl is based on a Mixed-Integer Linear Programming (MILP) model implemented in [JuMP.jl](https://jump.dev/JuMP.jl), accounting for:

  * Technical operation of assets (loads, PV, storage, flexible resources).
  * Market interaction with the main grid (imports/exports, tariffs).
  * Energy shared among users of the community.
  * Configuration of the EC: non-cooperative, aggregated-non-cooperative, cooperative.

In the following, we provide a general description of the mathematical model, starting from the techno-economic model that is valid for all EC configurations, and then describing the specific models suited for the specific configurations.

The techno-economic model of the Energy Community (EC) is based on the model depicted in the figure below, which highlights the general structure of components available by each user $j \in I$, where $I$ is the set of community members, and energy flows. In the following, we first describe the user's expenses and then the main constraints of the model.

![Scheme of the Energy Community](./images/energy_model.png)

# Energy Community Configuration

The mathematical model implemented in EnergyCommunity.jl can be configured to represent different types of Energy Communities (ECs), namely:

- **Non-cooperative EC**: In this configuration, each user $j \in I$ optimizes its own energy system independently, without considering energy sharing with other community members. The objective function for each user is to maximize its own Net Present Value (NPV) based on individual energy consumption, generation, and costs. Let ${SW}^{NC}(J) = \sum{j \in J} \mathrm{NPV}_j$ be the sum of the Net Present Value for all users, then the optimization problem for the Non-Cooperative formulation is formulated as follows:

  ```math
  \begin{array}{ll}
  \max & {SW}^{NC}(I) = \sum_{j \in I} \mathrm{NPV}_j \\
  \text{s.t.} & \text{Users' power and energy system constraints}
  \end{array}
  ```

  Note that as the problem is separable for each user $j$, it can be solved independently for each user. However, for simplicity, EnergyCommunity.jl implements the problem as a single optimization problem including all users as shown in the previous equation.

- **Aggregated Non-cooperative EC**: In this configuration, each user $j \in I$ still optimizes its own energy system independently, but the model allows for the aggregation of certain resources or costs at the community level. This can include shared infrastructure or collective purchasing of energy, leading to potential cost savings for individual users while still maintaining independent optimization. In mathematical terms, the social welfare ${SW}^{ANC}(I)$ of the community is defined as the sum of the individual NPVs of each user plus an additional term $\mathrm{NPV}^{sh}_{NC}$ that accounts for the benefits or costs associated with shared resources or collective actions. The actual optimization problem remains the same as in the Non-Cooperative case, but the overall social welfare is adjusted to reflect the aggregated aspects of the community.

  ```math
  {SW}^{ANC}(I) = {SW}^{AC}(I) + \mathrm{NPV}^{sh}_{NC}
  ```

- **Cooperative EC**: In this configuration, all users $j \in I$ collaborate to optimize the energy system of the entire community as a whole. The objective function is to maximize the collective NPV of the community, taking into account the energy system of each user havign objective term ${NPV}_j$ and the additional term $\mathrm{NPV}^{sh}$ related to the shared energy. This configuration promotes cooperation and can lead to more efficient energy management and cost savings for all members.

  ```math
  \begin{array}{ll}
  \max & {SW}^{CO}(I) = \sum_{j \in I} \mathrm{NPV}_j + \mathrm{NPV}^{sh} \\
  \text{s.t.} & \text{Users' power and energy system constraints}\\
              & \text{Shared energy constraints}
  \end{array}
  ```


# User power system

## User's goal

### Net Present Value

The Net Present Value $NPV_j$ of each user $j$ accounts for the cash flows for every year $y \in Y$, where $Y$ is the set of years in the planning horizon, accounting for net revenues $R_{j,y}$ by exchanging energy with the grid, investment costs $I_{j,y}$, peak charges $PP_{j,y}$, operating costs $OP_{j,y}$, replacement costs ${RP}_{j,y}$, and residual value ${RV}_{j,y}$ at the end of the project, discounted at rate $r$:

```math
\mathrm{NPV}_j = \sum_{y \in Y} \frac{ R_{j,y} - I_{j,y} - OF_{j,y} - OV_{j,y} - PP_{j,y} - RP_{j,y} + RV_{j,y} }{(1+r)^y}
```

### Net Revenues of energy flow with the grid

The net revenues are proportional to the energy withdrawn from the grid $P^{U-}_{j,t}$, the energy injected into the grid $P^{U+}_{j,t}$, and the consumption $P^L_{j,t}$ to the main grid, weighted by the respective prices ${\pi}^{+}_{j,t}$, ${\pi}^{-}_{j,t}$, and excise ${\pi}^{ex}_{j,t}$ at each time period $t \in T$, where $t$ is the set of time periods in the planning horizon, and scaled by the time resolution $\Delta_t$ and the weighting factor $m^T_t$ of each period to account for the use of representative days:

```math
R_{j,y} = \sum_{t \in T} m^T_t \Delta_t \left( {\pi}^{+}_{j,t}P^U_{j,t,+} - {\pi}^{-}_{j,t}P^U_{j,t,-} - {\pi}^{ex}_{j,t}P^L_{j,t} \right)
```

### Investment Costs

Investment charges are incurred only at the beginning of the project ($y = 0$) and account for the all assets $A_j$ owned by the user $j$. The cost of each asset $a \in A_j$ is proportional to the nominal capacity $x_{a,j}$ of that asset and the per-unit cost $c^I_{a,j}$:

```math
I_{j,0} = \sum_{a\in A_j} c^I_{a,j} x_{a,j}, \qquad I_{j,y}=0 \;\; \forall y>0
```

### Fixed Operating costs

Yearly fixed operating costs $OP_{j,y}$ include costs proportional the nominal capacity $x_{a,j}$ of each asset by per-unit cost factor $c^M_{a,j}$. Fixed operating costs do not apply to fuel-fired generators $A^G_j$, as their maintenance charges are proportional to the number of dispatched hours and accounted for in the variable operating costs.

```math
OF_{j,y} = \sum_{a\in A_j} x_{a,j} c^M_{a,j} \quad \forall a \in A_j / A^G_j
```

### Variable Operating costs (fuel generators)

Variable operating costs $OV_{j,y}$ account for the fuel costs and maintenance charges related to the operation of fuel-fired generators $A^G_j$, where $A^G_j$ is the set of fuel-fired generators owned by user $j$. The fuel consumption $F_{j,g,t}$ of each generator $g \in A^G_j$ at time $t$ is multiplied by the fuel cost ${\pi}^F_{j,g}$ and scaled by the weighting factor $m^T_t$ of each period to account for the use of representative days. The maintenance costs of generators are proportional to the number of hours the units have been dispatched and the per-unit maintenance cost $c^M_{g,j}$.

```math
OV_{j,y} = \sum_{t\in T} m^T_t \sum_{g \in A^G_j} ( \pi^F_{j,g} F_{j,g,t} + \Delta_t c^M_{g,j} s_{j,g,t})
```

### Peak Power Charges

The peak-power charges ${PP}_{j,y}$ describes charges related to the nominal capacity of the connection to the grid, that are modelled proportional the maximum peak power at the POD $P^{U,max}_{j,w}$ and the per-unit cost $c^P_{j,w}$ for each representative peak period $w \in W$, where $W$ is the set of peak periods, scaled by the weighting factor $m^W_w$ of each period to account for the use of representative days:

```math
{PP}_{j,y} = \sum_{w\in W} m^W_w \, c^P_{j,w} \, P^{U,\max}_{j,w}
```

### Replacement Costs

The replacement charges $RP_{j,y}$ describe the costs for replacing assets during the project. When an asset $a \in A_j$ reaches its end of life $N^Y_{a,j}$, that is $ {mod}(y, N^Y_{a,j}) = 0 $, the asset is replaced thus leading to additional expences. The replacement costs are modelled proportional the nominal capacity $x_{a,j}$ of each asset by per-unit cost factor $c^I_{a,j}$, as for the investment costs:

```math
RP_{j,y} = \begin{cases}
\displaystyle
\sum_{a\in A_j} x_{a,j} c^I_{a,j},
& \text{if } \mathrm{mod}(y, N^Y_{a,j}) = 0 \\
0, & \text{otherwise}
\end{cases}
```

### Residual Value

Finally, the residual value $RV_{j,y}$ accounts for the remaining value of assets at the end of the project ($y = |Y|$); for all other years $RV_{j,y} = 0$. For each asset $a \in A_j$, if the asset has not reached its end of life $N^Y_{a,j}$, a fraction of the investment cost proportional to the remaining useful life is considered.

```math
RV_{j,|Y|} = \sum_{a\in A_j} x_{a,j} c^I_{a,j} \frac{ N^Y_{a,j} - \mathrm{mod}(|Y|-1, N^Y_{a,j}) }{N^Y_{a,j}}
```

## Power Balance

The energy balance of the energy system at each user $j$ and time $t$ is guaranted by the following equation, where $P^{U+}_{j,t}$ is the power injected into the grid, $P^{U-}_{j,t}$ is the power withdrawn from the grid, $P^c_{j,t,+}$ and $P^{c+/c-}_{j,t,-}$ are the charging (+) and discharging (-) power of each storage asset $c \in A^C_j$, where $A^C_j$ is the set of storage assets owned by user $j$, $P^R_{j,t}$ is the total renewable generation of the user, and $P^L_{j,t}$ is the load consumption:

```math
P^U_{j,t,+} - P^U_{j,t,-} + \sum_{c\in A^C_j}(P^{c-}_{j,t} - P^{c+}_{j,t}) - P^R_{j,t} +  \sum_{g \in A^G_j}P^g_{j,t} = - P^L_{j,t}
```

## Peak Power Definition

For each user $j$ and window `w`, the peak-power $P^{U,\max}_{j,w}$ is defined as the maximum power withdrawn or injected from the grid $P^U_{j,t,-}$ over all time periods $t$ in the representative peak-period window $T_w$:

```math
P^{U,\max}_{j,w} \ge \max\left(P^U_{j,t,+},\, P^U_{j,t,-}\right) \quad \forall t \in T_w
```

In linear form, the max is implemented with the following two constraints:

- $ P^{U,\max}_{j,w} \ge P^U_{j,t,+}, \quad \forall t \in T_w $
- $ P^{U,\max}_{j,w} \ge P^U_{j,t,-}, \quad \forall t \in T_w $

## Renewable Generation Limit

For each user $j$ and time step $t$, the total renewable generation $P^R_{j,t}$ is limited by the set $A^R_j$ of renewable assets, their nominal capacity $x_{r,j}$ that is a variable optimized by the algorithm and the per-unit renewable production $p^r_{j,t}$:

```math
P^R_{j,t} \le \sum_{r\in A^R_j} p^r_{j,t}\, x_{r,j}
```

## Battery and Converter Constraints

Each battery $b \in A^B_j$ owned by user $j$, where $A^B_j$ is the set of storage assets owned by user $j$, must have a corresponding converter $c(b) \in A^C_j$, where $A^C_j$ is the set of converters owned by user $j$. The converter $c(b)$ is used to charge and discharge the battery $b$. 

For battery $b \in A^B_j$ owned by user $j$, the energy $E_{j,b,t}$ stored in the battery is regulated by the following equation, where $P^{c(b)+}_{j,t}$ is the charging power of the converter $c(b)$, $P^{c(b)-}_{j,t}$ is the discharging power of the converter $c(b)$, and ${\eta}_b$ is the round-trip efficiency of the battery $b$.

```math
E_{j,b,t} = E_{j,b,t-1} - \Delta_t \frac{P^{c(b)+}_{j,t}}{\eta_b} + \Delta_t \eta_b P^{c(b)-}_{j, t}
``` 

Maximum and minimum energy limits apply:

```math
\beta^{min}_{b,j} x_{b,j} \le E_{j,b,t} \le \beta^{max}_{b,j} x_{b,j}
```

Power limits on the converter $c$ apply as follows, where $x_{c,j}$ is the nominal power capacity of the converter $c$ owned by user $j$:

- Maximum charging $ P^{c+}_{j,t} \le x_{c,j} $
- Maximum discharging $ P^{c-}_{j,t,-} \le x_{c,j} $


## Modular units

Units where modularity option is enabled are modelled by introducing integer variables $n_{a,j}$ representing the number of installed modules of type $A^M_j$ and constraints linking the total capacity to the number of modules and the capacity per module. $n_{a,j}$ is an integer variable representing the number of modules of asset $a$ owned by user $j$, and $ \overline{S}^a_j $ is the capacity per module.

```math
x_{a,j} = n_{a,j} \overline{S}^a_j` \quad \forall a \in A^M_j
```


## Fuel-Fired Generators

The dispatch of each fuel-fired generator $g \in A^G_j$ owned by user $j$ is regulated by unit-commitment constraints and require modularity option, that is the fuel-fired generators are of standardized nominal capacity $\overline{S}^a_j$. Minimum and maximum power limitations apply. Accordingly, the generation $P^g_{j,t}$ is limited by the number of dispatched units $s_{j,g,t}$ as shown below:

```math
\beta^{min}_{j,g} \overline{S}^a_j x_{g,j} \le P^g_{j,t} \le \beta^{max}_{j,g} \overline{S}^a_j x_{g,j}
```

The number of dispatched units is limited by the number of installed units $n_{g,j}$:

```math
s_{g,j} \le n_{g,j}
```

The fuel consumption $F_{j,g,t}$ is proportional to the generated power $P^g_{j,t}$ by the using a piece-wise linear function of slope $c^{FS,g}_j$ and intercept $c^{FI,g}_j$:

```math
F^g_{j,t} = c^{FS,g}_j P^g_{j,t} + \Delta c^{FI,g}_j s_{j,g,t}
```

## Deferrable loads (not implemented yet)

Not implemented yet.

## Adjustable loads

Adjustable loads represent appliances whose electrical consumption can be modulated in time within technical boundaries while still satisfying a mandatory **energy trajectory** over the planning horizon. Examples include electric vehicles (EVs) or flexible industrial processes. Adjustable loads do have power constraints and energy constraints. The latter ensures that the total energy consumed (or supplied) by the adjustable load over the planning horizon matches a predefined energy trajectory.

Each adjustable load $d \in A^D_j$ among the adjustable loads $A^D_j$ owned by the user $j$ is indexed by can absorb ($P^{\text{adj},N}_{j,d,t}$) or supply ($P^{\text{adj},P}_{j,d,t}$) power in agreement to specific constraints, where $\overline{P}^{\text{withdrawal}}_{j,d,t}$ and $\overline{P}^{\text{supply}}_{j,d,t}$ are specific inputs (constants or time series) provided by the user. For simplicity, we denote $P^{\text{adj}}_{j,d,t}$ the net power exchanged by the adjustable load $d$ at time $t$, defined as the difference between the power withdrawn and supplied.

```math
  0 \le P^{\text{adj},N}_{j,d,t} \le \overline{P}^{\text{withdrawal}}_{j,d,t}
  0 \le P^{\text{adj},P}_{j,d,t} \le \overline{P}^{\text{supply}}_{j,d,t}
  P^{\text{adj}}_{j,d,t} = P^{\text{adj},N}_{j,d,t} - P^{\text{adj},P}_{j,d,t}
```

The energy trajectory is regulated by the exogenous energy inflow ${\xi}_{j,d,t}$ (positive for charging and negative for discharging) that defines the net energy flows to the component. The energy stored in the adjustable load $E^{\text{adj}}_{j,d,t}$ at each time $t$ is modelled as follows, where $\eta^P_{j,d}$ and $\eta^N_{j,d}$ are the efficiencies related to power supply and withdrawal.

```math
  E^{\text{adj}}_{j,d,t} = E^{\text{adj}}_{j,d,t-1} - \Delta_t \frac{P^{\text{adj},P}_{j,d,t}}{\eta^P_{j,d}} + \Delta_t P^{\text{adj},N}_{j,d,t}\,\eta^N_{j,d} + {\xi}_{j,d,t}
```

Maximum and minimum energy limits also apply:

```math
  \underline{E}_{j,d,t} \le E^{\text{adj}}_{j,d,t} \le \overline{E}_{j,d,t}
```

This component can be used to model both energy storage systems (e.g., EV batteries) and flexible loads with specific energy requirements. For example, a charging station for Electric Vehicles can be modelled as an adjustable load where power and energy limits are non-zero when vehicles are connected to the recharging station, and the energy trajectory ${\xi}_{j,d,t}$ corresponds to the required state of charge by a specific time (e.g., departure time). In particular, when an EV with a given state of charge connects to the station, ${\xi}_{j,d,t}$ in that time step can be positive and match that value, signaling the additional state of charge that is being connected. Conversely, when an EV leaves the station, the station is deprived of energy and thus ${\xi}_{j,d,t}$ becomes negative. Energy limits are adapted accordingly to model the total minimum and maximum state of charge of all EVs connected to the station at each time $t$.

# Shared Energy and benefits

In cooperative and aggregated-non-cooperative ECs, users can share energy among each other, leading to potential cost savings and increased efficiency. The shared energy exchanged among users is modelled by introducing additional variables and constraints that regulate the energy flows within the community.

In mathematical terms, the shared energy benefits $\mathrm{NPV}^{sh}$ in cooperative ECs and $\mathrm{NPV}^{sh}_{NC}$ in aggregated-non-cooperative ECs are defined based on the discunted value of the yearly net benefit $R^{sh}_y$ related to the energy shared.

```math
\mathrm{NPV}^{sh} = \sum_{y \in Y} \dfrac{ \sum R^{sh}_y }{(1+r)^y}
```

$R^{sh}_y$ is defined as proportional to the power $P^{sh}_{j,t}$ that is procuded and consumed among members of the community; ${\pi}^{sh}_{j,t}$ is the per-unit reward for every unit of energy shared. Quantities are scaled by the time resolution $\Delta_t$ and weighted by factor $m^T_t$ similalrly to other terms in the model.

```math
R^{sh}_y = \sum_{t \in T} m^T_t \Delta_t {\pi}^{sh}_{j,t} P^{sh}_{j,t}
```

The shared power $P^{sh}_{j,t}$ for each user $j$ and time $t$ is limited by the surplus generation and demand measured at users' PoD:

```math
P^{sh}_{j,t} = \min \left\lbrace \sum_{j \in I} P^{U-}_{j,t} \; , \; \sum_{j \in I} P^{U-}_{j,t} \right\rbrace
```

In linear form, the min is implemented with the following two constraints:
- $ P^{sh}_{j,t} \le \sum_{j \in I} P^{U-}_{j,t} $
- $ P^{sh}_{j,t} \le \sum_{j \in I} P^{U-}_{j,t} $
