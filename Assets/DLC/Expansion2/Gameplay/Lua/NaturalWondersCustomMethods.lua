------------------------------------------------------------------------------
--	FILE:	  NaturalWondersCustomMethods.lua
--	AUTHOR:   Bob Thomas
--	PURPOSE:  Functions designed to support custom natural wonder placement.
------------------------------------------------------------------------------
--	Copyright (c) 2011 Firaxis Games, Inc. All rights reserved.
------------------------------------------------------------------------------

--[[ -------------------------------------------------------------------------
NOTE: This file is an essential component of the Start Plot System. I have
separated out the functions in this file to permit more convenient operation
for modders wishing to add new natural wonders or modify existing ones. If
you are supplying new custom methods, you will not have to supply an updated
version of AssignStartingPlots with your mod; instead, you only have to supply
an update of this file along with your updated Civ5Features.xml file.

CONTENTS OF THIS FILE:

* NWCustomEligibility(x, y, method_number)
* NWCustomPlacement(x, y, row_number, method_number)
------------------------------------------------------------------------- ]]--

include("MapmakerUtilities");

------------------------------------------------------------------------------
function NWCustomEligibility(x, y, method_number)
	if method_number == 1 then
		-- This method checks a candidate plot for eligibility to be the Great Barrier Reef.
		local iW, iH = Map.GetGridSize();
		local plotIndex = y * iW + x + 1;
		-- We don't care about the center plot for this wonder. It can be forced. It's the surrounding plots that matter.
		-- This is also the only natural wonder type with a footprint larger than seven tiles.
		-- So first we'll check the extra tiles, make sure they are there, are ocean water, and have no Ice.
		local iNumCoast = 0;
		local extra_direction_types = {
			DirectionTypes.DIRECTION_EAST,
			DirectionTypes.DIRECTION_SOUTHEAST,
			DirectionTypes.DIRECTION_SOUTHWEST};
		local SEPlot = Map.PlotDirection(x, y, DirectionTypes.DIRECTION_SOUTHEAST)
		local southeastX = SEPlot:GetX();
		local southeastY = SEPlot:GetY();
		for loop, direction in ipairs(extra_direction_types) do -- The three plots extending another plot past the SE plot.
			local adjPlot = Map.PlotDirection(southeastX, southeastY, direction)
			if adjPlot == nil then
				return false
			end
			if adjPlot:IsWater() == false or adjPlot:IsLake() == true then
				return false
			end
			local featureType = adjPlot:GetFeatureType()
			if featureType ~= FeatureTypes.NO_FEATURE then
				return false
			end
			local terrainType = adjPlot:GetTerrainType()
			if terrainType == TerrainTypes.TERRAIN_COAST then
				iNumCoast = iNumCoast + 1;
			end
		end
		-- Now check the rest of the adjacent plots.
		local direction_types = { -- Not checking to southeast.
			DirectionTypes.DIRECTION_NORTHEAST,
			DirectionTypes.DIRECTION_EAST,
			DirectionTypes.DIRECTION_SOUTHWEST,
			DirectionTypes.DIRECTION_WEST,
			DirectionTypes.DIRECTION_NORTHWEST};
		for loop, direction in ipairs(direction_types) do
			local adjPlot = Map.PlotDirection(x, y, direction)
			if adjPlot:IsWater() == false then
				return false
			end
			local terrainType = adjPlot:GetTerrainType()
			if terrainType == TerrainTypes.TERRAIN_COAST then
				iNumCoast = iNumCoast + 1;
			end
		end
		-- If not enough coasts, reject this site.
		if iNumCoast < 4 then
			return false
		end
		-- This site is in the water, with at least some of the water plots being coast, so it's good.
		return true
	
	elseif method_number == 2 then
		-- This method checks a candidate plot for eligibility to be Rock of Gibraltar.
		local plot = Map.GetPlot(x, y);
		-- Checking center plot, which must be in the water or on the coast.
		local iW, iH = Map.GetGridSize();
		if plot:IsWater() == false and AdjacentToSaltWater(x, y) == false then
			return false
		end
		-- Now process the surrounding plots.
		local iNumLand, iNumCoast = 0, 0;
		local direction_types = {
			DirectionTypes.DIRECTION_NORTHEAST,
			DirectionTypes.DIRECTION_EAST,
			DirectionTypes.DIRECTION_SOUTHEAST,
			DirectionTypes.DIRECTION_SOUTHWEST,
			DirectionTypes.DIRECTION_WEST,
			DirectionTypes.DIRECTION_NORTHWEST
		};
		for loop, direction in ipairs(direction_types) do
			local adjPlot = Map.PlotDirection(x, y, direction)
			local plotType = adjPlot:GetPlotType();
			local terrainType = adjPlot:GetTerrainType()
			local featureType = adjPlot:GetFeatureType()
			if terrainType == TerrainTypes.TERRAIN_COAST and plot:IsLake() == false then
				if featureType == FeatureTypes.NO_FEATURE then
					iNumCoast = iNumCoast + 1;
				end
			end
			if plotType ~= PlotTypes.PLOT_OCEAN then
				iNumLand = iNumLand + 1;
			end
		end
		-- If too much land (or none), reject this site.
		if iNumLand ~= 1 then
			return false
		end
		-- If not enough coast, reject this site.
		if iNumCoast < 3 then
			return false
		end
		-- This site is good.
		return true

	-- These method numbers are not needed for the core game's natural wonders;
	-- however, this is where a modder could insert more custom methods, as needed.
	-- Any new methods added must be called from Natural_Wonder_Placement in Civ5Features.xml - Sirian, June 2011
	--
	--elseif method_number == 3 then
	--elseif method_number == 4 then
	--elseif method_number == 5 then

	else -- Unidentified Method Number
		return false
	end
