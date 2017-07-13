# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

require 'erb'
require 'json'
require 'securerandom'
require 'mongo'
require 'time'
require_relative 'resources/Output'

#start the measure
class PushCustomResultsToMongoDB < OpenStudio::Ruleset::ReportingUserScript

  # human readable name
  def name
    return "PushCustomResultsToMongoDB"
  end

  # human readable description
  def description
    return "Will push a user-customized report to MongoDB"
  end

  # human readable description of modeling approach
  def modeler_description
    return "I think that you will like this one."
  end

  # define the arguments that the user will input
  def arguments()
    args = OpenStudio::Ruleset::OSArgumentVector.new

    # this measure will require arguments, but at this time, they are not known

    return args
  end 
  
  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)
    
    result = OpenStudio::IdfObjectVector.new
    
    # use the built-in error checking 
    if !runner.validateUserArguments(arguments(), user_arguments)
      return result
    end
    
    request = OpenStudio::IdfObject.load("Output:Variable,,Site Outdoor Air Drybulb Temperature,Hourly;").get
    result << request
    
    return result
  end

  # sql_query method
  def sql_query(runner, sql, report_name, query)
    val = nil
    result = sql.execAndReturnFirstDouble("SELECT Value FROM TabularDataWithStrings WHERE ReportName='#{report_name}' AND #{query}")
    if result.empty?
      runner.registerWarning("Query failed for #{report_name} and #{query}")
    else
      begin
        val = result.get
      rescue
        val = nil
        runner.registerWarning('Query result.get failed')
      end
    end

    val
  end
  
  # define what happens when the measure is run
  def run(runner, user_arguments)
    post = true
    super(runner, user_arguments)
    runner.registerInfo("Starting PushCustomResultsToMongoDB...")
    # use the built-in error checking 
    if !runner.validateUserArguments(arguments(), user_arguments)
      return false
    end

    # get the last model and sql file
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError("Cannot find last model.")
      return false
    end
    #get the large pieces
    model = model.get
    building = model.getBuilding
    site = model.getSite
    #puts model

    sqlFile = runner.lastEnergyPlusSqlFile
    if sqlFile.empty?
      runner.registerError("Cannot find last sql file.")
      return false
    end
    sqlFile = sqlFile.get

    model.setSqlFile(sqlFile)

    epwFile = runner.lastEpwFile
    if epwFile.empty?
      runner.registerError("Cannot find last epw file.")
      return false
    end
    epwFile = epwFile.get

    #building calls
    floorArea = building.floorArea
    surfaceArea = building.exteriorSurfaceArea
    volume = building.airVolume
    wallArea = building.exteriorWallArea
    building_rotation = building.northAxis
    lighting_power_density = building.lightingPowerPerFloorArea
    equip_power_density = building.electricEquipmentPowerPerFloorArea
    infiltration = building.infiltrationDesignFlowPerExteriorWallArea
    infiltration_units = "m3/m2"
    latitude = site.latitude
    longitude = site.longitude
    city = epwFile.city
    country = epwFile.country
    state = epwFile.stateProvinceRegion

    buildingType = building.suggestedStandardsBuildingTypes
    puts buildingType #in order to make this work (return 1 value) it has to be set apriori todo: look into a measure to set the type?

    #climes = site.climateZones
    #puts climes.get

    
    # SQL calls
    # put data into the local variable 'output', all local variables are available for erb to use when configuring the input html file
    window_to_wall_ratio_north = sql_query(runner, sqlFile, 'InputVerificationandResultsSummary', "TableName='Window-Wall Ratio' AND RowName='Gross Window-Wall Ratio' AND ColumnName='North (315 to 45 deg)'")
    window_to_wall_ratio_south = sql_query(runner, sqlFile, 'InputVerificationandResultsSummary', "TableName='Window-Wall Ratio' AND RowName='Gross Window-Wall Ratio' AND ColumnName='South (135 to 225 deg)'")
    window_to_wall_ratio_east = sql_query(runner, sqlFile, 'InputVerificationandResultsSummary', "TableName='Window-Wall Ratio' AND RowName='Gross Window-Wall Ratio' AND ColumnName='East (45 to 135 deg)'")
    window_to_wall_ratio_west = sql_query(runner, sqlFile, 'InputVerificationandResultsSummary', "TableName='Window-Wall Ratio' AND RowName='Gross Window-Wall Ratio' AND ColumnName='West (225 to 315 deg)'")
    total_site_eui = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary', "TableName='Site and Source Energy' AND RowName='Total Site Energy' AND ColumnName='Energy Per Conditioned Building Area'")
    time_setpoint_not_met_during_occupied_heating = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary', "TableName='Comfort and Setpoint Not Met Summary' AND RowName='Time Setpoint Not Met During Occupied Heating' AND ColumnName='Facility'")
    time_setpoint_not_met_during_occupied_cooling = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary', "TableName='Comfort and Setpoint Not Met Summary' AND RowName='Time Setpoint Not Met During Occupied Cooling' AND ColumnName='Facility'")
    time_setpoint_not_met_during_occupied_hours = time_setpoint_not_met_during_occupied_heating + time_setpoint_not_met_during_occupied_cooling
    heating_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Heating' AND ColumnName='Electricity'" )
    cooling_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Cooling' AND ColumnName='Electricity'" )
    lighting_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Interior Lighting' AND ColumnName='Electricity'" )
    ext_lighting_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Exterior Lighting' AND ColumnName='Electricity'" )
    equipment_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Interior Equipment' AND ColumnName='Electricity'" )
    ext_equipment_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Exterior Equipment' AND ColumnName='Electricity'" )
    fan_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Fans' AND ColumnName='Electricity'" )
    pump_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Pumps' AND ColumnName='Electricity'" )
    heat_rejection_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Heat Rejection' AND ColumnName='Electricity'" )
    humidification_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Humidification' AND ColumnName='Electricity'" )
    heat_recovery_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Heat Recovery' AND ColumnName='Electricity'" )
    water_systems_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Water Systems' AND ColumnName='Electricity'" )
    refrigeration_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Refrigeration' AND ColumnName='Electricity'" )
    generators_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Generators' AND ColumnName='Electricity'" )
    total_elec = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Total End Uses' AND ColumnName='Electricity'" )

    heating_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Heating' AND ColumnName='Natural Gas'" )
    cooling_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Cooling' AND ColumnName='Natural Gas'" )
    lighting_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Interior Lighting' AND ColumnName='Natural Gas'" )
    ext_lighting_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Exterior Lighting' AND ColumnName='Natural Gas'" )
    equipment_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Interior Equipment' AND ColumnName='Natural Gas'" )
    ext_equipment_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Exterior Equipment' AND ColumnName='Natural Gas'" )
    fan_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Fans' AND ColumnName='Natural Gas'" )
    pump_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Pumps' AND ColumnName='Natural Gas'" )
    heat_rejection_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Heat Rejection' AND ColumnName='Natural Gas'" )
    humidification_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Humidification' AND ColumnName='Natural Gas'" )
    heat_recovery_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Heat Recovery' AND ColumnName='Natural Gas'" )
    water_systems_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Water Systems' AND ColumnName='Natural Gas'" )
    refrigeration_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Refrigeration' AND ColumnName='Natural Gas'" )
    generators_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Generators' AND ColumnName='Natural Gas'" )
    total_ng = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Total End Uses' AND ColumnName='Natural Gas'" )

    heating_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Heating' AND ColumnName='Water'" )
    cooling_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Cooling' AND ColumnName='Water'" )
    lighting_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Interior Lighting' AND ColumnName='Water'" )
    ext_lighting_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Exterior Lighting' AND ColumnName='Water'" )
    equipment_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Interior Equipment' AND ColumnName='Water'" )
    ext_equipment_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Exterior Equipment' AND ColumnName='Water'" )
    fan_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Fans' AND ColumnName='Water'" )
    pump_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Pumps' AND ColumnName='Water'" )
    heat_rejection_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Heat Rejection' AND ColumnName='Water'" )
    humidification_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Humidification' AND ColumnName='Water'" )
    heat_recovery_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Heat Recovery' AND ColumnName='Water'" )
    water_systems_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Water Systems' AND ColumnName='Water'" )
    refrigeration_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Refrigeration' AND ColumnName='Water'" )
    generators_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Generators' AND ColumnName='Water'" )
    total_water = sql_query(runner, sqlFile, 'AnnualBuildingUtilityPerformanceSummary',"TableName='End Uses' AND RowName='Total End Uses' AND ColumnName='Water'" )

    output = OutputVariables.new
    envelope = EnvelopeDefinition.new
    envelope.wwr_north = window_to_wall_ratio_north
    envelope.wwr_east = window_to_wall_ratio_east
    envelope.wwr_south = window_to_wall_ratio_south
    envelope.wwr_west = window_to_wall_ratio_west
    envelope.infiltration_per_wall_area = infiltration
    envelope.infiltration_per_wall_area_units = infiltration_units

    site = SiteOutput.new
    site.rotation = building_rotation
    site.city = city
    site.state = state
    site.country = country
    building = BuildingOutput.new
    building.floor_area = floorArea
    building.floor_area_units = "m2"
    building.surface_area = surfaceArea
    building.surface_area_units = "m2"
    building.volume = volume
    building.volume_units = "m3"
    building.exterior_wall_area = wallArea
    building.lpd = lighting_power_density
    building.lpd_units = "W/m2" #this is how EnergyPlus works today
    building.epd = equip_power_density
    building.epd_units = "W/m2" #this is how EnergyPlus works today


    geoLoc = GeoCoordinates.new
    geoLoc.lon = longitude 
    geoLoc.lat = latitude

    unmet = UnmetHours.new
    unmet.occ_cool = time_setpoint_not_met_during_occupied_cooling
    unmet.occ_heat = time_setpoint_not_met_during_occupied_heating
    unmet.occ_total = time_setpoint_not_met_during_occupied_hours

    eeu = ElectricityEndUses.new
    eeu.energy_units = "GJ"
    eeu.heating = heating_elec
    eeu.cooling = cooling_elec
    eeu.interior_lighting = lighting_elec
    eeu.exterior_lighting = ext_lighting_elec
    eeu.interior_equipment = equipment_elec
    eeu.exterior_equipment = ext_equipment_elec
    eeu.fans = fan_elec
    eeu.pumps = pump_elec
    eeu.heat_rejection = heat_rejection_elec
    eeu.humidification = humidification_elec
    eeu.heat_recovery = heat_recovery_elec
    eeu.water_systems = water_systems_elec
    eeu.refrigeration = refrigeration_elec
    eeu.generators = generators_elec
    eeu.total = total_elec

    neu = NaturalGasEndUses.new
    neu.energy_units = "GJ"
    neu.heating = heating_ng
    neu.cooling = cooling_ng
    neu.interior_lighting = lighting_ng
    neu.exterior_lighting = ext_lighting_ng
    neu.interior_equipment = equipment_ng
    neu.exterior_equipment = ext_equipment_ng
    neu.fans = fan_ng
    neu.pumps = pump_ng
    neu.heat_rejection = heat_rejection_ng
    neu.humidification = humidification_ng
    neu.heat_recovery = heat_recovery_ng
    neu.water_systems = water_systems_ng
    neu.refrigeration = refrigeration_ng
    neu.generators = generators_ng
    neu.total = total_ng

    weu = WaterEndUses.new
    weu.units = "GJ"
    weu.heating = heating_water
    weu.cooling = cooling_water
    weu.interior_lighting = lighting_water
    weu.exterior_lighting = ext_lighting_water
    weu.interior_equipment = equipment_water
    weu.exterior_equipment = ext_equipment_water
    weu.fans = fan_water
    weu.pumps = pump_water
    weu.heat_rejection = heat_rejection_water
    weu.humidification = humidification_water
    weu.heat_recovery = heat_recovery_water
    weu.water_systems = water_systems_water
    weu.refrigeration = refrigeration_water
    weu.generators = generators_water
    weu.total = total_water

    output.building_envelope = envelope
    output.site = site
    output.building = building
    output.unmet_hours = unmet
    output.electricity_end_uses = eeu
    output.natural_gas_end_uses = neu
    output.water_end_uses = weu
    
    inputVars = InputVariables.new
    inputVars.user_data_points = "{}" #TODO: get this from the mongostore on OS-server


    outObj = Output.new
    outObj.input_variables = inputVars
    outObj.user_id = 1 #how do we pass a user id into this measure?
    outObj.os_model_id = -1 #how do we get a job id, or is this impossible?
    outObj.sql_path = sqlFile.path.to_s #todo: this could be parsed to grab the analysis uuid if I wish when using OpenStudio
    outObj.building_type = "Retail" #how might this be passed in as an argument?  Is this possible?
    outObj.climate_zone = "2A" #must be a way to get this from the model, weather file, or site?
    outObj.output_variables = output
    outObj.EUI = sqlFile.netSiteEnergy.get / model.getBuilding.floorArea #always GJ/m2 by default in the db, it will be converted on the front end
    outObj.EUI_units = "GJ/m2"
    outObj.EUI = total_site_eui #or we can have it in MJ/m2 if we want
    outObj.EUI_units = "MJ/m2"
    outObj.daylight_autonomy = -1 #how do we calculate daylight autonomy?
    outObj.geo_coords = geoLoc
    
    puts outObj.to_hash

    web_asset_path = OpenStudio.getSharedResourcesPath() / OpenStudio::Path.new("web_assets")


    # get the weather file run period (as opposed to design day run period)
    ann_env_pd = nil
    sqlFile.availableEnvPeriods.each do |env_pd|
      env_type = sqlFile.environmentType(env_pd)
      if env_type.is_initialized
        if env_type.get == OpenStudio::EnvironmentType.new("WeatherRunPeriod")
          ann_env_pd = env_pd
          break
        end
      end
    end

    # only try to get the annual timeseries if an annual simulation was run
    runner.registerInfo("annual run? #{ann_env_pd}")
    if ann_env_pd

      # get desired variable
      key_value =  "Environment"
      time_step = "Hourly" # "Zone Timestep", "Hourly", "HVAC System Timestep"
      variable_name = "Site Outdoor Air Drybulb Temperature"
      output_timeseries = sqlFile.timeSeries(ann_env_pd, time_step, variable_name, key_value) # key value would go at the end if we used it.
      
      if output_timeseries.empty?
        runner.registerWarning("Timeseries not found.")
      else
        runner.registerInfo("Found timeseries.")
      end
    else
      runner.registerWarning("No annual environment period found.")
    end
    
    if(post)
      encoded_url = '52.26.47.71:27017'
      client = Mongo::Client.new([encoded_url], :database => 'pw_test_os_server')
      collection = client[:sim_results]
      doc = { simName: SecureRandom.uuid, from: 'Open Studio in the Cloud', timestamp: Time.now.to_i }
      result = collection.insert_one(outObj.to_hash)
      puts "Result of #{doc} upload: #{result}"
    end

    # close the sql file
    sqlFile.close()
    puts "Sql file closed"
    return true
 
  end

end

# register the measure to be used by the application
PushCustomResultsToMongoDB.new.registerWithApplication
