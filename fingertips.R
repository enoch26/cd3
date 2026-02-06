
library(fingertipsR)
library(sf)
library(terra)
library(here)
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

e06 <- read_sf(here("./cd3/Local_Authority_District_to_County_and_Unitary_Authority_(December_2016)_Lookup_in_EW/Local_Authority_District_to_County_and_Unitary_Authority_(December_2016)_Lookup_in_EW.shp"))

unique(substr(names(table(e06$AreaCode)), 1,3))