end
------------------------------------------------------------------------------
function NWCustomPlacement(x, y, row_number, method_number)
	local iW, iH = Map.GetGridSize();
	if method_number == 1 then
		-- This method handles tile changes for the Great Barrier Reef.
		local plot = Map.GetPlot(x, y);
		if not plot:IsWater() then
			plot:SetPlotType(PlotTypes.PLOT_OCEAN, false, false);
		end
		if plot:GetTerrainType() ~= TerrainTypes.TERRAIN_COAST then
			plot:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, false)
		end
		-- The Reef has a longer shape and demands unique handling. Process the extra plots.
		local extra_direction_types = {
			DirectionTypes.DIRECTION_EAST,
			DirectionTypes.DIRECTION_SOUTHEAST,
			DirectionTypes.DIRECTION_SOUTHWEST};
		local SEPlot = Map.PlotDirection(x, y, DirectionTypes.DIRECTION_SOUTHEAST)
		if not SEPlot:IsWater() then
			SEPlot:SetPlotType(PlotTypes.PLOT_OCEAN, false, false);
		end
		if SEPlot:GetTerrainType() ~= TerrainTypes.TERRAIN_COAST then
			SEPlot:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, false)
		end
		if SEPlot:GetFeatureType() ~= FeatureTypes.NO_FEATURE then
			SEPlot:SetFeatureType(FeatureTypes.NO_FEATURE, -1)
		end
		local southeastX = SEPlot:GetX();
		local southeastY = SEPlot:GetY();
		for loop, direction in ipairs(extra_direction_types) do -- The three plots extending another plot past the SE plot.
			local adjPlot = Map.PlotDirection(southeastX, southeastY, direction)
			if adjPlot:GetTerrainType() ~= TerrainTypes.TERRAIN_COAST then
				adjPlot:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, false)
			end
			local adjX = adjPlot:GetX();
			local adjY = adjPlot:GetY();
			local adjPlotIndex = adjY * iW + adjX + 1;
		end
		-- Now check the rest of the adjacent plots.
		local direction_types = { -- Not checking to southeast.
			DirectionTypes.DIRECTION_NORTHEAST,
			DirectionTypes.DIRECTION_EAST,
			DirectionTypes.DIRECTION_SOUTHWEST,
			DirectionTypes.DIRECTION_WEST,
			DirectionTypes.DIRECTION_NORTHWEST
			};
		for loop, direction in ipairs(direction_types) do
			local adjPlot = Map.PlotDirection(x, y, direction)
			if adjPlot:GetTerrainType() ~= TerrainTypes.TERRAIN_COAST then
				adjPlot:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, false)
			end
		end
		-- Now place the Reef's second wonder plot. (The core method will place the main plot).
		local feature_type_to_place;
		for thisFeature in GameInfo.Features() do
			if thisFeature.Type == "FEATURE_REEF" then
				feature_type_to_place = thisFeature.ID;
				break
			end
		end
		SEPlot:SetFeatureType(feature_type_to_place);
	
	elseif method_number == 2 then
		-- This method handles tile changes for the Rock of Gibraltar.
		local plot = Map.GetPlot(x, y);
		plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
		plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false)
		local direction_types = {
			DirectionTypes.DIRECTION_NORTHEAST,
			DirectionTypes.DIRECTION_EAST,
			DirectionTypes.DIRECTION_SOUTHEAST,
			DirectionTypes.DIRECTION_SOUTHWEST,
			DirectionTypes.DIRECTION_WEST,
			DirectionTypes.DIRECTION_NORTHWEST};
		for loop, direction in ipairs(direction_types) do
			local adjPlot = Map.PlotDirection(x, y, direction)
			if adjPlot:GetPlotType() == PlotTypes.PLOT_OCEAN then
				if adjPlot:GetTerrainType() ~= TerrainTypes.TERRAIN_COAST then
					adjPlot:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, false)
				end
			else
				if adjPlot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					adjPlot:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
				end
			end
		end

	-- These method numbers are not needed for the core game's natural wonders;
	-- however, this is where a modder could insert more custom methods, as needed.
	-- Any new methods added must be called from Natural_Wonder_Placement in Civ5Features.xml - Sirian, June 2011
	--
	--elseif method_number == 3 then
	--elseif method_number == 4 then
	--elseif method_number == 5 then

	end
end
------------------------------------------------------------------------------
