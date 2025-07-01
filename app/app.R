library(bsicons)
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
    actionButton("city", "Check"),
    # River name as input
    textInput("river_name", label = "River name:", value = "river name"),
    actionButton("river", "Check"),
    # Other inputs for corridor delineation and segmentation
    numericInput(
      "max_corridor_width",
      label = "Max corridor width (meters):",
      value = 3000
    ),
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
    # Add a numericInput field only if the checkbox is unchecked
    uiOutput("corridor_init_input"),
    # Whether to run segmentation as well
    checkboxInput("segments", label = "segments", value = TRUE),
    # Action button to start delineation
    actionButton("delineate", label = "Delineate"),
    # When delineation is done, add download button
    uiOutput("download_button")
  ),
  leafletOutput("outmap", height = 950)
)


server <- function(input, output, session) {

  observeEvent(input$city, {
    withProgress(message = "Fetching city bounding box", value = 1 / 3, {
      bb <- get_osm_bb(input$city_name)
    })
    polygon <- st_as_sfc(bb)
    leafletProxy("outmap", session) |>
      clearGroup("bbox") |>
      addPolygons(data = polygon, color = "red", group = "bbox")
  })

  observeEvent(input$river, {
    withProgress(message = "Fetching river geometry", value = 1 / 3, {
      river <- get_river(input$river_name)
    })
    leafletProxy("outmap", session) |>
      clearGroup("river") |>
      addPolylines(data = river, color = "blue", group = "river")
  })

  output$corridor_init_input <- renderUI({
    if (!input$valley) {
      numericInput(
        "corridor_init",
        label = "Initial corridor width (meters):",
        value = 1000
      )
    }
  })

  corridor <- eventReactive(input$delineate, {
    city_name <- input$city_name
    river_name <- input$river_name
    max_width <- input$max_corridor_width
    withProgress(message = "Setting up the delineation", value = 0, {
      bb <- get_osm_bb(city_name)
      river <- get_river(river_name)
      # Transform to projected CRS and determine area of interest
      crs <- get_utm_zone(bb)
      river <- st_transform(river, crs)
      bb <- st_transform(bb, crs)
      aoi <- get_aoi(river = river, bb = bb, buffer = max_width)
      setProgress(1 / 7, message = "Fetching network data")
      streets <- get_osm_streets(st_transform(aoi, "EPSG:4326"), crs = crs)
      railways <- get_osm_railways(st_transform(aoi, "EPSG:4326"), crs = crs)
      setProgress(2 / 7, message = "Building the network")
      network <- bind_rows(streets, railways) |>
        as_network()
      setProgress(3 / 7, message = "Initializing the corridor")
      if (input$valley) {
        aoi_dem <- st_buffer(st_transform(aoi, "EPSG:4326"), 2500)
        dem <- get_dem(aoi_dem, crs = crs)
        corridor_init <- delineate_valley(dem, river)
      } else {
        corridor_init <- input$corridor_init
      }
      setProgress(4 / 7, message = "Delineating the corridor")
      corridor <- delineate_corridor(network, river, max_width = max_width,
                                     corridor_init = corridor_init)
      if (input$segments) {
        setProgress(5 / 7, message = "Filtering the network")
        corridor_buffer <- st_buffer(corridor, 100)
        network_filtered <- filter_network(network, corridor_buffer)
        setProgress(6 / 7, message = "Delineating the segments")
        segments <- delineate_segments(corridor, network_filtered, river)
        # Return segments in lat/lon
        st_transform(segments, "EPSG:4326")
      } else {
        # Return the corridor in lat/lon
        st_transform(corridor, "EPSG:4326")
      }
    })
  })

  output$outmap <- renderLeaflet({
    leaflet("outmap") |>
      addTiles()
  })

  observeEvent(input$delineate, {
    output$download_button <- renderUI({
      downloadButton("download")
    })
  })

  output$download <- downloadHandler(
    filename = "corridor.gpkg",
    content = function(file) {
      st_write(corridor(), file, append = FALSE)
    }
  )

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

filter_network <- function(network, target) {
  network |>
    tidygraph::activate("nodes") |>
    tidygraph::filter(sfnetworks::node_intersects(target)) |>
    # keep only the main connected component of the network
    tidygraph::activate("nodes") |>
    dplyr::filter(tidygraph::group_components() == 1)
}

shinyApp(ui = ui, server = server)
