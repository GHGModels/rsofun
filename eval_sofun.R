eval_sofun <- function( mod, settings_eval, settings_sims, siteinfo, obs_eval = NA, overwrite = TRUE, doplot = FALSE ){
	
  require(dplyr)
  require(purrr)
  require(lubridate)
  require(tidyr)
  require(stringr)

  source("remove_outliers.R")
  source("analyse_modobs.R")

  metrics <- list()
  
	if (settings_eval$benchmark$gpp=="fluxnet2015"){
		##-------------------------------------------------------
		## GPP EVALUATION AGAINST FLUXNET 2015 DATA
		## Evaluate model vs. observations for decomposed time series
		## into:
		## - spatial
		## - inter-annual
		## - multi-year trend
		## - seasonal (different time scales: daily/weekly/monthly)
		## - anomalies (different time scales: daily/weekly/monthly)
		##-------------------------------------------------------

	  ## get sites for which no model output is available and overwrite settings_eval$sitenames
	  missing_mod <- purrr::map_lgl( mod, ~identical(., NA ) ) %>% which() %>% names()
	  settings_eval$sitenames <- settings_eval$sitenames[which(!(settings_eval$sitenames %in% missing_mod))]
	  
	  metrics$gpp$fluxnet2015 <- list()

	  ## Evaluation against FLUXNET 2015 data is done with daily model outputs
	  mod <- mod$daily

	  ##------------------------------------------------------------
	  ## Get daily model output
	  ##------------------------------------------------------------
	  ddf_mod <- lapply( as.list(settings_eval$sitenames),  function(x) dplyr::select( mod[[x]], date, gpp_mod = gpp ) %>% mutate( sitename = x ) ) %>%
	    bind_rows()

    ##------------------------------------------------------------
    ## Get observations for evaluation
    ##------------------------------------------------------------
	  if (identical(obs_eval, NA)) obs_eval <- get_obs_eval( settings_eval = settings_eval, settings_input = settings_input, settings_sims = settings_sims, overwrite = overwrite )
    
    ##------------------------------------------------------------
    ## Aggregate model output data to annual/monthly/weekly, only for selected sites,
    ## and merge into respective observational data frame 
    ##------------------------------------------------------------
    ## annual sum
    obs_eval$adf <- ddf_mod %>%
      mutate( year = year(date) ) %>%
      group_by( sitename, year ) %>%
      summarise( gpp_mod = sum(gpp_mod), n = n() ) %>%
      mutate( gpp_mod = ifelse( n<365, NA, gpp_mod ) ) %>%
      ## merge into observational data frame
      right_join( adf, by = c("sitename", "year"))

    ## monthly mean
    obs_eval$mdf <- ddf_mod %>%
      mutate( year = year(date), moy = month(date) ) %>%
      group_by( sitename, year, moy ) %>%
      summarise( gpp_mod = mean(gpp_mod), n = n() ) %>%
      ## merge into observational data frame
      right_join( mutate( mdf, moy = month(date) ), by = c("sitename", "year", "moy"))

    ## mean across multi-day period
    obs_eval$xdf <- ddf_mod %>% 
    	# mutate( year = year(date), week = week(date) ) %>%
    	mutate( year = year(date), inbin = cut( date, breaks = breaks, right = FALSE ) ) %>%
      group_by( sitename, inbin ) %>%
      summarise( gpp_mod_mean = mean( gpp_mod, na.rm = TRUE ), gpp_mod_min = min( gpp_mod, na.rm = TRUE ), gpp_mod_max = max( gpp_mod, na.rm = TRUE ), n_mod = sum(!is.na(gpp_mod)) ) %>%
      dplyr::rename( gpp_mod = gpp_mod_mean ) %>%
    	right_join( xdf, by = c("sitename", "inbin") )
    
    ## daily
    obs_eval$ddf <- ddf_mod %>%
      ## merge into observational data frame
      right_join( ddf, by = c("sitename", "date"))

    ##------------------------------------------------------------
    ## Create table for overview
    ##------------------------------------------------------------
    filn <- "siteinfo_eval.csv"
    if (!file.exists(filn)||overwrite){
    	## Get additional meta information for sites: Koeppen-Geiger Class
    	## First, get this info from a separate CSV file
      tmp <-  read_csv("~/data/FLUXNET-2015_Tier1/meta/fluxnet_site_info_mysub.csv") %>%
              dplyr::rename( sitename = fluxnetid ) %>% dplyr::select( sitename, koeppen_climate )
      
  	  meta <- tmp %>%
  	          mutate( koeppen_climate = str_split( koeppen_climate, " - " ) ) %>%
  	          mutate( koeppen_code = purrr::map( koeppen_climate, 1 ) ) %>%
  	          mutate( koeppen_word = purrr::map( koeppen_climate, 2 ) ) %>%
  	          unnest( koeppen_code )

  	  ## add info: number of data points (daily GPP)
  		siteinfo_eval <- ddf %>% group_by( sitename ) %>% summarise( ndailygpp = sum(!is.na(gpp_obs)) ) %>% 
  												right_join( dplyr::rename( siteinfo$light, sitename = mysitename), by = "sitename" ) %>%
  												left_join( meta, by = "sitename")
  		
  		legend <- tmp$koeppen_climate %>% as_tibble() %>% 
  		  filter( !is.na(value) ) %>%
  		  filter( value!="-" ) %>%
  		  mutate( koeppen_climate = str_split( value, " - " ) ) %>%
  		  mutate( koeppen_code = purrr::map( koeppen_climate, 1 ) ) %>%
  		  mutate( koeppen_word = purrr::map( koeppen_climate, 2 ) ) %>%
  		  unnest( koeppen_code ) %>% 
  		  unnest( koeppen_word ) %>% 
  		  dplyr::select( Code = koeppen_code, Climate = koeppen_word ) %>% 
  		  distinct( Code, .keep_all = TRUE ) %>%
  		  arrange( Code )

  		write_csv( legend, path = "koeppen_legend.csv" )
  		
  		## Second, extract the class from a global map, complement missing in above
  		require(raster)
  		kgclass <- raster("~/data/koeppengeiger/koeppen-geiger.tif")
  		kglegend <- read_csv("~/data/koeppengeiger/koppen-geiger_legend.csv") %>% setNames( c("kgnumber", "koeppen_code_extr"))
  		siteinfo_eval <- siteinfo_eval %>% mutate( kgnumber = extract( kgclass, data.frame( x=.$lon, y=.$lat ) ) ) %>% 
  		  left_join( kglegend, by = "kgnumber" ) %>%
  		  mutate( koeppen_code = ifelse( is.na(koeppen_code), koeppen_code_extr, koeppen_code ) ) %>%
  		  dplyr::select( -koeppen_climate, -koeppen_word )
  					
  		write_csv( siteinfo_eval, path = filn )
    } else {
      siteinfo_eval <- read_csv( filn )
    }

		## metrics for daily and x-daily values, all sites pooled
    metrics$gpp$fluxnet2015$daily_pooled  <- with( obs_eval$ddf, get_stats( gpp_mod, gpp_obs ) )
    metrics$gpp$fluxnet2015$xdaily_pooled <- with( obs_eval$xdf, get_stats( gpp_mod, gpp_obs ) )

    ##------------------------------------------------------------
	  ## Evaluate annual values by site
    ##------------------------------------------------------------
		adf_stats <- obs_eval$adf %>% group_by( sitename ) %>% 
								 nest() %>%
		             mutate( nyears = purrr::map( data, ~sum(!is.na( .$gpp_obs )  ) ) ) %>%
		             unnest( nyears ) %>%
		             filter( nyears > 2 ) %>%
		             mutate( linmod = purrr::map( data, ~lm( gpp_obs ~ gpp_mod, data = . ) ),
    		                 stats  = purrr::map( data, ~get_stats( .$gpp_mod, .$gpp_obs ) ) ) %>%
		             mutate( data   = purrr::map( data, ~add_fitted(.) ) ) %>%
		             unnest( stats )

		## metrics for annual values, all sites pooled
    metrics$gpp$fluxnet2015$annual_pooled <- with( obs_eval$adf, get_stats( gpp_mod, gpp_obs ) )

    ##------------------------------------------------------------
	  ## Evaluate annual values by site
    ##------------------------------------------------------------
		mdf_stats <- obs_eval$mdf %>% group_by( sitename ) %>% 
								 nest() %>%
		             mutate( nmonths = purrr::map( data, ~sum(!is.na( .$gpp_obs )  ) ) ) %>%
		             unnest( nmonths ) %>%
		             filter( nmonths > 2 ) %>%
		             mutate( linmod = purrr::map( data, ~lm( gpp_obs ~ gpp_mod, data = . ) ),
    		                 stats  = purrr::map( data, ~get_stats( .$gpp_mod, .$gpp_obs ) ) ) %>%
		             mutate( data   = purrr::map( data, ~add_fitted(.) ) ) %>%
		             unnest( stats )

		## metrics for annual values, all sites pooled
    metrics$gpp$fluxnet2015$monthly_pooled <- with( obs_eval$mdf, get_stats( gpp_mod, gpp_obs ) )

    ##------------------------------------------------------------
	  ## Get mean annual GPP -> "spatial" data frame and evaluate it
    ##------------------------------------------------------------
    meandf <- obs_eval$adf %>% group_by( sitename ) %>%
							summarise(  gpp_obs = mean( gpp_obs, na.rm=TRUE ),
												  gpp_mod = mean( gpp_mod, na.rm=TRUE ) )

    linmod_meandf <- lm( gpp_obs ~ gpp_mod, data = meandf ) 
    metrics$gpp$fluxnet2015$spatial <- with( meandf, get_stats( gpp_mod, gpp_obs ) )
    
		# ## test if identical data to previous evaluation
		# mymeandf <- meandf
		# load("../soilm_global/meandf_soilm_global.Rdata")
		# meandf <- meandf %>% dplyr::select( sitename=mysitename, gpp_obs_old=gpp_obs, gpp_mod_old=gpp_pmodel ) %>% 
		#           left_join( mymeandf, by="sitename" ) %>%
		#           mutate( diff = gpp_mod - gpp_mod_old )
		# with(meandf, plot( gpp_obs_old, gpp_obs))
		# lines(c(0,4000), c(0,4000))
		# with(meandf, plot( gpp_mod_old, gpp_mod))
		# lines(c(0,4000), c(0,4000))
		
		# ## daily values seem to be identical. something wrong with aggregating model outputs to annual values?
		# load( file="../soilm_global/data/nice_nn_agg_lue_obs_evi.Rdata" )
		# ddf_old <- nice_agg %>% dplyr::select( sitename = mysitename, date, gpp_mod_old = gpp_pmodel )
		# ddf_new <- lapply( as.list(settings_eval$sitenames),  function(x) dplyr::select( mod[[x]] , date, gpp_mod = gpp ) %>% mutate( sitename = x ) ) %>%
		#   bind_rows() %>% left_join( ddf_old, by=c("sitename", "date"))
		# with( filter(ddf_new, sitename=="AR-Vir"), plot(gpp_mod_old, gpp_mod) )
		# with( filter(ddf_new, sitename=="AU-ASM"), plot(gpp_mod_old, gpp_mod) )
		# with( filter(ddf_new, sitename=="US-Me2"), plot(gpp_mod_old, gpp_mod) )
		# with( ddf_new, plot( gpp_mod_old, gpp_mod ) )
		
    ##------------------------------------------------------------
	  ## Get IAV as annual value minus mean by site
    ##------------------------------------------------------------
		iavdf <- obs_eval$adf %>% left_join( dplyr::rename( meandf, gpp_mod_mean = gpp_mod, gpp_obs_mean = gpp_obs ), by = "sitename" ) %>%
							mutate( gpp_mod = gpp_mod - gpp_mod_mean, 
							        gpp_obs = gpp_obs - gpp_obs_mean ) %>%
							dplyr::select( -gpp_obs_mean, -gpp_mod_mean )
		
		iavdf_stats <- iavdf %>% 
									  group_by( sitename ) %>%
									  nest() %>%
									  mutate( nyears = purrr::map( data, ~sum(!is.na( .$gpp_obs )  ) ) ) %>%
									  unnest( nyears ) %>%
									  filter( nyears > 2 ) %>%
									  mutate( linmod = purrr::map( data, ~lm( gpp_obs ~ gpp_mod, data = . ) ),
									          stats  = purrr::map( data, ~get_stats( .$gpp_mod, .$gpp_obs ) ) ) %>%
									  mutate( data   = purrr::map( data, ~add_fitted(.) ) ) %>%
									  unnest( stats )

		metrics$gpp$fluxnet2015$anomalies_annual  <- with( iavdf, get_stats( gpp_mod, gpp_obs ) )
		
    ##------------------------------------------------------------
	  ## Get mean seasonal cycle (by day of year)
    ##------------------------------------------------------------
		meandoydf <- obs_eval$ddf %>%  mutate( doy = yday(date) ) %>%
	                filter( doy != 366 ) %>% ## XXXX this is a dirty fix! better force lubridate to ignore leap years when calculating yday()
									group_by( sitename, doy ) %>% 
									summarise( obs_mean = mean( gpp_obs, na.rm=TRUE ), obs_min = min( gpp_obs, na.rm=TRUE ), obs_max = max( gpp_obs, na.rm=TRUE ),
														 mod_mean = mean( gpp_mod, na.rm=TRUE ), mod_min = min( gpp_mod, na.rm=TRUE ), mod_max = max( gpp_mod, na.rm=TRUE )
														 ) %>%
	                mutate( obs_min = ifelse( is.infinite(obs_min), NA, obs_min ), obs_max = ifelse( is.infinite(obs_max), NA, obs_max ) ) %>%
									mutate( obs_mean = interpol_lin(obs_mean), obs_min = interpol_lin(obs_min), obs_max = interpol_lin( obs_max ), site=sitename )

		meandoydf_stats <- meandoydf %>% group_by( sitename ) %>%
											 nest()

		metrics$gpp$fluxnet2015$meandoy  <- with( meandoydf, get_stats( mod_mean, obs_mean ) )

    ## aggregate mean seasonal cycle by climate zone (koeppen-geiger) and hemisphere (pooling sites within the same climate zone)
		meandoydf_byclim <- obs_eval$ddf %>% mutate( doy = yday(date) ) %>%
											  left_join( dplyr::select( siteinfo_eval, sitename, lat, koeppen_code ), by = "sitename" ) %>%
											  mutate( hemisphere = ifelse( lat>0, "north", "south" ) ) %>%
											  dplyr::select( -lat ) %>%
											  filter( doy != 366 ) %>% ## XXXX this is a dirty fix! better force lubridate to ignore leap years when calculating yday()
											  group_by( koeppen_code, hemisphere, doy ) %>% 
											  summarise( obs_mean = median( gpp_obs, na.rm=TRUE ), obs_min = quantile( gpp_obs, 0.33, na.rm=TRUE ), obs_max = quantile( gpp_obs, 0.66, na.rm=TRUE ),
											             mod_mean = median( gpp_mod, na.rm=TRUE ), mod_min = quantile( gpp_mod, 0.33, na.rm=TRUE ), mod_max = quantile( gpp_mod, 0.66, na.rm=TRUE ) ) %>%
                        mutate( obs_min = ifelse( is.infinite(obs_min), NA, obs_min ), obs_max = ifelse( is.infinite(obs_max), NA, obs_max ) ) %>%
                        mutate( obs_mean = interpol_lin(obs_mean), obs_min = interpol_lin(obs_min), obs_max = interpol_lin( obs_max ) ) %>%
                        mutate( climatezone = paste( koeppen_code, hemisphere ) ) %>%
                        left_join( 
                        	(siteinfo_eval %>% mutate( hemisphere = ifelse( lat>0, "north", "south" ) ) %>% group_by( koeppen_code, hemisphere ) %>% summarise( nsites = n() )), 
                        	by = c("koeppen_code", "hemisphere") 
                        	)

		meandoydf_byclim_stats <- meandoydf_byclim %>% group_by( koeppen_code, hemisphere ) %>%
															nest()
		  
    ##------------------------------------------------------------
	  ## Get IDV (inter-day variability) as daily value minus mean by site and DOY
    ##------------------------------------------------------------
		idvdf <- obs_eval$ddf %>%  mutate( doy = yday(date) ) %>%
	            left_join( dplyr::rename( meandoydf, gpp_mod_mean = mod_mean, gpp_obs_mean = obs_mean ), by = c("sitename", "doy") ) %>%
							mutate( gpp_mod = gpp_mod - gpp_mod_mean, gpp_obs = gpp_obs - gpp_obs_mean ) %>%
							dplyr::select( -gpp_obs_mean, -gpp_mod_mean, -obs_min, -obs_max, -mod_min, -mod_max )
		
		idvdf_stats <- idvdf %>% 
									  group_by( sitename ) %>%
									  nest() %>%
									  mutate( linmod = purrr::map( data, ~lm( gpp_obs ~ gpp_mod, data = . ) ),
									          stats  = purrr::map( data, ~get_stats( .$gpp_mod, .$gpp_obs ) ) ) %>%
									  mutate( data   = purrr::map( data, ~add_fitted(.) ) ) %>%
									  unnest( stats )									  
		
		metrics$gpp$fluxnet2015$anomalies_daily  <- with( idvdf, get_stats( gpp_mod, gpp_obs ) )
		
    ##------------------------------------------------------------
	  ## Get mean seasonal cycle (by week (or X-day period) of year)
    ##------------------------------------------------------------
		meanxoydf <- obs_eval$xdf %>%  mutate( xoy = yday(inbin) ) %>%
									group_by( sitename, xoy ) %>% 
									summarise( obs_mean = mean( gpp_obs, na.rm=TRUE ), obs_min = min( gpp_obs, na.rm=TRUE ), obs_max = max( gpp_obs, na.rm=TRUE ),
														 mod_mean = mean( gpp_mod, na.rm=TRUE ), mod_min = min( gpp_mod, na.rm=TRUE ), mod_max = max( gpp_mod, na.rm=TRUE )
														 ) %>%
                  mutate( obs_min = ifelse( is.infinite(obs_min), NA, obs_min ), obs_max = ifelse( is.infinite(obs_max), NA, obs_max ) ) %>%
									mutate( obs_mean = interpol_lin(obs_mean), obs_min = interpol_lin(obs_min), obs_max = interpol_lin( obs_max ), site=sitename )

		meanxoydf_stats <- meanxoydf %>% group_by( sitename ) %>%
											 nest()

		metrics$gpp$fluxnet2015$meanxoy  <- with( meanxoydf, get_stats( mod_mean, obs_mean ) )

    ##------------------------------------------------------------
	  ## Get IXV (inter-day variability) as daily value minus mean by site and DOY
    ##------------------------------------------------------------
		ixvdf <- obs_eval$xdf %>%  mutate( xoy = yday(inbin) ) %>%
              left_join( dplyr::rename( meanxoydf, gpp_mod_mean = mod_mean, gpp_obs_mean = obs_mean ), by = c("sitename", "xoy") ) %>%
							mutate( gpp_mod = gpp_mod - gpp_mod_mean, gpp_obs = gpp_obs - gpp_obs_mean ) %>%
							dplyr::select( -gpp_obs_mean, -gpp_mod_mean, -obs_min, -obs_max, -mod_min, -mod_max )
		
		ixvdf_stats <- ixvdf %>% 
									  group_by( sitename ) %>%
									  nest() %>%
									  mutate( linmod = purrr::map( data, ~lm( gpp_obs ~ gpp_mod, data = . ) ),
									          stats  = purrr::map( data, ~get_stats( .$gpp_mod, .$gpp_obs ) ) ) %>%
									  mutate( data   = purrr::map( data, ~add_fitted(.) ) ) %>%
									  unnest( stats )
		
		metrics$gpp$fluxnet2015$anomalies_xdaily  <- with( ixvdf, get_stats( gpp_mod, gpp_obs ) )
		

    ##------------------------------------------------------------
	  ## Plotting
    ##------------------------------------------------------------
    if (doplot){
			modobs_ddf <- plot_modobs_daily( obs_eval$ddf, makepdf=FALSE )
			modobs_xdf <- plot_modobs_xdaily( obs_eval$xdf, makepdf=FALSE )
			modobs_mdf <- plot_modobs_monthly( obs_eval$mdf, makepdf=FALSE )
	    modobs_spatial <- plot_modobs_spatial( meandf, makepdf=FALSE )
			plot_modobs_spatial_annual( meandf, linmod_meandf, adf_stats, makepdf=FALSE )
			modobs_anomalies_annual <- plot_modobs_anomalies_annual( iavdf, iavdf_stats, makepdf=FALSE )
		  modobs_anomalies_daily <- plot_modobs_anomalies_daily( idvdf, idvdf_stats, makepdf=FALSE)
	  	modobs_anomalies_xdaily <- plot_modobs_anomalies_xdaily( ixvdf, ixvdf_stats, makepdf=FALSE )
	  	modobs_meandoy <- plot_modobs_meandoy( meandoydf, meandoydf_stats, makepdf=FALSE )
			plot_by_doy_allsites( meandoydf_stats, makepdf=FALSE )
			plot_by_doy_allzones( meandoydf_byclim_stats, makepdf=FALSE )
			modobs_meanxoy <- plot_modobs_meanxoy( meanxoydf, makepdf=FALSE )
			plot_by_xoy_allsites( meanxoydf_stats, makepdf=FALSE )
    }


	}
  
  data = list(  
  	adf_stats              = adf_stats,
  	mdf_stats              = mdf_stats,
    meandf                 = meandf, 
    meandf                 = meandf, 
    linmod_meandf          = linmod_meandf, 
    iavdf                  = iavdf, 
    iavdf_stats            = iavdf_stats, 
    idvdf                  = idvdf, 
    idvdf_stats            = idvdf_stats, 
    ixvdf                  = ixvdf, 
    ixvdf_stats            = ixvdf_stats, 
    meandoydf              = meandoydf, 
    meandoydf_stats        = meandoydf_stats, 
    meandoydf_stats        = meandoydf_stats, 
    meandoydf_byclim_stats = meandoydf_byclim_stats, 
    meanxoydf              = meanxoydf, 
    meanxoydf_stats        = meanxoydf_stats,
    adf                    = obs_eval$adf,
    mdf                    = obs_eval$mdf,
    ddf                    = obs_eval$ddf, 
    xdf                    = obs_eval$xdf
  )
  
	return( list( metrics=metrics, data=data ) )
}


