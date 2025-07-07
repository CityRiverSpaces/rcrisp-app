# rcrisp shiny app

This repository hosts the code for the [Shiny](https://shiny.posit.co/) web app built for the [`rcrisp`](https://github.com/CityRiverSpaces/rcrisp) software package.

## Deployment

You can try out the app at the following URL: https://fnattino.shinyapps.io/rcrisp/

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

