# 3. `users` Section

The `users` section defines all participating users and their asset portfolios, as shown below:

```yaml
users:
  ...
  user1:
    tariff_name: <tariff_type>
    asset1:
      type: <asset_type>
      ...
    asset2:
      type: <asset_type>
      ...
    ...
  
  user2:
    tariff_name: <tariff_type>
    ...

  ...
```

The overall structure has the following major characteristics:
- Each user is identified by a unique user ID (e.g., `user1`, `user2`)
- Each user has a specified tariff type under the `tariff_name` field, which determines the pricing structure applicable to that user in agreement to the tariff types available in the `market` section
- Each user can own multiple assets, each defined under its unique asset name (e.g., `asset1`, `asset2`), with each asset having a specified type (e.g., `renewable`, `storage`, `load`, etc.) and associated parameters relevant to that asset type
- Each user may own different types and numbers of assets, also of the same type, allowing for diverse configurations within the Energy Community to investigate technology options

### Example

An example for a domestic user having a photovoltaic (PV) system and a load profile is shown below:

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
