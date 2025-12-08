# User energy model

This section describes the mathematical model used to represent the energy system beyond power in *EnergyCommunity.jl*. The model integrates:

- **Heat Pumps (HP)**: devices providing heating and cooling
- **Thermal Storage (TES)**: storage tanks with losses and capacity limits for heat and/or cool
- **Boilers**: fuel-fired boilers
- **Thermal Loads**: time-varying heating/cooling demand

## Heat Pumps

Each heat pump ``h \in A^{HP}_j`` operated by user ``j`` consumes electricity ``P^{HP,el}_{j,h,t}`` to provide thermal power ``P^{HP}_{j,h,t}``, where ``x_{j,h}`` is the variable of the nominal electrical capacity of the heat pump.

```math
0 \le P^{HP,el}_{j,h,t} \le x_{j,h}
```

The heat pump can operate in either heating or cooling mode, determined by the variable `mode`: when `mode` is greater than or equal to +0.5, the heat pump operates in heating mode; when `mode` is less than or equal to –0.5, it operates in cooling mode.

- **Heating power when mode ≥ +0.5**
- **Cooling power when mode ≤ –0.5**

Accordingly, the thermal output ``P^{HP}_{j,h,t}`` of the heat pump is defined based on the mode of operation using temperature-dependent COP/EER values:

```math
P^{HP}_{j,h,t} =
\begin{cases}
\;\; P^{HP,el}_{j,h,t} \cdot COP_{j,h,t}, & \text{(heating mode)}\\
-\, P^{HP,el}_{j,h,t} \cdot EER_{j,h,t}, & \text{(cooling mode)}
\end{cases}
```

The performances of heat pump are modelled using a **second-law efficiency** multiplied by the Carnot efficiency:

```math
COP_{j,h,t}
= \eta^{II,heat}_{j,h,t}
\cdot
\frac{T_{sink}}{T_{sink} - T_{source}(t)}
```
```math
EER_{j,h,t}
= \eta^{II,cool}_{j,h,t}
\cdot
\frac{T_{source}(t)}{T_{sink} - T_{source}(t)}
```
where:
- ``\eta^{II,heat}_{j,h,t}`` and ``\eta^{II,cool}_{j,h,t}`` are the second-law efficiencies for heating and cooling, respectively.
- ``T_{sink}`` is the temperature of the heat sink (e.g., indoor temperature for heating, outdoor temperature for cooling).
- ``T_{source}(t)`` is the time-varying temperature of the heat source (e.g., outdoor temperature).

## Thermal Storage (TES)

Each thermal energy storage ``s \in A^{TES}_j`` has volumetric capacity ``x_{j,s}`` and supports storing heat and/or cool depending on the input parameters and operation ``mode``. The thermal energy ``E^{TES}_{j,s,t}`` stored in the storage ``s`` at time step ``t`` is modelled depending on the specific heat capacity of the fluid ``{cp}_{j,s}``, the reference temperature of the fluid in the storage in heating/cooling mode ``T^{ref,heat/cool}_{j,s,t}``, and the input temperature of the fluid ``T^{in,heat/cool}_{j,s,t}``:

When in heating mode (`mode` ≥ +0.5):

```math
0 \le E^{TES}_{j,s,t} \le {cp}_{j,s} x_{j,s} \left(T^{ref,heat}_{j,s,t} - T^{in,heat}_{j,s,t} \right)
```

When in cooling mode (`mode` ≤ –0.5):

```math
{cp}_{j,s} x_{j,s} \left(T^{in,cool}_{j,s,t} - T^{ref,cool}_{j,s,t} \right) \le E^{TES}_{j,s,t} \le 0
```

TES loses heat proportionally by factor ``k_{j,s}`` to stored energy and to the temperature difference between the reference heating or cooling temperature of the fluid ``T^{ref,heat/cool}_{j,s,t}``, in the storage and the unheated-zone temperature ``T^U_{j,s,t}``:

When in heating mode (`mode` ≥ +0.5):

```math
L^{TES}_{j,s,t} = k_{j,s} E^{TES}_{j,s,t-1} \left(T^{ref,heat}_{j,s,t} - T^U_{j,s,t}\right)
```

When in cooling mode (`mode` ≤ –0.5):

```math
L^{TES}_{j,s,t} = k_{j,s} E^{TES}_{j,s,t-1} \left(T^U_{j,s,t} - T^{ref,cool}_{j,s,t}\right)
```

The effective temperature ``T^U_{j,s,t}`` is modelled as a fraction of the indoor–outdoor temperature gradient:

```math
T^U_{j,s,t} = T^{int}_{j,s,t} - b^{tr}_{j,s} \left( T^{int}_{j,s,t} - T^{ext}_{j,s,t} \right)
```

where:

* ``T^{int}_{j,s,t}`` = indoor reference temperature (user profile `"T_int"`)
* ``T^{ext}_{j,s,t}`` = external ambient temperature (user profile `"T_ext"`)
* ``b^{tr}_{j,s}`` = thermal transmittance factor (`"b_tr_x"`) controlling how much of the indoor–outdoor gradient affects the TES


## Boilers

Boilers ``o \in A^{BOIL}_j`` are fuel-fired heating units producing thermal power ``P^{boil}_{j,o,t}``. Their nominal capacity is represented by variable ``x_{j,o}`` and limits the thermal power output:

```math
0 \le P^{boil}_{j,o,t} \le x_{j,o}
```

## Thermal Energy Balance

For each user ``j`` at every time step ``t``, the thermal balance equation ensures that thermal demand is met by thermal technologies:

```math
\sum_{s \in A^{TES}_j} \left[ E^{TES}_{j,s,t} - E^{TES}_{j,s,t-1} + L^{TES}_{j,s,t} \right]
+
\sum_{l \in A^{TL}_j}
P^{th}_{j,l,t} \Delta_t
=
\sum_{h \in A^{HP}_j} P^{HP}_{j,h,t} \Delta t
+
\sum_{o \in A^{BOIL}_j} P^{boil}_{j,o,t}\Delta t
```

where:
- ``A^{TL}_j`` is the set of thermal loads for user ``j``
- ``P^{th}_{j,l,t}`` is the thermal power demand of load ``l`` at time ``t`` (positive for heating, negative for cooling)
- ``\Delta_t`` is the time step duration
- ``L^{TES}_{j,s,t}`` are the thermal losses from TES
- ``P^{HP}_{j,h,t}`` is the thermal power provided by heat pumps
- ``P^{boil}_{j,o,t}`` is the thermal power provided by boilers
- ``E^{TES}_{j,s,t}`` is the energy stored in TES at time ``t``
