# 3. `users` Section

## Scope and overview of `users` Section

The `users` section defines all participating users and their asset portfolios.

Example:

```yaml
users:
  user1:
    tariff_name: non_commercial
    PV:
      type: renewable
      CAPEX_lin: 1700
      OEM_lin: 30
      lifetime_y: 25
      max_capacity: 300
      profile:
        ren_pu: pv
    load:
      type: load
      profile:
        load: load_user1
  ...
```
