# rcrisp Shiny app

This repository hosts the web app for the [`rcrisp`](https://github.com/CityRiverSpaces/rcrisp) repositoy, built using the [Shiny](https://shiny.posit.co/) framework.

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

