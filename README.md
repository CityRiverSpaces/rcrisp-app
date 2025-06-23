# CRiSp Shiny

Shiny app for City River Spaces (CRiSp)

## Run the app locally

Create an environment with all the required dependencies (select `explicit` mode when prompted for input):

```r
# install.packages("renv")
renv::init()
```

Start the app, listening on port 3838:

```r
library(shiny)
runApp("app", port = 3838)
```

Open browser on <http://127.0.0.1:3838>

