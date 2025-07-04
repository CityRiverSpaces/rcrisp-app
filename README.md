# CRiSp Shiny App

This repository hosts the City River Spaces (CRiSp) web app, built using the [Shiny](https://shiny.posit.co/) framework. The app represents a graphical user interface (GUI) to [`rcrisp`](https://github.com/CityRiverSpaces/rcrisp).

## Run the app locally

Create an environment with all the required dependencies:

```r
# install.packages("renv")
renv::init(bare = TRUE)
renv::restore()
```

Start the app, listening on port 3838:

```r
library(shiny)
runApp(port = 3838)
```

Open browser on <http://127.0.0.1:3838>

