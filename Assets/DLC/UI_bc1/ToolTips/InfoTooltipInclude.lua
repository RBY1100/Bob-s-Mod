--==========================================================
-- Modified by bc1 from 1.0.3.276 code using Notepad++
-- extend full unit & building info pregame
-- extend AI mood info
-- code is common across civ5 versions using switches
-- compatible with Communitas breaking yield types
-- TODO: lots !
-- remove YieldIcons
--==========================================================

if not GameInfoCache then
	include "GameInfoCache" -- warning! booleans are true, not 1, and use iterator ONLY with table field conditions, NOT string SQL query
end
local GameInfo = GameInfoCache

local IsCiv5 = InStrategicView ~= nil
local IsCivBE = not IsCiv5
local IsCiv5BNW = IsCiv5 and ContentManager.IsActive("6DA07636-4123-4018-B643-6575B4EC336B", ContentType.GAMEPLAY)
local IsCiv5Vanilla = IsCiv5 and not IsCiv5BNW and not ContentManager.IsActive("0E3751A1-F840-4e1b-9706-519BF484E59D", ContentType.GAMEPLAY)

if IsCiv5BNW and not GreatPeopleIcons then
	include "GreatPeopleIcons"
end
local GreatPeopleIcons = GreatPeopleIcons

--print( "Root contexts:", LookUpControl( "/FrontEnd" ) or "nil", LookUpControl( "/InGame" ) or "nil", LookUpControl( "/LeaderHeadRoot" ) or "nil")

--==========================================================
-- Minor lua optimizations
--==========================================================

local ipairs = ipairs
local ceil = math.ceil
local floor = math.floor
local max = math.max
local pairs = pairs
local format = string.format
local concat = table.concat
local insert = table.insert
local sort = table.sort
local tonumber = tonumber
local tostring = tostring
local type = type

local DataBaseQuery = DB.Query
local DisputeLevelTypes = DisputeLevelTypes
local Game = Game
local GameDefines = GameDefines
local GameInfoTypes = GameInfoTypes
local GameOptionTypes = GameOptionTypes
local Locale_ToLower = Locale.ToLower
local Locale_ToUpper = Locale.ToUpper
local Locale_HasTextKey = Locale.HasTextKey
local MajorCivApproachTypes = MajorCivApproachTypes
local OptionsManager = OptionsManager
local Players = Players
local PreGame = PreGame
local Teams = Teams
local ThreatTypes = ThreatTypes
local TradeableItems = TradeableItems
local GetHeadSelectedCity = UI.GetHeadSelectedCity
local GetNumCurrentDeals = UI.GetNumCurrentDeals
local LoadCurrentDeal = UI.LoadCurrentDeal
local YieldTypes = YieldTypes
local L
do
	local _L = Locale.ConvertTextKey
	function L( text, ...)
		return _L( tostring(text), ... )
	end
end

local YieldIcons = {}
for row in GameInfo.Yields() do
	YieldIcons[row.ID or false] = row.IconString
	YieldIcons[row.Type or false] = row.IconString
end
YieldIcons.YIELD_CULTURE = YieldIcons.YIELD_CULTURE or "[ICON_CULTURE]"

local unit_keys = {}
for row in DataBaseQuery( "PRAGMA table_info(units)" ) do
	local k = row.name
	local s = type(k)=="string" and "TXT_KEY_EUI_UNIT_" .. k:upper()
	if s and Locale_HasTextKey( s ) then
		unit_keys[ k ] = s
	end
end
--print "unit_keys" for k, v in pairs( unit_keys ) do print(k, v) end

local building_keys = {}
for row in DataBaseQuery( "PRAGMA table_info(buildings)" ) do
	local k = row.name
	local s = type(k)=="string" and "TXT_KEY_EUI_BUILDING_" .. k:upper()
	if s and Locale_HasTextKey( s ) then
		building_keys[ k ] = s
	end
end
--print "building_keys" for k, v in pairs( building_keys ) do print(k, v) end
local building_foreign_keys = {}
for row in DataBaseQuery( "PRAGMA foreign_key_list(buildings)" ) do
--	id	seq	table	from	to	on_update	on_delete
	if row.to == "Type" then
		building_foreign_keys[ row.from ] = row.table
	end
end
--print "building_foreign_keys" for k, v in pairs( building_foreign_keys ) do print(k, v) end

local function InsertTags( item, tips, keys, foreign_keys )
	local v
	for k, s in pairs( keys ) do
		v = item[ k ]
		if v then
			if v == true then
				insert( tips, L( s ) )
			elseif tonumber(v) then 
				if v ~=0 then
					insert( tips, L( s, v, v/100 ) )
				end
			else
				k = foreign_keys[ k ]
				if k then
					k = GameInfo[ k ]
					if k then
						v = k[ v ]
						if v then
							insert( tips, L( s, v._Name ) )
						end
					end
				end
			end
		end
	end
--[[
	for k, s in pairs( foreign_keys ) do
		v = GameInfo[s][ item[ k ] ]
		if v then
			insert( tips, k.." : "..tostring(v._Name) )
		end
	end
--]]
end

local function append( t, text )
	t[#t] = t[#t] .. text
end

local function insertLocalizedIfNonZero( t, textKey, ... )
	if ... ~= 0 then
		return insert( t, L( textKey, ... ) )
	end
end

local function insertLocalizedBulletIfNonZero( t, a, b, ... )
	if tonumber( b ) then
		if b ~= 0 then
			return insert( t, "[ICON_BULLET]" .. L( a, b, ... ) )
		end
	elseif ... ~= 0 then
		return insert( t, a .. L( b, ... ) )
	end
end

local g_currencyIcon = IsCiv5 and "[ICON_GOLD]" or "[ICON_ENERGY]"
local g_maintenanceCurrency = IsCiv5 and "GoldMaintenance" or "EnergyMaintenance"
local g_isScienceEnabled = true
local g_isPoliciesEnabled = true
--local g_isHappinessEnabled = true
local g_isReligionEnabled = not IsCiv5Vanilla

local function GetCivUnit( civilizationType, unitClassType )
	if unitClassType then
		if civilizationType then
			local unit = GameInfo.Civilization_UnitClassOverrides{ CivilizationType = civilizationType, UnitClassType = unitClassType }()
			unit = unit and GameInfo.Units[ unit.UnitType ]
			if unit then
				return unit
			end
		end
		local unitClass = GameInfo.UnitClasses[ unitClassType ]
		return unitClass and GameInfo.Units[ unitClass.DefaultUnit ]
	end
end

local function GetCivBuilding( civilizationType, buildingClassType )
	if buildingClassType then
		if civilizationType then
			local building = GameInfo.Civilization_BuildingClassOverrides{ CivilizationType = civilizationType, BuildingClassType = buildingClassType }()
			building = building and GameInfo.Buildings[ building.BuildingType ]
			if building then
				return building
			end
		end
		local buildingClass = GameInfo.BuildingClasses[ buildingClassType ]
		return buildingClass and GameInfo.Buildings[ buildingClass.DefaultBuilding ]
	end
end

local function GetCustomYieldString( tag, s, iterator )
	local tip = ""
	for row in iterator do
		if (row[tag] or 0) ~=0 then
			tip = format( s, tip, row[tag], YieldIcons[ row.YieldType ] or "?" )
		end
	end
	return tip
end
local function GetYieldString( iterator )
	return GetCustomYieldString( "Yield", "%s %+i%s", iterator )
end


local negativeOrPositiveTextColor = { [true] = "[COLOR_POSITIVE_TEXT]", [false] = "[COLOR_WARNING_TEXT]" }

local function TextColor( c, s )
	return c..(s or "???").."[ENDCOLOR]"
end

local function UnitColor( s )
	return TextColor("[COLOR_UNIT_TEXT]", s)
end

local function BuildingColor( s )
	return TextColor("[COLOR_YIELD_FOOD]", s)
end

local function PolicyColor( s )
	return TextColor("[COLOR_MAGENTA]", s)
end

local function TechColor( s )
	return TextColor("[COLOR_CYAN]", s)
end

local function BeliefColor( s )
	return TextColor("[COLOR_WHITE]", s)
end

local function BuildColor( s )
	return TextColor("[COLOR_GREEN]", s)
end

local function ResourceColor( s )
	return TextColor("[COLOR_BROWN]", s)
end

local function ResourceString( resource )
	return ( resource.IconString or "?" ) .. ResourceColor( resource._Name ) 
end

local function ResourceQuantity( resource, quantity )
	return format( "%+i%s%s", quantity, resource.IconString or "?", ResourceColor( resource._Name ) )
end

local function XPcolor( s )
	return TextColor("[COLOR_BLUE]", s)
end

local function SetKey( t, key, value )
	if key then
		t[key] = value or true
	end
end

local function AddPreWrittenHelpTextAndConcat( tips, row ) -- assumes tips is a table
	local tip = row and row.Help and L( row.Help ) or ""
	if tip ~= "" then
		if #tips > 2 then
			insert( tips, "----------------" )
		end
		insert( tips, tip )
	end
	return concat( tips, "[NEWLINE]" )
end

local GreatPeopleIcon = GreatPeopleIcons and function (k)
	return GreatPeopleIcons[k] 
end or function()
	return "[ICON_GREAT_PEOPLE]"
end

-------------------------------------------------
-- Help text for Units
-------------------------------------------------

-- How much does it cost to upgrade a Unit to a shiny new eUnit?
local function unitUpgradePrice( unit, unitUpgrade, unitProductionCost, unitUpgradeProductionCost )
	local upgradePrice = GameDefines.BASE_UNIT_UPGRADE_COST
		+ max( 0, (unitUpgradeProductionCost or unitUpgrade.Cost or 0) - (unitProductionCost or unit.Cost or 0) ) * GameDefines.UNIT_UPGRADE_COST_PER_PRODUCTION
	-- Upgrades for later units are more expensive
	local tech = GameInfo.Technologies[ unitUpgrade.PrereqTech ]
	local era = tech and GameInfo.Eras[ tech.Era ]
	if era then
		upgradePrice = floor( upgradePrice * ( era.ID * GameDefines.UNIT_UPGRADE_COST_MULTIPLIER_PER_ERA + 1 ) )
	end
	-- Discount
	-- upgradePrice = upgradePrice - floor( upgradePrice * unit:UpgradeDiscount() / 100)
	-- Mod (Policies, etc.)
	-- upgradePrice = floor( (upgradePrice * (100 + activePlayer:GetUnitUpgradeCostMod()))/100 )
	upgradePrice = floor( upgradePrice ^ GameDefines.UNIT_UPGRADE_COST_EXPONENT )
	-- Make the number not be funky
	return floor( upgradePrice / GameDefines.UNIT_UPGRADE_COST_VISIBLE_DIVISOR ) * GameDefines.UNIT_UPGRADE_COST_VISIBLE_DIVISOR
end

function GetHelpTextForUnit( unitID ) -- isIncludeRequirementsInfo )
	local unit = GameInfo.Units[ unitID ]
	if not unit then
		return "<Unit undefined in game database>"
	end

	-- Unit XML stats
	local productionCost = unit.Cost
	local rangedStrength = unit.RangedCombat
	local unitRange = unit.Range
	local combatStrength = unit.Combat
	local unitMoves = unit.Moves
	local unitDomainType = unit.Domain

	local thisUnitType = { UnitType = unit.Type }
	local thisUnitClass =  { UnitClassType = unit.Class }

	local freePromotions = {}

	local city, activeCivilizationType, item, resource

	for row in GameInfo.Unit_FreePromotions( thisUnitType ) do
		item = GameInfo.UnitPromotions[ row.PromotionType ]
		if item then
			insert( freePromotions, item._Name )
			unitRange = unitRange + (item.RangeChange or 0)
			unitMoves = unitMoves + (item.MovesChange or 0)
		end
	end

	-- Player data
	local activePlayerID = Game and Game.GetActivePlayer()
	local activePlayer = activePlayerID and Players[ activePlayerID ]

	-- BE orbital units
	local orbitalInfo = IsCivBE and unit.Orbital and GameInfo.OrbitalUnits[ unit.Orbital ]

	-- BE unit upgrades
	local unitName = unit._Name
	if activePlayer and IsCivBE then
		item = GameInfo.UnitUpgrades[ activePlayer:GetBestUnitUpgrade(unit.ID) ]
		unitName = item and item._Name or unitName
	end

	if activePlayer then
		productionCost = activePlayer:GetUnitProductionNeeded( unitID )
		item = GameInfo.Civilizations[ activePlayer:GetCivilizationType() ]
		activeCivilizationType = item and item.Type
		city = GetHeadSelectedCity()
		if city and city:GetOwner() ~= activePlayerID then
			city = nil
		end
		city = city or activePlayer:GetCapitalCity() or activePlayer:Cities()(activePlayer)
	end

	-- Name
	item = GameInfo.UnitCombatInfos[ unit.CombatClass ]
	local tip =  UnitColor( Locale_ToUpper( unitName ) )
	if item then
		tip = tip .. " (" .. (item._Name or "???") .. ")"
	end

	local tips = { tip }

	if orbitalInfo then
		append( tips, " ("..L"TXT_KEY_ORBITAL_UNITS"..")" )
		-- Orbital Duration
		if activePlayer then
			insert( tips, L("TXT_KEY_PRODUCTION_ORBITAL_DURATION", activePlayer:GetTurnsUnitAllowedInOrbit(unit.ID, true) ) ) --todo xml
		end
		-- Orbital Effect Range
		insert( tips, L( "TXT_KEY_PRODUCTION_ORBITAL_EFFECT_RANGE", orbitalInfo.EffectRange or 0  ) )
	elseif unitDomainType ~= "DOMAIN_AIR" then
		-- Movement:
		insert( tips, L"TXT_KEY_PEDIA_MOVEMENT_LABEL" .. " " .. unitMoves .. "[ICON_MOVES]" )
	end

	-- Ranged Combat:
	if rangedStrength > 0 then
		insert( tips, L"TXT_KEY_PEDIA_RANGEDCOMBAT_LABEL" .. " " .. rangedStrength .. "[ICON_RANGE_STRENGTH]" .. unitRange )
	end

	-- Combat:
	if combatStrength > 0 then
		insert( tips, format( "%s %g[ICON_STRENGTH]", L"TXT_KEY_PEDIA_COMBAT_LABEL", combatStrength ) )
	end

	-- Abilities:	--TXT_KEY_PEDIA_FREEPROMOTIONS_LABEL
	if #freePromotions > 0 then
		insert( tips, "[ICON_BULLET]" .. concat( freePromotions, "[NEWLINE][ICON_BULLET]" ) )
	end

	-- Ability to create building in city (e.g. vanilla great general)
	for row in GameInfo.Unit_Buildings( thisUnitType ) do
		item = GameInfo.Buildings[ row.BuildingType ]
		if item then
			insert( tips, "[ICON_BULLET]"..L"TXT_KEY_MISSION_CONSTRUCT".." " .. BuildingColor( item._Name ) )
		end
	end

	-- Actions	--TXT_KEY_PEDIA_WORKER_ACTION_LABEL
	for row in GameInfo.Unit_Builds( thisUnitType ) do
		local build = GameInfo.Builds[ row.BuildType ]
		if build then
			item = GameInfo.Improvements[ build.ImprovementType ]
			if not item or not item.SpecificCivRequired or not activePlayer or GameInfoTypes[ GameInfo.Civilizations[ item.CivilizationType ] ] == activePlayer:GetCivilizationType() then -- GameInfoTypes not available pregame: works because activePlayer is also nil
				item = GameInfo.Technologies[ build.PrereqTech ]
				insert( tips, "[ICON_BULLET]" .. (item and TechColor( item._Name ) .. " " or "") .. BuildColor( build._Name ) )
			end
		end
	end
	-- Great Engineer
	if (unit.BaseHurry or 0) > 0 then
		insert( tips, format( "[ICON_BULLET]%s %i[ICON_PRODUCTION]%+i[ICON_PRODUCTION]/[ICON_CITIZEN]", L"TXT_KEY_MISSION_HURRY_PRODUCTION", unit.BaseHurry, unit.HurryMultiplier or 0 ) )
	end

	-- Great Merchant
	if (unit.BaseGold or 0) > 0 then
		insert( tips, format( "[ICON_BULLET]%s %i%s%+i[ICON_INFLUENCE]", L"TXT_KEY_MISSION_CONDUCT_TRADE_MISSION", unit.BaseGold + ( unit.NumGoldPerEra or 0 ) * ( Game and Teams[Game.GetActiveTeam()]:GetCurrentEra() or PreGame.GetEra() ), g_currencyIcon, GameDefines.MINOR_FRIENDSHIP_FROM_TRADE_MISSION or 0 ) )
	end

	-- Other tags
	local v
	for k, s in pairs( unit_keys ) do
		v = unit[ k ]
		if v and v ~=0 and v~=-1 then
			insert( tips, "[ICON_BULLET]" .. L( s, v ) )
		end
	end
	-- Technology_DomainExtraMoves
	for row in GameInfo.Technology_DomainExtraMoves{ DomainType = unitDomainType } do
		item = GameInfo.Technologies[ row.TechType ]
		if item and (row.Moves or 0)~=0 then
			insert( tips, format( "[ICON_BULLET]%s %+i[ICON_MOVES]", TechColor( item._Name ), row.Moves ) )
		end
	end
--TODO Technology_TradeRouteDomainExtraRange

	-- Ability to generate tourism upon spawn
	if IsCiv5BNW then
		for row in GameInfo.Policy_TourismOnUnitCreation( thisUnitClass ) do
			item = GameInfo.Policies[ row.PolicyType ]
			if item and (row.Tourism or 0)~=0 then
				insert( tips, format( "[ICON_BULLET]%s %+i[ICON_TOURISM]", PolicyColor( item._Name ), row.Tourism ) )
			end
		end
	end

	-- Resources required:
	if Game then
		for resource in GameInfo.Resources() do
			item = Game.GetNumResourceRequiredForUnit( unitID, resource.ID )
			if resource and item ~= 0 then
				insert( tips, ResourceQuantity( resource, -item ) )
			end
		end
	else
		for row in GameInfo.Unit_ResourceQuantityRequirements( thisUnitType ) do
			resource = GameInfo.Resources[ row.ResourceType ]
			if resource and (row.Cost or 0)~=0 then
				insert( tips, ResourceQuantity( resource, -row.Cost ) )
			end
		end
	end

	insert( tips, "----------------" )

	-- Cost:
	local costTip
	if productionCost > 1 then -- Production cost
		if not unit.PurchaseOnly then
			costTip = productionCost .. "[ICON_PRODUCTION]"
		end
		local goldCost = 0
		if city then
			goldCost = city:GetUnitPurchaseCost( unitID )
		elseif (unit.HurryCostModifier or 0) > 0 then
			goldCost = (productionCost * GameDefines.GOLD_PURCHASE_GOLD_PER_PRODUCTION ) ^ GameDefines.HURRY_GOLD_PRODUCTION_EXPONENT
			goldCost = (unit.HurryCostModifier + 100) * goldCost / 100
			goldCost = goldCost - ( goldCost % GameDefines.GOLD_PURCHASE_VISIBLE_DIVISOR )
		end
		if goldCost > 0 then
			if costTip then
				costTip = costTip .. ("(%i%%)"):format(productionCost*100/goldCost)
				if IsCiv5Vanilla then
					costTip = costTip .. " / " .. goldCost .. g_currencyIcon
				else
					costTip = L("TXT_KEY_PEDIA_A_OR_B", costTip, goldCost .. g_currencyIcon )
				end
			else
				costTip = goldCost .. g_currencyIcon
			end
		end
	end -- production cost
	if g_isReligionEnabled then -- Faith cost
		local faithCost = 0
		if city then
			faithCost = city:GetUnitFaithPurchaseCost( unitID, true )
		elseif Game then
			faithCost = Game.GetFaithCost( unitID )
		elseif unit.RequiresFaithPurchaseEnabled and unit.FaithCost then
			faithCost = unit.FaithCost
		end
		if ( faithCost or 0 ) > 0 then
			if costTip then
				costTip = L("TXT_KEY_PEDIA_A_OR_B", costTip, faithCost .. "[ICON_PEACE]" )
			else
				costTip = faithCost .. "[ICON_PEACE]"
			end
		end
	end --faith cost
	if costTip then
		insert( tips, L"TXT_KEY_PEDIA_COST_LABEL" .. " " .. ( costTip or L"TXT_KEY_FREE" ) )
	end

	-- build using food / stop city growth
	if unit.Food then
		insert( tips, L"TXT_KEY_CITYVIEW_STAGNATION_TEXT" )
	end
	-- Settler Specifics
	if unit.Found or unit.FoundAbroad then
		append( tips, L("TXT_KEY_NO_ACTION_SETTLER_SIZE_LIMIT", GameDefines.CITY_MIN_SIZE_FOR_SETTLERS) )
	end

	-- Civilization:
	local civs = {}
	for requiredCivilizationType in GameInfo.Civilization_UnitClassOverrides( thisUnitType ) do
		item = GameInfo.Civilizations[ requiredCivilizationType.CivilizationType ]
		if item then
			insert( civs, item._Name )
		end
	end
	if #civs > 0 then
		insert( tips, L"TXT_KEY_PEDIA_CIVILIZATIONS_LABEL".." "..concat( civs, ", ") )
	end

	-- Replaces:
	item = GameInfo.UnitClasses[ unit.Class ]
	item = item and GameInfo.Units[ item.DefaultUnit ]
	if item and item ~= unit then
		insert( tips, L"TXT_KEY_PEDIA_REPLACES_LABEL".." "..UnitColor( item._Name ) ) --!!! row
	end

	if IsCivBE then
		-- Affinity Level Requirements
		for affinityPrereq in GameInfo.Unit_AffinityPrereqs( thisUnitType ) do
			local affinityInfo = (tonumber( affinityPrereq.Level) or 0 ) > 0 and GameInfo.Affinity_Types[ affinityPrereq.AffinityType ]
			if affinityInfo then
				insert( tips, L( "TXT_KEY_AFFINITY_LEVEL_REQUIRED", affinityInfo.ColorType, affinityPrereq.Level, affinityInfo.IconString or "?", affinityInfo._Name or "???" ) )
			end
		end
	end

	-- Required Policies:
	item = GameInfo.Policies[ unit.PolicyType ]
	if item then
		insert( tips, L( "TXT_KEY_EUI_REQUIRES", PolicyColor( item._Name ) ) )
	end

	-- Required Buildings:
	local buildings = {}
	for row in GameInfo.Unit_BuildingClassRequireds( thisUnitType ) do
		item = GetCivBuilding( activeCivilizationType, row.BuildingClassType )
		if item then
			insert( buildings, BuildingColor( item._Name ) )
		end
	end
	item = GameInfo.Projects[ unit.ProjectPrereq ]
	if item then
		insert( buildings, BuildingColor( item._Name ) )
	end
	if #buildings > 0 then
		insert( tips, L( "TXT_KEY_EUI_REQUIRES", concat( buildings, ", ") ) )
	end

	-- Prerequisite Techs:
	item = GameInfo.Technologies[ unit.PrereqTech ]
	if item and item.ID > 0 then
		insert( tips, L( "TXT_KEY_EUI_REQUIRES", TechColor( item._Name ) ) )
	end

	-- Upgrade from:
	local unitClassUpgrades = {}
	for unitUpgrade in GameInfo.Unit_ClassUpgrades( thisUnitClass ) do
		unitUpgrade = GameInfo.Units[ unitUpgrade.UnitType ]
		SetKey( unitClassUpgrades, unitUpgrade and unitUpgrade.Class )
	end
	local unitUpgrades = {}
	for unitToUpgrade in pairs( unitClassUpgrades ) do
		item = GetCivUnit( activeCivilizationType, unitToUpgrade )
		if item then
			insert( unitUpgrades, UnitColor( item._Name ) .. " ("..unitUpgradePrice( item, unit, activePlayer and activePlayer:GetUnitProductionNeeded( item.ID ), productionCost )..g_currencyIcon..")" )
		end
	end
	if #unitUpgrades > 0 then
		insert( tips, L"TXT_KEY_GOLD_UPGRADE_UNITS_HEADING3_TITLE" .. ": " .. concat( unitUpgrades, ", ") )
	end

	-- Becomes Obsolete with:
	item = GameInfo.Technologies[ unit.ObsoleteTech ]
	if item then
		insert( tips, L"TXT_KEY_PEDIA_OBSOLETE_TECH_LABEL" .. " " .. TechColor( item._Name ) )
	end

	-- Upgrade unit
	if Game then
		local item = Game.GetUnitUpgradesTo( unit.ID )
		item = GameInfo.Units[ item ]
		if item and activeCivilizationType then
			item = GetCivUnit( activeCivilizationType, item.Class )
			insert( tips, L"TXT_KEY_COMMAND_UPGRADE" .. ": " .. UnitColor( item._Name ) .. " ("..unitUpgradePrice( unit, item, productionCost, activePlayer:GetUnitProductionNeeded( item.ID ) )..g_currencyIcon..")" )
		end
	else
		local unitClassUpgrades = {}
		for unitClassUpgrade in GameInfo.Unit_ClassUpgrades( thisUnitType ) do
			SetKey( unitClassUpgrades, unitClassUpgrade.UnitClassType )
		end
		local unitUpgrades = {}
		for unitUpgrade in pairs( unitClassUpgrades ) do
			item = GetCivUnit( activeCivilizationType, unitUpgrade )
			if item then
				insert( unitUpgrades, UnitColor( item._Name ) .. " ("..unitUpgradePrice( unit, item, productionCost )..g_currencyIcon..")" )
			end
		end
		if #unitUpgrades > 0 then
			insert( tips, L"TXT_KEY_COMMAND_UPGRADE" .. ": " .. concat( unitUpgrades, ", ") )
		end
	end

	-- Pre-written Help text
	return AddPreWrittenHelpTextAndConcat( tips, unit )