get_obs_eval <- function( settings_eval, settings_input, settings_sims, overwrite ){

	require(dplyr)
	require(purrr)
	require(lubridate)

  if (settings_eval$benchmark$gpp=="fluxnet2015"){
	  ##------------------------------------------------------------
	  ## Read annual observational data from FLUXNET 2015 files (from annual files!).
	  ##------------------------------------------------------------
	  ## loop over sites to get data frame with all variables
	  print("getting annual FLUXNET-2015_Tier1 data...")
	  if (!file.exists("adf_obs_eval.Rdata")||overwrite){
		  adf <-  lapply( as.list(settings_eval$sitenames),
											  	function(x) get_obs_bysite_gpp_fluxnet2015( x,
														path_fluxnet2015 = settings_eval$path_fluxnet2015_y,
														timescale = "y" ) %>%
										## Remove outliers, i.e. when data is outside 1.5 times the inter-quartile range
										mutate( gpp_obs = remove_outliers( gpp_obs, coef=1.5 ),
														year = year(date),
														sitename = x ) ) %>%
		  							bind_rows() %>%
		                dplyr::select(-soilm_obs_mean) %>%
		                mutate( gpp_obs = ifelse( year < 2000, NA, gpp_obs ) ) # remove pre-modis data
    } else {
    	load("adf_obs_eval.Rdata")
    }

		##------------------------------------------------------------
		## Read monthly observational data from FLUXNET 2015 files (from monthly files!).
		##------------------------------------------------------------
		## loop over sites to get data frame with all variables
		print("getting monthly FLUXNET-2015_Tier1 data...")
		if (!file.exists("mdf_obs_eval.Rdata")||overwrite){
			mdf <-  lapply( as.list(settings_eval$sitenames),
											  	function(x) get_obs_bysite_gpp_fluxnet2015( x,
														path_fluxnet2015 = settings_eval$path_fluxnet2015_m,
														timescale = "m" ) %>%
										mutate( year = year(date),
														sitename = x ) ) %>%
										bind_rows() %>%
										mutate( gpp_obs = ifelse( date < "2000-02-18", NA, gpp_obs ) ) # remove pre-modis data
		} else {
    	load("mdf_obs_eval.Rdata")
    }

		##------------------------------------------------------------
		## Read daily observational data from FLUXNET 2015 files (from daily files!).
		##------------------------------------------------------------
		## loop over sites to get data frame with all variables
		print("getting daily FLUXNET-2015_Tier1 data...")
		if (!file.exists("ddf_obs_eval.Rdata")||overwrite){
			ddf <-  lapply( as.list(settings_eval$sitenames),
											  	function(x) get_obs_bysite_gpp_fluxnet2015( x,
														path_fluxnet2015 = settings_eval$path_fluxnet2015_d,
														timescale = "d" ) %>%
										mutate( year = year(date),
														sitename = x ) ) %>%
										bind_rows() %>%
										mutate( gpp_obs = ifelse( date < "2000-02-18", NA, gpp_obs ) ) # remove pre-modis data

			##------------------------------------------------------------
			## Read daily observational data from GEPISAT files (only daily files!).
			##------------------------------------------------------------
			tmp <- lapply( as.list(settings_eval$sitenames),
											function(x) get_obs_bysite_gpp_gepisat( x, 
											  settings_eval$path_gepisat_d, 
												timescale = "d" ) )
			names(tmp) <- settings_eval$sitenames

			missing_gepisat <- purrr::map_lgl( tmp, ~identical(., NULL ) ) %>% which() %>% names()
			settings_eval$sitenames_gepisat <- settings_eval$sitenames[which(!(settings_eval$sitenames %in% missing_gepisat))]

			tmp <- tmp %>% bind_rows( .id = "sitename" ) %>%
			               mutate( year = year(date) ) %>%
			               mutate( gpp_obs = ifelse( date < "2000-02-18", NA, gpp_obs ) ) %>%  # remove pre-modis data
			               dplyr::rename( gpp_obs_gepisat = gpp_obs )
			  
			if (!is.null(tmp)){
			  ddf <- tmp %>% right_join( ddf, by = "date" )
			} else {
			  ddf <- ddf %>% mutate( gpp_obs_gepisat = NA )
			}			  							

			##------------------------------------------------------------
			## Add forcing data to daily data frame (for neural network-based evaluation)
			##------------------------------------------------------------
			ddf <- lapply( as.list(settings_eval$sitenames), function(x) get_forcing_from_csv( x, settings_sims ) ) %>%
			       bind_rows() %>%
			       dplyr::select(-year_dec.x, -year_dec.y) %>%
						 right_join( ddf, by = c("sitename", "date") )

		} else {
    	load("ddf_obs_eval.Rdata")
    }

	  ##------------------------------------------------------------
	  ## Aggregate to multi-day periods
	  ## periods should start with the 1st of January each year, otherwise can't compute mean seasonal cycle
	  ##------------------------------------------------------------
		if (!file.exists("xdf_obs_eval.Rdata")||overwrite){
			# ## 8-day periods corresponding to MODIS dates (problem: doesn't start with Jan 1 each year)
	    	#  breaks <- modisdates <- read_csv( "modisdates.csv" )$date

		  # ## aggregate to weeks
		  # xdf <- ddf %>% mutate( inbin = week(date) ) %>%
		  #                group_by( sitename, year, inbin ) %>%
		  #                summarise( gpp_obs = mean( gpp_obs, na.rm=TRUE) )

		  ## Generate vector of starting dates of X-day periods, making sure the 1st of Jan is always the start of a new period
			listyears <- seq( ymd("1990-01-01"), ymd("2018-01-01"), by = "year" )	                 
			breaks <- purrr::map( as.list(listyears), ~seq( from=., by=paste0( settings_eval$agg, " days"), length.out = ceiling(365 / settings_eval$agg)) ) %>% Reduce(c,.)
		
			## take mean across periods
			xdf <- ddf %>% mutate( inbin = cut( date, breaks = breaks, right = FALSE ) ) %>%
			 							 group_by( sitename, inbin ) %>%
			 							 summarise( gpp_obs_mean = mean( gpp_obs, na.rm = TRUE ), gpp_obs_min = min( gpp_obs, na.rm = TRUE ), gpp_obs_max = max( gpp_obs, na.rm = TRUE ), n_obs = sum(!is.na(gpp_obs)) ) %>%
			               dplyr::rename( gpp_obs = gpp_obs_mean ) %>%
			               mutate( gpp_obs = ifelse(is.nan(gpp_obs), NA, gpp_obs ), gpp_obs_min = ifelse(is.infinite(gpp_obs_min), NA, gpp_obs_min ), gpp_obs_max = ifelse(is.infinite(gpp_obs_max), NA, gpp_obs_max ) )
			} else {
				load("xdf_obs_eval.Rdata")
			}

	}
	return( list( ddf=ddf, xdf=xdf, mdf=mdf, adf=adf ) )
}


