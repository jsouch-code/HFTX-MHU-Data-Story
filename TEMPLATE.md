# Reusable Dataset Template

This project can be reused for another geography/program by swapping data files and updating a few parameters.

## 1) Prepare replacement data

Provide two GeoJSON files with the same schema expected by `index.qmd`:

- `population_geojson` (county/region polygons)
- `provider_geojson` (provider point locations)

### Required columns

In `population_geojson`:
- `CNTY_NM`
- `PWCT_TX_2023_pop`
- `PWCT_TX_2023_total_PerK`

In `provider_geojson`:
- `Latitude`
- `Longitude` (or geometry with valid coordinates)

## 2) Set template params in `index.qmd`

Edit the `params:` block at the top:

```yaml
params:
  place_name: "Texas"
  population_geojson: "GHWMI_PCWT_2023.geojson"
  provider_geojson: "ProviderLocations.geojson"
  report_year: 2023
```

For a new dataset, point these to your replacement files and set `report_year`.

## 3) Update narrative copy

Search and update state/program-specific text in `index.qmd` (for example, references to Texas-specific programs).

## 4) Render

```bash
quarto render index.qmd
```

## 5) QA checklist

- Map loads and polygons render.
- Provider markers render.
- Tooltips show correct year and place.
- Citations and references still align with new data claims.
