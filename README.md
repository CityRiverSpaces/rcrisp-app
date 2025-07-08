# rcrisp shiny app

This repository hosts the code for the [Shiny](https://shiny.posit.co/) web app built for the [`rcrisp`](https://github.com/CityRiverSpaces/rcrisp) software package.

You can try out the app at the following URL: https://cforgaci.shinyapps.io/rcrisp/

## Deploy the app on shinyapps.io

The app is deployed on shinyapps.io. In order to setup the deployment:

* Login to https://www.shinyapps.io/ (GitHub authentication can be used);

* When logging in the first time, you will be prompted to choose a username;

* Get a token and the corresponding secret to authorize deployment of the app: on shinyapps.io, select ["Account" > "Tokens"](https://www.shinyapps.io/admin/#/tokens), then select a token (or create a new one), finally click on "Show" and "Show secret".

* Save username, token, and secret as GitHub repository secrets: select ["Settings" > "Secrets and variables" > "Actions"](https://github.com/CityRiverSpaces/rcrisp-app/settings/secrets/actions), then create (or modify) the following repository secrets assigning them the corresponding values retrieved from shinyapps.io: `SHINYAPPS_USERNAME`, `SHINYAPPS_TOKEN`, `SHINYAPPS_SECRET`.

* The app is deployed to shinyapps.io using GitHub actions via this [workflow file](.github/workflows/deploy.yml). The action updates the deployment every time `app.R` or `renv.lock` are modified on the "main" branch of this repository. It is also possible to manually trigger a new deployment from [the "Actions" tab](https://github.com/CityRiverSpaces/rcrisp-app/actions/workflows/deploy.yml), by clicking on `Run workflow`.

* The app is deployed at a URL of the following form: https://USERNAME.shinyapps.io/APPNAME/ (the APPNAME is set in the [workflow file](.github/workflows/deploy.yml)). If the URL of the deployment is modified, please update the URL in the first section of this README file and the URL in the repository details.

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