get_stats <- function( mod, obs ){

	linmod <- lm( obs ~ mod )
	linmod_sum <- summary( linmod )
	rsq <- linmod_sum$adj.r.squared
	rmse <- sqrt( mean( (mod - obs)^2, na.rm=TRUE ) )
	slope <- coef(linmod)[2]
	nvals <- sum( !is.na(mod) & !is.na(obs) )
	bias <- mean( (mod - obs), na.rm=TRUE )
	return( tibble( rsq=rsq, rmse=rmse, slope=slope, bias=bias, nvals=nvals ) )

}

add_fitted <- function( data ){
  linmod <- lm( gpp_obs ~ gpp_mod, data = data, na.action = "na.exclude" )
  data$fitted <- fitted( linmod )
  return(data)  
}

interpol_lin <- function(vec){
	out <- approx( seq(length(vec)), vec, xout = seq(length(vec)) )$y
	return(out)
}

get_forcing_from_csv <- function( sitename, settings_sims ){

	## get climate data
  dir <- paste0( settings_sims$path_input, "/sitedata/climate/", sitename )
  csvfiln <- paste0( dir, "/clim_daily_", sitename, ".csv" )
  ddf <- read_csv( csvfiln )

  ## get fapar data
  dir <- paste0( settings_sims$path_input, "/sitedata/fapar/", sitename )
  csvfiln <- paste0( dir, "/fapar_daily_", sitename, ".csv" )
  ddf <- read_csv( csvfiln ) %>%
         mutate( fapar = as.numeric(fapar)) %>%
  			 right_join( ddf, by = "date" )

  return(ddf)

}

extract_koeppen_code <- function( str ){
	require(stringr)
	out <- str_split( str, " - ")[[1]][1]
	return( out )
}

