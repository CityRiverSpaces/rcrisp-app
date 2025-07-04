library(bsicons)
library(bslib)
library(dplyr)
library(leaflet)
library(osmdata)
library(rcrisp)
library(shiny)
library(sf)
library(sfnetworks)
library(tidygraph)


ui <- page_sidebar(
  title = "City River Spaces (CRiSp)",
  sidebar = sidebar(
    # City name as text input
    textInput("city_name", label = "City name:", value = "city name"),
    actionButton("city", "Check"),
    # River name as text input
    textInput("river_name", label = "River name:", value = "river name"),
    actionButton("river", "Check"),
    # Network buffer size as numeric input
    numericInput(
      "max_corridor_width",
      label = "Max corridor width (meters):",
      value = 3000
    ),
    # Checkbox to select the valley method
    checkboxInput(
      "valley",
      label = tooltip(
        trigger = list("valley", bs_icon("info-circle")),
        "Use an estimate of the river valley as initial guess of the corridor.
        If unchecked, use a fix buffer region around the river (provide initial
        size).",
        placement = "bottom"
      ),
      value = TRUE
    ),
    # Only if the valley checkbox is unchecked, add the corridor_init field
    uiOutput("corridor_init_input"),
    # Checkbox to run segmentation as well
    checkboxInput("segments", label = "segments", value = TRUE),
    # Action button to start delineation
    actionButton("delineate", label = "Delineate"),
    # Only after the delineate button is clicked, add the download button
    uiOutput("download_button")
  ),
  leafletOutput("outmap", height = 950)
)


server <- function(input, output, session) {
  # Sidebar element control

  # If the "valley" checkbox is unchecked, the corridor_init field is added
  output$corridor_init_input <- renderUI({
    if (!input$valley) {
      numericInput(
        "corridor_init",
        label = "Initial corridor width (meters):",
        value = 1000
      )
    }
  })

  # Clicking the "delineate" button adds the "download" button
  observeEvent(input$delineate, {
    output$download_button <- renderUI({
      downloadButton("download")
    })
  })

  # Actual server control

  # Create the map
  output$outmap <- renderLeaflet({
    leaflet("outmap") |>
      addTiles()
  })

  # Clicking the "check" button under the "city name" field retrieves the
  # bounding box and plots it on the map
  observeEvent(input$city, {
    withProgress(message = "Fetching city bounding box", value = 1 / 3, {
      bb <- get_osm_bb(input$city_name)
    })
    polygon <- st_as_sfc(bb)
    leafletProxy("outmap", session) |>
      clearGroup("bbox") |>
      addPolygons(data = polygon, color = "red", group = "bbox")
  })

  # Clicking the "check" button under the "river name" field retrieves the
  # river geometry and plots it on the map
  observeEvent(input$river, {
    withProgress(message = "Fetching river geometry", value = 1 / 3, {
      river <- get_river(input$river_name)
    })
    leafletProxy("outmap", session) |>
      clearGroup("river") |>
      addPolylines(data = river, color = "blue", group = "river")
  })

  # Clicking the "delineate" button runs the corridor delineation (and,
  # optionally, the segmentation)
  corridor <- eventReactive(input$delineate, {
    withProgress(value = 0, {
      run_delineation(
        input$city_name, input$river_name, max_width = input$max_corridor_width,
        valley = input$valley, corridor_init = input$corridor_init,
        segments = input$segments
      )
    })
  })

  # When a corridor becomes available, add it to the map
  observe({
    leafletProxy("outmap", session) |>
      clearGroup("corridor") |>
      addPolygons(data = corridor(), color = "blue", group = "corridor")
  })

  # Clicking the "download" button saves the corridor to a gpkg file
  output$download <- downloadHandler(
    filename = "corridor.gpkg",
    content = function(file) {
      st_write(corridor(), file, append = FALSE)
    }
  )

}

get_river <- function(river_name) {
  # Query the Nominatim API, return all results
  waterway_rivers <- getbb(river_name, format_out = "data.frame") |>
    filter(class == "waterway" & type == "river" & osm_type == "relation")
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
  # Character or numeric (not integer) is required
  opq_osm_id(type = type, id = as.character(id)) |>
    opq_string() |>
    osmdata_sf()
}

run_delineation <- function(
  city_name, river_name, max_width = 3000, valley = FALSE, corridor_init = 1000,
  segments = FALSE
) {
  # Determine area of interest and transform to projected CRS
  incProgress(message = "Setting up input data")
  bb <- get_osm_bb(city_name)
  river <- get_river(river_name)
  aoi <- get_aoi(river = river, bb = bb, buffer = max_width)
  crs <- get_utm_zone(bb)
  river <- st_transform(river, crs)
  bb <- st_transform(bb, crs)

  # Setting up spatial network
  incProgress(message = "Fetching network data")
  streets <- get_osm_streets(aoi, crs = crs)
  railways <- get_osm_railways(aoi, crs = crs)
  incProgress(message = "Building the network")
  network <- bind_rows(streets, railways) |>
    as_network()

  # If using the valley method, get the DEM and delineate the valley
  if (valley) {
    aoi_dem <- st_buffer(aoi, 2500)
    dem <- get_dem(aoi_dem, crs = crs)
    corridor_init <- delineate_valley(dem, river)
  }

  # Delineate the corridor
  incProgress(message = "Delineating the corridor")
  corridor <- delineate_corridor(
    network, river, max_width = max_width, corridor_init = corridor_init
  )

  # If required, run the segmentation
  if (segments) {
    incProgress(message = "Filtering the network")
    corridor_buffer <- st_buffer(corridor, 100)
    network_filtered <- filter_network(network, corridor_buffer)

    incProgress(message = "Delineating the segments")
    corridor <- delineate_segments(corridor, network_filtered, river)
  }

  # Return geometry after transforming it back to lat/lon
  st_transform(corridor, "EPSG:4326")
}

get_aoi <- function(river, bb = NULL, buffer = NULL) {
  if (!is.null(bb)) river <- st_crop(river, bb)
  if (!is.null(buffer)) river <- st_buffer(river, buffer)
  river
}

filter_network <- function(network, target) {
  network |>
    activate("nodes") |>
    filter(node_intersects(target)) |>
    # keep only the main connected component of the network
    activate("nodes") |>
    filter(group_components() == 1)
}

shinyApp(ui = ui, server = server)
