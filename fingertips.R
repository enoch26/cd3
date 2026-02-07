
# library -----------------------------------------------------------------


libs_name <- c("fingertipsR", "INLA", "inlabru", "sf", "terra", "here", "tidyterra", "ggplot2")
lapply(libs_name, require, character.only = TRUE)


# E06 shape file  ---------------------------------------------------------
# https://geoportal.statistics.gov.uk/search?categories=%252Fcategories%252Fboundaries%2520-%2520administrative%2C%252Fcategories%252Fboundaries%2520-%2520administrative%252F2011%2C%252Fcategories%252Fboundaries%2520-%2520administrative%252F2012%2C%252Fcategories%252Fboundaries%2520-%2520administrative%252F2013%2C%252Fcategories%252Fboundaries%2520-%2520administrative%252F2014%2C%252Fcategories%252Fboundaries%2520-%2520administrative%252F2015%2C%252Fcategories%252Fboundaries%2520-%2520administrative%252F2016%2C%252Fcategories%252Fboundaries%2520-%2520administrative%252F2017%2C%252Fcategories%252Fboundaries%2520-%2520administrative%252F2018%2C%252Fcategories%252Fboundaries%2520-%2520administrative%252F2019%2C%252Fcategories%252Fboundaries%2520-%2520administrative%252F2020%2C%252Fcategories%252Fboundaries%2520-%2520administrative%252F2021%2C%252Fcategories%252Fboundaries%2520-%2520administrative%252F2022%2C%252Fcategories%252Fboundaries%2520-%2520administrative%252F2023%2C%252Fcategories%252Fboundaries%2520-%2520administrative%252F2024%2C%252Fcategories%252Fons%2520geography%2520open%2520data&collection=dataset&q=Local%20Authority%20Districts%20LAD%20boundaries
# Local Authority Districts (April 2019) Boundaries UK BFC
# Local Authority Districts (December 2021) Boundaries UK BUC
# e06 <- read_sf("./data/Local_Authority_District_to_County_and_Unitary_Authority_(December_2016)_Lookup_in_EW/Local_Authority_District_to_County_and_Unitary_Authority_(December_2016)_Lookup_in_EW.shp")
# e06 <- read_sf("./data/Rural_Urban_Classification_(2021)_of_Local_Authority_Districts_(2021)_in_EW/Rural_Urban_Classification_(2021)_of_Local_Authority_Districts_(2021)_in_EW.shp")
e06_2021 <- read_sf("./data/Local_Authority_Districts_May_2021_UK_BFC_2022_-4054626209059053555/LAD_MAY_2021_UK_BFC.shp")

ggplot() +
  geom_sf(data = e06, aes(fill = LAD21CD)) 


unique(substr(names(table(e06$AreaCode)), 1,3))


# fingertips data ---------------------------------------------------------

profs <- profiles()

profs_smoke <- profs[grepl("Smok", profs$ProfileName),]
head(profs_smoke)
# A tibble: 6 × 4
# ProfileID ProfileName       DomainID DomainName                                
# <int> <chr>                <int> <chr>                                     
# 1        18 Smoking Profile 1938132885 Key indicators                            
# 2        18 Smoking Profile 1938132886 Smoking prevalence in adults              
# 3        18 Smoking Profile 1938132900 Smoking prevalence in priority populations
# 4        18 Smoking Profile 1938132887 Smoking related mortality                 
# 5        18 Smoking Profile 1938132888 Smoking related ill health                
# 6        18 Smoking Profile 1938132889 Impact of smoking   

profid <- 18
inds <- indicators(ProfileID = profid)
# smoking prevalence indicators from the Annual Population Survey (APS) updated with 2024 data
# smoking prevalence indicators from the GP Patient Survey (GPPS) updated with 2024 to 2025 data

# key indictor 
print(inds[grepl("never", inds$IndicatorName), c("IndicatorID", "IndicatorName")])
# A tibble: 4 × 2
# IndicatorID IndicatorName                                                        
# <int> <fct>                                                                
# 1       92538 Smoking Prevalence in adults (aged 18 and over) - never smoked (APS) 
# 2       92308 Smoking prevalence in adults (aged 18 and over) - never smoked (GPPS…

# AreaCode GSS Code

indid <- 92538
df <- fingertips_data(IndicatorID = indid, AreaTypeID = "All")
unique(substr(names(table(df$AreaCode)), 1,3))
# "E06" "E07" "E08" "E09" "E10" "E38" "E54" "E92"
a <- head(df)

# obesity
indid <- 93088
df <- fingertips_data(IndicatorID = indid, AreaTypeID = "All")
head(df)
df_2015 <- df[df$Timeperiod=="2015/16", ] %>% 
  
df_ <- df_2015 %>% filter(substr(AreaCode, 1,3) == "E06")

unique(substr(names(table(df_2015$AreaCode)), 1,3))



