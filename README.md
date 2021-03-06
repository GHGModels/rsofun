# rsofun

This repository contains R-wrapper functions for all the routine steps in running the SOFUN model:

- setup of the environment
- preparation of input files
- calibrating model parameters
- running the model
- reading outputs into R
- evaluating outputs (benchmarking)

## Environment

Load the package. This contains all the necessary wrapper functions to set up and run SOFUN and read its output. 
```r
library(rsofun)  ## Not yet implemented
```

For the time being, we just go with a set of wrapper functions `prepare_setup_sofun()`, `prepare_input_sofun()`, `runread_sofun()` , and `update_params()`. Load the respective functions.
```r
source("prepare_metainfo_fluxnet2015.R")
source("prepare_setup_sofun.R")
source("prepare_input_sofun.R")
source("runread_sofun.R")
source("update_params.R")
source("eval_sofun.R")
```

## Setup
### Simulation settings
Define the simulation settings as a list. Components of the simulation settings should specify only variables that are identical across simulations within an ensemble. Other variables that differ between simulation within an ensemble (e.g. start and end year of the simulation, vegetation type C3 or C4, longitude and latitude of the site, soil type, etc.) are to be specified in the meta info file `path_siteinfo` (CSV file created "by hand" or some other more clever method for large ensembles - up to you.). The function `prepare_setup_sofun()` complements the simulation settings list by these additional components as lists with elements for each site, nested within the simulation settings list.
```r
settings_sims <- list( 
  path_siteinfo   = "./metainfo_fluxnet2015.csv",
  ensemble        = TRUE,
  lonlat          = FALSE,
  name            = "fluxnet2015",
  dir_sofun       = "~/sofun/trunk/",
  path_output     = "~/sofun/output_fluxnet2015_sofun/s21/",
  path_output_nc  = "~/sofun/output_nc_fluxnet2015_sofun/s21/",
  path_input      = "~/sofun/input_fluxnet2015_sofun_TEST/",
  grid            = NA,
  implementation  = "fortran",
  in_ppfd         = TRUE,
  recycle         = 1,
  spinupyears     = 10,
  soilmstress     = TRUE,
  loutplant       = FALSE,
  loutgpp         = FALSE,
  loutwaterbal    = FALSE,
  loutdtemp_soil  = FALSE,
  loutdgpp        = FALSE,
  loutdrd         = FALSE,
  loutdtransp     = FALSE,
  lncoutdtemp     = FALSE,
  lncoutdfapar    = FALSE,
  lncoutdgpp      = TRUE, 
  lncoutdwaterbal = TRUE
  )
```

- `path_siteinfo`: Path (character string) of a CSV file that contains all the information needed for defining simulations. One row for each simulation in an ensemble, typically sites. Columns are as follows:
    - site name, must be: column number 1 
    - longitude of site, column must be named 'lon'
    - latitude of site, column must be named 'lat'
    - elevation of site, column must be named 'elv'
    - years for which simulation is to be done (corresponding to data availability from site), 
      requires two columns named 'year_start' and 'year_end'.
