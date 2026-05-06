#| message: false
#| warning: false
library(leaflet)
library(leaflet.extras)
library(sf)
library(rmapshaper)
library(htmlwidgets)

center_lng <- -95.3; center_lat <- 31.0

texas_map <- st_read("GHWMI_PCWT_2023.geojson", quiet=TRUE) |> 
  st_transform(4326) |>
  ms_simplify(keep = 0.05, keep_shapes = TRUE)

providers <- st_read("ProviderLocations.geojson", quiet=TRUE) |>
  st_transform(4326)
providers <- providers[!is.na(providers$Latitude), ]

texas_map$population <- as.numeric(texas_map$PWCT_TX_2023_pop)
min_val <- min(texas_map$population, na.rm = TRUE)
texas_map$population[is.na(texas_map$population)] <- min_val

pal_pop <- colorNumeric(palette = c("#efe9ef", "#53284F"), domain = texas_map$population)
pal_perk <- colorNumeric(palette = c("#efe9ef", "#53284F"), domain = texas_map$PWCT_TX_2023_total_PerK)

m <- leaflet(
  elementId = "test_map",
  height = "85vh",
  width  = "99vw",
  options = leafletOptions(
    zoomDelta = 0.5,
    zoomSnap = 0,
    dragging = FALSE,
    minZoom = 6.2999,
    scrollWheelZoom = FALSE
  )
) |>
  addProviderTiles(
    "CartoDB.Positron",
    options = providerTileOptions(opacity = 0)
  ) |>
  setView(
    lng = center_lng - 3,
    lat = center_lat,
    zoom = 6.4999
  ) |>
  setMaxBounds(
    lng1 = -106.6,
    lat1 = 25.8,
    lng2 = -93.5,
    lat2 = 36.5
  ) |>
  mapOptions(zoomToLimits = "always") |>
  
  addPolygons(
    data = texas_map,
    group = "Population",
    fillColor = ~pal_pop(population),
    weight = 2,
    color = "white",
    fillOpacity = 1,
    stroke = TRUE,
    highlightOptions = highlightOptions(
      weight = 5,
      opacity = 1,
      color = "#D24699",
      bringToFront = TRUE
    ),
    label = ~paste(
      "There were",
      format(round(population, 0), big.mark = ","),
      "women aged 15–49 in",
      CNTY_NM,
      "County in 2023."
    ),
    popup = ~paste(CNTY_NM, "County"),
    labelOptions = labelOptions(
      direction = "auto",
      textsize = "14px",
      style = list(
        "font-weight" = "normal",
        "padding" = "8px 10px",
        "font-size" = "14px",
        "line-height" = "1.3",
        "width" = "280px",
        "white-space" = "normal",
        "word-wrap" = "break-word"
      )
    )
  ) |>
  addPolygons(
    data = texas_map,
    group = "Total Providers per 1,000 Women 15-49",
    fillColor = ~pal_perk(PWCT_TX_2023_total_PerK),
    weight = 2,
    color = "white",
    fillOpacity = 1,
    stroke = TRUE,
    highlightOptions = highlightOptions(
      weight = 5,
      opacity = 1,
      color = "#D24699",
      bringToFront = TRUE
    ),
    label = ~paste(
      "There were",
      round(PWCT_TX_2023_total_PerK, 2),
      "providers per 1,000 women aged 15–49 in",
      CNTY_NM,
      "County in 2023 with 10 new birth control prescriptions per 1,000 women of reproductive age in 2023."
    ),
    popup = ~paste(CNTY_NM, "County"),
    labelOptions = labelOptions(
      direction = "auto",
      textsize = "14px",
      style = list(
        "font-weight" = "normal",
        "padding" = "8px 10px",
        "font-size" = "14px",
        "line-height" = "1.3",
        "width" = "280px",
        "white-space" = "normal",
        "word-wrap" = "break-word"
      )
    )
  ) |>
  
  addMarkers(
    data = providers[providers$Grantee == "FPP", ],
    lat = ~Latitude,
    lng = ~Longitude,
    popup = ~paste0(Provider.Name, " is an FPP provider."),
    clusterOptions = markerClusterOptions(),
    group = "FPP Providers"
  ) |>
  addMarkers(
    data = providers[providers$Grantee == "HTW", ],
    lat = ~Latitude,
    lng = ~Longitude,
    popup = ~paste0(Provider.Name, " is an HTW provider."),
    clusterOptions = markerClusterOptions(),
    group = "HTW Providers"
  ) |>
  
  addLayersControl(
    baseGroups = c("Population", "Total Providers per 1,000 Women 15-49"),
    overlayGroups = c("FPP Providers", "HTW Providers"),
    position = "bottomright",
    options = layersControlOptions(collapsed = TRUE)
  ) |>
  
  addLegend(
    pal = pal_pop,
    values = texas_map$population,
    title = "Population of women (15–49)",
    opacity = 1,
    group = "Population",
    className = "legend-pop"
  ) |>

  addLegend(
    pal = pal_perk,
    values = texas_map$PWCT_TX_2023_total_PerK[!is.na(texas_map$PWCT_TX_2023_total_PerK)],
    title = "Total providers per 1,000 women (15–49)",
    opacity = 1,
    group = "Total Providers per 1,000 Women 15-49",
    className = "legend-perk"
  ) |>
  setMapWidgetStyle(list(background = "white")) |>
  addResetMapButton() |>
  hideGroup("Total Providers per 1,000 Women 15-49") |>
  hideGroup("FPP Providers") |>
  hideGroup("HTW Providers")

m
