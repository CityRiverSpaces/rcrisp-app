library(bslib)
library(dplyr)
library(leaflet)
library(osmdata)
library(rcrisp)
library(shiny)
library(sf)


ui <- page_sidebar(
  title = "City River Spaces (CRiSp)",
  sidebar = sidebar(
    # City name as input
    textInput("city_name", label = "City name:", value = "city name"),
    actionButton("city", "Fetch"),
    # River name as input
    textInput("river_name", label = "River name:", value = "river name"),
    actionButton("river", "Fetch"),
    # Run corridor delineation
    numericInput(
      "max_corridor_width",
      label = "Max corridor width (meter):",
      value = 3000
    ),
    actionButton("corridor", "Delineate Corridor"),
    # Download output of delineation
    downloadButton("download")
  ),
  leafletOutput("outmap", height = 950)
)

server <- function(input, output, session) {

  bb <- eventReactive(input$city, {
    withProgress(message = "Fetching city bounding box", value = 1/3, {
      get_osm_bb(input$city_name)
    })
  })

  river <- eventReactive(input$river, {
    withProgress(message = "Fetching river geometry", value = 1/3, {
      get_river(input$river_name)
    })
  })

  corridor <- eventReactive(input$corridor, {
    bb <- bb()
    river <- river()
    max_width <- input$max_corridor_width
    withProgress(message = "Setting up the delineation", value = 0, {
      # Transform to projected CRS and determine area of interest
      crs <- get_utm_zone(bb)
      river <- st_transform(river, crs)
      bb <- st_transform(bb, crs)
      aoi <- get_aoi(river = river, bb = bb, buffer = max_width)
      setProgress(1/4, message = "Fetching network data")
      streets <- get_osm_streets(st_transform(aoi, "EPSG:4326"), crs = crs)
      railways <- get_osm_railways(st_transform(aoi, "EPSG:4326"), crs = crs)
      setProgress(2/4, message = "Building the network")
      network <- bind_rows(streets, railways) |>
        as_network()
      setProgress(3/4, message = "Running the delineation")
      corridor <- delineate_corridor(network, river, max_width = max_width)
      # Return the corridor in lat/lon
      st_transform(corridor, "EPSG:4326")
    })
  })

  output$outmap <- renderLeaflet({
    leaflet("outmap") |>
      addTiles()
  })

  output$download <- downloadHandler(
    filename = "corridor.gpkg",
    content = function(file) {
      st_write(corridor(), file, append = FALSE)
    }
  )

  observe({
    polygon <- st_as_sfc(bb())
    leafletProxy("outmap", session) |>
      clearGroup("bbox") |>
      addPolygons(data = polygon, color = "red", group = "bbox")
  })

  observe({
    leafletProxy("outmap", session) |>
      clearGroup("river") |>
      addPolylines(data = river(), color = "blue", group = "river")
  })

  observe({
    leafletProxy("outmap", session) |>
      clearGroup("corridor") |>
      addPolygons(data = corridor(), color = "blue", group = "corridor")
  })
}

get_river <- function(river_name) {
  # Query the Nominatim API, return all results
  waterway_rivers <- getbb(river_name, format_out="data.frame") |>
    filter(class == "waterway"  & type == "river" & osm_type == "relation")
  # Only consider top entry, and extract OSM ID (type should be "relation")
  # TODO: error handling for no element found or multiple matches
  waterway_river <- waterway_rivers[1, ]
  feature <- get_osm_feature(waterway_river$osm_type, waterway_river$osm_id)
  # Extract the geometries of the features, merge in a (MULTI)LINESTRING
  # TODO: fix invalid geometries?
  river_geometry <- st_geometry(feature$osm_lines)
  river_geometry <- st_union(river_geometry)
}

get_osm_feature <- function(type, id) {
  # Character or numeric (not integer) is equired
  opq_osm_id(type = type, id = as.character(id)) |>
    opq_string() |>
    osmdata_sf()
}

get_aoi <- function(river, bb = NULL, buffer = NULL) {
  if (!is.null(bb)) river <- st_crop(river, bb)
  if (!is.null(buffer)) river <- st_buffer(river, buffer)
  river
}

shinyApp(ui = ui, server = server)
