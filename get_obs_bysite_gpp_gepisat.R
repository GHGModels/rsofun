##----------------------------------------------------------------------
## Function for reading observational GPP data from GePiSaT (Tyler's 
## alternative flux decomposition) for FLUXNET 2015 stations.
##----------------------------------------------------------------------
get_obs_bysite_gpp_gepisat <- function( sitename, path_gepisat, timescale ){

  require(dplyr)
  require(rlang)

  ## Take only file for this site
  if (timescale=="d"){

    ## Daily
    filn <- list.files( path_gepisat, 
      pattern = paste0( sitename, ".*_daily_GPP.txt" ), 
      recursive = TRUE 
      )

  } else {

    abort("Aborting. GePiSaT data only available for daily time step.")

  }

  if (length(filn)>0){

    ## This returns a data frame with columns (date, temp, prec, nrad, ppfd, vpd, ccov)
    df <- get_obs_gepisat_raw( 
      sitename = sitename, 
      path = paste0(path_gepisat, filn), 
      freq = timescale 
      ) %>%
      
      ## Convert units
      ## given in molCO2 m-2 d-1, converted to gC m-2 d-1
      mutate_at( vars(starts_with("GPP_")), funs(convert_gpp_gepisat) ) %>%
      
      ## rename so that it is like in FLUXNET 2015
      rename( gpp_obs = GPP_mol.m2, gpp_err_obs = GPP_err_mol.m2 ) %>%
      
      ## some are NaN
      mutate( gpp_obs = ifelse( is.nan(gpp_obs), NA, gpp_obs ) )
  
  } else {

    df <- NULL
  
  }
  
  return(df)

}


get_obs_gepisat_raw <- function( sitename, path, freq="d" ){
  ##--------------------------------------------------------------------
  ## Function returns a dataframe containing all the data of the GePiSaT
  ## data file of respective temporal resolution.
  ## Returns data in units given in the fluxnet 2015 dataset
  ##--------------------------------------------------------------------
  require(dplyr)
  require(readr)
  require(lubridate)

  ## get data
  df <-  read_csv( path, na="-9999", col_types = cols() )

  ## get dates, their format differs slightly between temporal resolution
  if ( freq=="d" ){

    df <- df %>% mutate( Timestamp = ymd( Timestamp ) ) %>% rename( date = Timestamp )

  } else {

    abort("get_obs_gepisat_raw() implemented only for daily time step.")

  }

  return( df )

}


##--------------------------------------------------------------------
## Converts units of GPP variables from GePiSaT to SOFUN standard
## in GePiSaT given in molCO2 m-2 d-1, converted to gC m-2 d-1
##--------------------------------------------------------------------
convert_gpp_gepisat <- function( gpp ){
  c_molmass <- 12.0107  # molar mass of C
  gpp_coverted <- gpp * c_molmass
  return(gpp_coverted)
}