end


-------------------------------------------------
-- Help text for Buildings
-------------------------------------------------

local g_gameAvailableBeliefs = Game and { Game.GetAvailablePantheonBeliefs, Game.GetAvailableFounderBeliefs, Game.GetAvailableFollowerBeliefs, Game.GetAvailableFollowerBeliefs, Game.GetAvailableEnhancerBeliefs, Game.GetAvailableBonusBeliefs }

-------------------------------------------------
-- Helper function to build religion tooltip string
-------------------------------------------------
local function GetSpecialistSlotsTooltip( specialistType, numSlots )
	local tip = ""
	for row in GameInfo.SpecialistYields{ SpecialistType = specialistType } do
		tip = format( "%s %+i%s", tip, row.Yield, YieldIcons[ row.YieldType ] or "?" )
	end
	local row = GameInfo.Specialists[ specialistType ]
	return format( "%i %s%s", numSlots, row and row._Name or "???", tip )
end

local function GetSpecialistYields( city, specialist )
	local specialistID = specialist.ID
	local tip = ""
	if city then
		-- Culture
		local cultureFromSpecialist = city:GetCultureFromSpecialist( specialistID )
		-- Yield
		for yieldID = 0, YieldTypes.NUM_YIELD_TYPES-1 do
			local specialistYield = city:GetSpecialistYield( specialistID, yieldID )
			if specialistYield ~= 0 then
				tip = format( "%s %+i%s", tip, specialistYield, YieldIcons[ yieldID ] or "?" )
				if yieldID == YieldTypes.YIELD_CULTURE then
					cultureFromSpecialist = 0
				end
			end
		end
		if cultureFromSpecialist > 0 then
			tip = format( "%s %+i[ICON_CULTURE]", tip, cultureFromSpecialist )
		end
	else
		for row in GameInfo.SpecialistYields{ SpecialistType = specialist.Type or -1 } do
			tip = format( "%s %+i%s", tip, row.Yield, YieldIcons[ row.YieldType ] or "?" )
		end
	end
	if IsCiv5 and (specialist.GreatPeopleRateChange or 0) > 0 then
		tip = format( "%s %+i%s", tip, specialist.GreatPeopleRateChange, GreatPeopleIcon( specialist.Type ) )
	end
	return tip
end

function GetHelpTextForBuilding( buildingID, bExcludeName, bExcludeHeader, bNoMaintenance, city )
	local building = GameInfo.Buildings[ buildingID ]
	if not building then
		return "<Building undefined in game database>"
	end
	local buildingType = building.Type or -1
	local buildingClassType = building.BuildingClass
	local buildingClass = GameInfo.BuildingClasses[ buildingClassType ]
	local buildingClassID = buildingClass and buildingClass.ID
	local activePlayerID = Game and Game.GetActivePlayer()
	local activePlayer = activePlayerID and Players[ activePlayerID ]
	local maxGlobalInstances = buildingClass and tonumber(buildingClass.MaxGlobalInstances) or 0
	local thisBuildingType = { BuildingType = buildingType }
	local thisBuildingAndResourceTypes =  { BuildingType = buildingType }
	local thisBuildingClassType = { BuildingClassType = buildingClassType }
	local activeTeamID = Game and Game.GetActiveTeam()
	local activeTeam = activeTeamID and Teams[ activeTeamID ]
	local activeTeamTechs = activeTeam and activeTeam:GetTeamTechs()
	local activePlayerIdeologyID = activePlayer and activePlayer.GetLateGamePolicyTree and activePlayer:GetLateGamePolicyTree()
	local activePlayerIdeology = activePlayerIdeologyID and GameInfo.PolicyBranchTypes[ activePlayerIdeologyID ]
	local activePlayerIdeologyType = activePlayerIdeology and activePlayerIdeology.Type
	local activePlayerBeliefs = {}
	local availableBeliefs = {}
	local activePerkTypes = {}
	local tip, tips, items, item, activeCivilizationType, yieldID, yieldChange, yieldModifier, yieldPerPop, resource

	if g_isReligionEnabled and activePlayer then
		local religionID = activePlayer:GetReligionCreatedByPlayer()
		if religionID > 0 then
			activePlayerBeliefs = Game.GetBeliefsInReligion( religionID )
		elseif activePlayer:HasCreatedPantheon() then
			activePlayerBeliefs = { activePlayer:GetBeliefInPantheon() }
		end

		for i = 1, activePlayer:IsTraitBonusReligiousBelief() and 6 or 5 do
			if (activePlayerBeliefs[i] or -1) < 0 then -- active player does not already have a belief in "i" belief class
				for _,beliefID in pairs( g_gameAvailableBeliefs[i]() ) do
					availableBeliefs[beliefID] = true -- because available to active player in "i" belief class
				end
			end
		end
	end
	------------------
	-- Tech Filter
	local function techFilter( row )
		return row and g_isScienceEnabled and ( not activeTeamTechs or not activeTeamTechs:HasTech( row.ID ) )
	end

	------------------
	-- Policy Filter
	local function policyFilter( row )
		return row and g_isPoliciesEnabled
			and not( activePlayer and activePlayer:HasPolicy( row.ID ) and not activePlayer:IsPolicyBlocked( row.ID ) )
			and not( activePlayerIdeologyType and activePlayerIdeologyType ~= row.PolicyBranchType )
	end

	------------------
	-- Belief Filter
	local function beliefFilter( row )
		return row and g_isReligionEnabled and ( not activePlayer or availableBeliefs[ row.ID ] )
	end


	local productionCost = tonumber(building.Cost) or 0
	local maintenanceCost = tonumber(building[g_maintenanceCurrency]) or 0
	local happinessChange = (tonumber(building.Happiness) or 0) + (tonumber(building.UnmoddedHappiness) or 0)
	local defenseChange = tonumber(building.Defense) or 0
	local hitPointChange = tonumber(building.ExtraCityHitPoints) or 0
	local cultureChange = tonumber(building.Culture) or 0
	local cultureModifier = tonumber(building.CultureRateModifier) or 0

	local enhancedYieldTech = GameInfo.Technologies[ building.EnhancedYieldTech ]
	local enhancedYieldTechName = enhancedYieldTech and TechColor( enhancedYieldTech._Name )

	if activePlayer then
		item = GameInfo.Civilizations[ activePlayer:GetCivilizationType() ]
		activeCivilizationType = item and item.Type
		city = city or GetHeadSelectedCity()
		city = (city and city:GetOwner() == activePlayerID and city) or activePlayer:GetCapitalCity() or activePlayer:Cities()(activePlayer)

		-- player production cost
		productionCost = activePlayer:GetBuildingProductionNeeded( buildingID )
		if IsCiv5 then
			-- player extra happiness
			happinessChange = happinessChange + activePlayer:GetExtraBuildingHappinessFromPolicies( buildingID )
			if not IsCiv5Vanilla then
				happinessChange = happinessChange + activePlayer:GetPlayerBuildingClassHappiness( buildingClassID )
			end
		else
			-- get the active perk types
			activePerkTypes = activePlayer:GetAllActivePlayerPerkTypes()
		end
	end

	if city and not IsCiv5Vanilla and buildingClassID then
		happinessChange = happinessChange + city:GetReligionBuildingClassHappiness(buildingClassID)
	end

	-- Name
	tips = { BuildingColor( Locale_ToUpper( building._Name or "???" ) ) }

	-- Other tags
	InsertTags( building, tips, building_keys, building_foreign_keys )

--local function GetBuildingYields( buildingID, buildingType, buildingClassID, activePlayer )
	-- Yields
	local thisBuildingAndYieldTypes = { BuildingType = buildingType }
	for yield in GameInfo.Yields() do
		yieldID = yield.ID
		yieldChange = 0
		yieldModifier = 0
		thisBuildingAndYieldTypes.YieldType = yield.Type

		if Game and buildingClassID and yieldID < YieldTypes.NUM_YIELD_TYPES then -- weed out strange Communitas yields
			yieldChange = Game.GetBuildingYieldChange( buildingID, yieldID )
			yieldModifier = Game.GetBuildingYieldModifier( buildingID, yieldID )
			if activePlayer then
				if not IsCiv5Vanilla then
					yieldChange = yieldChange + activePlayer:GetPlayerBuildingClassYieldChange( buildingClassID, yieldID )
								+ activePlayer:GetPolicyBuildingClassYieldChange( buildingClassID, yieldID )
				end
				yieldModifier = yieldModifier + activePlayer:GetPolicyBuildingClassYieldModifier( buildingClassID, yieldID )
				for i=1, #activePerkTypes do
					yieldChange = yieldChange + Game.GetPlayerPerkBuildingClassFlatYieldChange( activePerkTypes[i], buildingClassID, yieldID )
					yieldModifier = yieldModifier + Game.GetPlayerPerkBuildingClassPercentYieldChange( activePerkTypes[i], buildingClassID, yieldID )
				end
			end
			if city and not IsCiv5Vanilla then
				yieldChange = yieldChange + city:GetReligionBuildingClassYieldChange( buildingClassID, yieldID )
				if IsCiv5BNW then
					yieldChange = yieldChange + city:GetLeagueBuildingClassYieldChange( buildingClassID, yieldID )
				end
			end
		else -- not Game
			for row in GameInfo.Building_YieldChanges( thisBuildingAndYieldTypes ) do
				yieldChange = yieldChange + (row.Yield or 0)
			end
			for row in GameInfo.Building_YieldModifiers( thisBuildingAndYieldTypes ) do
				yieldModifier = yieldModifier + (row.Yield or 0)
			end
		end
		if yield.Type == "YIELD_CULTURE" then -- works pregame, when GameInfoTypes is not available
			yieldChange = yieldChange + cultureChange
			yieldModifier = yieldModifier + cultureModifier
			cultureChange = 0
			cultureModifier = 0
		end
		yieldPerPop = 0
		for row in GameInfo.Building_YieldChangesPerPop( thisBuildingAndYieldTypes ) do
			yieldPerPop = yieldPerPop + (row.Yield or 0)
		end
		if yieldChange ~=0 then
			tip = format(" %+i%s", yieldChange, yield.IconString or "?" )
		else
			tip = ""
		end
		if yieldModifier ~=0 then
			tip = format("%s %+i%%%s", tip, yieldModifier, yield.IconString or "?" )
		end
		if yieldPerPop ~= 0 then
			tip = format("%s %+i%%[ICON_CITIZEN]%s", tip, yieldPerPop, yield.IconString or "?" )
		end
		if tip ~= "" then
			insert( tips, yield._Name .. ":" .. tip )
		end
	end
	-- Culture leftovers
	if cultureChange ~=0 then
		tip = format(" %+i[ICON_CULTURE]", cultureChange )
	else
		tip = ""
	end
	if cultureModifier ~=0 then
		tip = format("%s %+i%%[ICON_CULTURE]", tip, cultureModifier )
	end
	if tip ~= "" then
		insert( tips, L"TXT_KEY_PEDIA_CULTURE_LABEL" .. tip )
	end
	if IsCiv5 then
		-- Happiness:
		if happinessChange ~=0 then
			tip = format( " %+i[ICON_HAPPINESS_1]", happinessChange )
		else
			tip = ""
		end
		if (building.HappinessPerXPolicies or 0)~=0 then
			tip = format( "%s +1[ICON_HAPPINESS_1]/%i %s", tip, building.HappinessPerXPolicies, PolicyColor( L"TXT_KEY_VP_POLICIES" ) )
		end
		if tip ~= "" then
			insert( tips, L"TXT_KEY_PEDIA_HAPPINESS_LABEL" .. tip )
		end
	else
		-- Health
		local healthChange = (tonumber(building.Health) or 0) + (tonumber(building.UnmoddedHealth) or 0)
		local healthModifier = tonumber(building.HealthModifier) or 0
		if activePlayer then
			-- Health from Virtues
			healthChange = healthChange + activePlayer:GetExtraBuildingHealthFromPolicies( buildingID )
			-- Player Perks
			for i=1, #activePerkTypes do
				healthChange = healthChange + Game.GetPlayerPerkBuildingClassPercentHealthChange( activePerkTypes[i], buildingClassID )
				healthModifier = healthModifier + Game.GetPlayerPerkBuildingClassPercentHealthChange( activePerkTypes[i], buildingClassID )
				defenseChange = defenseChange + Game.GetPlayerPerkBuildingClassCityStrengthChange( activePerkTypes[i], buildingClassID )
				hitPointChange = hitPointChange + Game.GetPlayerPerkBuildingClassCityHPChange( activePerkTypes[i], buildingClassID )
				maintenanceCost = maintenanceCost + Game.GetPlayerPerkBuildingClassEnergyMaintenanceChange( activePerkTypes[i], buildingClassID )
			end
		end
		if healthChange ~=0 then
			tip = format(" %+i[ICON_HEALTH_1]", healthChange )
		else
			tip = ""
		end
		if healthModifier ~=0 then
			tip = format("%s %+i%%[ICON_HEALTH_1]", tip, healthModifier )
		end
		if tip~="" then
			insert( tips, L"TXT_KEY_HEALTH" .. ":" .. tip )
		end
	end

	-- Defense:
	if defenseChange ~=0 then
		tip = format(" %+g[ICON_STRENGTH]", defenseChange / 100 )
	else
		tip = ""
	end
	if hitPointChange ~=0 then
		tip = tip .. " " .. L( "TXT_KEY_PEDIA_DEFENSE_HITPOINTS", hitPointChange )
	end
	if tip~="" then
		insert( tips, L"TXT_KEY_PEDIA_DEFENSE_LABEL" .. tip )
	end
	-- Maintenance:
	if maintenanceCost ~= 0 then
		insert( tips, format( "%s %+i%s", L"TXT_KEY_PEDIA_MAINT_LABEL", -maintenanceCost, g_currencyIcon) )
	end

	-- Resources required:
	if Game then
		for resource in GameInfo.Resources() do
			item = Game.GetNumResourceRequiredForBuilding( buildingID, resource.ID )
			if item ~= 0 then
				insert( tips, ResourceQuantity( resource, -item ) )
			end
		end
	else
		for row in GameInfo.Building_ResourceQuantityRequirements( thisBuildingType ) do
			resource = GameInfo.Resources[ row.ResourceType ]
			if resource and (row.Cost or 0)~=0 then
				insert( tips, ResourceQuantity( resource, -row.Cost ) )
			end
		end
	end


	-- Specialists
	local specialistType = building.SpecialistType
	local specialist = GameInfo.Specialists[ specialistType ]
	if specialist then
		if ( building.GreatPeopleRateChange or 0 ) ~= 0 then
			insert( tips, format("%s %+i%s", L( specialist.GreatPeopleTitle ), building.GreatPeopleRateChange, GreatPeopleIcon( specialistType ) ) )
		end
		if (building.SpecialistCount or 0) ~= 0 then
			if IsCiv5 then
				local numSpecialistsInBuilding = city and city:GetNumSpecialistsInBuilding( buildingID ) or building.SpecialistCount
				if numSpecialistsInBuilding ~= building.SpecialistCount then
					numSpecialistsInBuilding = numSpecialistsInBuilding.."/"..building.SpecialistCount
				end
				insert( tips, L( "TXT_KEY_CITYVIEW_BUILDING_SPECIALIST_YIELD", numSpecialistsInBuilding, specialist.Description, GetSpecialistYields( city, specialist ) ) )
			else
				insert( tips, format( "%i[ICON_CITIZEN]%s /%s", building.SpecialistCount, UnitColor( specialist._Name ), GetSpecialistYields( city, specialist ) ) )
			end
		end
	end

	if IsCiv5BNW then
		-- Great Work Slots
		local greatWorkType = (building.GreatWorkCount or 0) > 0 and GameInfo.GreatWorkSlots[building.GreatWorkSlotType]
		if greatWorkType then
			insert( tips, L( greatWorkType.SlotsToolTipText, building.GreatWorkCount ) )
		end
		for row in GameInfo.Building_DomainFreeExperiencePerGreatWork( thisBuildingType ) do
			item = GameInfo.Domains[ row.DomainType ]
			if item and (row.Experience or 0)>0 then
				insert( tips, XPcolor(item._Name).." "..L( "TXT_KEY_EXPERIENCE_POPUP", row.Experience ).."/ "..L"TXT_KEY_VP_GREAT_WORKS" )
			end
		end
		-- Theming Bonus
-- TODO Building_ThemingBonuses
--		if building.ThemingBonusHelp then insert( tips, L( building.ThemingBonusHelp ) ) end
		-- Free Great Work
		local freeGreatWork = GameInfo.GreatWorks[ building.FreeGreatWork ]
-- TODO type rather than blurb
		if freeGreatWork then
			insert( tips, L"TXT_KEY_FREE" .." "..PolicyColor(freeGreatWork._Name) )
		end

-- TODO sacred sites properly
-- TODO Building_YieldChangesPerReligion
		tip = ""
		if (building.FaithCost or 0) > 0 and building.UnlockedByBelief and building.Cost == -1 then
			local tourism = city and city:GetFaithBuildingTourism() or 0
			if tourism ~= 0 then
				tip = format(" %+i[ICON_TOURISM]", tourism )
			end
		end
		if enhancedYieldTechName and (building.TechEnhancedTourism or 0) ~= 0 then
			tip = format("%s %s %+i[ICON_TOURISM]", tip, enhancedYieldTechName, building.TechEnhancedTourism )
		end
		if tip ~= "" then
			insert( tips, L"TXT_KEY_CITYVIEW_TOURISM_TEXT" .. ":" .. tip )
		end
	end
-- TODO GetInternationalTradeRouteYourBuildingBonus
	if not IsCiv5Vanilla then
		-- Resources
		for row in GameInfo.Building_ResourceQuantity( thisBuildingType ) do
			resource = GameInfo.Resources[ row.ResourceType ]
			if resource and (row.Quantity or 0)~=0 then
				insert( tips, ResourceQuantity( resource, -row.Quantity ) )
			end
		end
	end

	-- Resource Yields enhanced by Building
	for resource in GameInfo.Resources() do
		thisBuildingAndResourceTypes.ResourceType = resource.Type or -1
		tip = GetYieldString( GameInfo.Building_ResourceYieldChanges( thisBuildingAndResourceTypes ) )
		for row in GameInfo.Building_ResourceCultureChanges( thisBuildingAndResourceTypes ) do
			if (row.CultureChange or 0)~= 0 then
				tip = format("%s %+i[ICON_CULTURE]", tip, row.CultureChange )
			end
		end
		if g_isReligionEnabled then
			for row in GameInfo.Building_ResourceFaithChanges( thisBuildingAndResourceTypes ) do
				if (row.FaithChange or 0)~= 0 then
					tip = format("%s %+i[ICON_FAITH]", tip, row.FaithChange )
				end
			end
		end
-- TODO GameInfo.Building_ResourceYieldModifiers( thisBuildingType ), ResourceType, YieldType, Yield
		if tip ~= "" then
			insert( tips, ResourceString( resource ) .. ":" .. tip )
		end
	end

	-- Feature Yields enhanced by Building
	for feature in GameInfo.Features() do
		tip = GetYieldString( GameInfo.Building_FeatureYieldChanges{ BuildingType = buildingType, FeatureType = feature.Type } )
		if tip ~= "" then
			insert( tips, ResourceColor( feature._Name ) .. ":" .. tip )
		end
	end
	if not IsCiv5Vanilla then
		-- Terrain Yields enhanced by Building
		for terrain in GameInfo.Terrains() do
			tip = GetYieldString( GameInfo.Building_TerrainYieldChanges{ BuildingType = buildingType, TerrainType = terrain.Type } )
			if IsCivBE then
				local health = 0
				for row in GameInfo.Building_TerrainHealthChange{ BuildingType = buildingType, TerrainType = terrain.Type } do
					health = health + ( tonumber( row.Quantity ) or 0 )
				end
				if health ~= 0 then
					tip = format( "%s %+i[ICON_HEALTH_1]", tip, health )
				end
			end
			if tip ~= "" then
				insert( tips, ResourceColor( terrain._Name ) .. ":" .. tip )
			end
		end
	end
	-- Specialist Yields enhanced by Building
	for specialist in GameInfo.Specialists() do
		tip = GetYieldString( GameInfo.Building_SpecialistYieldChanges{ BuildingType = buildingType, SpecialistType = specialist.Type } )
		if tip ~= "" then
			insert( tips, UnitColor( specialist._Name ) .. ":" .. tip )
		end
	end

	-- River Yields enhanced by Building
	tip = GetYieldString( GameInfo.Building_RiverPlotYieldChanges( thisBuildingType ) )
	if tip ~= "" then
		insert( tips, L"TXT_KEY_PLOTROLL_RIVER" .. ":" .. tip )
	end

	-- Lake Yields enhanced by Building
	tip = GetYieldString( GameInfo.Building_LakePlotYieldChanges( thisBuildingType ) )
	if tip ~= "" then
		insert( tips, L"TXT_KEY_PLOTROLL_LAKE" .. ":" .. tip )
	end

	-- Ocean Yields enhanced by Building
	tip = GetYieldString( GameInfo.Building_SeaPlotYieldChanges( thisBuildingType ) )
	if tip ~= "" then
		insert( tips, L"TXT_KEY_PLOTROLL_OCEAN" .. ":" .. tip )
	end

	-- Ocean Resource Yields enhanced by Building
	tip = GetYieldString( GameInfo.Building_SeaResourceYieldChanges( thisBuildingType ) )