- `ensemble`: TRUE if an ensemble of site-level simulations are to be run (This may become obsolte, this information is given already if the number of rows in the CSV file `path_siteinfo` is larger than one.)
- `lonlat`: TRUE if simulation(s) are on a spatial longitude/latitude grid (multiple gridcells in one simulation). For point-scale (site-scale) simulations, `lonlat` is FALSE.
- `name`: a character string specifying the name of the ensemble (e.g. 'fluxnet2015') or of a single simulation.
- `dir_sofun`: Path (character string) where the model sits (corresponding to the parent directory of the respective git repository).
- `path_output`: Path (character string) where model output (ascii text files) is written to.
- `path_output_nc`: Path (character string) where NetCDF model output is written to.
- `path_input`: Path (character string) where model input is located. 
- `grid`: Character string defining the type of grid used, e.g. `halfdeg` for half-degree resolution in lon. and lat. (only used if `lonlat=TRUE`).
- `implementation`: Character string specifying whether Fortran (`implementation= "fortran"`) or Python (`implementation= "python"`) version is to be used.
- `in_ppfd`: Switch (`TRUE` of `FALSE`) whether PPFD should be read from data (prescribed) or simulated online using SPLASH and prescribed fractional cloud cover data.
- `recycle`: Periodicity (integer, number of years) of repeating forcing years during spinup (e.g. if the simulation start year is 1982 and `recycle=3`, then forcing years 1979-1981 are repeated during the duration of the model spinup, so that the last year of the spinup is forcing year 1981. For `recycle=1` and simulation start year 1982, forcing year 1981 is used for all years of the model spinup. Here, 'forcing year' refers to the year AD in the climate, CO2, fAPAR, etc. data used as model forcing.
- `spinupyears`: Integer, number of model spinup years before the transient simulation. Use `spinupyears > 0` if the model contains pool variables that that are simulated by dynamics that depend on their current state (typically soil water storage, or plant and soil carbon pools). Typically `spinupyears = 10` is sufficient to bring soil water pools to equilibrium across the globe (unless you chose a large soil water holding capacity).
- `soilmstress`: Switch (`TRUE` of `FALSE`) defining whether soil moisture stress function is to be applied to GPP.
- `lout<var>`: Switch (`TRUE` of `FALSE`) whether variable `<var>` is to be written to output (ascii text file for time series). To be anbandoned, only NetCDF output should be maintained.
- `lncout<var>`: Switch (`TRUE` of `FALSE`) whether variable `<var>` is to be written to output (NetCDF file).

### Input settings
Define data sources used for SOFUN input. This is based on keywords passed on as strings. E.g. `"fluxnet2015"` triggers specific functions that read input data from specific files, here all the site-level meteo data from FLUXNET 2015. Define the input settings as a list.
```r
settings_input <-  list( 
  temperature              = "fluxnet2015",
  precipitation            = "fluxnet2015",
  vpd                      = "fluxnet2015",
  ppfd                     = "fluxnet2015",
  netrad                   = NA,
  cloudcover               = "cru_ts4_01",
  fapar                    = "MODIS_FPAR_MCD15A3H",
  splined_fapar            = TRUE,
  co2                      = "cmip",
  path_cx1data             = "~/data/",
  path_fluxnet2015         = "~/data/FLUXNET-2015_Tier1/20160128/point-scale_none_1d/original/unpacked/",
  path_watch_wfdei         = "~/data/watch_wfdei/",
  path_cru_ts4_01          = "~/data/cru/ts_4.01/",
  path_MODIS_EVI_MOD13Q1   = "~/data/fapar_MODIS_EVI_MOD13Q1_gee_MOD13Q1_fluxnet2015_gee_subset/",
  path_MODIS_FPAR_MCD15A3H = "~/data/fapar_MODIS_FPAR_MCD15A3H_gee_MCD15A3H_fluxnet2015_gee_subset/"
  )
```

- `temperature`: A character string specifying the source for temperature data. Any of `"fluxnet2015"`, `"watch_wfdei"`, and/or `"cru"`. This can also be a vector of strings (e.g. `c("fluxnet2015", "watch_wfdei")`, to specify priorities: first take FLUXNET 2015 data for periods where data is available. For remaining years (given by `settings_sims$date_start` and `settings_sims$date_end`), use WATCH-WFDEI data. If `"fluxnet2015"` is specified for any of `temperature`, `precipitation`, `vpd`, `ppfd`, or `netrad`, then `path_fluxnet2015` must be specified as well in the settings.
- `precipitation`: See `temperature`.
- `vpd`: See `temperature`.
- `ppfd`: See `temperature`.
- `netrad`: See `temperature`.
- `fapar`: A character string specifying the type of fAPAR data used as input. Implemented for use of data from CX1 are `"MODIS_FPAR_MCD15A3H"` and `"MODIS_EVI_MOD13Q1"`. Use `NA` in case no fAPAR data is used as forcing (internally simulated fAPAR).
- `splined_fapar`: Logical defining whether splined fAPAR data is to be used. If `FALSE`, linearly interpolated fAPAR data is used.
- `co2`: A character string specifying which CO$_2$ file should be used (globally uniform and identical for each site in an ensemble). All available CO$_2$ forcing files are located on CX1 at `/work/bstocker/labprentice/data/co2/`. `co2="cmip"` specifies that the CMIP-standard CO2 file `cCO2_rcp85_const850-1765.dat` should be used.
- `path_cx1data`: A character string specifying the local directory that mirrors the data directory on CX1 (very handy!).
- `path_fluxnet2015`: A character string specifying the path where standard FLUXNET 2015 CSV files are located.         
- `path_watch_wfdei`: A character string specifying the path where standard WATCH-WFDEI NetCDF files are located.                  
- `path_cru_ts4_01`: A character string specifying the path where standard CRU NetCDF files are located.
- `path<fapar>`: A character string specifying the path where site-specific fapar files are located. This element is named according to the `fapar` setting (element `fapar` in the list `settings_input`). E.g., an element named `path_MODIS_FPAR_MCD15A3H` is required if `fapar = MODIS_FPAR_MCD15A3H`.

### Model setup
Define model setup as a list.
```r
setup_sofun <- list( 
  model      = "pmodel",
  dir        = "~/sofun/trunk",
  do_compile = FALSE,
  simsuite   = FALSE
  )
```

- `model`: For Fortran version: A character string specifying the compilation option. The name of the executable is derived from this as `"run<setup_sofun$model>"`.
- `dir`: A path (character) specifying the directory of where the executables are located (corresponds to the parent directory of the model git repository).
- `do_compile`: If `TRUE`, the model code is compiled as `make <setup_sofun$model>`. If `FALSE`, compiled executables are used (compiled with gfortran on a Mac 64-bit).
- `simsuite`: If `TRUE`, the SOFUN option for running an entire simulation suite (ensemble of simulations) with a single executable. (In the Fortran implementation, this this requires the main program file `sofun_simsuite.f90` to be compiled instead of `sofun.f90`). This is to be preferred over a set of individual runs submitted individually when doing calibration runs because the cost across the entire ensemble (mod-obs error) can thus be calculated online.


### Calibration settings
Define model calibration settings as a list. Note that in the example below, the element `sitenames` is all the sites where no C4 vegetation is present (or documented to be present). To get this information, first run::
```{r, eval=TRUE, message=FALSE, warning=FALSE}
siteinfo <- prepare_metainfo_fluxnet2015( 
  settings_sims = settings_sims, 
  settings_input = settings_input, 
  overwrite = FALSE, 
  filn_elv_watch = paste0( settings_input$path_cx1data, "watch_wfdei/WFDEI-elevation.nc" ) 
  )
```

Then define the calibration settings as.

```r
settings_calib <- list(
  name             = "kphio_gpp_fluxnet2015",
  par              = list( kphio = list( lower=0.03, upper=0.08, init=0.05792348 ) ),
  method           = "gensa",
  targetvars       = c("gpp"),
  datasource       = list( gpp = "fluxnet2015" ),
  timescale        = list( gpp = "d" ),
  path_fluxnet2015 = "~/data/FLUXNET-2015_Tier1/20160128/",
  maxit            = 300,
  sitenames        = filter(siteinfo$light, c4 %in% c(FALSE, NA) )$mysitename, # calibrate for non-C4 sites
  filter_temp_min  = 5.0,
  filter_temp_max  = 35.0,
  filter_soilm_min = 0.5
 )
```

- `name`: A character string to define a name used for this calibration, used in file names containing calibration outputs.
- `par`: list of parameters to calibrate with their lower and upper boundaries. This is rigid. If you chose to use different parameters or in a different order, modify code in `calib_sofun.R` (function `cost_rmse()`) and in the model source code (`sofun/src/sofun.f90`).
- `targetvars`: Character string for name of variable in SOFUN output
- `datasource`: Named list of character strings with data source identifiers for each calibration target variable. The list is named corresponding to variable names defined by 'targetvars'. The identifier triggers certain functions to be used for reading and processing observational data. Use, e.g., `datasource = list( gpp = "fluxnet2015" )` to specify that observational data for the target variable `"gpp"` comes from `"fluxnet2015"`.
- `timescale`: Named list of characters specifying the time scale used for aggregating modelled and observational data in time series before calculating the cost function. For naming the list, see point above. Set, e.g., `timescale = list( gpp = "d" )` to calibrate to observational GPP aggregated to daily intervals (i.e. not aggregated). Use `"w"` for weekly, `"m"` for monthly, or `"y"` for annual (XXX NOT YET IMPLEMENTED).
- `path_fluxnet2015`: Path (character string) for where FLUXNET 2015 data is located (data files may be in subdirectories thereof). This settings list element needs to be specified if any of `datasource` is equal "fluxnet2015".
- `sitenames`: Vector of character strings for site names of sites' data to be used for calibration.
- `filter_temp_min`: Minimum temperature of data used for calibration. Data points for days where air temperature is below, are removed (replaced by NA) in the observational data.
- `filter_temp_max`: Maximum temperature of data used for calibration. Data points for days where air temperature is above, are removed (replaced by NA) in the observational data.
- `filter_soilm_min`: Minimum soil moisture (relative, normalised to maximum of mean across multiple depths at each site) of data used for calibration. Data points for days where soil moisture is below, are removed (replaced by NA) in the observational data.

### Evaluation settings
Define model evaluation settings as a list.
```r
mylist <- read_csv("myselect_fluxnet2015.csv") %>% filter( use==1 ) %>% select( -use ) %>% unlist()
settings_eval <- list(
  sitenames = filter(siteinfo$light, c4 %in% c(FALSE, NA) )$mysitename,
  sitenames_siteplots = mylist,
  agg = 5,
  benchmark = list( gpp="fluxnet2015" ),
  path_fluxnet2015 = "~/data/FLUXNET-2015_Tier1/20160128/"
  )
```

## Workflow

### Prepare meta info file
This step is either done by hand so that the file has a certain structure (for column names etc see above: `path_siteinfo`). Below is an example for creating such a meta info file (info for each site in an ensemble) for the FLUXNET 2015 Tier 1 ensemble.
```r
siteinfo <- prepare_metainfo_fluxnet2015( 
  settings_sims = settings_sims, 
  settings_input = settings_input, 
  overwrite = FALSE, 
  filn_elv_watch = paste0( settings_input$path_cx1data, "watch_wfdei/WFDEI-elevation.nc" ) 
  )
```

- `overwrite`: Set to `TRUE` if meta info file in wide format is to be overwritten (original is in long format, a wide-format version is used by `prepare_metainfo_fluxnet2015()`).
- `filn_elv_watch`: File name (full path, character string) of the WATCH-WFDEI elevation file (NetCDF format) used to complement missing elevation information.


### Prepare simulation setup
Create a run directory with all the simulation parameter files (defining simulation years, length, etc.). This returs the `settings_sims` list, complemented by additional information. Calibration settings are an optional argument. When passed on, simulation parameter files will contain information which target variables are to be written to special calibration output files (a single file written for an entire ensemble).
```r
settings_sims <- prepare_setup_sofun( 
  settings = settings_sims, 
  settings_calib = settings_calib, 
  write_paramfils = FALSE 
  )
```

### Prepare inputs
Prepare SOFUN input (climate input, CO2, etc.). Complements `settings_input`. This will require inputs from the user through the prompt, entered in the console to specify whether data files should be downloaded from Imperial CX1. In case you chose to download, you must have access to CX1 and be connected to the Imperial VPN. Once asked (see console!), enter your user name on CX1. This also requires that no additional entering of the password is required. In order to set this up, you need to generate an SSH key pair beforehand (see [here](https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys--2)). 
```r
inputdata <- prepare_input_sofun( 
  settings_input = settings_input, 
  settings_sims = settings_sims, 
  return_data = TRUE, 
  overwrite = TRUE, 
  verbose = TRUE 
  )
```

### Calibrate the model
Calibrate SOFUN, returns calibration settings, now including calibrated parameters inside the list (`settings_calib$par[[param_name]]$opt`).
```r
settings_calib <- calib_sofun( 
  setup = setup_sofun, 
  settings_calib = settings_calib, 
  settings_sims = settings_sims 
  )
```

### Run the model
Run SOFUN with calibrated parameters. Set `r setup_sofun$is_calib <- FALSE` to write normal SOFUN output.
```r
params_opt <- read_csv( paste0("params_opt_", settings_calib$name,".csv") )
nothing <- update_params( params_opt )
out <- runread_sofun( 
  settings = settings_sims, 
  setup = setup_sofun 
  )
```

### Evaluate the model
Evaluate SOFUN results based on calibrated parameters. The first argument to the `eval_sofun()` function is the output from `runread()` executed above. (Here, in order to avoid running all steps while knitting this RMarkdown file, we first read model outputs from a previous run.)
```r
nothing <- eval_sofun( out, settings_eval = settings_eval )
```