-- todo determine sea resources
	if tip ~= "" then
		insert( tips, L"TXT_KEY_PLOTROLL_OCEAN" .." "..L"TXT_KEY_TOPIC_RESOURCES".. ":" .. tip )
	end

	-- Area Yields enhanced by Building
	tip = GetCustomYieldString( "Yield", "%s %+i%%%s", GameInfo.Building_AreaYieldModifiers( thisBuildingType ) )
	if tip ~= "" then
		insert( tips, L"TXT_KEY_PGSCREEN_CONTINENTS" .. ":" .. tip )
	end
	-- Map Yields enhanced by Building
	tip = GetCustomYieldString( "Yield", "%s %+i%%%s", GameInfo.Building_GlobalYieldModifiers( thisBuildingType ) )
	if tip ~= "" then
		insert( tips, L"TXT_KEY_TOPIC_CITIES" .. ":" .. tip )
	end

	-- Victory requisite
	item = GameInfo.Victories[ building.VictoryPrereq ]
	if item then
		insert( tips, TextColor( "[COLOR_GREEN]", item._Name ) )
	end

	-- free building in this city
	item = GetCivBuilding( activeCivilizationType, building.FreeBuildingThisCity )
	if item then
		insert( tips, L"TXT_KEY_FREE".." "..BuildingColor( item._Name ) )
	end

	-- free building in all cities
	item = GetCivBuilding( activeCivilizationType, building.FreeBuilding )
	if item then
		insert( tips, L"TXT_KEY_FREE".." "..BuildingColor( item._Name ) )-- todo xml
	end

	-- free units
	for row in GameInfo.Building_FreeUnits( thisBuildingType ) do
		item = GameInfo.Units[ row.UnitType ]
		item = item and GetCivUnit( activeCivilizationType, item.Class )
		if item and (row.NumUnits or 0)>0 then
			insert( tips, L("{1: plural 2?{1} ;}{TXT_KEY_FREE} {2}", row.NumUnits, UnitColor( item._Name ) ) )
		end
	end
--Building_FreeSpecialistCounts unused ?
	-- free promotion to units trained in this city
	item = GameInfo.UnitPromotions[ building.TrainedFreePromotion ]
	if item then
		insert( tips, L"TXT_KEY_PEDIA_FREEPROMOTIONS_LABEL".." "..L( item.Help or "???" ) )
	end

	-- free promotion for all units
	item = GameInfo.UnitPromotions[ building.FreePromotion ]
	if item then
		insert( tips, L"TXT_KEY_PEDIA_FREEPROMOTIONS_LABEL".." "..L( item.Help or "???" ) )
	end

	-- Hurry modifiers
	for row in GameInfo.Building_HurryModifiers( thisBuildingType ) do
		item = GameInfo.HurryInfos[ row.HurryType ]
		if item and (row.HurryCostModifier or 0)~=0 then
			insert( tips, format( "%s %+i%%", TextColor( "[COLOR_GREEN]", item._Name ), row.HurryCostModifier ) )
		end
	end

	-- Unit production modifier
	for row in GameInfo.Building_UnitCombatProductionModifiers( thisBuildingType ) do
		item = GameInfo.UnitCombatInfos[ row.UnitCombatType ]
		if item and (row.Modifier or 0)~=0 then
			insert( tips, format( "%s %+i%%[ICON_PRODUCTION]", UnitColor( item._Name ), row.Modifier ) )
		end
	end
	for row in GameInfo.Building_DomainProductionModifiers( thisBuildingType ) do
		item = GameInfo.Domains[ row.DomainType ]
		if item and (row.Modifier or 0)~=0 then
			insert( tips, format( "%s %+i%%[ICON_PRODUCTION]", UnitColor( item._Name ), row.Modifier ) )
		end
	end

	-- free experience
	for row in GameInfo.Building_DomainFreeExperiences( thisBuildingType ) do
		item = GameInfo.Domains[ row.DomainType ]
		if item and (row.Experience or 0)~=0 then
			insert( tips, UnitColor( item._Name ).." "..L( "TXT_KEY_EXPERIENCE_POPUP", row.Experience ) )
		end
	end
	for row in GameInfo.Building_UnitCombatFreeExperiences( thisBuildingType ) do
		item = GameInfo.UnitCombatInfos[ row.UnitCombatType ]
		if item and (row.Experience or 0)>0 then
			insert( tips, UnitColor( item._Name ).." "..L( "TXT_KEY_EXPERIENCE_POPUP", row.Experience ) )
		end
	end

	-- Yields enhanced by Technology
	if techFilter( enhancedYieldTech ) then
		tip = GetYieldString( GameInfo.Building_TechEnhancedYieldChanges( thisBuildingType ) )
		if #tip > 0 then
			insert( tips, "[ICON_BULLET]" .. enhancedYieldTechName .. tip )
		end
	end

	items = {}
	-- Yields enhanced by Policy
	for row in GameInfo.Policy_BuildingClassYieldChanges( thisBuildingClassType ) do
		if row.PolicyType and (row.YieldChange or 0)~=0 then
			items[row.PolicyType] = format( "%s %+i%s", items[row.PolicyType] or "", row.YieldChange, YieldIcons[row.YieldType] or "?" )
		end
	end
	for row in GameInfo.Policy_BuildingClassCultureChanges( thisBuildingClassType ) do
		if row.PolicyType and (row.CultureChange or 0)~=0 then
			items[row.PolicyType] = format( "%s %+i[ICON_CULTURE]", items[row.PolicyType] or "", row.CultureChange )
		end
	end
	-- Yield modifiers enhanced by Policy
	for row in GameInfo.Policy_BuildingClassYieldModifiers( thisBuildingClassType ) do
		if row.PolicyType and (row.YieldMod or 0)~=0 then
			items[row.PolicyType] = format( "%s %+i%%%s", items[row.PolicyType] or "", row.YieldMod, YieldIcons[row.YieldType] or "?" )
		end
	end
	if IsCiv5 then
		if IsCiv5BNW then
			for row in GameInfo.Policy_BuildingClassTourismModifiers( thisBuildingClassType ) do
				if row.PolicyType and (row.TourismModifier or 0)~=0 then
					items[row.PolicyType] = format( "%s %+i%%[ICON_TOURISM]", items[row.PolicyType] or "", row.TourismModifier )
				end
			end
		end
		for row in GameInfo.Policy_BuildingClassHappiness( thisBuildingClassType ) do
			if row.PolicyType and (row.Happiness or 0)~=0 then
				items[row.PolicyType] = format( "%s %+i[ICON_HAPPINESS_1]", items[row.PolicyType] or "", row.Happiness )
			end
		end
		local lastTip -- universal healthcare kludge
		for policyType, tip in pairs( items ) do
			local policy = GameInfo.Policies[ policyType ]
			if policyFilter( policy ) and #tip > 0 then
				tip = "[ICON_BULLET]" .. PolicyColor( policy._Name ) .. tip
				if tip~=lastTip then
					insert( tips, tip )
				end
				lastTip = tip
			end
		end

		if not IsCiv5Vanilla then
			-- Yields enhanced by Beliefs
			items = {}
			for row in GameInfo.Belief_BuildingClassYieldChanges( thisBuildingClassType ) do
				if row.BeliefType and (row.YieldChange or 0)~=0 then
					items[row.BeliefType] = format( "%s %+i%s", items[row.BeliefType] or "", row.YieldChange, YieldIcons[row.YieldType] or "?" )
				end
			end
			if maxGlobalInstances > 0 then -- world wonder
				for row in GameInfo.Belief_YieldChangeWorldWonder() do
					if row.BeliefType and (row.Yield or 0)~=0 then
						items[row.BeliefType] = format( "%s %+i%s", items[row.BeliefType] or "", row.Yield, YieldIcons[row.YieldType] or "?" )
					end
				end
			end
			if IsCiv5BNW then
				for row in GameInfo.Belief_BuildingClassTourism( thisBuildingClassType ) do
					if row.BeliefType and (row.Tourism or 0)~=0 then
						items[row.BeliefType] = format( "%s %+i[ICON_TOURISM]", items[row.BeliefType] or "", row.Tourism )
					end
				end
			end
			for row in GameInfo.Belief_BuildingClassHappiness( thisBuildingClassType ) do
				if row.BeliefType and (row.Happiness or 0)~=0 then
					items[row.BeliefType] = format( "%s %+i[ICON_HAPPINESS_1]", items[row.BeliefType] or "", row.Happiness )
				end
			end
			for beliefType, tip in pairs( items ) do
				local belief = GameInfo.Beliefs[beliefType]
				if beliefFilter( belief ) and #tip > 0 then
					insert( tips, "[ICON_BULLET]" .. BeliefColor( belief._Name ) .. tip )
				end
			end

			-- Other Building Yields enhanced by this Building
			local buildingClassTypes = {}
			for row in GameInfo.Building_BuildingClassYieldChanges( thisBuildingType ) do
				SetKey( buildingClassTypes, row.BuildingClassType )
			end
			if IsCiv5 then
				for row in GameInfo.Building_BuildingClassHappiness( thisBuildingType ) do
					SetKey( buildingClassTypes, row.BuildingClassType )
				end
			end
			local condition = { BuildingType = buildingType }
			for buildingClassType in pairs( buildingClassTypes ) do
				condition.BuildingClassType = buildingClassType
				tip = GetCustomYieldString( "YieldChange", "%s %+i%s", GameInfo.Building_BuildingClassYieldChanges( condition ) )
				if IsCiv5 then
					local happinessChange = 0
					for row in GameInfo.Building_BuildingClassHappiness( condition ) do
						happinessChange = happinessChange + (row.Happiness or 0)
					end
					if happinessChange ~= 0 then
						tip = format( "%s %+i[ICON_HAPPINESS_1]", tip, happinessChange )
					end
				end
				local enhancedBuilding = GetCivBuilding( activeCivilizationType, buildingClassType )
				if enhancedBuilding and #tip > 0 then
					insert( tips, "[ICON_BULLET]" ..L"TXT_KEY_SV_ICONS_ALL".." ".. BuildingColor( enhancedBuilding._Name ) .. tip )
				end
			end
		end
	else
		-- Orbital Production
		insertLocalizedIfNonZero( tips, "TXT_KEY_DOMAIN_PRODUCTION_MOD", building.OrbitalProductionModifier or 0, "TXT_KEY_ORBITAL_UNITS" )

		-- Orbital Coverage
		insertLocalizedIfNonZero( tips, "TXT_KEY_BUILDING_ORBITAL_COVERAGE", building.OrbitalCoverageChange or 0 )

		-- Anti-Orbital Strike
		insertLocalizedIfNonZero( tips, "TXT_KEY_UNITPERK_RANGE_AGAINST_ORBITAL_CHANGE", building.OrbitalStrikeRangeChange or 0 )

		-- Covert Ops Intrigue Cap
		insertLocalizedIfNonZero( tips, "TXT_KEY_BUILDING_CITY_INTRIGUE_CAP", -(building.IntrigueCapChange or 0) * (GameDefines.MAX_CITY_INTRIGUE_LEVELS or 0) / 100 )
	end

	insert( tips, "----------------" )

	-- Cost:
	local costTip
	-- League project
	if IsCiv5BNW and building.UnlockedByLeague then
		if Game
			and Game.GetNumActiveLeagues() > 0
			and Game.GetActiveLeague()
		then
			costTip = L( "TXT_KEY_LEAGUE_PROJECT_COST_PER_PLAYER",
				Game.GetActiveLeague():GetProjectBuildingCostPerPlayer( buildingID ) )
		else
			local leagueProjectReward = GameInfo.LeagueProjectRewards{ Building = buildingType }()
			local leagueProject = leagueProjectReward and GameInfo.LeagueProjects{ RewardTier3 = leagueProjectReward.Type }()
			local costPerPlayer = leagueProject and leagueProject.CostPerPlayer	-- * GameInfo.GameSpeeds[ PreGame.GetGameSpeed() ].ConstructPercent * GameInfo.Eras[ PreGame.GetEra() ].ConstructPercent / 100000	-- GameInfo.Eras[ player:GetCurrentEra() ]
			if costPerPlayer then
				costTip = L( "TXT_KEY_LEAGUE_PROJECT_COST_PER_PLAYER", costPerPlayer )
			end
		end
	-- Production
	else
		if productionCost > 1 then
			costTip = productionCost .. "[ICON_PRODUCTION]"
			local goldCost = 0
			if city then
				goldCost = city:GetBuildingPurchaseCost( buildingID )

			elseif building.HurryCostModifier and building.HurryCostModifier >= 0 then
				goldCost = (productionCost * GameDefines.GOLD_PURCHASE_GOLD_PER_PRODUCTION ) ^ GameDefines.HURRY_GOLD_PRODUCTION_EXPONENT
				goldCost = (building.HurryCostModifier + 100) * goldCost / 100
				goldCost = goldCost - ( goldCost % GameDefines.GOLD_PURCHASE_VISIBLE_DIVISOR )
			end
			if goldCost > 0 then
				if costTip then
					costTip = costTip .. ("(%i%%)"):format(productionCost*100/goldCost)
					if IsCiv5Vanilla then
						costTip = costTip .. " / " .. goldCost .. g_currencyIcon
					else
						costTip = L( "TXT_KEY_PEDIA_A_OR_B", costTip, goldCost .. g_currencyIcon )
					end
				else
					costTip = goldCost .. g_currencyIcon
				end
			end
		end
		-- Faith
		if g_isReligionEnabled then
			local faithCost = 0
			if city then
				faithCost = city:GetBuildingFaithPurchaseCost( buildingID, true )
			else
				faithCost = building.FaithCost or 0
			end
			if faithCost > 0 then
				if costTip then
					costTip = L( "TXT_KEY_PEDIA_A_OR_B", costTip, faithCost .. "[ICON_PEACE]" )
				else
					costTip = faithCost .. "[ICON_PEACE]"
				end
			end
		end
	end
	insert( tips, L"TXT_KEY_PEDIA_COST_LABEL" .. " " .. ( costTip or L"TXT_KEY_FREE" ) )

	-- Production Modifiers
	for row in GameInfo.Policy_BuildingClassProductionModifiers( thisBuildingClassType ) do
		local policy = GameInfo.Policies[ row.PolicyType ]
		if policyFilter( policy ) and (row.ProductionModifier or 0)~=0 then
			insert( tips, format( "[ICON_BULLET]%s +%i%%[ICON_PRODUCTION]", PolicyColor( policy._Name ), row.ProductionModifier ) )
		end
	end


	if IsCivBE then
		-- Affinity Level Requirement
		for affinityPrereq in GameInfo.Building_AffinityPrereqs( thisBuildingType ) do
			local affinityInfo = (tonumber( affinityPrereq.Level) or 0 ) > 0 and GameInfo.Affinity_Types[ affinityPrereq.AffinityType ]
			if affinityInfo then
				insert( tips, L( "TXT_KEY_AFFINITY_LEVEL_REQUIRED", affinityInfo.ColorType, affinityPrereq.Level, affinityInfo.IconString or "?", affinityInfo._Name or "???" ) )
			end
		end
	end

	-- Civilization:
	local civs = {}
	local t
	for row in GameInfo.Civilization_BuildingClassOverrides( thisBuildingType ) do
		t = GameInfo.Civilizations[ row.CivilizationType ]
		if t then
			insert( civs, t._Name )
		end
	end
	if #civs > 0 then
		insert( tips, L"TXT_KEY_PEDIA_CIVILIZATIONS_LABEL" .. " " .. concat( civs, ", ") )
	end

	-- Replaces:
	item = buildingClass and GameInfo.Buildings[ buildingClass.DefaultBuilding ]
	if item and item ~= building then
		insert( tips, L"TXT_KEY_PEDIA_REPLACES_LABEL".." "..BuildingColor( item._Name ) ) --!!! row
	end

--[[
	-- Required Social Policy:
	item = GameInfo.PolicyBranchTypes[ building.PolicyBranchType ]
	if item then
		insert( tips, L( "TXT_KEY_EUI_REQUIRES", PolicyColor( item._Name ) ) )
	end
--]]
	-- Prerequisite Techs:
	local techs = {}
	item = GameInfo.Technologies[ building.PrereqTech ]
	if item and item.ID > 0 then
		insert( techs, TechColor( item._Name ) )
	end
	for row in GameInfo.Building_TechAndPrereqs( thisBuildingType ) do
		item = GameInfo.Technologies[ row.TechType ]
		if item and item.ID > 0 then
			insert( techs, TechColor( item._Name ) )
		end
	end
	if #techs > 0 then
		insert( tips, L( "TXT_KEY_EUI_REQUIRES", concat( techs, ", " ) ) )
	end

	-- Required Buildings:
	local buildings = {}
	for row in GameInfo.Building_PrereqBuildingClasses( thisBuildingType ) do
		local item = GetCivBuilding( activeCivilizationType, row.BuildingClassType )
		if item then
			insert( tips, L( "TXT_KEY_EUI_REQUIRES", BuildingColor( item._Name ).." ("..((row.NumBuildingNeeded or -1)==-1 and L"TXT_KEY_SV_ICONS_ALL" or row.NumBuildingNeeded)..")" ) )
			buildings[ item ] = true
		end
	end
	for row in GameInfo.Building_ClassesNeededInCity( thisBuildingType ) do
		local item = GetCivBuilding( activeCivilizationType, row.BuildingClassType )
		if item and not buildings[ item ] then
			insert( buildings, BuildingColor( item._Name ) )
		end
	end
	items = {}
	if (building.MutuallyExclusiveGroup or -1) >= 0 then
		for row in GameInfo.Buildings{ MutuallyExclusiveGroup = building.MutuallyExclusiveGroup } do
			SetKey( items, row.BuildingClass ~= buildingClassType and row.BuildingClass )
		end
	end
	for buildingClassType in pairs( items ) do
		local item = GetCivBuilding( activeCivilizationType, buildingClassType )
		if item then
			insert( buildings, TextColor( "[COLOR_RED]", item._Name ) )
		end
	end
	if #buildings > 0 then
		insert( tips, L( "TXT_KEY_EUI_REQUIRES", concat( buildings, ", ") ) )
	end

	-- Local Resources Required:
	local resources = {}
	for row in GameInfo.Building_LocalResourceAnds( thisBuildingType ) do
		resource = GameInfo.Resources[ row.ResourceType ]
		if resource then
			insert( resources, ResourceString( resource ) ) -- resource.IconString
		end
	end
	if #resources > 0 then
		resources = { concat( resources, ", ") }
	end
	for row in GameInfo.Building_LocalResourceOrs( thisBuildingType ) do
		resource = GameInfo.Resources[ row.ResourceType ]
		if resource then
			insert( resources, ResourceString( resource ) ) -- resource.IconString
		end
	end
	if IsCiv5Vanilla then
		resources = concat( resources, " / ")
	else
		local txt = resources[1] or ""
		for i = 2, #resources do
			txt = L( "TXT_KEY_PEDIA_A_OR_B", txt, resources[i] )
		end
		resources = txt
	end
	if #resources > 0 then
		insert( tips, L"TXT_KEY_PEDIA_LOCAL_RESRC_LABEL" .. " " .. resources )
	end

	local terrains = {}
	if building.Water then
		insert( terrains, L"TXT_KEY_TERRAIN_COAST" )
	end
	if building.River then
		insert( terrains, L"TXT_KEY_PLOTROLL_RIVER" )
	end
	if building.FreshWater then
		insert( terrains, L"TXT_KEY_ABLTY_FRESH_WATER_STRING" )
	end
	if building.Mountain then
		insert( terrains, L"TXT_KEY_TERRAIN_MOUNTAIN" .. "[ICON_RANGE_STRENGTH]1" )
	end
	if building.NearbyMountainRequired then
		insert( terrains, L"TXT_KEY_TERRAIN_MOUNTAIN" .. "[ICON_RANGE_STRENGTH]2" )
	end
	if building.Hill then
		insert( terrains, L"TXT_KEY_TERRAIN_HILL" )
	end
	if building.Flat then
		insert( terrains, L"TXT_KEY_MAP_OPTION_FLAT" )
	end
	-- mandatory terrain
	local terrain = GameInfo.Terrains[ building.NearbyTerrainRequired ]
	if terrain then
		insert( terrains, ResourceColor( terrain._Name ) .. "[ICON_RANGE_STRENGTH]1" )
	end
	-- prohibited terrain
	terrain = GameInfo.Terrains[ building.ProhibitedCityTerrain ]
	if terrain then
		insert( terrains, TextColor( "[COLOR_RED]", terrain._Name ) )
	end

	if #terrains > 0 then
		insert( tips, L"TXT_KEY_PEDIA_TERRAIN_LABEL"..": "..concat( terrains, ", ") )
	end
--[[
	-- Becomes Obsolete with:
	item = GameInfo.Technologies[ building.ObsoleteTech ]
	if item then
		insert( tips, L"TXT_KEY_PEDIA_OBSOLETE_TECH_LABEL" .. " " .. TechColor( item._Name ) )
	end
--]]
	-- Buildings Unlocked:
	local buildingsUnlocked = {}
	for row in GameInfo.Building_ClassesNeededInCity( thisBuildingClassType ) do
		local buildingUnlocked = GameInfo.Buildings[ row.BuildingType ]
		SetKey( buildingsUnlocked, buildingUnlocked and buildingUnlocked.BuildingClass )
	end
	items = {}
	for buildingUnlocked in pairs(buildingsUnlocked) do
		buildingUnlocked = GetCivBuilding( activeCivilizationType, buildingUnlocked )
		if buildingUnlocked then
			insert( items, BuildingColor( buildingUnlocked._Name ) )
		end
	end
	if #items > 0 then
		insert( tips, L"TXT_KEY_PEDIA_BLDG_UNLOCK_LABEL" .. " " .. concat( items, ", ") )
	end

	-- Limited number can be built
	local function InsertBuiltLimit( count, text, id, activeTeamID )
		if (count or 0) > 0 then
			if activePlayer then
				for playerID = id or 0, id or (GameDefines.MAX_CIV_PLAYERS - 1) do -- GameDefines.MAX_CIV_PLAYERS because city state may have captured wonder city
					local player = Players[playerID]
					if player and player:IsAlive() and (not activeTeamID or player:GetTeam() == activeTeamID) then
						for city in player:Cities() do
							local n = city:GetNumBuilding( buildingID )
							if n > 0 then
								count = count - n
								local builderID = city:GetBuildingOriginalOwner( buildingID )
								local buildTime = city:GetBuildingOriginalTime( buildingID )
								local builder = Players[ builderID ] or player
								insert( tips, (playerID == activePlayerID and "[COLOR_POSITIVE_TEXT]" or "[COLOR_WARNING_TEXT]")..L( "TXT_KEY_EUI_WONDER_BUILT_BY", builderID == activePlayerID and "TXT_KEY_YOU" or (activeTeam:IsHasMet(builder:GetTeam()) and builder:GetName()) or "TXT_KEY_UNMET_PLAYER", city:Plot():IsRevealed( activeTeamID ) and city:GetName() or "TXT_KEY_EUI_UNKNOWN_CITY", buildTime < 0 and L("TXT_KEY_TIME_BC", -buildTime) or L("TXT_KEY_TIME_AD", buildTime) ).."[ENDCOLOR]" )
							end
							if count < 1 then return true end
						end
					end
				end
			end
			if id == false and Game and Game.GetBuildingClassCreatedCount( buildingClassID ) >= maxGlobalInstances then
				insert( tips, "[COLOR_WARNING_TEXT]"..L"TXT_KEY_RAZED_CITY".."[ENDCOLOR]" )
			else
				append( tips, L( text, count ) )
			end
			return true
		end
	end
	if not ( InsertBuiltLimit( maxGlobalInstances, "TXT_KEY_NO_ACTION_GAME_COUNT_MAX", false )
		or InsertBuiltLimit( buildingClass.MaxTeamInstances, "TXT_KEY_NO_ACTION_TEAM_COUNT_MAX", nil, activeTeamID )
		or InsertBuiltLimit( buildingClass.MaxPlayerInstances, "TXT_KEY_NO_ACTION_PLAYER_COUNT_MAX", activePlayerID ) )
		and activePlayer
	then
		insert( tips, L( "TXT_KEY_EUI_BUILT_IN_X_CITIES", activePlayer:GetBuildingClassCount( buildingClassID ), activePlayer:GetBuildingClassMaking( buildingClassID ), activePlayer:GetNumCities() ) )
	end
	-- Pre-written Help text
	return AddPreWrittenHelpTextAndConcat( tips, building )
end

-------------------------------------------------
-- Help text for Improvements
-------------------------------------------------
function GetHelpTextForImprovement( improvementID )
	local improvement = GameInfo.Improvements[ improvementID ]

	local thisImprovementType = { ImprovementType = improvement.Type or -1 }
	local ItemBuild = GameInfo.Builds( thisImprovementType )()
	local tip, items, item, condition

	-- Name
	local tips = { Locale_ToUpper( TextColor( "[COLOR_GREEN]", improvement._Name ) ) }

	-- Maintenance:
	if (improvement[g_maintenanceCurrency] or 0) ~= 0 then
		insert( tips, format( "%s %+i%s", L"TXT_KEY_PEDIA_MAINT_LABEL", -improvement[g_maintenanceCurrency], g_currencyIcon) )
	end

	-- Improved Resources
	items = {}
	for row in GameInfo.Improvement_ResourceTypes( thisImprovementType ) do
		item = GameInfo.Resources[ row.ResourceType ]
		if item then
			insert( items, ResourceString( item ) ) -- item.IconString
		end
	end
	if #items > 0  then
		insert( tips, L"TXT_KEY_PEDIA_IMPROVES_RESRC_LABEL" .. " " .. concat( items, ", " ) )
	end

	-- Yields
	items = {}
	for row in GameInfo.Improvement_Yields( thisImprovementType ) do
		SetKey( items, (row.Yield or 0)~=0 and row.YieldType, format("%s %+i%s", items[ row.YieldType ] or "", row.Yield, YieldIcons[ row.YieldType ] or "?" ) )
	end
	for row in GameInfo.Improvement_FreshWaterYields( thisImprovementType ) do
		SetKey( items, (row.Yield or 0)~=0 and row.YieldType, format( "%s %s %+i%s", items[ row.YieldType ] or "", L"TXT_KEY_ABLTY_FRESH_WATER_STRING", row.Yield, YieldIcons[ row.YieldType ] or "?" ) )
	end
	if IsCiv5BNW then  -- or CivBE ?
		for row in GameInfo.Improvement_YieldPerEra( thisImprovementType ) do
			SetKey( items, (row.Yield or 0)~=0 and row.YieldType, format( "%s %+i%s/%s", items[ row.YieldType ] or "", row.Yield, YieldIcons[ row.YieldType ] or "?", L"TXT_KEY_AD_SETUP_GAME_ERA" ) )
		end
	end
	for yieldType, tip in pairs( items ) do
		item = GameInfo.Yields[ yieldType ]
		if item then
			insert( tips, item._Name .. ":" ..  tip )
		end
	end

	-- Culture
	if (improvement.Culture or 0)~=0 then
		insert( tips, format( "%s: %+i[ICON_CULTURE]", L"TXT_KEY_CITYVIEW_CULTURE_TEXT", improvement.Culture ) )
	end

	-- Mountain Bonus
	tip = GetYieldString( GameInfo.Improvement_AdjacentMountainYieldChanges( thisImprovementType ) )
	if #tip>0 then
		insert( tips, L"TXT_KEY_PEDIA_MOUNTAINADJYIELD_LABEL" .. tip )
	end
	-- Defense Modifier
	if (improvement.DefenseModifier or 0)~=0 then
		insert( tips, format( "%s %+i%%[ICON_STRENGTH]", L"TXT_KEY_PEDIA_DEFENSE_LABEL", improvement.DefenseModifier ) )
	end

	-- Tech yield changes
	items = {}
	condition = { ImprovementType = improvement.Type }
	for row in GameInfo.Improvement_TechYieldChanges( thisImprovementType ) do
		SetKey( items, row.TechType )
	end
	for techType in pairs( items ) do
		item = GameInfo.Technologies[ techType ]
		if item then
			condition.TechType = techType
			tip = GetYieldString( GameInfo.Improvement_TechYieldChanges( condition ) )
			if tip~="" then
				insert( tips, "[ICON_BULLET]" .. TechColor( item._Name ) .. tip )
			end
		end
	end
	items = {}
	for row in GameInfo.Improvement_TechFreshWaterYieldChanges( thisImprovementType ) do
		SetKey( items, row.TechType )
	end
	for techType in pairs( items ) do
		item = GameInfo.Technologies[ techType ]
		if item then
			condition.TechType = techType
			tip = GetYieldString( GameInfo.Improvement_TechFreshWaterYieldChanges( condition ) )
			if tip~="" then
				insert( tips, "[ICON_BULLET]" .. TechColor( item._Name ) .. " (" .. L"TXT_KEY_ABLTY_FRESH_WATER_STRING" .. ")" .. tip )
			end
		end
	end
	items = {}
	for row in GameInfo.Improvement_TechNoFreshWaterYieldChanges( thisImprovementType ) do
		SetKey( items, row.TechType )
	end
	for techType in pairs( items ) do
		item = GameInfo.Technologies[ techType ]
		if item then
			condition.TechType = techType
			tip = GetYieldString( GameInfo.Improvement_TechNoFreshWaterYieldChanges( condition ) )
			if tip~="" then
				insert( tips, "[ICON_BULLET]" .. TechColor( item._Name ) .. " (" .. L"TXT_KEY_ABLTY_NO_FRESH_WATER_STRING" .. ")" .. tip )
			end
		end
	end

	-- Policy yield changes
	items = {}
	condition = { ImprovementType = improvement.Type }
	for row in GameInfo.Policy_ImprovementYieldChanges( thisImprovementType ) do
		SetKey( items, row.PolicyType )
	end
	for row in GameInfo.Policy_ImprovementCultureChanges( thisImprovementType ) do
		SetKey( items, row.PolicyType )
	end
	for policyType in pairs( items ) do
		item = GameInfo.Policies[ policyType ]
		if item then
			tip = ""
			condition.PolicyType = policyType
			tip = GetYieldString( GameInfo.Policy_ImprovementYieldChanges( condition ) )
			for row in GameInfo.Policy_ImprovementCultureChanges( condition ) do
				if (row.CultureChange or 0)~=0 then
					tip = format( "%s %+i[ICON_CULTURE]", tip, row.CultureChange )
				end
			end
			if tip~="" then
				insert( tips, "[ICON_BULLET]" .. PolicyColor( item._Name ) .. tip )
			end
		end
	end

	-- Belief yield changes
	if g_isReligionEnabled then
		items = {}
		condition = { ImprovementType = improvement.Type }
		for row in GameInfo.Belief_ImprovementYieldChanges( thisImprovementType ) do
			SetKey( items, row.BeliefType )
		end
		for beliefType in pairs( items ) do
			item = GameInfo.Beliefs[ beliefType ]
			if item then
				condition.BeliefType = beliefType
				tip = GetYieldString( GameInfo.Belief_ImprovementYieldChanges( condition ) )
				if tip~="" then
					insert( tips, "[ICON_BULLET]" .. BeliefColor( item._Name ) .. tip )
				end
			end
		end

	end

	-- Resource Yields
	local thisImprovementAndResourceTypes = { ImprovementType = improvement.Type or -1 }
	for resource in GameInfo.Resources() do
		thisImprovementAndResourceTypes.ResourceType = resource.Type or -1
		tip = GetYieldString( GameInfo.Improvement_ResourceType_Yields( thisImprovementAndResourceTypes ) )
		if #tip > 0 then
			insert( tips, ResourceString( resource ) .. ":" .. tip )
		end
	end

	insert( tips, "----------------" )

	-- Civ Requirement
	if improvement.SpecificCivRequired then
		item = GameInfo.Civilizations[ improvement.CivilizationType ]
		insert( tips, L"TXT_KEY_PEDIA_CIVILIZATIONS_LABEL".." "..(item and item._Name or "???") )
	end

	-- Tech Requirements
	item = ItemBuild and GameInfo.Technologies[ ItemBuild.PrereqTech ]
	if item and item.ID > 0  then
		insert( tips, L( "TXT_KEY_EUI_REQUIRES", TechColor( item._Name ) ) )
	end

	-- Terrain
	items = {}
	for row in GameInfo.Improvement_ValidTerrains( thisImprovementType ) do
		item = GameInfo.Terrains[ row.TerrainType ]
		if item then
			insert( items, item._Name )
		end
	end
	for row in GameInfo.Improvement_ValidFeatures( thisImprovementType ) do
		item = GameInfo.Features[ row.FeatureType ]
		if item then
			insert( items, item._Name )
		end
	end
	if IsCiv5BNW then -- or CivBE ?
		for row in GameInfo.Improvement_ValidImprovements( thisImprovementType ) do
			item = GameInfo.Improvements[ row.PrereqImprovement ]
			if item then
				insert( items, item._Name )
			end
		end
	end
	for row in GameInfo.Improvement_ResourceTypes( thisImprovementType ) do
		item = GameInfo.Resources[ row.ResourceType ]
		if item and row.ResourceMakesValid then
			insert( items, ResourceString( item ) )
		end
	end
--	if improvement.HillsMakesValid then insert( items, (GameInfo.Terrains.TERRAIN_HILL or {})._Name ) end -- hackery for hills
	if #items > 0  then
		insert( tips, L"TXT_KEY_PEDIA_FOUNDON_LABEL" .. " " .. concat( items, ", " ) )
	end

--[[
	-- Upgrade
	item = GameInfo.Improvements[ improvement.ImprovementUpgrade ]
-- TODO xml text
	if item then
		insert( tips, L"" .. " " .. item._Name )
	end
--]]
	-- Pre-written Help text
	return AddPreWrittenHelpTextAndConcat( tips, improvement )
end

-- ===========================================================================
-- Help text for Projects
-- ===========================================================================
function GetHelpTextForProject( projectID )
	local project = GameInfo.Projects[ projectID ]

	-- Name & Cost
	local productionCost = (Game and Players[Game.GetActivePlayer()]:GetProjectProductionNeeded(projectID)) or project.Cost
	local tips = { Locale_ToUpper( project._Name or "???" ), "----------------", L"TXT_KEY_PEDIA_COST_LABEL" .. " " .. productionCost .. "[ICON_PRODUCTION]" }

	if IsCivBE then
		-- Affinity Level Requirement
		for affinityPrereq in GameInfo.Project_AffinityPrereqs{ ProjectType = project.Type } do
			local affinityInfo = (tonumber( affinityPrereq.Level) or 0 ) > 0 and GameInfo.Affinity_Types[ affinityPrereq.AffinityType ]
			if affinityInfo then
				insert( tips, L( "TXT_KEY_AFFINITY_LEVEL_REQUIRED", affinityInfo.ColorType, affinityPrereq.Level, affinityInfo.IconString or "?", affinityInfo._Name or "???" ) )
			end
		end
	end

	-- Requirements?
	if project.Requirements then
		insert( tips, L( project.Requirements ) )
	end

	-- Pre-written Help text
	return AddPreWrittenHelpTextAndConcat( tips, project )
end

-- ===========================================================================
-- Help text for Processes
-- ===========================================================================
function GetHelpTextForProcess( processID )
	local process = GameInfo.Processes[ processID ]

	-- Name
	local tips = { Locale_ToUpper( process._Name or "???" ), "----------------" }
	for row in GameInfo.Process_ProductionYields{ ProcessType = process.Type } do
		local yield = GameInfo.Yields[ row.YieldType ]
		local percent = yield and tonumber( row.Yield ) or 0
		if percent == 0 then
		elseif IsCivBE then
			insert( tips, L( "TXT_KEY_PROCESS_GENERIC_HELP", percent, yield.IconString or "?", yield._Name or "???" ) )
		else
			insert( tips, format( "%s = %i%%([ICON_PRODUCTION])", yield.IconString, percent ) )
		end
	end
	-- League Project text
	local activeLeague = IsCiv5BNW and Game and not Game.IsOption("GAMEOPTION_NO_LEAGUES") and Game.GetActiveLeague()
	if activeLeague then
		for row in GameInfo.LeagueProjects{ Process = process.Type } do
			insert( tips, activeLeague:GetProjectDetails( row.ID, Game.GetActivePlayer() ) )
			insert( tips, "" )
			insert( tips, ( L( "TXT_KEY_LEAGUE_PROJECT_POPUP_TOTAL_COST", activeLeague:GetProjectCost(row.ID )/100 ):gsub("%. .*","."):gsub("。.*:","。") ) )
		end
	end

	-- Pre-written Help text
	return AddPreWrittenHelpTextAndConcat( tips, process )
end


if Game then
	include "ScratchDeal"
	local ScratchDeal = ScratchDeal
	local PushScratchDeal = PushScratchDeal
	local PopScratchDeal = PopScratchDeal

	if not GetCityStateStatusToolTip then
		include "CityStateStatusHelper"
	end
	local GetCityStateStatusToolTip = GetCityStateStatusToolTip
	GetCityStateStatus = function( minorPlayer, majorPlayerID )
		return GetCityStateStatusToolTip( majorPlayerID, minorPlayer:GetID(), true )
	end

	local g_dealDuration = Game.GetDealDuration()
	g_isScienceEnabled = not Game.IsOption(GameOptionTypes.GAMEOPTION_NO_SCIENCE)
	g_isPoliciesEnabled = not Game.IsOption(GameOptionTypes.GAMEOPTION_NO_POLICIES)
	--g_isHappinessEnabled = not Game.IsOption(GameOptionTypes.GAMEOPTION_NO_HAPPINESS)
	g_isReligionEnabled = not IsCiv5Vanilla and not Game.IsOption(GameOptionTypes.GAMEOPTION_NO_RELIGION)

	local function GetCivName( player )
		-- Met
		if Teams[Game.GetActiveTeam()]:IsHasMet(player:GetTeam()) then
			return player:GetCivilizationShortDescription()
		-- Not met
		else
			return L"TXT_KEY_UNMET_PLAYER"
		end
	end

	local function GetLeaderName( player )
		-- You
		if player:GetID() == Game.GetActivePlayer() then
			return L"TXT_KEY_YOU"
		-- Not met
		elseif not Teams[Game.GetActiveTeam()]:IsHasMet(player:GetTeam()) then
			return L"TXT_KEY_UNMET_PLAYER"
		-- Human
		elseif player:IsHuman() then -- Game.IsGameMultiPlayer()
			local n = player:GetNickName()
			if n and n ~= "" then
				return player:GetNickName()
			end
		end
		local n = PreGame.GetLeaderName(player:GetID())
		if n and n ~= "" then
			return L( n )
		else
			n = GameInfo.Leaders[ player:GetLeaderType() ]
			return n and n._Name or "???"
		end
	end

	-- ===========================================================================
	-- Tooltips for Yield & Similar (e.g. Culture)
	-- ===========================================================================

	-- Helper function to build yield tooltip string
	function GetYieldTooltip( city, yieldID, baseYield, totalYield, yieldIconString, strModifiersString )

		yieldIconString = yieldIconString or YieldIcons[yieldID] or "?"
		local tips = {}

		-- Base Yield from Terrain
		insertLocalizedBulletIfNonZero( tips, "TXT_KEY_YIELD_FROM_TERRAIN", city:GetBaseYieldRateFromTerrain( yieldID ), yieldIconString )

		-- Base Yield from Buildings
		insertLocalizedBulletIfNonZero( tips, "TXT_KEY_YIELD_FROM_BUILDINGS", city:GetBaseYieldRateFromBuildings( yieldID ), yieldIconString )

		-- Base Yield from Specialists
		insertLocalizedBulletIfNonZero( tips, "TXT_KEY_YIELD_FROM_SPECIALISTS", city:GetBaseYieldRateFromSpecialists( yieldID ), yieldIconString )

		-- Base Yield from Misc
		insertLocalizedBulletIfNonZero( tips, yieldID == YieldTypes.YIELD_SCIENCE and "TXT_KEY_YIELD_FROM_POP" or "TXT_KEY_YIELD_FROM_MISC", city:GetBaseYieldRateFromMisc( yieldID ), yieldIconString )

		-- Base Yield from Population
		insertLocalizedBulletIfNonZero( tips, "TXT_KEY_YIELD_FROM_POP_EXTRA", city:GetYieldPerPopTimes100( yieldID ) * city:GetPopulation() / 100, yieldIconString )

		-- Base Yield from Religion
		if not IsCiv5Vanilla then
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_YIELD_FROM_RELIGION", city:GetBaseYieldRateFromReligion( yieldID ), yieldIconString )
		end

		if IsCivBE then
			-- Yield from Production Processes
			local yieldFromProcesses = city:GetYieldRateFromProductionProcesses( yieldID )
			if yieldFromProcesses ~= 0 then
				local processInfo = GameInfo.Processes[ city:GetProductionProcess() ]
				strModifiersString = strModifiersString .. "[NEWLINE][ICON_BULLET]" .. L( "TXT_KEY_SHORT_YIELD_FROM_SPECIFIC_OBJECT", yieldFromProcesses, yieldIconString, processInfo and processInfo._Name or "???" )
			end
			-- Base Yield from Loadout (colonists)
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_YIELD_FROM_LOADOUT", city:GetYieldPerTurnFromLoadout( yieldID ), yieldIconString )
		end

		-- Food eaten by pop
		if yieldID == YieldTypes.YIELD_FOOD then
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_FOOD_FROM_TRADE_ROUTES", city:GetYieldRate( yieldID, false ) - city:GetYieldRate( yieldID, true ) )
			strModifiersString = "[NEWLINE][ICON_BULLET]" .. L( "TXT_KEY_YIELD_EATEN_BY_POP", city:FoodConsumption( true, 0 ), yieldIconString ) .. strModifiersString
		elseif IsCivBE then
			local yieldFromTrade = city:GetYieldPerTurnFromTrade( yieldID )
			if yieldFromTrade ~= 0 then
				strModifiersString = strModifiersString .. "[NEWLINE][ICON_BULLET]" .. L( "TXT_KEY_YIELD_FROM_TRADE", yieldFromTrade, yieldIconString )
			end
		end

		-- Modifiers
		if strModifiersString ~= "" then
			insert( tips, "----------------" )
			insert( tips, L( "TXT_KEY_YIELD_BASE", baseYield, yieldIconString ) )
			insert( tips, strModifiersString )
		end
		-- Total
		insert( tips, "----------------" )
		insert( tips, L( totalYield >= 0 and "TXT_KEY_YIELD_TOTAL" or "TXT_KEY_YIELD_TOTAL_NEGATIVE", totalYield, yieldIconString ) )

		return concat( tips, "[NEWLINE]" )

	end
	local GetYieldTooltip = GetYieldTooltip

	-- Yield Tooltip Helper
	function GetYieldTooltipHelper( city, yieldID, yieldIconString )

		return GetYieldTooltip( city, yieldID, city:GetBaseYieldRate( yieldID ) + city:GetYieldPerPopTimes100( yieldID ) * city:GetPopulation() / 100, yieldID == YieldTypes.YIELD_FOOD and city:FoodDifferenceTimes100()/100 or city:GetYieldRateTimes100( yieldID )/100, yieldIconString, city:GetYieldModifierTooltip( yieldID ) )
	end
	local GetYieldTooltipHelper = GetYieldTooltipHelper

	-- FOOD
	function GetFoodTooltip( city )

		local tipText
		local isNoob = IsCivBE or not OptionsManager.IsNoBasicHelp()
		local cityPopulation = city:GetPopulation()

		local foodStoredTimes100 = city:GetFoodTimes100()
		local foodPerTurnTimes100 = city:FoodDifferenceTimes100( true )	-- true means size 1 city cannot starve
		local foodThreshold = city:GrowthThreshold()
		local turnsToCityGrowth = city:GetFoodTurnsLeft()

		if foodPerTurnTimes100 < 0 then
			foodThreshold = 0
			turnsToCityGrowth = floor( foodStoredTimes100 / -foodPerTurnTimes100 ) + 1
			tipText = "[COLOR_WARNING_TEXT]" .. cityPopulation - 1 .. "[ENDCOLOR][ICON_CITIZEN]"
			if isNoob then
				tipText = L"TXT_KEY_CITYVIEW_STARVATION_TEXT" .. "[NEWLINE]"
				.. L( "TXT_KEY_PROGRESS_TOWARDS", tipText )
			end
		elseif city:IsForcedAvoidGrowth() then
			tipText = "[ICON_LOCKED]".. cityPopulation .."[ICON_CITIZEN]"
			if isNoob then
				tipText = L"TXT_KEY_CITYVIEW_FOCUS_AVOID_GROWTH_TEXT" .. " " .. tipText
			end
			foodPerTurnTimes100 = 0
		elseif foodPerTurnTimes100 == 0 then
			tipText = "[COLOR_YELLOW]" .. cityPopulation .. "[ENDCOLOR][ICON_CITIZEN]"
			if isNoob then
				tipText = L( "TXT_KEY_PROGRESS_TOWARDS", tipText )
			end
		else
			tipText = "[COLOR_POSITIVE_TEXT]" .. cityPopulation +1 .. "[ENDCOLOR][ICON_CITIZEN]"
			if isNoob then
				tipText = L( "TXT_KEY_PROGRESS_TOWARDS", tipText )
			end
		end

		tipText = GetYieldTooltipHelper( city, YieldTypes.YIELD_FOOD ) .. "[NEWLINE][NEWLINE]" .. tipText .. "  " .. foodStoredTimes100 / 100 .. "[ICON_FOOD]/ " .. foodThreshold .. "[ICON_FOOD][NEWLINE]"

		if foodPerTurnTimes100 == 0 then

			tipText = tipText .. L"TXT_KEY_CITYVIEW_STAGNATION_TEXT"
		else
			local foodOverflowTimes100 = foodPerTurnTimes100 * turnsToCityGrowth + foodStoredTimes100 - foodThreshold * 100

			if turnsToCityGrowth > 1 then
				tipText = format( "%s%s %+g[ICON_FOOD]  ", tipText, L( "TXT_KEY_STR_TURNS", turnsToCityGrowth -1 ), ( foodOverflowTimes100 - foodPerTurnTimes100 ) / 100 )
			end
			tipText =  format( "%s%s%s[ENDCOLOR] %+g[ICON_FOOD]", tipText, foodPerTurnTimes100 < 0 and "[COLOR_WARNING_TEXT]" or "[COLOR_POSITIVE_TEXT]", Locale_ToUpper( L( "TXT_KEY_STR_TURNS", turnsToCityGrowth ) ), foodOverflowTimes100 / 100 )
		end

		if isNoob then
			return L"TXT_KEY_FOOD_HELP_INFO" .. "[NEWLINE][NEWLINE]" .. tipText
		else
			return tipText
		end
	end

	-- GOLD
	function GetGoldTooltip( city )

		if IsCiv5 and OptionsManager.IsNoBasicHelp() then
			return GetYieldTooltipHelper( city, YieldTypes.YIELD_GOLD )
		else
			return L"TXT_KEY_GOLD_HELP_INFO" .. "[NEWLINE][NEWLINE]" .. GetYieldTooltipHelper( city, YieldTypes.YIELD_GOLD )
		end
	end

	-- ENERGY
	function GetEnergyTooltip( city )

		return L"TXT_KEY_ENERGY_HELP_INFO" .. "[NEWLINE][NEWLINE]" .. GetYieldTooltipHelper( city, YieldTypes.YIELD_ENERGY )
	end

	-- SCIENCE
	function GetScienceTooltip( city )

		if g_isScienceEnabled then
			if IsCiv5 and OptionsManager.IsNoBasicHelp() then
				return GetYieldTooltipHelper( city, YieldTypes.YIELD_SCIENCE )
			else
				return L"TXT_KEY_SCIENCE_HELP_INFO" .. "[NEWLINE][NEWLINE]" .. GetYieldTooltipHelper( city, YieldTypes.YIELD_SCIENCE )
			end
		else
			return L"TXT_KEY_TOP_PANEL_SCIENCE_OFF_TOOLTIP"
		end
	end

	-- PRODUCTION
	function GetProductionTooltip( city )

		local isNoob = IsCivBE or not OptionsManager.IsNoBasicHelp()
		local cityProductionName = city:GetProductionNameKey()
		local tipText = ""
		local productionColor

		local productionPerTurn100 = city:GetCurrentProductionDifferenceTimes100( false, false )	-- food = false, overflow = false
		local productionStored100 = city:GetProductionTimes100() + city:GetCurrentProductionDifferenceTimes100(false, true) - productionPerTurn100
		local productionNeeded = 0
		local productionTurnsLeft = 1

		local unitProductionID = city:GetProductionUnit()
		local buildingProductionID = city:GetProductionBuilding()
		local projectProductionID = city:GetProductionProject()
		local processProductionID = city:GetProductionProcess()

		if unitProductionID ~= -1 then
	--		tipText = GetHelpTextForUnit( unitProductionID, false )
			productionColor = UnitColor

		elseif buildingProductionID ~= -1 then
	--		tipText = GetHelpTextForBuilding( buildingProductionID, true, true, true, city )
			productionColor = BuildingColor

		elseif projectProductionID ~= -1 then
	--		tipText = GetHelpTextForProject( projectProductionID, false )
			productionColor = BuildingColor

		elseif processProductionID ~= -1 then
			tipText = GetHelpTextForProcess( processProductionID, false )
		else
			if isNoob then
				tipText = L( "TXT_KEY_CITY_NOT_PRODUCING", city:GetName() )
			else
				tipText = L"TXT_KEY_PRODUCTION_NO_PRODUCTION"
			end
		end

		if productionColor then
			productionNeeded = city:GetProductionNeeded()
			productionTurnsLeft = city:GetProductionTurnsLeft()
			tipText = productionColor( Locale_ToUpper( cityProductionName ) )
			if isNoob then
				tipText = L( "TXT_KEY_PROGRESS_TOWARDS", tipText )
			end
			tipText = tipText .. "  " .. productionStored100 / 100 .. "[ICON_PRODUCTION]/ " .. productionNeeded .. "[ICON_PRODUCTION]"
			if productionPerTurn100 > 0 then

				tipText = tipText .. "[NEWLINE]"

				local productionOverflow100 = productionPerTurn100 * productionTurnsLeft + productionStored100 - productionNeeded * 100
				if productionTurnsLeft > 1 then
					tipText =  format( "%s%s %+g[ICON_PRODUCTION]  ", tipText, L( "TXT_KEY_STR_TURNS", productionTurnsLeft -1 ), ( productionOverflow100 - productionPerTurn100 ) / 100 )
				end
				tipText = format( "%s%s %+g[ICON_PRODUCTION]", tipText, productionColor( Locale_ToUpper( L( "TXT_KEY_STR_TURNS", productionTurnsLeft ) ) ), productionOverflow100 / 100 )
			end
		end
		local strModifiersString = city:GetYieldModifierTooltip( YieldTypes.YIELD_PRODUCTION )
		-- Extra Production from Food (ie. producing Colonists)
		if city:IsFoodProduction() then
			local productionFromFood = city:GetYieldRate( YieldTypes.YIELD_FOOD, false ) - city:FoodConsumption( true, 0 )
			if productionFromFood <= 0 then
				productionFromFood = 0
			elseif productionFromFood <= 2 then
				productionFromFood = productionFromFood * 100
			elseif productionFromFood <= 4 then
				productionFromFood = 200 + (productionFromFood - 2) * 50
			else
				productionFromFood = 300 + (productionFromFood - 4) * 25
			end
			if productionFromFood > 0 then
				strModifiersString = strModifiersString .. L( "TXT_KEY_PRODMOD_FOOD_CONVERSION", productionFromFood / 100 )
			end
		end
		tipText = GetYieldTooltip( city, YieldTypes.YIELD_PRODUCTION, city:GetBaseYieldRate( YieldTypes.YIELD_PRODUCTION ), productionPerTurn100 / 100, "[ICON_PRODUCTION]", strModifiersString ) .. "[NEWLINE][NEWLINE]" .. tipText

		-- Basic explanation of production
		if isNoob then
			return L"TXT_KEY_PRODUCTION_HELP_INFO" .. "[NEWLINE][NEWLINE]" .. tipText
		else
			return tipText
		end
	end

	-- HEALTH
	function GetHealthTooltip(city)

		local tips = { L"TXT_KEY_HEALTH_HELP_INFO", "", L"TXT_KEY_HEALTH_HELP_INFO_POP_CAP_WARNING", "" }
		
		-- base Health
		local localHealth = city:GetLocalHealth()
		local healthFromTerrain = city:GetHealthFromTerrain()
		local healthFromBuildings = city:GetHealthFromBuildings()	
		local baseLocalHealth = healthFromTerrain + healthFromBuildings
			
		insertLocalizedBulletIfNonZero( tips, "TXT_KEY_YIELD_FROM_BUILDINGS", healthFromBuildings, "[ICON_HEALTH_1]" )
		insertLocalizedBulletIfNonZero( tips, "TXT_KEY_YIELD_FROM_TERRAIN", healthFromTerrain, "[ICON_HEALTH_1]" )
		insert( tips, L( "TXT_KEY_YIELD_BASE", baseLocalHealth, "[ICON_HEALTH_1]" ) )
		insert( tips, "----------------" )

		-- health Modifier
		local healthModifier = city:GetTotalHealthModifier() - 100
		if healthModifier ~= 0 then
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_HEALTH_BUILDING_MOD_INFO", healthModifier )
			insert( tips, "----------------" )
		end

		-- total Health
		local tip = L( "TXT_KEY_YIELD_TOTAL", localHealth, localHealth < 0 and "[ICON_HEALTH_3]" or "[ICON_HEALTH_1]" )

		-- if local health is positive and our output is higher than the city's population, include the cap reminder
		if baseLocalHealth > localHealth then
			tip = tip .. L( "TXT_KEY_HEALTH_POP_CAPPED", city:GetPopulation() )
		end
		insert( tips, tip )
		return concat( tips, "[NEWLINE]" )
	end

	-- CULTURE
	function GetCultureTooltip( city )

		local tips = {}
		local cityOwner = Players[city:GetOwner()]
		local culturePerTurn, cultureStored, cultureNeeded, cultureFromBuildings, cultureFromPolicies, cultureFromSpecialists, cultureFromTraits, baseCulturePerTurn
		-- Thanks fo Firaxis Cleverness...
		if IsCiv5 then
			culturePerTurn = city:GetJONSCulturePerTurn()
			cultureStored = city:GetJONSCultureStored()
			cultureNeeded = city:GetJONSCultureThreshold()
			cultureFromBuildings = city:GetJONSCulturePerTurnFromBuildings()
			cultureFromPolicies = city:GetJONSCulturePerTurnFromPolicies()
			cultureFromSpecialists = city:GetJONSCulturePerTurnFromSpecialists()
			cultureFromTraits = city:GetJONSCulturePerTurnFromTraits()
			baseCulturePerTurn = city:GetBaseJONSCulturePerTurn()
		else
			culturePerTurn = city:GetCulturePerTurn()
			cultureStored = city:GetCultureStored()
			cultureNeeded = city:GetCultureThreshold()
			cultureFromBuildings = city:GetCulturePerTurnFromBuildings()
			cultureFromPolicies = city:GetCulturePerTurnFromPolicies()
			cultureFromSpecialists = city:GetCulturePerTurnFromSpecialists()
			cultureFromTraits = city:GetCulturePerTurnFromTraits()
			baseCulturePerTurn = city:GetBaseCulturePerTurn()
		end

		if IsCivBE or not OptionsManager.IsNoBasicHelp() then
			insert( tips, L"TXT_KEY_CULTURE_HELP_INFO" )
			insert( tips, "" )
		end

		-- Culture from Buildings
		insertLocalizedBulletIfNonZero( tips, "TXT_KEY_CULTURE_FROM_BUILDINGS", cultureFromBuildings )

		-- Culture from Policies
		insertLocalizedBulletIfNonZero( tips, "TXT_KEY_CULTURE_FROM_POLICIES", cultureFromPolicies )

		-- Culture from Specialists
		insertLocalizedBulletIfNonZero( tips, "TXT_KEY_CULTURE_FROM_SPECIALISTS", cultureFromSpecialists )

		-- Culture from Religion
		if not IsCiv5Vanilla then
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_CULTURE_FROM_RELIGION", city:GetJONSCulturePerTurnFromReligion() )
		end

		if IsCiv5BNW then
			-- Culture from Great Works
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_CULTURE_FROM_GREAT_WORKS", city:GetJONSCulturePerTurnFromGreatWorks() )
			-- Culture from Leagues
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_CULTURE_FROM_LEAGUES", city:GetJONSCulturePerTurnFromLeagues() )
		end

		-- Culture from Terrain
		insertLocalizedBulletIfNonZero( tips, "TXT_KEY_CULTURE_FROM_TERRAIN", IsCiv5Vanilla and city:GetJONSCulturePerTurnFromTerrain() or city:GetBaseYieldRateFromTerrain( YieldTypes.YIELD_CULTURE ) )

		-- Culture from Traits
		insertLocalizedBulletIfNonZero( tips, "TXT_KEY_CULTURE_FROM_TRAITS", cultureFromTraits )
		-- Base Total
		if baseCulturePerTurn ~= culturePerTurn then
			insert( tips, "----------------" )
			insert( tips, L( "TXT_KEY_YIELD_BASE", baseCulturePerTurn, "[ICON_CULTURE]" ) )
			insert( tips, "" )
		end

		-- Empire Culture modifier
		insertLocalizedBulletIfNonZero( tips, "TXT_KEY_CULTURE_PLAYER_MOD", cityOwner and cityOwner:GetCultureCityModifier() or 0 )

		if IsCiv5 then
			-- City Culture modifier
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_CULTURE_CITY_MOD", city:GetCultureRateModifier())

			-- Culture Wonders modifier
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_CULTURE_WONDER_BONUS", city:GetNumWorldWonders() > 0 and cityOwner and cityOwner:GetCultureWonderMultiplier() or 0 )
		end

		-- Puppet modifier
		local puppetMod = city:IsPuppet() and GameDefines.PUPPET_CULTURE_MODIFIER or 0
		if puppetMod ~= 0 then
			append( tips, L( "TXT_KEY_PRODMOD_PUPPET", puppetMod ) )
		end

		-- Total
		insert( tips, "----------------" )
		insert( tips, L( "TXT_KEY_YIELD_TOTAL", culturePerTurn, "[ICON_CULTURE]" ) )

		-- Tile growth
		insert( tips, "" )
		insert( tips, L( "TXT_KEY_CULTURE_INFO", "[COLOR_MAGENTA]" .. cultureStored .. "[ICON_CULTURE][ENDCOLOR]", "[COLOR_MAGENTA]" .. cultureNeeded .. "[ICON_CULTURE][ENDCOLOR]" ) )
		if culturePerTurn > 0 then
			local tipText = ""
			local turnsRemaining =  max(ceil((cultureNeeded - cultureStored ) / culturePerTurn), 1)
			local overflow = culturePerTurn * turnsRemaining + cultureStored - cultureNeeded
			if turnsRemaining > 1 then
				tipText = format( "%s %+g[ICON_CULTURE]  ", L( "TXT_KEY_STR_TURNS", turnsRemaining -1 ), overflow - culturePerTurn )
			end
			insert( tips, format( "%s[COLOR_MAGENTA]%s[ENDCOLOR] %+g[ICON_CULTURE]", tipText, Locale_ToUpper( L( "TXT_KEY_STR_TURNS", turnsRemaining ) ), overflow ) )
		end
		return concat( tips, "[NEWLINE]" )
	end

	-------------------------------------------------
	-- Helper function to build religion tooltip string
	-------------------------------------------------
	function GetReligionTooltip( city )

		if g_isReligionEnabled then

			local tips = {}
			local majorityReligionID = city:GetReligiousMajority()
			local pressureMultiplier = GameDefines.RELIGION_MISSIONARY_PRESSURE_MULTIPLIER or 1

			for religion in GameInfo.Religions() do
				local religionID = religion.ID

				if religionID >= 0 then
					local pressureLevel, numTradeRoutesAddingPressure = city:GetPressurePerTurn(religionID)
					local numFollowers = city:GetNumFollowers(religionID)
					local religionName = L( Game.GetReligionName(religionID) )
					local religionIcon = religion.IconString or "?"

					if pressureLevel > 0 or numFollowers > 0 then

						local religionTip = ""
						if pressureLevel > 0 then
							religionTip = L( "TXT_KEY_RELIGIOUS_PRESSURE_STRING", floor(pressureLevel/pressureMultiplier))
						end

						if numTradeRoutesAddingPressure and numTradeRoutesAddingPressure > 0 then
							religionTip = L( "TXT_KEY_RELIGION_TOOLTIP_LINE_WITH_TRADE", religionIcon, numFollowers, religionTip, numTradeRoutesAddingPressure)
						else
							religionTip = L( "TXT_KEY_RELIGION_TOOLTIP_LINE", religionIcon, numFollowers, religionTip)
						end

						if religionID == majorityReligionID then
							local beliefs
							if religionID > 0 then
								beliefs = Game.GetBeliefsInReligion( religionID )
							else
								beliefs = {Players[city:GetOwner()]:GetBeliefInPantheon()}
							end
							if beliefs then
								local item
								for _, beliefID in pairs( beliefs ) do
									item = GameInfo.Beliefs[ beliefID ]
									religionTip = religionTip .. "[NEWLINE][ICON_BULLET]"..BeliefColor( item and item._Name )
								end
								insert( tips, 1, religionTip )
							end
						else
							insert( tips, religionTip )
						end
					end

					if city:IsHolyCityForReligion( religionID ) then
						insert( tips, 1, L( "TXT_KEY_HOLY_CITY_TOOLTIP_LINE", religionIcon, religionName) )
					end
				end
			end
			return concat( tips, "[NEWLINE]" )
		else
			return L"TXT_KEY_TOP_PANEL_RELIGION_OFF_TOOLTIP"
		end
	end
	local GetReligionTooltip = GetReligionTooltip

	--------
	-- FAITH
	--------
	function GetFaithTooltip( city )

		if g_isReligionEnabled then
			local tips = {}

			if IsCivBE or not OptionsManager.IsNoBasicHelp() then
				insert( tips, L"TXT_KEY_FAITH_HELP_INFO" )
				insert( tips, "" )
			end

			-- Faith from Buildings
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_FAITH_FROM_BUILDINGS", city:GetFaithPerTurnFromBuildings() )

			-- Faith from Traits
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_FAITH_FROM_TRAITS", city:GetFaithPerTurnFromTraits() )

			-- Faith from Terrain
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_FAITH_FROM_TERRAIN", city:GetBaseYieldRateFromTerrain( YieldTypes.YIELD_FAITH ) )

			-- Faith from Policies
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_FAITH_FROM_POLICIES", city:GetFaithPerTurnFromPolicies() )

			-- Faith from Religion
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_FAITH_FROM_RELIGION", city:GetFaithPerTurnFromReligion() )

			-- Puppet modifier
			insertLocalizedBulletIfNonZero( tips, "TXT_KEY_PRODMOD_PUPPET", city:IsPuppet() and GameDefines.PUPPET_FAITH_MODIFIER or 0 )

			-- Citizens breakdown
			insert( tips, "----------------")
			insert( tips, L( "TXT_KEY_YIELD_TOTAL", city:GetFaithPerTurn(), "[ICON_PEACE]" ) )
			insert( tips, "" )
			insert( tips, GetReligionTooltip( city ) )

			return concat( tips, "[NEWLINE]" )
		else
			return L"TXT_KEY_TOP_PANEL_RELIGION_OFF_TOOLTIP"
		end
	end

	-- TOURISM
	function GetTourismTooltip(city)
		return city:GetTourismTooltip()
	end

	----------------------------------------------------------------
	-- MAJOR PLAYER MOOD INFO
	----------------------------------------------------------------
	local function addIfNz( v, icon )
		if v and v > 0 then
			return "+"..(v/100)..icon
		else
			return ""
		end
	end
	local function routeBonus( route, d )
		return addIfNz( route[d.."GPT"], g_currencyIcon )
			.. addIfNz( route[d.."Food"], "[ICON_FOOD]" )
			.. addIfNz( route[d.."Production"], "[ICON_PRODUCTION]" )
			.. addIfNz( route[d.."Science"], "[ICON_RESEARCH]" )
	end
	local function inParentheses( duration )
		if duration and duration >= 0 then
			return " (".. duration ..")"
		else
			return ""
		end
	end

	local g_relationshipDuration = (GameInfo.GameSpeeds[ PreGame.GetGameSpeed() ]or {}).RelationshipDuration or 50

	function GetMoodInfo( playerID )

		local activePlayerID = Game.GetActivePlayer()
		local activePlayer = Players[activePlayerID]
		local activeTeamID = activePlayer:GetTeam()
		local activeTeam = Teams[activeTeamID]

		local player = Players[playerID]
		local teamID = player:GetTeam()
		local team = Teams[teamID]

		-- Player & civ names
		local strInfo = GetCivName(player) .. " (" .. GetLeaderName(player) .. ") "

		-- Always war ?
		if (playerID ~= activePlayerID) and (
			( activeTeam:IsAtWar( teamID )
			and Game.IsOption( GameOptionTypes.GAMEOPTION_NO_CHANGING_WAR_PEACE ) )
			or Game.IsOption(GameOptionTypes.GAMEOPTION_ALWAYS_WAR) )
		then
			return strInfo .. L"TXT_KEY_ALWAYS_WAR_TT"
		end

		-- Era
		local item = GameInfo.Eras[ player:GetCurrentEra() ]
		strInfo = strInfo .. (item and item._Name or "???")

		-- Tech in Progress
		if teamID == activeTeamID then
			local currentTechID = player:GetCurrentResearch()
			local currentTech = GameInfo.Technologies[currentTechID]
			if currentTech and g_isScienceEnabled then
				strInfo = strInfo .. " [ICON_RESEARCH] " .. TechColor( currentTech._Name )
			end
		else
		-- Mood
			local visibleApproachID = activePlayer:GetApproachTowardsUsGuess(playerID)
			strInfo = strInfo .. " " .. (
			-- At war
			((team:IsAtWar( activeTeamID ) or visibleApproachID == MajorCivApproachTypes.MAJOR_CIV_APPROACH_WAR) and L"TXT_KEY_DIPLO_MAJOR_CIV_DIPLO_STATE_WAR")
			-- Denouncing
			or (player:IsDenouncingPlayer( activePlayerID ) and L"TXT_KEY_DIPLO_MAJOR_CIV_DIPLO_STATE_DENOUNCING")
			-- Resurrected
			or (not IsCiv5Vanilla and player:WasResurrectedThisTurnBy( activePlayerID ) and L"TXT_KEY_DIPLO_MAJOR_CIV_DIPLO_STATE_LIBERATED")
			-- Appears Hostile
			or (visibleApproachID == MajorCivApproachTypes.MAJOR_CIV_APPROACH_HOSTILE and L"TXT_KEY_DIPLO_MAJOR_CIV_DIPLO_STATE_HOSTILE")
			-- Appears Guarded
			or (visibleApproachID == MajorCivApproachTypes.MAJOR_CIV_APPROACH_GUARDED and L"TXT_KEY_DIPLO_MAJOR_CIV_DIPLO_STATE_GUARDED")
			-- Appears Afraid
			or (visibleApproachID == MajorCivApproachTypes.MAJOR_CIV_APPROACH_AFRAID and L"TXT_KEY_DIPLO_MAJOR_CIV_DIPLO_STATE_AFRAID")
			-- Appears Friendly
			or (visibleApproachID == MajorCivApproachTypes.MAJOR_CIV_APPROACH_FRIENDLY and L"TXT_KEY_DIPLO_MAJOR_CIV_DIPLO_STATE_FRIENDLY")
			-- Neutral - default string
			or L"TXT_KEY_DIPLO_MAJOR_CIV_DIPLO_STATE_NEUTRAL" ) .. "[/COLOR]"
		end

		-- Techs Known
		local tips = { team:GetTeamTechs():GetNumTechsKnown() .. " " .. TechColor( Locale_ToLower("TXT_KEY_VP_TECH") ) }
		-- Policies
		for policyBranch in GameInfo.PolicyBranchTypes() do
			local policyCount = 0

			for policy in GameInfo.Policies() do
				if policy.PolicyBranchType == policyBranch.Type and player:HasPolicy(policy.ID) then
					policyCount = policyCount + 1
				end
			end

			if policyCount > 0 then
				insert( tips, policyCount .. " " .. PolicyColor( Locale_ToLower(policyBranch._Name or "???") ) )
			end
		end
		-- Religion Founded
		if g_isReligionEnabled then
			local religionID = player:GetReligionCreatedByPlayer()
			if religionID > 0 then
				item = GameInfo.Religions[ religionID ]
				insert( tips, (item and item.IconString or "?")..BeliefColor( L("TXT_KEY_RO_STATUS_FOUNDER", Game.GetReligionName( religionID ) ) ) )
			end
		end
		tips = { strInfo, concat( tips, ", ") }

		-- Wonders
		local wonders = {}
		for building in GameInfo.Buildings() do
			item = GameInfo.BuildingClasses[building.BuildingClass]
			if item and ( item.MaxGlobalInstances or 0 ) > 0 and player:CountNumBuildings(building.ID) > 0 then
				insert( wonders, BuildingColor( building._Name ) )
			end
		end
		-- Population
		insert( tips, player:GetTotalPopulation() .. "[ICON_CITIZEN]"
				.. ", "
				.. L("{1} {1: plural 1?{TXT_KEY_CITY:lower}; 2?{TXT_KEY_VP_CITIES:lower};}", player:GetNumCities() )
				.. ", "
				.. player:GetNumWorldWonders() .. " " .. L("{TXT_KEY_VP_WONDERS:lower}")
				.. (#wonders>0 and ": " .. concat( wonders, ", " ) or "") )
	--[[ too much info
		local cities = {}
		for city in player:Cities() do
			-- Name & population
			local cityTxt = format("%i[ICON_CITIZEN] %s", city:GetPopulation(), city:GetName())
			if city:IsCapital() then
				cityTxt = "[ICON_CAPITAL]" .. cityTxt
			end
			-- Wonders
			local wonders = {}
			for building in GameInfo.Buildings() do
				if city:IsHasBuilding(building.ID) and GameInfo.BuildingClasses[building.BuildingClass].MaxGlobalInstances > 0 then
					insert( wonders, building._Name )
				end
			end
			if #wonders > 0 then
				cityTxt = cityTxt .. " (" .. concat( wonders, ", ") .. ")"
			end
			insert( cities, cityTxt )
		end
		if #cities > 1 then
			insert( tips, #cities .. " " .. L"TXT_KEY_DIPLO_CITIES":lower() .. " : " .. concat( cities, ", ") )
		elseif #cities ==1 then
			insert( tips, cities[1] )
		end
	--]]

		-- Gold (can be seen in diplo relation ship)
		insert( tips, format( "%i%s(%+i)", player:GetGold(), g_currencyIcon, player:CalculateGoldRate() ) )


		--------------------------------------------------------------------
		-- Loop through the active player's current deals
		--------------------------------------------------------------------

		local isTradeable, isActiveDeal
		local dealsFinalTurn = {}
		local deals = {}
		local tradeRoutes = {}
		local opinions = {}
		local treaties = {}
		local currentTurn = Game.GetGameTurn() -1
		local isUs = playerID == activePlayerID
		local bnw_be = IsCiv5BNW or IsCivBE

		local function GetDealTurnsRemaining( itemID )
			local turnsRemaining
			if bnw_be and itemID == TradeableItems.TRADE_ITEM_DECLARATION_OF_FRIENDSHIP then -- DoF special kinky case
				turnsRemaining = g_relationshipDuration - activePlayer:GetDoFCounter( playerID )
			elseif itemID then
				local finalTurn = dealsFinalTurn[ itemID ]
				if finalTurn then
					turnsRemaining = finalTurn - currentTurn
				end
			end
			return inParentheses( isActiveDeal and turnsRemaining )
		end

		local dealItems = {}
		local finalTurns = {}
		PushScratchDeal()
		for i = 0, GetNumCurrentDeals( activePlayerID ) - 1 do
			LoadCurrentDeal( activePlayerID, i )
			local toPlayerID = ScratchDeal:GetOtherPlayer( activePlayerID )
			ScratchDeal:ResetIterator()
			repeat
				local itemID, duration, finalTurn, data1, data2, data3, flag1, fromPlayerID = ScratchDeal:GetNextItem()
				if itemID then
					if not bnw_be then
						fromPlayerID = data3
					end
					if isUs or toPlayerID == playerID or fromPlayerID == playerID then
	--					finalTurn = finalTurn - currentTurn
						local isFromUs = fromPlayerID == activePlayerID
						local dealItem = dealItems[ finalTurn ]
						if not dealItem then
							dealItem = {}
							dealItems[ finalTurn ] = dealItem
							insert( finalTurns, finalTurn )
						end
						if itemID == TradeableItems.TRADE_ITEM_GOLD_PER_TURN then
							dealItem.GPT = (dealItem.GPT or 0) + (isFromUs and -data1 or data1)
						elseif itemID == TradeableItems.TRADE_ITEM_RESOURCES then
							dealItem[data1] = (dealItem[data1] or 0) + (isFromUs and -data2 or data2)
						else
							dealsFinalTurn[ itemID + (isFromUs and 65536 or 0) ] = finalTurn
						end
					end
				else
					break
				end
			until false
		end
		PopScratchDeal()
		sort( finalTurns )
		for i = 1, #finalTurns do
			local finalTurn = finalTurns[i]
			local dealItem = dealItems[ finalTurn ] or {}
	--todo!
			local deal = {}
			local quantity = dealItem.GPT
			if quantity and quantity ~= 0 then
				insert( deal, format( "%+g%s", quantity, g_currencyIcon ) )
			end
			for resource in GameInfo.Resources() do
				local quantity = dealItem[ resource.ID ]
				if (quantity or 0) ~= 0 then
					insert( deal, format( "%+i%s", quantity, resource.IconString or "?" ) )
				end
			end
			if #deal > 0 then
				insert( deals, concat( deal ) .. "("..( finalTurn - currentTurn )..")" )
			end
		end

		local tip
		if bnw_be then
			for _, route in ipairs( activePlayer:GetTradeRoutes() ) do
				if isUs or route.ToID == playerID then
					tip = "   [ICON_INTERNATIONAL_TRADE]" .. route.FromCityName .. " "
							.. routeBonus( route, "From" )
							.. "[ICON_MOVES]" .. route.ToCityName
					if route.ToID == activePlayerID then
						tip = tip .. " ".. routeBonus( route, "To" )
					end
					insert( tradeRoutes, tip .. " ("..(route.TurnsLeft-1)..")" )
				end
			end
			for _, route in ipairs( activePlayer:GetTradeRoutesToYou() ) do
				if isUs or route.FromID == playerID then
					insert( tradeRoutes, "   [ICON_INTERNATIONAL_TRADE]" .. route.FromCityName .. "[ICON_MOVES]" .. route.ToCityName .. " " .. routeBonus( route, "To" ) )
				end
			end
		end

		if isUs then

			-- Resources available for trade
			local luxuries = {}
			local strategic = {}
			for resource in GameInfo.Resources() do
				local i = activePlayer:GetNumResourceAvailable( resource.ID, false )
				if i > 0 then
					if resource.ResourceClassType == "RESOURCECLASS_LUXURY" then
						insert( luxuries, " " .. activePlayer:GetNumResourceAvailable( resource.ID, true ) .. ResourceString( resource ) )
					elseif resource.ResourceClassType ~= "RESOURCECLASS_BONUS" then
						insert( strategic, " " .. i .. ResourceString( resource ) )
					end
				end
			end
	-- todo !!!
			append( tips, concat(luxuries) .. concat(strategic) )

		else  --if teamID ~= activeTeamID then

			local visibleApproachID = activePlayer:GetApproachTowardsUsGuess(playerID)

			if activeTeam:IsAtWar( teamID ) then	-- At war right now

				insert( opinions, L"TXT_KEY_DIPLO_MAJOR_CIV_DIPLO_STATE_WAR" )

			else	-- Not at war right now

				-- Resources available from them
				local luxuries = {}
				local strategic = {}
				for resource in GameInfo.Resources() do
					if ScratchDeal:IsPossibleToTradeItem( playerID, activePlayerID, TradeableItems.TRADE_ITEM_RESOURCES, resource.ID, 1 ) then	-- 1 here is 1 quantity of the Resource, which is the minimum possible
						tip = "  " .. player:GetNumResourceAvailable( resource.ID, false ) .. ResourceString( resource )
						if resource.ResourceClassType == "RESOURCECLASS_LUXURY" then
							insert( luxuries, tip )
						else
							insert( strategic, tip )
						end
					end
				end
				append( tips, concat(luxuries) .. concat(strategic) )

				-- Resources they would like from us
				luxuries = {}
				strategic = {}
				for resource in GameInfo.Resources() do
					if ScratchDeal:IsPossibleToTradeItem( activePlayerID, playerID, TradeableItems.TRADE_ITEM_RESOURCES, resource.ID, 1 ) then	-- 1 here is 1 quantity of the Resource, which is the minimum possible
						if resource.ResourceClassType == "RESOURCECLASS_LUXURY" then
							insert( luxuries, " " .. activePlayer:GetNumResourceAvailable( resource.ID, true ) .. ResourceString( resource ) )
						else
							insert( strategic, " " .. activePlayer:GetNumResourceAvailable( resource.ID, false ) .. ResourceString( resource ) )
						end
					end
				end
				if #luxuries > 0 or #strategic > 0 then
					insert( tips, L"TXT_KEY_DIPLO_YOUR_ITEMS_LABEL" .. ": " .. concat(luxuries) .. concat(strategic) )
				end

				-- Treaties
				local peaceTurnExpire = dealsFinalTurn[ TradeableItems.TRADE_ITEM_PEACE_TREATY ]
				if peaceTurnExpire and peaceTurnExpire > currentTurn then
					insert( treaties, "[ICON_PEACE]" .. L( "TXT_KEY_DIPLO_PEACE_TREATY", peaceTurnExpire - currentTurn ) )
				end
				if not IsCiv5Vanilla then

					-- Embassy to them
					isTradeable = ScratchDeal:IsPossibleToTradeItem( activePlayerID, playerID, TradeableItems.TRADE_ITEM_ALLOW_EMBASSY, g_dealDuration )
					isActiveDeal = team:HasEmbassyAtTeam( activeTeamID )

					if isTradeable or isActiveDeal then
						insert( treaties, negativeOrPositiveTextColor[isActiveDeal] .. "[ICON_CAPITAL]"
								.. L"TXT_KEY_DIPLO_ALLOW_EMBASSY":lower()
								.. "[ENDCOLOR]" .. GetDealTurnsRemaining( TradeableItems.TRADE_ITEM_ALLOW_EMBASSY + 65536 ) -- 65536 means from us
						)
					end

					-- Embassy from them
					isTradeable = ScratchDeal:IsPossibleToTradeItem( playerID, activePlayerID, TradeableItems.TRADE_ITEM_ALLOW_EMBASSY, g_dealDuration )
					isActiveDeal = activeTeam:HasEmbassyAtTeam( teamID )

					if isTradeable or isActiveDeal then
						insert( treaties, negativeOrPositiveTextColor[isActiveDeal]
								.. L"TXT_KEY_DIPLO_ALLOW_EMBASSY":lower()
								.. "[ICON_CAPITAL][ENDCOLOR]" .. GetDealTurnsRemaining( TradeableItems.TRADE_ITEM_ALLOW_EMBASSY )
						)
					end
				end

				-- Open Borders to them
				isTradeable = ScratchDeal:IsPossibleToTradeItem( activePlayerID, playerID, TradeableItems.TRADE_ITEM_OPEN_BORDERS, g_dealDuration )
				isActiveDeal = activeTeam:IsAllowsOpenBordersToTeam(teamID)

				if isTradeable or isActiveDeal then
					insert( treaties, negativeOrPositiveTextColor[isActiveDeal] .. "<"
							.. L"TXT_KEY_DO_OPEN_BORDERS"
							.. "[ENDCOLOR]" .. GetDealTurnsRemaining( TradeableItems.TRADE_ITEM_OPEN_BORDERS + 65536 ) -- 65536 means from us
					)
				end

				-- Open Borders from them
				isTradeable = ScratchDeal:IsPossibleToTradeItem( playerID, activePlayerID, TradeableItems.TRADE_ITEM_OPEN_BORDERS, g_dealDuration )
				isActiveDeal = team:IsAllowsOpenBordersToTeam( activeTeamID )

				if isTradeable or isActiveDeal then
					insert( treaties, negativeOrPositiveTextColor[isActiveDeal]
							.. L"TXT_KEY_DO_OPEN_BORDERS"
							.. ">[ENDCOLOR]" .. GetDealTurnsRemaining( TradeableItems.TRADE_ITEM_OPEN_BORDERS )
					)
				end

				-- Declaration of Friendship
				isTradeable = IsCiv5Vanilla or ScratchDeal:IsPossibleToTradeItem( playerID, activePlayerID, TradeableItems.TRADE_ITEM_DECLARATION_OF_FRIENDSHIP, g_dealDuration )
				isActiveDeal = activePlayer:IsDoF(playerID)
				if isTradeable or isActiveDeal then
					insert( treaties, negativeOrPositiveTextColor[isActiveDeal] .. "[ICON_FLOWER]"
							.. L"TXT_KEY_DIPLOMACY_FRIENDSHIP_ADV_QUEST"
							.. "[ENDCOLOR]" .. GetDealTurnsRemaining( TradeableItems.TRADE_ITEM_DECLARATION_OF_FRIENDSHIP )
					)
				end

				-- Research Agreement
	--			isTradeable = (activeTeam:IsResearchAgreementTradingAllowed() or team:IsResearchAgreementTradingAllowed())
	--				and not activeTeam:GetTeamTechs():HasResearchedAllTechs() and not team:GetTeamTechs():HasResearchedAllTechs()
	--				and not g_isScienceEnabled
				isTradeable = ScratchDeal:IsPossibleToTradeItem( playerID, activePlayerID, TradeableItems.TRADE_ITEM_RESEARCH_AGREEMENT, g_dealDuration )
				isActiveDeal = activeTeam:IsHasResearchAgreement(teamID)
				if isTradeable or isActiveDeal then
					insert( treaties, negativeOrPositiveTextColor[isActiveDeal] .. "[ICON_RESEARCH]"
							.. L"TXT_KEY_DO_RESEARCH_AGREEMENT"
							.. "[ENDCOLOR]" .. GetDealTurnsRemaining( TradeableItems.TRADE_ITEM_RESEARCH_AGREEMENT )
					)
				end

				-- Trade Agreement
				isTradeable = ScratchDeal:IsPossibleToTradeItem( playerID, activePlayerID, TradeableItems.TRADE_ITEM_TRADE_AGREEMENT, g_dealDuration )
				isActiveDeal = activeTeam:IsHasTradeAgreement(teamID)
				if isTradeable or isActiveDeal then
					insert( treaties, negativeOrPositiveTextColor[isActiveDeal] .. "[ICON_RESEARCH]"
							.. L"TXT_KEY_DIPLO_TRADE_AGREEMENT":lower()
							.. "[ENDCOLOR]" .. GetDealTurnsRemaining( TradeableItems.TRADE_ITEM_TRADE_AGREEMENT )
					)
				end

				-- Defensive Pact
				isTradeable = ScratchDeal:IsPossibleToTradeItem( playerID, activePlayerID, TradeableItems.TRADE_ITEM_DEFENSIVE_PACT, g_dealDuration )
				isActiveDeal = activeTeam:IsDefensivePact(teamID)
				if isTradeable or isActiveDeal then
					insert( treaties, negativeOrPositiveTextColor[isActiveDeal] .. "[ICON_STRENGTH]"
							.. L"TXT_KEY_DO_PACT"
							.. "[ENDCOLOR]" .. GetDealTurnsRemaining( TradeableItems.TRADE_ITEM_DEFENSIVE_PACT )
					)
				end

				-- We've fought before
				if IsCiv5Vanilla and activePlayer:GetNumWarsFought(playerID) > 0 then
					-- They don't appear to be mad
					if visibleApproachID == MajorCivApproachTypes.MAJOR_CIV_APPROACH_FRIENDLY or
						visibleApproachID == MajorCivApproachTypes.MAJOR_CIV_APPROACH_NEUTRAL then
						insert( opinions, L"TXT_KEY_DIPLO_PAST_WAR_NEUTRAL" )
					-- They aren't happy with us
					else
						insert( opinions, L"TXT_KEY_DIPLO_PAST_WAR_BAD" )
					end
				end
			end

			if player.GetOpinionTable then
				opinions = player:GetOpinionTable( activePlayerID )
			else

				-- Good things
				if activePlayer:IsDoF(playerID) then
					insert( opinions, L"TXT_KEY_DIPLO_DOF" )
				end
				-- Human has a mutual friend with the AI
				if activePlayer:IsPlayerDoFwithAnyFriend(playerID) then
					insert( opinions, L"TXT_KEY_DIPLO_MUTUAL_DOF" )
				end
				-- Human has denounced an enemy of the AI
				if activePlayer:IsPlayerDenouncedEnemy(playerID) then
					insert( opinions, L"TXT_KEY_DIPLO_MUTUAL_ENEMY" )
				end
				if player:GetNumCiviliansReturnedToMe(activePlayerID) > 0 then
					insert( opinions, L"TXT_KEY_DIPLO_CIVILIANS_RETURNED" )
				end

				-- Neutral things
				if visibleApproachID == MajorCivApproachTypes.MAJOR_CIV_APPROACH_AFRAID then
					insert( opinions, L"TXT_KEY_DIPLO_AFRAID" )
				end

				-- Bad things

				-- Human was a friend and declared war on us
				if player:IsFriendDeclaredWarOnUs(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_HUMAN_FRIEND_DECLARED_WAR" )
				end
				-- Human was a friend and denounced us
				if player:IsFriendDenouncedUs(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_HUMAN_FRIEND_DENOUNCED" )
				end
				-- Human declared war on friends
				if activePlayer:GetWeDeclaredWarOnFriendCount() > 0 then
					insert( opinions, L"TXT_KEY_DIPLO_HUMAN_DECLARED_WAR_ON_FRIENDS" )
				end
				-- Human has denounced his friends
				if activePlayer:GetWeDenouncedFriendCount() > 0 then
					insert( opinions, L"TXT_KEY_DIPLO_HUMAN_DENOUNCED_FRIENDS" )
				end
				-- Human has been denounced by friends
				if activePlayer:GetNumFriendsDenouncedBy() > 0 then
					insert( opinions, L"TXT_KEY_DIPLO_HUMAN_DENOUNCED_BY_FRIENDS" )
				end
				if activePlayer:IsDenouncedPlayer(playerID) then
					insert( opinions, L"TXT_KEY_DIPLO_DENOUNCED_BY_US" )
				end
				if player:IsDenouncedPlayer(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_DENOUNCED_BY_THEM" )
				end
				if player:IsPlayerDoFwithAnyEnemy(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_HUMAN_DOF_WITH_ENEMY" )
				end
				if player:IsPlayerDenouncedFriend(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_HUMAN_DENOUNCED_FRIEND" )
				end
				if player:IsPlayerNoSettleRequestEverAsked(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_NO_SETTLE_ASKED" )
				end
				if player:IsDemandEverMade(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_TRADE_DEMAND" )
				end
				if player:GetNumTimesCultureBombed(activePlayerID) > 0 then
					insert( opinions, L"TXT_KEY_DIPLO_CULTURE_BOMB" )
				end
				if player:IsPlayerBrokenMilitaryPromise(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_MILITARY_PROMISE" )
				end
				if player:IsPlayerIgnoredMilitaryPromise(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_MILITARY_PROMISE_IGNORED" )
				end
				if player:IsPlayerBrokenExpansionPromise(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_EXPANSION_PROMISE" )
				end
				if player:IsPlayerIgnoredExpansionPromise(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_EXPANSION_PROMISE_IGNORED" )
				end
				if player:IsPlayerBrokenBorderPromise(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_BORDER_PROMISE" )
				end
				if player:IsPlayerIgnoredBorderPromise(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_BORDER_PROMISE_IGNORED" )
				end
				if player:IsPlayerBrokenCityStatePromise(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_CITY_STATE_PROMISE" )
				end
				if player:IsPlayerIgnoredCityStatePromise(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_CITY_STATE_PROMISE_IGNORED" )
				end
				if player:IsPlayerBrokenCoopWarPromise(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_COOP_WAR_PROMISE" )
				end
				if player:IsPlayerRecklessExpander(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_RECKLESS_EXPANDER" )
				end
				if player:GetNumRequestsRefused(activePlayerID) > 0 then
					insert( opinions, L"TXT_KEY_DIPLO_REFUSED_REQUESTS" )
				end
				if player:GetRecentTradeValue(activePlayerID) > 0 then
					insert( opinions, L"TXT_KEY_DIPLO_TRADE_PARTNER" )
				end
				if player:GetCommonFoeValue(activePlayerID) > 0 then
					insert( opinions, L"TXT_KEY_DIPLO_COMMON_FOE" )
				end
				if player:GetRecentAssistValue(activePlayerID) > 0 then
					insert( opinions, L"TXT_KEY_DIPLO_ASSISTANCE_TO_THEM" )
				end
				if player:IsLiberatedCapital(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_LIBERATED_CAPITAL" )
				end
				if player:IsLiberatedCity(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_LIBERATED_CITY" )
				end
				if player:IsGaveAssistanceTo(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_ASSISTANCE_FROM_THEM" )
				end
				if player:IsHasPaidTributeTo(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_PAID_TRIBUTE" )
				end
				if player:IsNukedBy(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_NUKED" )
				end
				if player:IsCapitalCapturedBy(activePlayerID) then
					insert( opinions, L"TXT_KEY_DIPLO_CAPTURED_CAPITAL" )
				end
				-- Protected Minors
				if player:GetOtherPlayerNumProtectedMinorsKilled(activePlayerID) > 0 then
					insert( opinions, L"TXT_KEY_DIPLO_PROTECTED_MINORS_KILLED" )
				-- Only worry about protected minors ATTACKED if they haven't KILLED any
				elseif player:GetOtherPlayerNumProtectedMinorsAttacked(activePlayerID) > 0 then
					insert( opinions, L"TXT_KEY_DIPLO_PROTECTED_MINORS_ATTACKED" )
				end

				--local actualApproachID = player:GetMajorCivApproach(activePlayerID)

				-- Bad things we don't want visible if someone is friendly (acting or truthfully)
				if visibleApproachID ~= MajorCivApproachTypes.MAJOR_CIV_APPROACH_FRIENDLY then
					-- and actualApproachID ~= MajorCivApproachTypes.MAJOR_CIV_APPROACH_DECEPTIVE then
					if player:GetLandDisputeLevel(activePlayerID) > DisputeLevelTypes.DISPUTE_LEVEL_NONE then
						insert( opinions, L"TXT_KEY_DIPLO_LAND_DISPUTE" )
					end
					--if player:GetVictoryDisputeLevel(activePlayerID) > DisputeLevelTypes.DISPUTE_LEVEL_NONE then insert( opinions, L"TXT_KEY_DIPLO_VICTORY_DISPUTE" ) end
					if player:GetWonderDisputeLevel(activePlayerID) > DisputeLevelTypes.DISPUTE_LEVEL_NONE then
						insert( opinions, L"TXT_KEY_DIPLO_WONDER_DISPUTE" )
					end
					if player:GetMinorCivDisputeLevel(activePlayerID) > DisputeLevelTypes.DISPUTE_LEVEL_NONE then
						insert( opinions, L"TXT_KEY_DIPLO_MINOR_CIV_DISPUTE" )
					end
					if player:GetWarmongerThreat(activePlayerID) > ThreatTypes.THREAT_NONE then
						insert( opinions, L"TXT_KEY_DIPLO_WARMONGER_THREAT" )
					end
				end
			end

			--  No specific events - let's see what string we should use
			if #opinions == 0 then
				-- At war
				if visibleApproachID == MajorCivApproachTypes.MAJOR_CIV_APPROACH_WAR then
					opinions = { L"TXT_KEY_DIPLO_AT_WAR" }
				-- Appears Friendly
				elseif visibleApproachID == MajorCivApproachTypes.MAJOR_CIV_APPROACH_FRIENDLY then
					opinions = { L"TXT_KEY_DIPLO_FRIENDLY" }
				-- Appears Guarded
				elseif visibleApproachID == MajorCivApproachTypes.MAJOR_CIV_APPROACH_GUARDED then
					opinions = { L"TXT_KEY_DIPLO_GUARDED" }
				-- Appears Hostile
				elseif visibleApproachID == MajorCivApproachTypes.MAJOR_CIV_APPROACH_HOSTILE then
					opinions = { L"TXT_KEY_DIPLO_HOSTILE" }
				-- Appears Affraid
				elseif visibleApproachID == MajorCivApproachTypes.MAJOR_CIV_APPROACH_AFRAID  then
					opinions = { L"TXT_KEY_DIPLO_AFRAID" }
				-- Neutral - default string
				else
					opinions = { L"TXT_KEY_DIPLO_DEFAULT_STATUS" }
				end
			end

		end -- playerID vs activePlayerID

	--TODO "TXT_KEY_DO_WE_PROVIDE" & "TXT_KEY_DO_THEY_PROVIDE"
		if #deals > 0 then
			insert( tips, L"TXT_KEY_DO_CURRENT_DEALS" .. "[NEWLINE]" .. concat( deals, ", " ) )
		end
		if #tradeRoutes > 0 then
			insert( tips, concat( tradeRoutes, "[NEWLINE]" ) )
		end
		if #treaties > 0 then
			insert( tips, concat( treaties, ", " ) .. "[ENDCOLOR]" )
		end
		if #opinions > 0 then
			insert( tips, "[ICON_BULLET]" .. concat( opinions, "[NEWLINE][ICON_BULLET]" ) .. "[ENDCOLOR]" )
		end

		local allied = {}
		local friends = {}
		local protected = {}
		local denouncements = {}
		local backstabs = {}
		local denouncedBy = {}
		local wars = {}

		-- Relationships with others
		for otherPlayerID = 0, GameDefines.MAX_CIV_PLAYERS - 1 do
			local otherPlayer = Players[otherPlayerID]
			local otherTeamID = otherPlayer:GetTeam()
			if otherPlayer
				and otherPlayerID ~= playerID
				and otherPlayer:IsAlive()
				and activeTeam:IsHasMet(otherTeamID)
			then
				local otherPlayerName =  GetCivName(otherPlayer)
				-- Wars
				if team:IsAtWar(otherTeamID) then
					insert( wars, otherPlayerName )
				end
				if otherPlayer:IsMinorCiv() then
					-- Alliances
					if otherPlayer:IsAllies(playerID) then
						insert( allied, otherPlayerName )
					-- Friendships
					elseif otherPlayer:IsFriends(playerID) then
						insert( friends, otherPlayerName )
					end
					-- Protections
					if player:IsProtectingMinor(otherPlayerID) then
						insert( protected, otherPlayerName .. inParentheses( not IsCiv5Vanilla and isUs and ( otherPlayer:GetTurnLastPledgedProtectionByMajor(playerID) - Game.GetGameTurn() + 10 ) ) )  -- todo check scaling % game speed
					end
				else
					-- Defensive pacts
					if team:IsDefensivePact(otherTeamID) then
						insert( allied, otherPlayerName )
					end
					-- Friendships
					if player:IsDoF(otherPlayerID) then
						insert( friends, otherPlayerName .. inParentheses( bnw_be and ( g_relationshipDuration - player:GetDoFCounter( otherPlayerID ) ) ) )
					end
					-- Backstab
					if otherPlayer:IsFriendDenouncedUs(playerID) or otherPlayer:IsFriendDeclaredWarOnUs(playerID) then
						insert( backstabs, otherPlayerName )
					-- Denouncement
					elseif player:IsDenouncedPlayer(otherPlayerID) then
						insert( denouncements, otherPlayerName .. inParentheses( bnw_be and ( g_relationshipDuration - player:GetDenouncedPlayerCounter( otherPlayerID ) ) ) )
					end
					-- Denounced by 3rd party
					if otherPlayer:IsDenouncedPlayer(playerID) then
						insert( denouncedBy, otherPlayerName .. inParentheses( bnw_be and ( g_relationshipDuration - otherPlayer:GetDenouncedPlayerCounter( playerID ) ) ) )
					end
				end
			end
		end

		if #allied > 0 then
			insert( tips, "[ICON_STRENGTH]" .. L( "TXT_KEY_ALLIED_WITH", concat( allied, ", ") ) )
		end
		if #friends > 0 then
			insert( tips, "[ICON_FLOWER]" .. L( "TXT_KEY_DIPLO_FRIENDS_WITH", concat( friends, ", ") ) )
		end
		if #protected > 0 then
			insert( tips, "[ICON_CITY_STATE]" .. L"TXT_KEY_POP_CSTATE_PLEDGE_TO_PROTECT" .. ": " .. concat( protected, ", ") )
		end
		if #backstabs > 0 then
			insert( tips, "[ICON_PIRATE]" .. L( "TXT_KEY_DIPLO_BACKSTABBED", concat( backstabs, ", ") ) )
		end
		if #denouncements > 0 then
			insert( tips, "[ICON_DENOUNCE]" .. L( "TXT_KEY_DIPLO_DENOUNCED", concat( denouncements, ", ") ) )
		end
		if #denouncedBy > 0 then
			insert( tips, "[ICON_DENOUNCE]" .. TextColor( negativeOrPositiveTextColor[false], L( "TXT_KEY_NTFN_DENOUNCED_US_S", concat( denouncedBy, ", ") ) ) )
		end
		if #wars > 0 then
			insert( tips, "[ICON_WAR]" .. L( "TXT_KEY_AT_WAR_WITH", concat( wars, ", ") ) )
		end

		return concat( tips, "[NEWLINE]" )
	end

	if IsCivBE then
		-- ===========================================================================
		-- PLAYER PERK (civ BE only)
		-- ===========================================================================

		function GetHelpTextForPlayerPerk( perkID )

			local perkInfo = GameInfo.PlayerPerks[ perkID ]

			-- Name
			local tips = { Locale_ToUpper( perkInfo._Name or "???" ), "----------------" }

			-- Yield from Buildings
			for playerPerkBuildingYieldEffect in GameInfo.PlayerPerks_BuildingYieldEffects{ PlayerPerkType = perkInfo.Type } do
				local building = GameInfo.BuildingClasses[ playerPerkBuildingYieldEffect.BuildingClassType ]
				local yield = building and GameInfo.Yields[ playerPerkBuildingYieldEffect.YieldType ]
				if yield then
					insert( tips, L( "TXT_KEY_PLAYERPERK_ALL_BUILDING_YIELD_EFFECT", playerPerkBuildingYieldEffect.FlatYield, yield.IconString, yield._Name or "???", building._Name or "???" ) )
				end
			end

			-- Pre-written Help text
			return AddPreWrittenHelpTextAndConcat( tips, perkInfo )
		end

		local getHelpTextForUnitAttributes, getHelpTextForUnitPlayerPerkBuffs, getHelpTextForUnitInherentPromotions, getHelpTextForUnitPromotions, getHelpTextForUnitPerks, getHelpTextForAffinityLevel
		----------------------------------------------------------------
		----------------------------------------------------------------
		-- UNIT COMBO THINGS
		----------------------------------------------------------------
		----------------------------------------------------------------
		function GetHelpTextForSpecificUnit(unit)
			local s = "";

			-- Attributes
			s = s .. getHelpTextForUnitAttributes(unit:GetUnitType(), "[ICON_BULLET]");

			-- Player Perks
			local temp = getHelpTextForUnitPlayerPerkBuffs(unit:GetUnitType(), unit:GetOwner(), "[ICON_BULLET]");
			if temp ~= "" then
				if s ~= "" then
					s = s .. "[NEWLINE]";
				end
				s = s .. temp;
			end

			-- Promotions
			temp = getHelpTextForUnitPromotions(unit, "[ICON_BULLET]");
			if temp ~= "" then
				if s ~= "" then
					s = s .. "[NEWLINE]";
				end
				s = s .. temp;
			end

			-- Upgrades and Perks
			local player = Players[unit:GetOwner()];
			if player then
				local allPerks = player:GetPerksForUnit(unit:GetUnitType());
				local tempPerks = player:GetFreePerksForUnit(unit:GetUnitType());
				for _, perk in ipairs(tempPerks) do
					insert(allPerks, perk);
				end
				local ignoreCoreStats = true;
				temp = getHelpTextForUnitPerks(allPerks, ignoreCoreStats, "[ICON_BULLET]");
				if temp ~= "" then
					if s ~= "" then
						s = s .. "[NEWLINE]";
					end
					s = s .. temp;
				end
			end

			return s;
		end

		function GetHelpTextForUnitType(unitType, playerID, includeFreePromotions)
			local s = "";

			-- Attributes
			s = s .. getHelpTextForUnitAttributes(unitType, nil);

			-- Player Perks
			if includeFreePromotions and includeFreePromotions == true then
				local temp = getHelpTextForUnitPlayerPerkBuffs(unitType, playerID, nil);
				if temp ~= "" then
					if s ~= "" then
						s = s .. "[NEWLINE]";
					end
					s = s .. temp;
				end
			end

			-- Promotions
			if includeFreePromotions and includeFreePromotions == true then
				local temp = getHelpTextForUnitInherentPromotions(unitType, nil);
				if temp ~= "" then
					if s ~= "" then
						s = s .. "[NEWLINE]";
					end
					s = s .. temp;
				end
			end

			-- Upgrades and Perks
			local player = Players[playerID];
			if player then
				local allPerks = player:GetPerksForUnit(unitType);
				local tempPerks = player:GetFreePerksForUnit(unitType);
				for _, perk in ipairs(tempPerks) do
					insert(allPerks, perk);
				end
				local ignoreCoreStats = true;
				local temp = getHelpTextForUnitPerks(allPerks, ignoreCoreStats, nil);
				if temp ~= "" then
					if s ~= "" then
						s = s .. "[NEWLINE]";
					end
					s = s .. temp;
				end
			end

			return s;
		end

		----------------------------------------------------------------
		----------------------------------------------------------------
		-- UNIT MISCELLANY
		-- Stuff not covered by promotions or perks
		----------------------------------------------------------------
		----------------------------------------------------------------
		function GetUpgradedUnitDescriptionKey(player, unitType)
			local descriptionKey = "";
			local unitInfo = GameInfo.Units[unitType];
			if unitInfo then
				descriptionKey = unitInfo._Name or "???";
				if player then
					local bestUpgrade = player:GetBestUnitUpgrade(unitType);
					if bestUpgrade ~= -1 then
						local bestUpgradeInfo = GameInfo.UnitUpgrades[bestUpgrade];
						if bestUpgradeInfo then
							descriptionKey = bestUpgradeInfo._Name or "???";
						end
					end
				end
			end
			return descriptionKey;
		end

		--TODO: antonjs: Once we have a text budget and refactor time,
		--roll these miscellaneous things (player perks, attributes in
		--the base unit XML) in with existing unit buff systems
		--instead of being special case like this.
		function GetHelpTextForUnitAttributes(unitType, prefix)
			local s = "";
			local unitInfo = GameInfo.Units[unitType];
			if unitInfo then
				if unitInfo.OrbitalAttackRange >= 0 then
					if s ~= "" then
						s = s .. "[NEWLINE]";
					end
					if prefix then
						s = s .. prefix;
					end
					s = s .. L"TXT_KEY_INTERFACEMODE_ORBITAL_ATTACK";
				end
			end
			return s;
		end
		getHelpTextForUnitAttributes = GetHelpTextForUnitAttributes

		function GetHelpTextForUnitPlayerPerkBuffs(unitType, playerID, prefix)
			local s = "";
			local player = Players[playerID];
			local unitInfo = GameInfo.Units[ unitType ]
			if player and unitInfo then
				for info in GameInfo.PlayerPerks() do
					if player:HasPerk(info.ID) then
						if info.MiasmaBaseHeal > 0 or info.UnitPercentHealChange > 0 then
							if s ~= "" then
								s = s .. "[NEWLINE]";
							end
							if prefix then
								s = s .. prefix;
							end
							s = s .. L(GameInfo.PlayerPerks[info.ID].Help);
						end

						-- Help text for this player perk is inaccurate. Commencing hax0rs.
						if info.UnitFlatVisibilityChange > 0 then
							if s ~= "" then
								s = s .. "[NEWLINE]";
							end
							if prefix then
								s = s .. prefix;
							end
							s = s .. L("TXT_KEY_UNITPERK_VISIBILITY_CHANGE", info.UnitFlatVisibilityChange);
						end
					end
				end
			end
			return s;
		end
		getHelpTextForUnitPlayerPerkBuffs = GetHelpTextForUnitPlayerPerkBuffs

		----------------------------------------------------------------
		----------------------------------------------------------------
		-- UNIT PROMOTIONS
		----------------------------------------------------------------
		----------------------------------------------------------------
		function GetHelpTextForUnitInherentPromotions(unitType, prefix)
			local s = "";
			local unitInfo = GameInfo.Units[unitType];
			if unitInfo then
				for pairInfo in GameInfo.Unit_FreePromotions{ UnitType = unitInfo.Type } do
					local promotionInfo = GameInfo.UnitPromotions[pairInfo.PromotionType];
					if promotionInfo and promotionInfo.Help then
						if s ~= "" then
							s = s .. "[NEWLINE]";
						end
						if prefix then
							s = s .. prefix;
						end
						s = s .. L(promotionInfo.Help);
					end
				end
			end
			return s;
		end
		getHelpTextForUnitInherentPromotions = GetHelpTextForUnitInherentPromotions

		function GetHelpTextForUnitPromotions(unit, prefix)
			local s = "";
			for promotionInfo in GameInfo.UnitPromotions() do
				if unit:IsHasPromotion(promotionInfo.ID) then
					if s ~= "" then
						s = s .. "[NEWLINE]";
					end
					if prefix then
						s = s .. prefix;
					end
					s = s .. L(promotionInfo.Help);
				end
			end
			return s;
		end

		----------------------------------------------------------------
		----------------------------------------------------------------
		-- UNIT PERKS
		----------------------------------------------------------------
		----------------------------------------------------------------

		local function ComposeUnitPerkNumberHelpText(perkIDTable, textKey, numberKey, firstEntry, prefix)
			local s = "";
			local number = 0;
			for _, perkID in ipairs(perkIDTable) do
				local perkInfo = GameInfo.UnitPerks[perkID];
				if perkInfo and perkInfo[numberKey] and perkInfo[numberKey] ~= 0 then
					number = number + perkInfo[numberKey];
				end
			end

			if number ~= 0 then
				if not firstEntry then
					s = s .. "[NEWLINE]";
				end
				if prefix then
					s = s .. prefix;
				end
				s = s .. L(textKey, number);
			end

			return s;
		end

		local function ComposeUnitPerkFlagHelpText(perkIDTable, textKey, flagKey, firstEntry, prefix)
			local s = "";
			local flag = false;
			for _, perkID in ipairs(perkIDTable) do
				local perkInfo = GameInfo.UnitPerks[perkID];
				if perkInfo and perkInfo[flagKey] and perkInfo[flagKey] then
					flag = true;
					break;
				end
			end

			if flag then
				if not firstEntry then
					s = s .. "[NEWLINE]";
				end
				if prefix then
					s = s .. prefix;
				end
				s = s .. L(textKey);
			end

			return s;
		end


		local function ComposeUnitPerkDomainCombatModHelpText(perkIDTable, textKey, domainKey, firstEntry, prefix)
			local s = "";
			local number = 0;
			for _, perkID in ipairs(perkIDTable) do
				local perkInfo = GameInfo.UnitPerks[perkID];
				if perkInfo then
					for domainCombatInfo in GameInfo.UnitPerks_DomainCombatMods("UnitPerkType = \"" .. perkInfo.Type .. "\" AND DomainType = \"" .. domainKey .. "\"") do
						if domainCombatInfo.CombatMod ~= 0 then
							number = number + domainCombatInfo.CombatMod;
						end
					end
				end
			end

			if number ~= 0 then
				if not firstEntry then
					s = s .. "[NEWLINE]";
				end
				if prefix then
					s = s .. prefix;
				end
				s = s .. L(textKey, number);
			end

			return s;
		end

		function getHelpTextForUnitPerks(perkIDTable, ignoreCoreStats, prefix)
			local s = "";

			-- Text key overrides
			local filteredPerkIDTable = {};
			for _, perkID in ipairs(perkIDTable) do
				local perkInfo = GameInfo.UnitPerks[perkID];
				if perkInfo then
					if perkInfo.Help then
						if s ~= "" then
							s = s .. "[NEWLINE]";
						end
						if prefix then
							s = s .. prefix;
						end
						s = s .. L(perkInfo.Help);
					else
						insert(filteredPerkIDTable, perkID);
					end
				end
			end

			-- Basic Attributes
			if not ignoreCoreStats then
				s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_EXTRA_COMBAT_STRENGTH", "ExtraCombatStrength", s == "", prefix);
				s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_EXTRA_RANGED_COMBAT_STRENGTH", "ExtraRangedCombatStrength", s == "", prefix);
			end
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_RANGE_CHANGE", "RangeChange", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_RANGE_AT_FULL_HEALTH_CHANGE", "RangeAtFullHealthChange", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_RANGE_AT_FULL_MOVES_CHANGE", "RangeAtFullMovesChange", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_RANGE_FOR_ONBOARD_CHANGE", "RangeForOnboardChange", s == "", prefix);
			if not ignoreCoreStats then
				s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_MOVES_CHANGE", "MovesChange", s == "", prefix);
			end
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_VISIBILITY_CHANGE", "VisibilityChange", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_CARGO_CHANGE", "CargoChange", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_RANGE_AGAINST_ORBITAL_CHANGE", "RangeAgainstOrbitalChange", s == "", prefix);
			-- General combat
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ATTACK_MOD", "AttackMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ATTACK_FORTIFIED_MOD", "AttackFortifiedMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ATTACK_WOUNDED_MOD", "AttackWoundedMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ATTACK_WHILE_IN_MIASMA_MOD", "AttackWhileInMiasmaMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ATTACK_CITY_MOD", "AttackCityMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ATTACK_FOR_ONBOARD_MOD", "AttackForOnboardMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_DEFEND_MOD", "DefendMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_DEFEND_RANGED_MOD", "DefendRangedMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_DEFEND_WHILE_IN_MIASMA_MOD", "DefendWhileInMiasmaMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_DEFEND_FOR_ONBOARD_MOD", "DefendForOnboardMod", s == "", prefix);
			-- Air combat
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ATTACK_WITH_AIR_SWEEP_MOD", "AttackWithAirSweepMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ATTACK_WITH_INTERCEPTION_MOD", "AttackWithInterceptionMod", s == "", prefix);
			-- Territory
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_FRIENDLY_LANDS_MOD", "FriendlyLandsMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_OUTSIDE_FRIENDLY_LANDS_MOD", "OutsideFriendlyLandsMod", s == "", prefix);
			-- Battlefield position
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ADJACENT_FRIENDLY_MOD", "AdjacentFriendlyMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_PER_ADJACENT_FRIENDLY_MOD", "PerAdjacentFriendlyMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_NO_ADJACENT_FRIENDLY_MOD", "NoAdjacentFriendlyMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_FLANKING_MOD", "FlankingMod", s == "", prefix);
			-- Other conditional bonuses
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ALIEN_COMBAT_MOD", "AlienCombatMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_FORTIFIED_MOD", "FortifiedMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_CITY_MOD", "CityMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_PER_UNUSED_MOVE_MOD", "PerUnusedMoveMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_DAMAGE_TO_ADJACENT_UNITS_ON_DEATH", "DamageToAdjacentUnitsOnDeath", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_DAMAGE_TO_ADJACENT_UNITS_ON_ATTACK", "DamageToAdjacentUnitsOnAttack", s == "", prefix);
			-- Attack logistics
			s = s .. ComposeUnitPerkFlagHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_IGNORE_RANGED_ATTACK_LINE_OF_SIGHT", "IgnoreRangedAttackLineOfSight", s == "", prefix);
			s = s .. ComposeUnitPerkFlagHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_MELEE_ATTACK_HEAVY_CHARGE", "MeleeAttackHeavyCharge", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_EXTRA_ATTACKS", "ExtraAttacks", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_EXTRA_INTERCEPTIONS", "ExtraInterceptions", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_RANGED_ATTACK_SETUPS_NEEDED_MOD", "RangedAttackSetupsNeededMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_RANGED_ATTACK_SCATTER_CHANCE_MOD", "RangedAttackScatterChanceMod", s == "", prefix);
			-- Movement logistics
			s = s .. ComposeUnitPerkFlagHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_MOVE_AFTER_ATTACKING", "MoveAfterAttacking", s == "", prefix);
			s = s .. ComposeUnitPerkFlagHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_IGNORE_TERRAIN_COST", "IgnoreTerrainCost", s == "", prefix);
			s = s .. ComposeUnitPerkFlagHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_IGNORE_PILLAGE_COST", "IgnorePillageCost", s == "", prefix);
			s = s .. ComposeUnitPerkFlagHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_IGNORE_ZONE_OF_CONTROL", "IgnoreZoneOfControl", s == "", prefix);
			s = s .. ComposeUnitPerkFlagHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_FLAT_MOVEMENT_COST", "FlatMovementCost", s == "", prefix);
			s = s .. ComposeUnitPerkFlagHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_MOVE_ANYWHERE", "MoveAnywhere", s == "", prefix);
			-- Don't show "Hover", since it is redundant with the descriptions for "FlatMovementCost" and "MoveAnywhere"
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_WITHDRAW_FROM_MELEE_CHANCE_MOD", "WithdrawFromMeleeChanceMod", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_FREE_REBASES", "FreeRebases", s == "", prefix);
			-- Healing
			s = s .. ComposeUnitPerkFlagHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ALWAYS_HEAL", "AlwaysHeal", s == "", prefix);
			s = s .. ComposeUnitPerkFlagHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_HEAL_OUTSIDE_FRIENDLY_TERRITORY", "HealOutsideFriendlyTerritory", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ENEMY_HEAL_CHANGE", "EnemyHealChange", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_NEUTRAL_HEAL_CHANGE", "NeutralHealChange", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_FRIENDLY_HEAL_CHANGE", "FriendlyHealChange", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_MIASMA_HEAL_CHANGE", "MiasmaHealChange", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ADJACENT_UNIT_HEAL_CHANGE", "AdjacentUnitHealChange", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_SAME_TILE_HEAL_CHANGE", "SameTileHealChange", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_KILL_UNIT_HEAL_CHANGE", "KillUnitHealChange", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_PILLAGE_HEAL_CHANGE", "PillageHealChange", s == "", prefix);
			-- Orbital layer
			s = s .. ComposeUnitPerkFlagHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_GENERATE_MIASMA_IN_ORBIT", "GenerateMiasmaInOrbit", s == "", prefix);
			s = s .. ComposeUnitPerkFlagHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ALLOW_MANUAL_DEORBIT", "AllowManualDeorbit", s == "", prefix);
			s = s .. ComposeUnitPerkNumberHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_ORBITAL_COVERAGE_RADIUS_CHANGE", "OrbitalCoverageRadiusChange", s == "", prefix);
			-- Attrition
			-- Actions
			-- Domain combat mods
			s = s .. ComposeUnitPerkDomainCombatModHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_DOMAIN_COMBAT_MOD_LAND", "DOMAIN_LAND", s == "", prefix);
			s = s .. ComposeUnitPerkDomainCombatModHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_DOMAIN_COMBAT_MOD_SEA", "DOMAIN_SEA", s == "", prefix);
			s = s .. ComposeUnitPerkDomainCombatModHelpText(filteredPerkIDTable, "TXT_KEY_UNITPERK_DOMAIN_COMBAT_MOD_AIR", "DOMAIN_AIR", s == "", prefix);

			return s;
		end
		GetHelpTextForUnitPerks = getHelpTextForUnitPerks

		function GetHelpTextForUnitPerk( perkID )
			return getHelpTextForUnitPerks( {perkID}, false )
		end

		----------------------------------------------------------------
		----------------------------------------------------------------
		-- VIRTUES
		----------------------------------------------------------------
		----------------------------------------------------------------

		local function ComposeVirtueNumberHelpText(virtueIDTable, textKey, numberKey, firstEntry, postProcessFunction)
			local s = "";
			local number = 0;
			for _, virtueID in ipairs(virtueIDTable) do
				local virtueInfo = GameInfo.Policies[virtueID];
				if virtueInfo and virtueInfo[numberKey] and virtueInfo[numberKey] ~= 0 then
					number = number + virtueInfo[numberKey];
				end
			end

			if number ~= 0 then
				if postProcessFunction then
					number = postProcessFunction(number);
				end
				if not firstEntry then
					s = s .. "[NEWLINE]";
				else
					firstEntry = false;
				end
				s = s .. "[ICON_BULLET]";
				s = s .. L(textKey, number);
			end

			return s;
		end

		local function ComposeVirtueFlagHelpText(virtueIDTable, textKey, flagKey, firstEntry)
			local s = "";
			local flag = false;
			for _, virtueID in ipairs(virtueIDTable) do
				local virtueInfo = GameInfo.Policies[virtueID];
				if virtueInfo and virtueInfo[flagKey] and virtueInfo[flagKey] then
					flag = true;
					break;
				end
			end

			if flag then
				if not firstEntry then
					s = s .. "[NEWLINE]";
				else
					firstEntry = false;
				end
				s = s .. "[ICON_BULLET]";
				s = s .. L(textKey);
			end

			return s;
		end

		local function ComposeVirtueInterestHelpText(virtueIDTable, textKey, numberKey, firstEntry)
			local s = "";
			local interestPercent = 0;
			for _, virtueID in ipairs(virtueIDTable) do
				local virtueInfo = GameInfo.Policies[virtueID];
				if virtueInfo and virtueInfo[numberKey] and virtueInfo[numberKey] ~= 0 then
					interestPercent = interestPercent + virtueInfo[numberKey];
				end
			end

			if interestPercent ~= 0 then
				local maximum = (interestPercent * GameDefines["ENERGY_INTEREST_PRINCIPAL_MAXIMUM"]) / 100;
				if not firstEntry then
					s = s .. "[NEWLINE]";
				else
					firstEntry = false;
				end
				s = s .. "[ICON_BULLET]";
				s = s .. L(textKey, interestPercent, maximum);
			end

			return s;
		end

		local function ComposeVirtueYieldHelpText(virtueIDTable, textKey, tableKey, firstEntry, postProcessFunction)
			local s = "";
			for _, virtueID in ipairs(virtueIDTable) do
				local virtueInfo = GameInfo.Policies[virtueID];
				if virtueInfo and GameInfo[tableKey] then
					for tableInfo in GameInfo[tableKey]("PolicyType = \"" .. virtueInfo.Type .. "\"") do
						if tableInfo.YieldType and tableInfo.Yield then
							local yieldInfo = GameInfo.Yields[tableInfo.YieldType];
							local yieldNumber = tableInfo.Yield;
							if yieldNumber ~= 0 then
								if postProcessFunction then
									yieldNumber = postProcessFunction(yieldNumber);
								end
								if not firstEntry then
									s = s .. "[NEWLINE]";
								else
									firstEntry = false;
								end
								s = s .. "[ICON_BULLET]";
								s = s .. L( textKey, yieldNumber, yieldInfo.IconString or "?", yieldInfo._Name or "???" );
							end
						end
					end
				end
			end
			return s;
		end

		local function ComposeVirtueResourceClassYieldHelpText(virtueIDTable, textKey, firstEntry)
			local s = "";
			for _, virtueID in ipairs(virtueIDTable) do
				local virtueInfo = GameInfo.Policies[virtueID];
				if virtueInfo then
					for tableInfo in GameInfo.Policy_ResourceClassYieldChanges("PolicyType = \"" .. virtueInfo.Type .. "\"") do
						local resourceClassInfo = GameInfo.ResourceClasses[tableInfo.ResourceClassType];
						local yieldInfo = GameInfo.Yields[tableInfo.YieldType];
						local yieldNumber = tableInfo.YieldChange;
						if yieldNumber ~= 0 then
							if not firstEntry then
								s = s .. "[NEWLINE]";
							else
								firstEntry = false;
							end
							s = s .. "[ICON_BULLET]";
							s = s .. L( textKey, yieldNumber, yieldInfo.IconString or "?", yieldInfo._Name or "???", resourceClassInfo._Name or "???" );
						end
					end
				end
			end
			return s;
		end

		local function ComposeVirtueImprovementYieldHelpText(virtueIDTable, textKey, firstEntry)
			local s = "";
			for _, virtueID in ipairs(virtueIDTable) do
				local virtueInfo = GameInfo.Policies[virtueID];
				if virtueInfo then
					for tableInfo in GameInfo.Policy_ImprovementYieldChanges("PolicyType = \"" .. virtueInfo.Type .. "\"") do
						local improvementInfo = GameInfo.Improvements[tableInfo.ImprovementType];
						local yieldInfo = GameInfo.Yields[tableInfo.YieldType];
						local yieldNumber = tableInfo.Yield;
						if yieldNumber ~= 0 then
							if not firstEntry then
								s = s .. "[NEWLINE]";
							else
								firstEntry = false;
							end
							s = s .. "[ICON_BULLET]";
							s = s .. L(textKey, yieldNumber, yieldInfo.IconString or "?", yieldInfo._Name or "???", improvementInfo._Name or "???" );
						end
					end
				end
			end
			return s;
		end

		local function ComposeVirtueFreeUnitHelpText(virtueIDTable, textKey, firstEntry)
			local s = "";
			for _, virtueID in ipairs(virtueIDTable) do
				local virtueInfo = GameInfo.Policies[virtueID];
				if virtueInfo then
					for tableInfo in GameInfo.Policy_FreeUnitClasses("PolicyType = \"" .. virtueInfo.Type .. "\"") do
						local unitClassInfo = GameInfo.UnitClasses[tableInfo.UnitClassType];
						local unitInfo = GameInfo.Units[unitClassInfo.DefaultUnit];
						if unitInfo then
							if not firstEntry then
								s = s .. "[NEWLINE]";
							else
								firstEntry = false;
							end
							s = s .. "[ICON_BULLET]";
							s = s .. L(textKey, unitInfo._Name or "???");
						end
					end
				end
			end
			return s;
		end

		local function getHelpTextForVirtues(virtueIDTable)
			local s = "";

			-- Post-processing functions to display values more clearly to player
			local divByHundred = function(number)
				-- Some database values are in multiplied by 100 to match game core usage
				number = number * 0.01;
				return number;
			end;
			local flipSign = function(number)
				number = number * -1;
				return number;
			end;
			local modByGameResearchSpeed = function(number)
				local gameSpeedResearchMod = 1;
				if Game then
					gameSpeedResearchMod = Game.GetResearchPercent() / 100;
				end
				number = number * gameSpeedResearchMod;
				number = floor(number); -- for display, truncate trailing decimals
				return number;
			end;

			s = s .. ComposeVirtueFlagHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_CAPTURE_OUTPOSTS_FOR_SELF", "CaptureOutpostsForSelf", s == "");

			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_BARBARIAN_COMBAT_BONUS", "BarbarianCombatBonus", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_RESEARCH_FROM_BARBARIAN_KILLS", "ResearchFromBarbarianKills", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_RESEARCH_FROM_BARBARIAN_CAMPS", "ResearchFromBarbarianCamps", s == "", modByGameResearchSpeed); --value modified by game speed
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_EXP_MODIFIER", "ExpModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_MILITARY_PRODUCTION_MODIFIER", "MilitaryProductionModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_HEALTH_PER_MILITARY_UNIT_TIMES_100", "HealthPerMilitaryUnitTimes100", s == "", divByHundred); --value in hundredths
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_TECH_AFFINITY_XP_MODIFIER", "TechAffinityXPModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_COVERT_OPS_INTRIGUE_MODIFIER", "CovertOpsIntrigueModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_NUM_FREE_AFFINITY_LEVELS", "NumFreeAffinityLevels", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_UNIT_PRODUCTION_MODIFIER_PER_UPGRADE", "UnitProductionModifierPerUpgrade", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_STRATEGIC_RESOURCE_MOD", "StrategicResourceMod", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_ORBITAL_COVERAGE_RADIUS_FROM_STATION_TRADE", "OrbitalCoverageRadiusFromStationTrade", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_UNIT_GOLD_MAINTENANCE_MOD", "UnitGoldMaintenanceMod", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_COMBAT_MODIFIER", "CombatModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_OUTPOST_GROWTH_MODIFIER", "OutpostGrowthModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_FOOD_KEPT_AFTER_GROWTH_PERCENT", "FoodKeptAfterGrowthPercent", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_WORKER_SPEED_MODIFIER", "WorkerSpeedModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_PLOT_CULTURE_COST_MODIFIER", "PlotCultureCostModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_EXPLORER_EXPEDITION_CHARGES", "ExplorerExpeditionCharges", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_LAND_TRADE_ROUTE_GOLD_CHANGE", "LandTradeRouteGoldChange", s == "", divByHundred); --value in hundredths
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_SEA_TRADE_ROUTE_GOLD_CHANGE", "SeaTradeRouteGoldChange", s == "", divByHundred); --value in hundredths
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_NEW_CITY_EXTRA_POPULATION", "NewCityExtraPopulation", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_EXTRA_HEALTH", "ExtraHealth", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_EXTRA_HEALTH_PER_LUXURY", "HealthPerBasicResourceTypeTimes100", s == "", divByHundred); --value in hundredths
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_UNHEALTH_MOD", "UnhealthMod", s == "", flipSign); --less confusing to show as a positive number in text
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_RESEARCH_MOD_PER_EXTRA_CONNECTED_TECH", "ResearchModPerExtraConnectedTech", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_HEALTH_TO_SCIENCE", "HealthToScience", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_HEALTH_TO_CULTURE", "HealthToCulture", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_POLICY_COST_MODIFIER", "PolicyCostModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_PERCENT_CULTURE_RATE_TO_ENERGY", "PercentCultureRateToEnergy", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_HEALTH_PER_X_POPULATION", "HealthPerXPopulation", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_NUM_CITIES_RESEARCH_COST_DISCOUNT", "NumCitiesResearchCostDiscount", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_NUM_CITIES_POLICY_COST_DISCOUNT", "NumCitiesPolicyCostDiscount", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_LEAF_TECH_RESEARCH_MODIFIER", "LeafTechResearchModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_PERCENT_CULTURE_RATE_TO_RESEARCH", "PercentCultureRateToResearch", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_CULTURE_PER_WONDER", "CulturePerWonder", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_BUILDING_PRODUCTION_MODIFIER", "BuildingProductionModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_WONDER_PRODUCTION_MODIFIER", "WonderProductionModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_BUILDING_ALREADY_IN_CAPITAL_MODIFIER", "BuildingAlreadyInCapitalModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_INTERNAL_TRADE_ROUTE_YIELD_MODIFIER", "InternalTradeRouteYieldModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_HEALTH_PER_TRADE_ROUTE_TIMES_100", "HealthPerTradeRouteTimes100", s == "", divByHundred); --value in hundredths
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_ORBITAL_PRODUCTION_MODIFIER", "OrbitalProductionModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_ORBITAL_DURATION_MODIFIER", "OrbitalDurationModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_UNIT_PURCHASE_COST_MODIFIER", "UnitPurchaseCostModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_HEALTH_PER_BUILDING_TIMES_100", "HealthPerBuildingTimes100", s == "", divByHundred); --value in hundredths
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_EXTRA_HEALTH_PER_CITY", "ExtraHealthPerCity", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_NUM_FREE_TECHS", "NumFreeTechs", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_NUM_FREE_POLICIES", "NumFreePolicies", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_NUM_FREE_COVERT_AGENTS", "NumFreeCovertAgents", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_ORBITAL_COVERAGE_MODIFIER", "OrbitalCoverageModifier", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_RESEARCH_FROM_EXPEDITIONS", "ResearchFromExpeditions", s == "", modByGameResearchSpeed); --value modified by game speed
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_CITY_GROWTH_MOD", "CityGrowthMod", s == "");
			s = s .. ComposeVirtueNumberHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_CAPITAL_GROWTH_MOD", "CapitalGrowthMod", s == "");

			s = s .. ComposeVirtueInterestHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_ENERGY_INTEREST_PERCENT_PER_TURN", "EnergyInterestPercentPerTurn", s == "");

			s = s .. ComposeVirtueYieldHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_YIELD_MODIFIER", "Policy_YieldModifiers", s == "");
			s = s .. ComposeVirtueYieldHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_CAPITAL_YIELD_MODIFIER", "Policy_CapitalYieldModifiers", s == "");
			s = s .. ComposeVirtueYieldHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_CITY_YIELD_CHANGE", "Policy_CityYieldChanges", s == "");
			s = s .. ComposeVirtueYieldHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_CITY_YIELD_PER_POP_CHANGE", "Policy_CityYieldPerPopChanges", s == "", divByHundred); --value in hundredths
			s = s .. ComposeVirtueYieldHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_CAPITAL_YIELD_CHANGE", "Policy_CapitalYieldChanges", s == "");
			s = s .. ComposeVirtueYieldHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_SPECIALIST_EXTRA_YIELD", "Policy_SpecialistExtraYields", s == "");
			s = s .. ComposeVirtueYieldHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_TRADE_ROUTE_WITH_STATION_PER_TIER_YIELD_CHANGE", "Policy_TradeRouteWithStationPerTierYieldChanges", s == "");

			s = s .. ComposeVirtueResourceClassYieldHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_RESOURCE_CLASS_YIELD_CHANGE", s == "");

			s = s .. ComposeVirtueImprovementYieldHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_IMPROVEMENT_YIELD_CHANGE", s == "");

			s = s .. ComposeVirtueFreeUnitHelpText(virtueIDTable, "TXT_KEY_POLICY_EFFECT_FREE_UNIT_CLASS", s == "");

			return s;
		end
		GetHelpTextForVirtues = getHelpTextForVirtues

		function GetHelpTextForVirtue(virtueID)
			return getHelpTextForVirtues{virtueID}
		end

		----------------------------------------------------------------
		----------------------------------------------------------------
		-- AFFINITIES
		----------------------------------------------------------------
		----------------------------------------------------------------
		function GetHelpTextForAffinity(affinityID, player)
			local s = "";
			local affinityInfo = GameInfo.Affinity_Types[affinityID]
			if affinityInfo then

				local currentLevel = -1;
				if player then
					-- Current level
					s = s .. L("TXT_KEY_AFFINITY_STATUS_DETAIL", affinityInfo.IconString or "?", affinityInfo.ColorType, affinityInfo._Name or "???", player:GetAffinityLevel(affinityInfo.ID));
					s = s .. "[NEWLINE][NEWLINE]";
					currentLevel = player:GetAffinityLevel(affinityID);
				end

				-- Player perks we can earn
				local firstEntry = true;
				for levelInfo in GameInfo.Affinity_Levels() do
					local levelText = getHelpTextForAffinityLevel(affinityID, levelInfo.ID);
					if levelText ~= "" then
						levelText = ( affinityInfo.IconString or "?" ) .. "[" .. affinityInfo.ColorType .. "]" .. levelInfo.ID .. "[ENDCOLOR] : " .. levelText;

						if levelInfo.ID <= currentLevel then
							levelText = "[" .. affinityInfo.ColorType .. "]" .. levelText .. "[ENDCOLOR]";
						end

						if firstEntry then
							firstEntry = false;
						else
							s = s .. "[NEWLINE]";
						end

						s = s .. levelText;
					end
				end

				if player then
					local nextLevel = player:GetAffinityLevel(affinityID) + 1;
					local nextLevelInfo = GameInfo.Affinity_Levels[nextLevel];

					-- Progress towards next level
					if nextLevelInfo then
						s = s .. "[NEWLINE][NEWLINE]";
						s = s .. L("TXT_KEY_AFFINITY_STATUS_PROGRESS", player:GetAffinityScoreTowardsNextLevel(affinityInfo.ID), player:CalculateAffinityScoreNeededForNextLevel(affinityInfo.ID));
					else
						s = s .. "[NEWLINE][NEWLINE]";
						s = s .. L"TXT_KEY_AFFINITY_STATUS_MAX_LEVEL";
					end

					-- Dominance
					local isDominant = affinityInfo.ID == player:GetDominantAffinityType();
					if nextLevelInfo then
						local penalty = nextLevelInfo.AffinityValueNeededAsNonDominant - nextLevelInfo.AffinityValueNeededAsDominant;
						-- Only show dominance once we are at the point where the level curve diverges
						if penalty > 0 then
							if isDominant then
								s = s .. "[NEWLINE][NEWLINE]";
								s = s .. L"TXT_KEY_AFFINITY_STATUS_DOMINANT";
							else
								s = s .. "[NEWLINE][NEWLINE]";
								s = s .. L("TXT_KEY_AFFINITY_STATUS_NON_DOMINANT_PENALTY", penalty);
							end
						end
					elseif isDominant then
						-- Or once we have reached max level
						s = s .. "[NEWLINE][NEWLINE]";
						s = s .. L"TXT_KEY_AFFINITY_STATUS_DOMINANT";
					end
				end
			end
			return s;
		end

		local g_playerPerkKey = { [GameInfoTypes.AFFINITY_TYPE_HARMONY] = "HarmonyPlayerPerk", [GameInfoTypes.AFFINITY_TYPE_PURITY] = "PurityPlayerPerk", [GameInfoTypes.AFFINITY_TYPE_SUPREMACY] = "SupremacyPlayerPerk" }
		-- Does not include unit upgrade unlocks
		function getHelpTextForAffinityLevel( affinityID, affinityLevel )
			local tips = {}
			local tip
			local affinityInfo = GameInfo.Affinity_Types[ affinityID ]
			local affinityLevelInfo = GameInfo.Affinity_Levels[ affinityLevel ]
			if affinityInfo and affinityLevelInfo then

				-- Gained a Player Perk?
				local perkInfo = GameInfo.PlayerPerks[ affinityLevelInfo[ g_playerPerkKey[affinityID] ] ]
				if perkInfo then
					insert( tips, L( perkInfo.Help ) )
				end

				-- Unlocked Covert Ops?
				for row in GameInfo.CovertOperation_AffinityPrereqs{ AffinityType = affinityInfo.Type, Level = affinityLevel } do
					local covertOpInfo = GameInfo.CovertOperations[ row.CovertOperationType ] or {}
					insert( tips, L( "TXT_KEY_AFFINITY_LEVEL_UP_DETAILS_COVERT_OP_UNLOCKED", covertOpInfo._Name or "???" ) )
				end

				-- Unlocked Projects (for Victory)?
				for row in GameInfo.Project_AffinityPrereqs{ AffinityType = affinityInfo.Type, Level = affinityLevel } do
					local projectInfo = GameInfo.Projects[ row.ProjectType ] or {}
					local victoryInfo = GameInfo.Victories[ projectInfo.VictoryPrereq ] or {}
					insert( tips, L( "TXT_KEY_AFFINITY_LEVEL_UP_DETAILS_PROJECT_UNLOCKED", projectInfo._Name or "???", victoryInfo._Name or "???" ) )
				end

				-- Unlocked Units
				for affinity in GameInfo.Unit_AffinityPrereqs{ AffinityType = affinityInfo.Type, Level = affinityLevel } do
					local unit = GameInfo.Units[affinity.UnitType]
					if unit then
						tip = UnitColor( unit._Name )
						if (unit.RangedCombat or 0) > 0 then
							tip = format("%s %i[ICON_RANGE_STRENGTH]", tip, unit.RangedCombat )
						elseif (unit.Combat or 0) > 0 then
							tip = format("%s %i[ICON_STRENGTH]", tip, unit.Combat )
						end
						insert( tips, tip )
					end
				end

				-- Unlocked Buildings
				for affinity in GameInfo.Building_AffinityPrereqs{ AffinityType = affinityInfo.Type, Level = affinityLevel } do
					local building = GameInfo.Buildings[ affinity.BuildingType ]
					if building then
						insert( tips, BuildingColor( building._Name ) )
					end
				end
			end
			return concat( tips, ", " )
		end
		GetHelpTextForAffinityLevel = getHelpTextForAffinityLevel
		function CacheDatabaseQueries() end
	end
end