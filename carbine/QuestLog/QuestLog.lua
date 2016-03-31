-----------------------------------------------------------------------------------------------
-- Client Lua Script for QuestLog
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------

require "Window"
require "Quest"
require "QuestLib"
require "QuestCategory"
require "Unit"
require "Episode"
require "Money"

local QuestLog = {}

function QuestLog:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    return o
end

function QuestLog:Init()
    Apollo.RegisterAddon(self)
end

local knEpisodeInfoBuffer = 10

local ktChatNotificationStrings =
{
	[Quest.QuestState_Accepted] 	= Apollo.GetString("QuestLog_QuestAccepted"),
	[Quest.QuestState_Completed] 	= Apollo.GetString("QuestLog_QuestComplete"),
	[Quest.QuestState_Botched] 		= Apollo.GetString("QuestLog_QuestFailed"),
	[Quest.QuestState_Abandoned] 	= Apollo.GetString("QuestLog_QuestAbandoned"),
}

-- Constants
local ktConToUI =
{
	{ "CRB_Basekit:kitFixedProgBar_1", "ff9aaea3", Apollo.GetString("QuestLog_Trivial") },
	{ "CRB_Basekit:kitFixedProgBar_2", "ff37ff00", Apollo.GetString("QuestLog_Easy") },
	{ "CRB_Basekit:kitFixedProgBar_3", "ff46ffff", Apollo.GetString("QuestLog_Simple") },
	{ "CRB_Basekit:kitFixedProgBar_4", "ff3052fc", Apollo.GetString("QuestLog_Standard") },
	{ "CRB_Basekit:kitFixedProgBar_5", "ffffffff", Apollo.GetString("QuestLog_Average") },
	{ "CRB_Basekit:kitFixedProgBar_6", "ffffd400", Apollo.GetString("QuestLog_Moderate") },
	{ "CRB_Basekit:kitFixedProgBar_7", "ffff6a00", Apollo.GetString("QuestLog_Tough") },
	{ "CRB_Basekit:kitFixedProgBar_8", "ffff0000", Apollo.GetString("QuestLog_Hard") },
	{ "CRB_Basekit:kitFixedProgBar_9", "fffb00ff", Apollo.GetString("QuestLog_Impossible") }
}

local ktValidCallButtonStats =
{
	[Quest.QuestState_Ignored] 		= true,
	[Quest.QuestState_Achieved] 	= true,
	[Quest.QuestState_Abandoned] 	= true,
	[Quest.QuestState_Botched] 		= true,
	[Quest.QuestState_Mentioned] 	= true,
}

local karEvalColors =
{
	[Item.CodeEnumItemQuality.Inferior] 		= ApolloColor.new("ItemQuality_Inferior"),
	[Item.CodeEnumItemQuality.Average] 			= ApolloColor.new("ItemQuality_Average"),
	[Item.CodeEnumItemQuality.Good] 			= ApolloColor.new("ItemQuality_Good"),
	[Item.CodeEnumItemQuality.Excellent] 		= ApolloColor.new("ItemQuality_Excellent"),
	[Item.CodeEnumItemQuality.Superb] 			= ApolloColor.new("ItemQuality_Superb"),
	[Item.CodeEnumItemQuality.Legendary] 		= ApolloColor.new("ItemQuality_Legendary"),
	[Item.CodeEnumItemQuality.Artifact]		 	= ApolloColor.new("ItemQuality_Artifact"),
}

function QuestLog:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("QuestLog.xml")-- QuestLog will always be kept in memory, so save parsing it over and over
	self.xmlDoc:RegisterCallback("OnDocumentReady", self)

	Apollo.RegisterEventHandler("InterfaceMenuListHasLoaded", "OnInterfaceMenuListHasLoaded", self)
end

function QuestLog:OnDocumentReady()
	if self.xmlDoc == nil then
		return
	end

	Apollo.RegisterEventHandler("ShowQuestLog", 		"Initialize", self)
	Apollo.RegisterEventHandler("Dialog_QuestShare", 	"OnDialog_QuestShare", self)
	Apollo.RegisterTimerHandler("ShareTimeout", 		"OnShareTimeout", self)
	--Apollo.RegisterEventHandler("QuestStateChanged", 	"OnQuestStateChanged", self) -- Routes to OnDestroyQuestObject if completed/botched
	
	Apollo.RegisterEventHandler("EpisodeStateChanged",						"OnEpisodeStateChanged", self)
	Apollo.RegisterEventHandler("QuestStateChanged",						"OnQuestStateChanged", self)
	Apollo.RegisterEventHandler("QuestTrackedChanged",						"OnQuestTrackedChanged", self)
	Apollo.RegisterEventHandler("QuestObjectiveUpdated",					"OnQuestObjectiveUpdated", self)
	
	
	
	Apollo.RegisterEventHandler("Group_Join",			"OnGroupUpdate", self)
	Apollo.RegisterEventHandler("Group_Left",			"OnGroupUpdate", self)

end

function QuestLog:OnInterfaceMenuListHasLoaded()
	Event_FireGenericEvent("InterfaceMenuList_NewAddOn", Apollo.GetString("InterfaceMenu_QuestLog"), {"ToggleQuestLog", "Codex", "Icon_Windows32_UI_CRB_InterfaceMenu_QuestLog"})
end

function QuestLog:Initialize()
	if (self.wndMain and self.wndMain:IsValid()) or not g_wndProgressLog then
		return
	end

	Apollo.RegisterEventHandler("GenericEvent_ShowQuestLog", 	"OnGenericEvent_ShowQuestLog", self)

    self.wndMain = Apollo.LoadForm(self.xmlDoc, "QuestLogForm", g_wndProgressLog:FindChild("ContentWnd_1"), self)
	self.wndLeftFilterActive = self.wndMain:FindChild("LeftSideFilterBtnsBG:LeftSideFilterBtnShowActive")
	self.wndLeftFilterFinished = self.wndMain:FindChild("LeftSideFilterBtnsBG:LeftSideFilterBtnShowFinished")
	self.wndLeftFilterHidden = self.wndMain:FindChild("LeftSideFilterBtnsBG:LeftSideFilterBtnShowHidden")
	self.wndLeftSideScroll = self.wndMain:FindChild("LeftSideScroll")
	self.wndRightSide = self.wndMain:FindChild("RightSide")
	self.wndQuestInfoControls = self.wndMain:FindChild("QuestInfoControls")

	-- Variables
	self.wndLastBottomLevelBtnSelection = nil -- Just for button pressed state faking of text color
	self.nQuestCountMax = QuestLib.GetMaxCount()
	self.arLeftTreeMap = {}
	self.tTreeQuestsById = {}

	-- Default states
	self.wndLeftFilterActive:SetCheck(true)
	self.wndMain:FindChild("QuestAbandonPopoutBtn"):AttachWindow(self.wndMain:FindChild("QuestAbandonConfirm"))
	self.wndMain:FindChild("EpisodeSummaryExpandBtn"):AttachWindow(self.wndMain:FindChild("EpisodeSummaryPopoutTextBG"))

	-- Measure Windows
	local wndMeasure = Apollo.LoadForm(self.xmlDoc, "TopLevelItem", nil, self)
	self.knTopLevelHeight = wndMeasure:GetHeight()
	wndMeasure:Destroy()

	wndMeasure = Apollo.LoadForm(self.xmlDoc, "MiddleLevelItem", nil, self)
	self.knMiddleLevelHeight = wndMeasure:GetHeight()
	wndMeasure:Destroy()

	wndMeasure = Apollo.LoadForm(self.xmlDoc, "BottomLevelItem", nil, self)
	self.knBottomLevelHeight = wndMeasure:GetHeight()
	wndMeasure:Destroy()

	wndMeasure = Apollo.LoadForm(self.xmlDoc, "ObjectivesItem", nil, self)
	self.knObjectivesItemHeight = wndMeasure:GetHeight()
	wndMeasure:Destroy()

	self.nRewardRecListHeight = self.wndMain:FindChild("QuestInfoRewardRecFrame"):GetHeight()
	self.nRewardChoListHeight = self.wndMain:FindChild("QuestInfoRewardChoFrame"):GetHeight()
	self.nMoreInfoHeight = self.wndMain:FindChild("QuestInfoMoreInfoFrame"):GetHeight()
	self.nEpisodeInfoHeight = self.wndMain:FindChild("EpisodeInfo"):GetHeight()

	self:DestroyAndRedraw()
end

function QuestLog:OnGenericEvent_ShowQuestLog(queTarget)
	if not queTarget then
		return
	end

	self.wndLeftFilterActive:SetCheck(true)
	self.wndLeftFilterHidden:SetCheck(false)
	self.wndLeftFilterFinished:SetCheck(false)
	self.wndLeftSideScroll:DestroyChildren()

	self:RedrawLeftTree() -- Add categories

	if queTarget:GetState() == Quest.QuestState_Unknown then
		self.wndQuestInfoControls:Show(false)

		self:DrawUnknownRightSide(queTarget)
		self:ResizeRight()
		self:ResizeTree()
		return
	end

	local qcTop = queTarget:GetCategory()
	local epiMid = queTarget:GetEpisode()
	
	local strCategoryKey
	local strEpisodeKey
	local strQuestKey

	if epiMid then
		if epiMid:IsWorldStory() then
			strCategoryKey = "CWorldStory"
			strEpisodeKey = strCategoryKey.."E"..epiMid:GetId()
			strQuestKey = strEpisodeKey.."Q"..queTarget:GetId()
		elseif epiMid:IsZoneStory() or epiMid:IsRegionalStory() then
			strCategoryKey = "C"..qcTop:GetId()
			strEpisodeKey = strCategoryKey.."E"..epiMid:GetId()
			strQuestKey = strEpisodeKey.."Q"..queTarget:GetId()
		else
			strCategoryKey = "C"..qcTop:GetId()
			strEpisodeKey = strCategoryKey.."ETasks"
			strQuestKey = strEpisodeKey.."Q"..queTarget:GetId()
		end
	end
	
	if qcTop then
		local wndTop = self.arLeftTreeMap[strCategoryKey]
		if wndTop ~= nil and wndTop:IsValid() then
			local wndTopLevelBtn = wndTop:FindChild("TopLevelBtn")
			wndTopLevelBtn:SetCheck(true)
			self:OnTopLevelBtnCheck(wndTopLevelBtn, wndTopLevelBtn)

			if epiMid then
				local wndMiddle = self.arLeftTreeMap[strEpisodeKey]
				if wndMiddle ~= nil and wndMiddle:IsValid() then

					local wndBot = self.arLeftTreeMap[strQuestKey]
					if wndBot ~= nil and wndBot:IsValid() then
						local wndBottomLevelBtn = wndBot:FindChild("BottomLevelBtn")
						wndBottomLevelBtn:SetCheck(true)
						self:OnBottomLevelBtnCheck(wndBottomLevelBtn, wndBottomLevelBtn)
					end
				end
			end
		end
	end

	self:ResizeTree()
	self:RedrawRight()
	
	local nVPos = 0
	
	local wndTop = self.arLeftTreeMap[strCategoryKey]
	if wndTop ~= nil and wndTop:IsValid() then
		nVPos = nVPos + ({wndTop:GetAnchorOffsets()})[2]
		
		local wndMiddle = self.arLeftTreeMap[strEpisodeKey]
		if wndMiddle ~= nil and wndMiddle:IsValid() then
			nVPos = nVPos + ({wndMiddle:GetAnchorOffsets()})[2]
			
			local wndBot = self.arLeftTreeMap[strQuestKey]
			if wndBot ~= nil and wndBot:IsValid() then
				nVPos = nVPos + ({wndBot:GetAnchorOffsets()})[2]
			end
		end
	end	
	
	self.wndLeftSideScroll:SetVScrollPos(nVPos)
end

function QuestLog:DestroyAndRedraw() -- TODO, remove as much as possible that calls this
	local nVScollPos = 0
	local strCategoryKey = self.strCurrentCategoryKey
	local strEpisodeKey = self.strCurrentEpisodeKey
	local strQuestKey = self.strCurrentQuestKey

	if self.wndMain and self.wndMain:IsValid() then
		nVScollPos = self.wndLeftSideScroll:GetVScrollPos()
		self.wndLeftSideScroll:DestroyChildren()
	end

	self.arLeftTreeMap = {}

	self:RedrawLeftTree() -- Add categories
	
	local function fnSelectFirstQuest(wndMiddleLevelItems)
		local wndBot = wndMiddleLevelItems:GetChildren()[1]
		if wndBot ~= nil then
			local wndBottomLevelBtn = wndBot:FindChild("BottomLevelBtn")
			wndBottomLevelBtn:SetCheck(true)
			self:OnBottomLevelBtnCheck(wndBottomLevelBtn, wndBottomLevelBtn)
		end
	end
	
	local function fnSelectFirstEpisode(wndTopLevelItems)
		local wndMiddle = wndTopLevelItems:GetChildren()[1]
		if wndMiddle then
			fnSelectFirstQuest(wndMiddle:FindChild("MiddleLevelItems"))
		end
	end
	
	local function fnSelectFirstCategory()
		local wndTop = self.wndLeftSideScroll:GetChildren()[1]
		if wndTop ~= nil then
			local wndTopLevelBtn = wndTop:FindChild("TopLevelBtn")
			wndTopLevelBtn:SetCheck(true)
			self:OnTopLevelBtnCheck(wndTopLevelBtn, wndTopLevelBtn)
			
			fnSelectFirstEpisode(wndTop:FindChild("TopLevelItems"))
		end
	end
	
	if strCategoryKey ~= nil then
		local wndTop = self.arLeftTreeMap[strCategoryKey]
		if wndTop ~= nil and wndTop:IsValid() then
			local wndTopLevelBtn = wndTop:FindChild("TopLevelBtn")
			wndTopLevelBtn:SetCheck(true)
			self:OnTopLevelBtnCheck(wndTopLevelBtn, wndTopLevelBtn)

			if strEpisodeKey then
				local wndMiddle = self.arLeftTreeMap[strEpisodeKey]
				if wndMiddle ~= nil and wndMiddle:IsValid() then

					if strQuestKey then
						local wndBot = self.arLeftTreeMap[strQuestKey]
						if wndBot ~= nil and wndBot:IsValid() then
							local wndBottomLevelBtn = wndBot:FindChild("BottomLevelBtn")
							wndBottomLevelBtn:SetCheck(true)
							self:OnBottomLevelBtnCheck(wndBottomLevelBtn, wndBottomLevelBtn)
						end
					else
						fnSelectFirstQuest(wndMiddle:FindChild("MiddleLevelItems"))
					end
				end
			else
				fnSelectFirstEpisode(wndTop:FindChild("TopLevelItems"))
			end
		end
	else
		fnSelectFirstCategory()
	end

	self:ResizeTree()
	self:RedrawRight()
	
	self.wndLeftSideScroll:SetVScrollPos(nVScollPos)
end

function QuestLog:RedrawLeftTreeFromUI()
	self:RedrawLeftTree()
	self:ResizeTree()
end

function QuestLog:RedrawFromUI()
	self:RedrawEverything()
end

function QuestLog:RedrawEverything()
	self:RedrawLeftTree()
	self:ResizeTree()

	local bLeftSideHasResults = #self.wndLeftSideScroll:GetChildren() ~= 0
	self.wndLeftSideScroll:SetText(bLeftSideHasResults and "" or Apollo.GetString("QuestLog_NoResults"))
	self.wndQuestInfoControls:Show(bLeftSideHasResults)
	self.wndRightSide:Show(bLeftSideHasResults)

	if self.wndRightSide:IsShown() and self.wndRightSide:GetData() then
		self:DrawRightSide(self.wndRightSide:GetData())
	end

	self:ResizeRight()
end

function QuestLog:RedrawRight()
	local bLeftSideHasResults = #self.wndLeftSideScroll:GetChildren() ~= 0
	self.wndLeftSideScroll:SetText(bLeftSideHasResults and "" or Apollo.GetString("QuestLog_NoResults"))
	self.wndQuestInfoControls:Show(bLeftSideHasResults)
	self.wndRightSide:Show(bLeftSideHasResults)

	if self.wndRightSide:IsShown() and self.wndRightSide:GetData() then
		self:DrawRightSide(self.wndRightSide:GetData())
	end

	self:ResizeRight()
end

function QuestLog:GetHaveWorldStoryQuestFunctions()
	local tEpisodeHasWorldStoryQuests = {}

	local function fnEpisodeHasWorldStoryQuests(arCategories, epiEpisode)
		if tEpisodeHasWorldStoryQuests[epiEpisode] ~= nil then
			return tEpisodeHasWorldStoryQuests[epiEpisode]
		end
	
		if epiEpisode:IsWorldStory() then
			for idx2, qcCategory in pairs(arCategories) do
				for idx3, queQuest in pairs(epiEpisode:GetAllQuests(qcCategory:GetId())) do
					if self:CheckLeftSideFilters(queQuest) then
						tEpisodeHasWorldStoryQuests[epiEpisode] = true
						return true
					end
				end
			end
		end
		tEpisodeHasWorldStoryQuests[epiEpisode] = false
		return false
	end

	local bHasWorldStoryQuests = nil

	local function fnHaveWorldStoryQuests(arCategories, arEpisodes)
		if bHasWorldStoryQuests ~= nil then
			return bHasWorldStoryQuests
		end
	
		for idx, epiEpisode in pairs(arEpisodes) do
			if fnEpisodeHasWorldStoryQuests(arCategories, epiEpisode) then
				bHasWorldStoryQuests = true
				return true
			end
		end
		bHasWorldStoryQuests = false
		return false
	end
	
	return fnHaveWorldStoryQuests, fnEpisodeHasWorldStoryQuests
end

function QuestLog:GetHaveQuestFunctions()
	local tCategoryEpisodeHaveQuestsCache = {}
	
	local fnDoesCategoryEpisodeHaveQuests = function(qcCategory, epiEpisode)
		local strEpisodeKey = "C"..qcCategory:GetId().."E"..epiEpisode:GetId()
		if tCategoryEpisodeHaveQuestsCache[strEpisodeKey] ~= nil then
			return tCategoryEpisodeHaveQuestsCache[strEpisodeKey]
		end

		if not epiEpisode:IsWorldStory() then
			for idx, queQuest in pairs(epiEpisode:GetAllQuests(qcCategory:GetId())) do
				if self:CheckLeftSideFilters(queQuest) then
					tCategoryEpisodeHaveQuestsCache[strEpisodeKey] = true
					return true
				end
			end
		end
		tCategoryEpisodeHaveQuestsCache[strEpisodeKey] = false
		return false
	end

	local tCategoryHaveQuestsCache = {}
	
	local fnDoesCategoryHaveQuests = function(qcCategory)
		local strCategoryKey = "C"..qcCategory:GetId()
		if tCategoryHaveQuestsCache[strCategoryKey] ~= nil then
			return tCategoryHaveQuestsCache[strCategoryKey]
		end

		for idx, epiEpisode in pairs(qcCategory:GetEpisodes()) do
			if fnDoesCategoryEpisodeHaveQuests(qcCategory, epiEpisode) then
				tCategoryHaveQuestsCache[strCategoryKey] = true
				return true
			end
		end
		tCategoryHaveQuestsCache[strCategoryKey] = false
		return false
	end
	
	return fnDoesCategoryHaveQuests, fnDoesCategoryEpisodeHaveQuests
end

function QuestLog:RedrawLeftTree()
	self.strCurrentCategoryKey = nil
	self.strCurrentEpisodeKey = nil
	self.strCurrentQuestKey = nil

	local nQuestCount = QuestLib.GetCount()
	local strColor = "UI_BtnTextGreenNormal"
	if nQuestCount + 3 >= self.nQuestCountMax then
		strColor = "ffff0000"
	elseif nQuestCount + 10 >= self.nQuestCountMax then
		strColor = "ffffb62e"
	end

	local strActiveQuests = string.format("<T TextColor=\"%s\">%s</T>", strColor, nQuestCount)
	strActiveQuests = String_GetWeaselString(Apollo.GetString("QuestLog_ActiveQuests"), strActiveQuests, self.nQuestCountMax)
	self.wndMain:FindChild("QuestLogCountText"):SetAML(string.format("<P Font=\"CRB_InterfaceTiny_BB\" Align=\"Left\" TextColor=\"UI_BtnTextGoldListNormal\">%s</P>", strActiveQuests))

	local bShowCompleted = self.wndLeftFilterFinished:IsChecked()
	
	local arAllCategories = QuestLib.GetKnownCategories()
	local arAllEpisodes = QuestLib.GetAllEpisodes(bShowCompleted, true)
	
	local fnHaveWorldStoryQuests, fnEpisodeHasWorldStoryQuests = self:GetHaveWorldStoryQuestFunctions()
	local fnDoesCategoryHaveQuests, fnDoesCategoryEpisodeHaveQuests = self:GetHaveQuestFunctions()
	
	if fnHaveWorldStoryQuests(arAllCategories, arAllEpisodes) then
		local strCategoryKey = "CWorldStory" -- Why can't we have nice things :(
		local wndTop = self:FactoryCacheProduce(self.wndLeftSideScroll, "TopLevelItem", strCategoryKey)
		wndTop:FindChild("TopLevelBtn"):SetText(Apollo.GetString("QuestLog_WorldStory"))
		
		wndTop:FindChild("TopLevelBtn"):SetData({
			wndTop = wndTop,
			strCategoryKey = strCategoryKey,
			bIsWorldStory = true
		})
	end
	
	for idx, qcCategory in pairs(arAllCategories) do
		if fnDoesCategoryHaveQuests(qcCategory) then
			local strCategoryKey = "C"..qcCategory:GetId()
			local wndTop = self:FactoryCacheProduce(self.wndLeftSideScroll, "TopLevelItem", strCategoryKey)
			wndTop:FindChild("TopLevelBtn"):SetText(qcCategory:GetTitle())
			
			wndTop:FindChild("TopLevelBtn"):SetData({
				wndTop = wndTop,
				strCategoryKey = strCategoryKey,
				qcCategory = qcCategory,
				bIsWorldStory = false
			})
		end
	end
end

function QuestLog:LeftTreeBuildWorldStoryEpisodes(wndTop, strCategoryKey)
	local bShowCompleted = self.wndLeftFilterFinished:IsChecked()

	local arAllCategories = QuestLib.GetKnownCategories()
	local arAllEpisodes = QuestLib.GetAllEpisodes(bShowCompleted, true)

	local wndTopLevelItems = wndTop:FindChild("TopLevelItems")
	for idx, epiEpisode in pairs(arAllEpisodes) do
		if epiEpisode:IsWorldStory() then
			for idx, qcCategory in pairs(arAllCategories) do
				if (function(qcCategory, epiEpisode) 
					for idx, queQuest in pairs(epiEpisode:GetAllQuests(qcCategory:GetId())) do
						if self:CheckLeftSideFilters(queQuest) then
							return true
						end
					end
					return false
					end)(qcCategory, epiEpisode) then
					
					local strEpisodeKey
					if epiEpisode:IsWorldStory() or epiEpisode:IsZoneStory() or epiEpisode:IsRegionalStory() then
						strEpisodeKey = strCategoryKey.."E"..epiEpisode:GetId()
					else
						strEpisodeKey = strCategoryKey.."ETasks"
					end
					
					local wndMiddle = self:FactoryCacheProduce(wndTopLevelItems, "MiddleLevelItem", strEpisodeKey)
					self:HelperSetupMiddleLevelWindow(wndMiddle, epiEpisode)
					
					local wndMiddleLevelItems = wndMiddle:FindChild("MiddleLevelItems")
				
					for idx, queQuest in pairs(epiEpisode:GetAllQuests(qcCategory:GetId())) do
						if self:CheckLeftSideFilters(queQuest) then
							local strQuestKey = strEpisodeKey.."Q"..queQuest:GetId()
							local wndBot = self:FactoryCacheProduce(wndMiddleLevelItems, "BottomLevelItem", strQuestKey)
							self:HelperSetupBottomLevelWindow(wndBot, queQuest)
						end
					end
				end
			end
		end
	end
end

function QuestLog:LeftTreeBuildEpisodes(wndTop, strCategoryKey, qcCategory)
	local fnDoesCategoryHaveQuests, fnDoesCategoryEpisodeHaveQuests = self:GetHaveQuestFunctions()

	local bShowCompleted = self.wndLeftFilterFinished:IsChecked()
	
	local arAllEpisodes = QuestLib.GetAllEpisodes(bShowCompleted, true)
	local wndTopLevelItems = wndTop:FindChild("TopLevelItems")
	for idx, epiEpisode in pairs(arAllEpisodes) do
		if not epiEpisode:IsWorldStory() then
			if fnDoesCategoryEpisodeHaveQuests(qcCategory, epiEpisode) then
			
				local strEpisodeKey
				if epiEpisode:IsWorldStory() or epiEpisode:IsZoneStory() or epiEpisode:IsRegionalStory() then
					strEpisodeKey = strCategoryKey.."E"..epiEpisode:GetId()
				else
					strEpisodeKey = strCategoryKey.."ETasks"
				end
				
				local wndMiddle = self:FactoryCacheProduce(wndTopLevelItems, "MiddleLevelItem", strEpisodeKey)
				self:HelperSetupMiddleLevelWindow(wndMiddle, epiEpisode)
				
				local wndMiddleLevelItems = wndMiddle:FindChild("MiddleLevelItems")
				
				for idx, queQuest in pairs(epiEpisode:GetAllQuests(qcCategory:GetId())) do
					if self:CheckLeftSideFilters(queQuest) then
						local strQuestKey = strEpisodeKey.."Q"..queQuest:GetId()
						local wndBot = self:FactoryCacheProduce(wndMiddleLevelItems, "BottomLevelItem", strQuestKey)
						self:HelperSetupBottomLevelWindow(wndBot, queQuest)
					end
				end
			end
		end
	end
end

function QuestLog:HelperSetupMiddleLevelWindow(wndMiddle, epiEpisode)
	local tEpisodeProgress = epiEpisode:GetProgress()
	wndMiddle:FindChild("MiddleLevelBtnText"):SetText(epiEpisode:GetTitle())
	wndMiddle:FindChild("MiddleLevelProgBar"):SetMax(tEpisodeProgress.nTotal)
	wndMiddle:FindChild("MiddleLevelProgBar"):SetProgress(tEpisodeProgress.nCompleted)
end

function QuestLog:HelperSetupFakeMiddleLevelWindow(wndMiddle, strText)
	local tEpisodeProgress = { nTotal = 100, nCompleted = 0 }
	wndMiddle:FindChild("MiddleLevelBtnText"):SetText(strText)
	wndMiddle:FindChild("MiddleLevelProgBar"):SetMax(tEpisodeProgress.nTotal)
	wndMiddle:FindChild("MiddleLevelProgBar"):SetProgress(tEpisodeProgress.nCompleted)
end

function QuestLog:HelperSetupBottomLevelWindow(wndBot, queQuest)
	self.tTreeQuestsById[queQuest:GetId()] = wndBot

	local wndBottomLevelBtn = wndBot:FindChild("BottomLevelBtn")
	local wndBottomLevelTrackBtn = wndBot:FindChild("BottomLevelTrackQuestBtn")
	local wndBottomLevelBtnText = wndBot:FindChild("BottomLevelBtnText")
	local bIsTracked = queQuest:IsTracked()
	
	if queQuest:IsInLog() then
		wndBottomLevelTrackBtn:Enable(true)
		wndBottomLevelTrackBtn:SetData(queQuest)
	else
		wndBottomLevelTrackBtn:Enable(false)
		wndBottomLevelTrackBtn:SetTooltip("This quest cannot be tracked yet.")
	end
	
	wndBottomLevelTrackBtn:SetCheck(bIsTracked)
	wndBottomLevelTrackBtn:SetTooltip(bIsTracked and Apollo.GetString("QuestTracker_StopTracking") or Apollo.GetString("QuestLog_AddToTracker"))

	local bOptionalQuest = queQuest:IsOptionalForEpisode(queQuest:GetEpisode():GetId())
	local strLevel = String_GetWeaselString(Apollo.GetString("CRB_BracketsNumber_Space"), queQuest:GetConLevel())
	local strQuestTitle = strLevel..String_GetWeaselString(queQuest:GetTitle())
	local strQuestTitleOptional = strLevel..String_GetWeaselString(Apollo.GetString("QuestLog_OptionalAppend"), queQuest:GetTitle())

	wndBottomLevelBtn:SetData(queQuest)
	wndBottomLevelBtnText:SetText(bOptionalQuest and strQuestTitleOptional or strQuestTitle)
	wndBottomLevelBtn:SetText(bOptionalQuest and strQuestTitleOptional or strQuestTitle)

	local strBottomLevelIconSprite = "QuestLogSprites:sprQuestDotComplete"
	local bHasCall = queQuest:GetContactInfo()
	local eState = queQuest:GetState()
	
	if eState == Quest.QuestState_Botched or eState == Quest.QuestState_Abandoned or eState == Quest.QuestState_Mentioned then
		strBottomLevelIconSprite = "QuestLogSprites:sprQuestDotUnknown"
	elseif eState == Quest.QuestState_Achieved then
		strBottomLevelIconSprite = "QuestLogSprites:sprQuestDotActive"
	end
	wndBot:FindChild("BottomLevelBtnIcon"):SetSprite(strBottomLevelIconSprite)
end

function QuestLog:HelperRemoveBottomLevelWindow(wndBot, queQuest)
	self.tTreeQuestsById[queQuest:GetId()] = nil
	
	local qcCategory = queQuest:GetCategory()
	local epiEpisode = queQuest:GetEpisode()
	
	local strCategoryKey
	local strEpisodeKey
	local strQuestKey

	if epiEpisode:IsWorldStory() then
		strCategoryKey = "CWorldStory"
		strEpisodeKey = strCategoryKey.."E"..epiEpisode:GetId()
		strQuestKey = strEpisodeKey.."Q"..queQuest:GetId()
	elseif epiEpisode:IsZoneStory() or epiEpisode:IsRegionalStory() then
		strCategoryKey = "C"..qcCategory:GetId()
		strEpisodeKey = strCategoryKey.."E"..epiEpisode:GetId()
		strQuestKey = strEpisodeKey.."Q"..queQuest:GetId()
	else
		strCategoryKey = "C"..qcCategory:GetId()
		strEpisodeKey = strCategoryKey.."ETasks"
		strQuestKey = strEpisodeKey.."Q"..queQuest:GetId()
	end
	
	local wndBottom = self.arLeftTreeMap[strQuestKey]
	if wndBottom ~= nil and wndBottom:IsValid() then
		wndBottom:Destroy()
	end
	
	local fnDoesCategoryHaveQuests, fnDoesCategoryEpisodeHaveQuests = self:GetHaveQuestFunctions()
	local fnHaveWorldStoryQuests, fnEpisodeHasWorldStoryQuests = self:GetHaveWorldStoryQuestFunctions()
		
	if (epiEpisode:IsWorldStory() and not fnHaveWorldStoryQuests(QuestLib.GetKnownCategories(), QuestLib.GetAllEpisodes(self.wndLeftFilterFinished:IsChecked(), true)))
		or (not epiEpisode:IsWorldStory() and not fnDoesCategoryHaveQuests(qcCategory)) then
		
		local wndTop = self.arLeftTreeMap[strCategoryKey]
		if wndTop ~= nil and wndTop:IsValid() then
			wndTop:Destroy()
		end
	elseif (epiEpisode:IsWorldStory() and not fnEpisodeHasWorldStoryQuests(QuestLib.GetKnownCategories(), epiEpisode))
		or (not epiEpisode:IsWorldStory() and not fnDoesCategoryEpisodeHaveQuests(qcCategory, epiEpisode)) then
		
		local wndMiddle = self.arLeftTreeMap[strEpisodeKey]
		if wndMiddle ~= nil and wndMiddle:IsValid() then
			wndMiddle:Destroy()
		end
	end
	
	self:ResizeTree()
end

function QuestLog:ResizeTree()
	for idx1, wndTop in pairs(self.wndLeftSideScroll:GetChildren()) do
		local wndTopLevelBtn = wndTop:FindChild("TopLevelBtn")
		local wndTopLevelItems = wndTop:FindChild("TopLevelItems")

		if wndTopLevelBtn:IsChecked() then
			for idx2, wndMiddle in pairs(wndTopLevelItems:GetChildren()) do
				local wndMiddleTitle = wndMiddle:FindChild("MiddleLevelTitle")
				local wndMiddleLevelItems = wndMiddle:FindChild("MiddleLevelItems")
				
				for idx3, wndBot in pairs(wndMiddleLevelItems:GetChildren()) do -- Resize if too long

					local wndBottomLevelBtnText = wndBot:FindChild("BottomLevelBtn:BottomLevelBtnText")
					wndBottomLevelBtnText:SetHeightToContentHeight()

					if wndBottomLevelBtnText:GetHeight() >= 25 then
						local nLeft, nTop, nRight, nBottom = wndBot:GetAnchorOffsets()
						wndBot:SetAnchorOffsets(nLeft, nTop, nRight, nTop + 40)
					end

					if wndBottomLevelBtnText:GetHeight() >= 50 then
						local nLeft, nTop, nRight, nBottom = wndBot:GetAnchorOffsets()
						wndBot:SetAnchorOffsets(nLeft, nTop, nRight, nTop + 55)
					end
				end

				local nItemHeights = wndMiddleLevelItems:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop)
				if nItemHeights > 0 then
					nItemHeights = nItemHeights + 4
				end

				local nMiddleLeft, nMiddleTop, nMiddleRight, nMiddleBottom = wndMiddle:GetAnchorOffsets()
				wndMiddle:SetAnchorOffsets(nMiddleLeft, nMiddleTop, nMiddleRight, nMiddleTop + self.knMiddleLevelHeight + nItemHeights)
			end
		else
			wndTopLevelItems:DestroyChildren()
		end
		wndTopLevelItems:SetSprite(wndTopLevelBtn:IsChecked() and "kitInnerFrame_MetalGold_FrameBright2" or "kitInnerFrame_MetalGold_FrameDull")

		local nItemHeights = wndTopLevelItems:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop, function(a,b) return a:GetData() > b:GetData() end) -- Tasks to bottom

		local nTopLeft, nTopTop, nTopRight, nTopBottom = wndTop:GetAnchorOffsets()
		wndTop:SetAnchorOffsets(nTopLeft, nTopTop, nTopRight, nTopTop + self.knTopLevelHeight + nItemHeights)
	end

	self.wndLeftSideScroll:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop, function(wndLeft, wndRight)
		local leftData = wndLeft:GetData()
		
		if leftData == "CWorldStory" then
			return true
		end
		
		local rightData = wndRight:GetData()
		
		if rightData == "CWorldStory" then
			return false
		end
		
		return leftData < rightData
	end)
	self.wndLeftSideScroll:RecalculateContentExtents()
end

function QuestLog:ResizeRight()
	local nWidth, nHeight, nLeft, nTop, nRight, nBottom

	-- Objectives Content
	for key, wndObj in pairs(self.wndMain:FindChild("QuestInfoObjectivesList"):GetChildren()) do

		if wndObj:FindChild("ObjectivesItemText") then
		nWidth, nHeight = wndObj:FindChild("ObjectivesItemText"):SetHeightToContentHeight()
		end
		if wndObj:FindChild("QuestProgressItem") then
			nHeight = nHeight + wndObj:FindChild("QuestProgressItem"):GetHeight()
		end
		if wndObj:FindChild("SpellItemBtn") then
			nHeight = nHeight + wndObj:FindChild("SpellItemBtn"):GetHeight()
		end
		nLeft, nTop, nRight, nBottom = wndObj:GetAnchorOffsets()
		wndObj:SetAnchorOffsets(nLeft, nTop, nRight, nTop + math.max(self.knObjectivesItemHeight, nHeight + 8)) -- TODO: Hardcoded formatting of text pad
	end

	-- Objectives Frame
	nHeight = self.wndMain:FindChild("QuestInfoObjectivesList"):ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop)
	nLeft, nTop, nRight, nBottom = self.wndMain:FindChild("QuestInfoObjectivesFrame"):GetAnchorOffsets()
	self.wndMain:FindChild("QuestInfoObjectivesFrame"):SetAnchorOffsets(nLeft, nTop, nRight, nTop + nHeight + 40)
	self.wndMain:FindChild("QuestInfoObjectivesFrame"):Show(#self.wndMain:FindChild("QuestInfoObjectivesList"):GetChildren() > 0)
	self.wndMain:FindChild("PaddingObjective"):Show(#self.wndMain:FindChild("QuestInfoObjectivesList"):GetChildren() > 0)

	-- Rewards Recevived
	nHeight = self.wndMain:FindChild("QuestInfoRewardRecList"):ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop)
	nLeft, nTop, nRight, nBottom = self.wndMain:FindChild("QuestInfoRewardRecFrame"):GetAnchorOffsets()
	self.wndMain:FindChild("QuestInfoRewardRecFrame"):SetAnchorOffsets(nLeft, nTop, nRight, nTop + nHeight + self.nRewardRecListHeight + 15) -- TODO: Hardcoded footer padding
	self.wndMain:FindChild("QuestInfoRewardRecFrame"):Show(#self.wndMain:FindChild("QuestInfoRewardRecList"):GetChildren() > 0)
	self.wndMain:FindChild("PaddingReward"):Show(#self.wndMain:FindChild("QuestInfoRewardRecList"):GetChildren() > 0)

	-- Rewards to Choose
	nHeight = self.wndMain:FindChild("QuestInfoRewardChoList"):ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop, function(a,b) return b:FindChild("RewardItemCantUse"):IsShown() end)
	nLeft, nTop, nRight, nBottom = self.wndMain:FindChild("QuestInfoRewardChoFrame"):GetAnchorOffsets()
	self.wndMain:FindChild("QuestInfoRewardChoFrame"):SetAnchorOffsets(nLeft, nTop, nRight, nTop + nHeight + self.nRewardChoListHeight + 15) -- TODO: Hardcoded footer padding
	self.wndMain:FindChild("QuestInfoRewardChoFrame"):Show(#self.wndMain:FindChild("QuestInfoRewardChoList"):GetChildren() > 0)
	self.wndMain:FindChild("PaddingRewardChoice"):Show(#self.wndMain:FindChild("QuestInfoRewardChoList"):GetChildren() > 0)

	-- More Info
	nWidth, nHeight = self.wndMain:FindChild("QuestInfoMoreInfoText"):SetHeightToContentHeight()
	nHeight = nHeight + 10
	nLeft, nTop, nRight, nBottom = self.wndMain:FindChild("QuestInfoMoreInfoFrame"):GetAnchorOffsets()
	self.wndMain:FindChild("QuestInfoMoreInfoFrame"):SetAnchorOffsets(nLeft, nTop, nRight, nTop + nHeight + self.nMoreInfoHeight + 3)

	-- Episode title
	nHeight = self.wndMain:FindChild("EpisodeSummaryTitle"):GetHeight()
	self.wndMain:FindChild("EpisodeSummaryTitle"):SetHeightToContentHeight()
	if self.wndMain:FindChild("EpisodeSummaryTitle"):GetHeight() > nHeight then
		self.nEpisodeInfoHeight = self.nEpisodeInfoHeight + knEpisodeInfoBuffer + self.wndMain:FindChild("EpisodeSummaryTitle"):GetHeight() - nHeight
	end

	-- Episode summary text
	nHeight = self.nEpisodeInfoHeight
	if self.wndMain:FindChild("EpisodeSummaryExpandBtn"):IsChecked() then

		-- Resize summary text
		self.wndMain:FindChild("EpisodeSummaryPopoutText"):SetHeightToContentHeight()
		nLeft,nTop,nRight,nBottom = self.wndMain:FindChild("EpisodeSummaryPopoutText"):GetAnchorOffsets()
		self.wndMain:FindChild("EpisodeSummaryPopoutText"):SetAnchorOffsets(nLeft, self.nEpisodeInfoHeight - knEpisodeInfoBuffer, nRight, self.wndMain:FindChild("EpisodeSummaryPopoutText"):GetHeight() + self.nEpisodeInfoHeight - knEpisodeInfoBuffer)
		nHeight = nHeight + self.wndMain:FindChild("EpisodeSummaryPopoutText"):GetHeight()
	end

	-- Episode info window
	nLeft, nTop, nRight, nBottom = self.wndMain:FindChild("EpisodeInfo"):GetAnchorOffsets()
	if self.wndMain:FindChild("EpisodeInfo"):IsShown() then
		self.wndMain:FindChild("EpisodeInfo"):SetAnchorOffsets(nLeft, nTop, nRight, nTop + nHeight)
	else
		self.wndMain:FindChild("EpisodeInfo"):SetAnchorOffsets(nLeft, nTop, nRight, nTop)
	end

	-- Resize
	local nLeft, nTop, nRight, nBottom = self.wndMain:FindChild("QuestInfo"):GetAnchorOffsets()
	self.wndMain:FindChild("QuestInfo"):SetAnchorOffsets(nLeft, nTop, nRight, nTop + self.wndMain:FindChild("QuestInfo"):ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop))

	self.wndRightSide:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop)
	self.wndRightSide:RecalculateContentExtents()
end

-----------------------------------------------------------------------------------------------
-- Draw Quest Info
-----------------------------------------------------------------------------------------------

function QuestLog:DrawRightSide(queSelected)
	local wndRight = self.wndRightSide
	local eQuestState = queSelected:GetState()

	-- Episode Summary
	local epiParent = queSelected:GetEpisode()
	local bIsTasks = epiParent:GetId() == 1
	local strEpisodeDesc = ""
	if not bIsTasks then
		strEpisodeDesc = epiParent:GetState() == Episode.EpisodeState_Complete and epiParent:GetSummary() or epiParent:GetDesc()
	end

	local tEpisodeProgress = epiParent:GetProgress()
	wndRight:FindChild("EpisodeSummaryTitle"):SetText(epiParent:GetTitle())
	wndRight:FindChild("EpisodeSummaryProgText"):SetAML(string.format("<P Font=\"CRB_HeaderTiny\" Align=\"Center\">"..
	"(<T Font=\"CRB_HeaderTiny\" Align=\"Center\">%s</T>/%s)</P>", tEpisodeProgress.nCompleted, tEpisodeProgress.nTotal))
	wndRight:FindChild("EpisodeSummaryPopoutText"):SetAML("<P Font=\"CRB_InterfaceMedium\" TextColor=\"ff2f94ac\">"..strEpisodeDesc.."</P>")
	wndRight:FindChild("EpisodeSummaryPopoutText"):SetHeightToContentHeight()
	wndRight:FindChild("EpisodeSummaryExpandBtn"):Enable(not bIsTasks)
	wndRight:FindChild("EpisodeSummaryProgBG"):Show(not bIsTasks)

	-- Text Summary
	local strQuestSummary = ""
	if eQuestState == Quest.QuestState_Completed and Apollo.StringLength(queSelected:GetCompletedSummary()) > 0 then
		strQuestSummary = queSelected:GetCompletedSummary()
	elseif Apollo.StringLength(queSelected:GetSummary()) > 0 then
		strQuestSummary = queSelected:GetSummary()
	end
	
	local nConLevel = queSelected:GetConLevel()
	local strDifficulty = String_GetWeaselString(Apollo.GetString("Tradeskills_Level"), nConLevel)
	wndRight:FindChild("QuestInfoDifficultyText"):SetAML(string.format("<P Font=\"CRB_HeaderTiny\" TextColor=\"UI_TextHoloBodyHighlight\">%s</P>", strDifficulty))

	local bOptionalQuest = queSelected:IsOptionalForEpisode(epiParent:GetId())	
	local strTitle = bOptionalQuest and String_GetWeaselString(Apollo.GetString("QuestLog_OptionalAppend"), queSelected:GetTitle()) or queSelected:GetTitle()
	local strTextColor = "UI_TextHoloTitle"

	if eQuestState == Quest.QuestState_Completed then
		wndRight:FindChild("QuestInfoTitleIcon"):SetTooltip(Apollo.GetString("QuestLog_HasBeenCompleted"))
		wndRight:FindChild("QuestInfoTitleIcon"):SetSprite("CRB_Basekit:kitIcon_Green_Checkmark")
		strTitle = String_GetWeaselString(Apollo.GetString("QuestLog_Completed"), strTitle)
		strTextColor = "UI_WindowTextChallengeGreenFlash"
	elseif eQuestState == Quest.QuestState_Achieved then
		wndRight:FindChild("QuestInfoTitleIcon"):SetTooltip(Apollo.GetString("QuestLog_QuestReadyToTurnIn"))
		wndRight:FindChild("QuestInfoTitleIcon"):SetSprite("CRB_Basekit:kitIcon_Green_Checkmark")
		strTextColor = "UI_WindowTextChallengeGreenFlash"
	else
		wndRight:FindChild("QuestInfoTitleIcon"):SetTooltip(Apollo.GetString("QuestLog_ObjectivesNotComplete"))
		wndRight:FindChild("QuestInfoTitleIcon"):SetSprite("CRB_Basekit:kitIcon_Gold_Checkbox")
	end

	wndRight:FindChild("QuestInfoTitle"):SetAML(string.format("<P Font=\"CRB_Header13\" TextColor=\"%s\">%s</P>", strTextColor ,strTitle))
	wndRight:FindChild("QuestInfoTitle"):SetHeightToContentHeight()
		
	wndRight:FindChild("QuestInfoDescriptionText"):SetAML(string.format("<P Font=\"CRB_InterfaceMedium\" TextColor=\"UI_TextHoloBodyCyan\">%s</P>", strQuestSummary))
	wndRight:FindChild("QuestInfoDescriptionText"):SetHeightToContentHeight()

	local nTitleAndEtcHeight = wndRight:FindChild("RightColumn"):ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop)
	local nLeft, nTop, nRight, nBottom = wndRight:FindChild("QuestInfoTitleAndEtcFrame"):GetAnchorOffsets()
	wndRight:FindChild("QuestInfoTitleAndEtcFrame"):SetAnchorOffsets(nLeft, nTop, nRight, nTop + nTitleAndEtcHeight)
	
	-- More Info
	local strMoreInfo = ""
	local tMoreInfoText = queSelected:GetMoreInfoText()
	if #tMoreInfoText > 0 then
		for idx, tValues in pairs(tMoreInfoText) do
			if Apollo.StringLength(tValues.strSay) > 0 or Apollo.StringLength(tValues.strResponse) > 0 then
				strMoreInfo = strMoreInfo .. "<P Font=\"CRB_InterfaceMedium\" TextColor=\"UI_TextHoloBody\">"..tValues.strSay.."</P>"
				strMoreInfo = strMoreInfo .. "<P Font=\"CRB_InterfaceMedium\" TextColor=\"UI_TextHoloBodyCyan\">"..tValues.strResponse.."</P>"
				if idx ~= #tMoreInfoText then
					strMoreInfo = strMoreInfo .. "<P TextColor=\"0\">.</P>"
				end
			end
		end
	end
	wndRight:FindChild("QuestInfoMoreInfoText"):SetAML(strMoreInfo)
	wndRight:FindChild("QuestInfoMoreInfoFrame"):Show(#tMoreInfoText > 0)
	wndRight:FindChild("PaddingInfo"):Show(#tMoreInfoText > 0)
	-- Objectives
	wndRight:FindChild("QuestInfoObjectivesList"):DestroyChildren()
	if eQuestState == Quest.QuestState_Achieved then
		local wndObj = Apollo.LoadForm(self.xmlDoc, "ObjectivesItem", wndRight:FindChild("QuestInfoObjectivesList"), self)
		local strAchieved = string.format("<T Font=\"CRB_InterfaceMedium\" TextColor=\"UI_TextHoloBody\">%s</T>", queSelected:GetCompletionObjectiveText())
		wndObj:FindChild("ObjectivesItemText"):SetAML(strAchieved)
		wndRight:FindChild("QuestInfoObjectivesTitle"):SetText(Apollo.GetString("QuestLog_ReadyToTurnIn"))
	elseif eQuestState == Quest.QuestState_Completed then
		for key, tObjData in pairs(queSelected:GetVisibleObjectiveData()) do
			if tObjData.nCompleted < tObjData.nNeeded then
				local wndObj = Apollo.LoadForm(self.xmlDoc, "ObjectivesItem", wndRight:FindChild("QuestInfoObjectivesList"), self)
				wndObj:FindChild("ObjectivesItemText"):SetAML(self:HelperBuildObjectiveTitleString(queSelected, tObjData))
			end
		end
		wndRight:FindChild("QuestInfoObjectivesTitle"):SetText(Apollo.GetString("QuestLog_Objectives"))
	elseif eQuestState ~= Quest.QuestState_Mentioned then
		for key, tObjData in pairs(queSelected:GetVisibleObjectiveData()) do
			if tObjData.nCompleted < tObjData.nNeeded then
				local wndObj = Apollo.LoadForm(self.xmlDoc, "ObjectivesItem", wndRight:FindChild("QuestInfoObjectivesList"), self)
				wndObj:FindChild("ObjectivesItemText"):SetAML(self:HelperBuildObjectiveTitleString(queSelected, tObjData))
			end
			-- Objective Spell
			if queSelected:GetSpell(tObjData.nIndex) then
				wndSpell = Apollo.LoadForm(self.xmlDoc, "SpellItem", wndRight:FindChild("QuestInfoObjectivesList"), self)

				wndSpell:FindChild("SpellItemBtn"):SetContentId(queSelected, tObjData.nIndex)
				wndSpell:FindChild("SpellItemBtn"):SetText(String_GetWeaselString(GameLib.GetKeyBinding("CastObjectiveAbility")))				
			end
		end
		wndRight:FindChild("QuestInfoObjectivesTitle"):SetText(Apollo.GetString("QuestLog_Objectives"))
	end
	wndRight:FindChild("QuestInfoObjectivesList"):ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop)

	-- Rewards Received
	local tRewardInfo = queSelected:GetRewardData()
	wndRight:FindChild("QuestInfoRewardRecList"):DestroyChildren()
	for key, tReward in pairs(tRewardInfo.arFixedRewards) do
		local wndReward = Apollo.LoadForm(self.xmlDoc, "RewardItem", wndRight:FindChild("QuestInfoRewardRecList"), self)
		self:HelperBuildRewardsRec(wndReward, tReward, true)
	end

	-- XP Received
	local nRewardXP = queSelected:CalcRewardXP()
	if nRewardXP > 0 then
		local wndReward = Apollo.LoadForm(self.xmlDoc, "RewardItem", wndRight:FindChild("QuestInfoRewardRecList"), self)	
		self:HelperBuildXPRewardsRec(wndReward, nRewardXP)
	end

	-- Rewards To Choose
	wndRight:FindChild("QuestInfoRewardChoList"):DestroyChildren()
	for key, tReward in pairs(tRewardInfo.arRewardChoices) do
		local wndReward = Apollo.LoadForm(self.xmlDoc, "RewardItem", wndRight:FindChild("QuestInfoRewardChoList"), self)
		self:HelperBuildRewardsRec(wndReward, tReward, false)
	end

	-- Special reward formatting for finished quests
	if eQuestState == Quest.QuestState_Completed then
		wndRight:FindChild("QuestInfoRewardRecTitle"):SetText(Apollo.GetString("QuestLog_YouReceived"))
		wndRight:FindChild("QuestInfoRewardChoTitle"):SetText(Apollo.GetString("QuestLog_YouChoseFrom"))
	else
		wndRight:FindChild("QuestInfoRewardRecTitle"):SetText(Apollo.GetString("QuestLog_WillReceive"))
		wndRight:FindChild("QuestInfoRewardChoTitle"):SetText(Apollo.GetString("QuestLog_CanChooseOne"))
	end

	-- Call Button
	if queSelected:GetContactInfo() and ktValidCallButtonStats[eQuestState] then
		local strContactLine1 = "<P Font=\"CRB_HeaderSmall\" TextColor=\"ff56b381\">" .. Apollo.GetString("QuestLog_ContactNPC") .. "</P>"
		local tContactInfo = queSelected:GetContactInfo()
		wndRight:FindChild("QuestInfoCallFrame"):Show(true)
		wndRight:FindChild("QuestInfoCostumeWindow"):SetCostumeToCreatureId(tContactInfo.idUnit)
		wndRight:FindChild("QuestInfoCallFrameText"):SetAML(strContactLine1 .. "<P Font=\"CRB_HeaderSmall\">" .. tContactInfo.strName .. "</P>")
	else
		wndRight:FindChild("QuestInfoCallFrame"):Show(false)
	end

	-- Bottom Buttons (outside of Scroll)
	self.wndMain:FindChild("QuestInfoControlsHideBtn"):Show(eQuestState == Quest.QuestState_Abandoned or eQuestState == Quest.QuestState_Mentioned)
	self.wndMain:FindChild("QuestRestartBtn"):Show(eQuestState == Quest.QuestState_Ignored)
	self.wndMain:FindChild("QuestInfoControlButtons"):Show(eQuestState == Quest.QuestState_Accepted or eQuestState == Quest.QuestState_Achieved or eQuestState == Quest.QuestState_Botched)
	if eQuestState ~= Quest.QuestState_Abandoned then
		self:OnGroupUpdate()
		self.wndMain:FindChild("QuestAbandonPopoutBtn"):Enable(queSelected:CanAbandon())
	end

	-- Hide Pop Out CloseOnExternalClick windows
	self.wndMain:FindChild("QuestAbandonConfirm"):Show(false)
end

function QuestLog:OnGroupUpdate()
	if not self.wndRightSide or not self.wndRightSide:IsValid() then
		return
	end

	local queSelected = self.wndRightSide:GetData()
	if queSelected and queSelected:GetState() ~= Quest.QuestState_Abandoned then
		local bCanShare = queSelected:CanShare()
		local strCantShareTooltip = String_GetWeaselString(Apollo.GetString("QuestLog_ShareNotPossible"), Apollo.GetString("QuestLog_ShareQuest"))
		self.wndMain:FindChild("QuestShareBtn"):Enable(bCanShare)
		self.wndMain:FindChild("QuestInfoControlsBGShare"):SetTooltip(bCanShare and Apollo.GetString("QuestLog_ShareQuest") or strCantShareTooltip)
	end
end

function QuestLog:DrawUnknownRightSide(queSelected)
	if not queSelected then
		return
	end

	local wndRight = self.wndRightSide
	local eQuestState = queSelected:GetState()

	-- Episode Summary
	local epiParent = queSelected:GetEpisode()
	local bIsTasks = true
	local strEpisodeDesc = ""
	local bOptionalQuest = false
	
	if epiParent then
		bIsTasks = epiParent:GetId() == 1
		bOptionalQuest = queSelected:IsOptionalForEpisode(epiParent:GetId())	
		if not bIsTasks then
			strEpisodeDesc = epiParent:GetState() == Episode.EpisodeState_Complete and epiParent:GetSummary() or epiParent:GetDesc()
		end
	else
		strEpisodeDesc = Apollo.GetString("QuestLog_UnknownQuest")
	end

	
	local strTitle = Apollo.GetString("QuestLog_UnknownQuest")
	local nCompleted = 0
	local nTotal = 0
	if epiParent then
		local tEpisodeProgress = epiParent:GetProgress()
		if tEpisodeProgress then
			nCompleted = tEpisodeProgress.nCompleted
			nTotal = tEpisodeProgress.nTotal
		end
		
		strTitle = epiParent:GetTitle()
	end
	wndRight:FindChild("EpisodeSummaryTitle"):SetText(strTitle)
	wndRight:FindChild("EpisodeSummaryProgText"):SetAML(string.format("<P Font=\"CRB_HeaderTiny\" Align=\"Center\">"..
	"(<T Font=\"CRB_HeaderTiny\" Align=\"Center\">%s</T>/%s)</P>", nCompleted, nTotal))
	wndRight:FindChild("EpisodeSummaryPopoutText"):SetAML("<P Font=\"CRB_InterfaceMedium\" TextColor=\"ff2f94ac\">"..strEpisodeDesc.."</P>")
	wndRight:FindChild("EpisodeSummaryPopoutText"):SetHeightToContentHeight()
	wndRight:FindChild("EpisodeSummaryExpandBtn"):Enable(false)
	wndRight:FindChild("EpisodeSummaryProgBG"):Show(not bIsTasks)

	-- Text Summary
	local strQuestSummary = ""
	if eQuestState == Quest.QuestState_Completed and Apollo.StringLength(queSelected:GetCompletedSummary()) > 0 then
		strQuestSummary = queSelected:GetCompletedSummary()
	elseif Apollo.StringLength(queSelected:GetSummary()) > 0 then
		strQuestSummary = queSelected:GetSummary()
	end

	local nConLevel = queSelected:GetConLevel()
	local strDifficulty = String_GetWeaselString(Apollo.GetString("Tradeskills_Level"), nConLevel )
	wndRight:FindChild("QuestInfoDifficultyText"):SetAML("<P Font=\"CRB_HeaderTiny\" TextColor=\"UI_TextHoloBodyHighlight\">"..strDifficulty.."</P>")

	local strTitle = bOptionalQuest and String_GetWeaselString(Apollo.GetString("QuestLog_OptionalAppend"), queSelected:GetTitle()) or queSelected:GetTitle()
	local strTextColor = "UI_TextHoloTitle"

	wndRight:FindChild("QuestInfoTitleIcon"):SetTooltip(Apollo.GetString("QuestLog_ObjectivesNotComplete"))
	wndRight:FindChild("QuestInfoTitleIcon"):SetSprite("CRB_Basekit:kitIcon_Gold_Checkbox")

	wndRight:FindChild("QuestInfoTitle"):SetAML(string.format("<P Font=\"CRB_Header13\" TextColor=\"%s\">%s</P>", strTextColor, strTitle))
	wndRight:FindChild("QuestInfoTitle"):SetHeightToContentHeight()	
	
	wndRight:FindChild("QuestInfoDescriptionText"):SetAML("<P Font=\"CRB_InterfaceMedium\" TextColor=\"ff56b381\">"..strQuestSummary.."</P>")
	wndRight:FindChild("QuestInfoDescriptionText"):SetHeightToContentHeight()

	-- More Info
	wndRight:FindChild("QuestInfoMoreInfoText"):SetAML("")
	wndRight:FindChild("QuestInfoMoreInfoFrame"):Show(false)

	-- Objectives
	wndRight:FindChild("QuestInfoObjectivesList"):DestroyChildren()

	-- Rewards Received
	local tRewardInfo = queSelected:GetRewardData()
	wndRight:FindChild("QuestInfoRewardRecList"):DestroyChildren()
	for key, tReward in pairs(tRewardInfo.arFixedRewards) do
		local wndReward = Apollo.LoadForm(self.xmlDoc, "RewardItem", wndRight:FindChild("QuestInfoRewardRecList"), self)
		self:HelperBuildRewardsRec(wndReward, tReward, true)
	end

	-- Rewards To Choose
	wndRight:FindChild("QuestInfoRewardChoList"):DestroyChildren()
	for key, tReward in pairs(tRewardInfo.arRewardChoices) do
		local wndReward = Apollo.LoadForm(self.xmlDoc, "RewardItem", wndRight:FindChild("QuestInfoRewardChoList"), self)
		self:HelperBuildRewardsRec(wndReward, tReward, false)
	end

	-- Special reward formatting for finished quests
	wndRight:FindChild("QuestInfoRewardRecTitle"):SetText(Apollo.GetString("QuestLog_WillReceive"))
	wndRight:FindChild("QuestInfoRewardChoTitle"):SetText(Apollo.GetString("QuestLog_CanChooseOne"))

	-- Call Button
	wndRight:FindChild("QuestInfoCallFrame"):Show(false)

	-- Bottom Buttons (outside of Scroll)
	self.wndMain:FindChild("QuestInfoControlsHideBtn"):Show(false)
	self.wndMain:FindChild("QuestInfoControlButtons"):Show(false)

	-- Hide Pop Out CloseOnExternalClick windows
	self.wndMain:FindChild("QuestAbandonConfirm"):Show(false)
end

function QuestLog:OnTopLevelBtnCheck(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
	
	local tData = wndControl:GetData()
	if tData.bIsWorldStory then
		self:LeftTreeBuildWorldStoryEpisodes(tData.wndTop, tData.strCategoryKey)
	else
		self:LeftTreeBuildEpisodes(tData.wndTop, tData.strCategoryKey, tData.qcCategory)
	end
	
	self:ResizeTree()
end

function QuestLog:OnTopLevelBtnUncheck(wndHandler, wndControl)
	self:ResizeTree()
end

function QuestLog:OnBottomLevelBtnCheck(wndHandler, wndControl) -- From Button or OnQuestObjectiveUpdated
	self.wndLastBottomLevelBtnSelection = wndHandler

	self.wndRightSide:Show(true)
	self.wndRightSide:SetVScrollPos(0)
	self.wndRightSide:RecalculateContentExtents()
	self.wndRightSide:SetData(wndHandler:GetData())
	self:RedrawRight()
end

function QuestLog:OnBottomLevelBtnUncheck(wndHandler, wndControl)
	self.wndQuestInfoControls:Show(false)
	self.wndRightSide:Show(false)
end

function QuestLog:OnBottomLevelBtnDown( wndHandler, wndControl, eMouseButton )
	if eMouseButton == GameLib.CodeEnumInputMouse.Right and Apollo.IsShiftKeyDown() then
		Event_FireGenericEvent("GenericEvent_QuestLink", wndControl:GetParent():FindChild("BottomLevelBtn"):GetData())
	end
end

-----------------------------------------------------------------------------------------------
-- Bottom Buttons and Quest Update Events
-----------------------------------------------------------------------------------------------

function QuestLog:OnQuestTrackCheckBtn(wndHandler, wndControl) -- QuestTrackCheckBtn
	local queSelected = wndControl:GetData()
	queSelected:SetTracked(true)
	wndControl:SetTooltip(Apollo.GetString("QuestTracker_StopTracking"))
	Event_FireGenericEvent("GenericEvent_QuestLog_TrackBtnClicked", queSelected)
end

function QuestLog:OnQuestTrackUncheckBtn(wndHandler, wndControl) -- QuestTrackCheckBtn
	local queSelected = wndControl:GetData()
	queSelected:SetTracked(false)
	wndControl:SetTooltip(Apollo.GetString("QuestLog_AddToTracker"))
	Event_FireGenericEvent("GenericEvent_QuestLog_TrackBtnClicked", queSelected)
end

function QuestLog:OnQuestShareBtn(wndHandler, wndControl) -- QuestShareBtn
	local queSelected = self.wndRightSide:GetData()
	queSelected:Share()
end

function QuestLog:OnQuestCallBtn(wndHandler, wndControl) -- QuestCallBtn or QuestInfoCostumeWindow
	local queSelected = self.wndRightSide:GetData()
	CommunicatorLib.CallContact(queSelected)
	Event_FireGenericEvent("ToggleCodex") -- Hide codex, not sure if we want this
end

function QuestLog:OnQuestLinkBtn(wndHandler, wndControl)
	local queSelected = self.wndRightSide:GetData()
	Event_FireGenericEvent("GenericEvent_QuestLink", queSelected)
end

function QuestLog:OnQuestAbandonBtn(wndHandler, wndControl) -- QuestAbandonBtn
	local queSelected = self.wndRightSide:GetData()
	queSelected:Abandon()
	self.wndRightSide:Show(false)
	self.wndQuestInfoControls:Show(false)
end

function QuestLog:OnQuestHideBtn(wndHandler, wndControl) -- QuestInfoControlsHideBtn
	local queSelected = self.wndRightSide:GetData()
	queSelected:ToggleIgnored()
	self.wndRightSide:Show(false)
	self.wndQuestInfoControls:Show(false)
end

function QuestLog:OnQuestAbandonPopoutClose(wndHandler, wndControl) -- QuestAbandonPopoutClose
	self.wndMain:FindChild("QuestAbandonConfirm"):Show(false)
end

-----------------------------------------------------------------------------------------------
-- State Updates
-----------------------------------------------------------------------------------------------

function QuestLog:OnEpisodeStateChanged(idEpisode, eOldState, eNewState)
	if self.wndMain == nil or not self.wndMain:IsValid() then
		return
	end

	local epiEpisode = QuestLib.GetEpisode(idEpisode)
	if epiEpisode == nil then
		return
	end
	
	local fnDoesCategoryHaveQuests, fnDoesCategoryEpisodeHaveQuests = self:GetHaveQuestFunctions()
	local fnHaveWorldStoryQuests, fnEpisodeHasWorldStoryQuests = self:GetHaveWorldStoryQuestFunctions()
	local arAllCategories = QuestLib.GetKnownCategories()
	
	if epiEpisode:IsWorldStory() then
		if not fnHaveWorldStoryQuests(arAllCategories, QuestLib.GetAllEpisodes(self.wndLeftFilterFinished:IsChecked(), true)) then
			
			local wndTop = self.arLeftTreeMap["CWorldStory"]
			if wndTop ~= nil and wndTop:IsValid() then
				wndTop:Destroy()
			end
		elseif not fnEpisodeHasWorldStoryQuests(arAllCategories, epiEpisode) then
			
			local wndMiddle = self.arLeftTreeMap["CWorldStory".."E"..epiEpisode:GetId()]
			if wndMiddle ~= nil and wndMiddle:IsValid() then
				wndMiddle:Destroy()
			end
		end
	else
		for idx, qcCategory in pairs(arAllCategories) do
			if not fnDoesCategoryHaveQuests(qcCategory) then
			
				local wndTop = self.arLeftTreeMap["C"..qcCategory:GetId()]
				if wndTop ~= nil and wndTop:IsValid() then
					wndTop:Destroy()
				end
			elseif not fnDoesCategoryEpisodeHaveQuests(qcCategory, epiEpisode) then
				
				local wndMiddle = self.arLeftTreeMap["C"..qcCategory:GetId().."E"..epiEpisode:GetId()]
				if wndMiddle ~= nil and wndMiddle:IsValid() then
					wndMiddle:Destroy()
				end
			end
		end
	end
	
	self:ResizeTree()
end

function QuestLog:OnQuestStateChanged(queUpdated, eState)
	if self.wndMain and self.wndMain:IsValid() then
		if self:CheckLeftSideFilters(queUpdated) then
			
			local qcCategory = queUpdated:GetCategory()
			local epiEpisode = queUpdated:GetEpisode()
			
			local strCategoryKey
			local strEpisodeKey
			local strQuestKey
		
			if epiEpisode:IsWorldStory() then
				strCategoryKey = "CWorldStory"
				strEpisodeKey = strCategoryKey.."E"..epiEpisode:GetId()
				strQuestKey = strEpisodeKey.."Q"..queUpdated:GetId()
			elseif epiEpisode:IsZoneStory() or epiEpisode:IsRegionalStory() then
				strCategoryKey = "C"..qcCategory:GetId()
				strEpisodeKey = strCategoryKey.."E"..epiEpisode:GetId()
				strQuestKey = strEpisodeKey.."Q"..queUpdated:GetId()
			else
				strCategoryKey = "C"..qcCategory:GetId()
				strEpisodeKey = strCategoryKey.."ETasks"
				strQuestKey = strEpisodeKey.."Q"..queUpdated:GetId()
			end
			
			
			local wndTop = self.arLeftTreeMap[strCategoryKey]
			if wndTop ~= nil and wndTop:IsValid() then
				local wndTopLevelBtn = wndTop:FindChild("TopLevelBtn")
				if wndTopLevelBtn:IsChecked() then
					self:OnTopLevelBtnCheck(wndTopLevelBtn, wndTopLevelBtn)
		
					local wndMiddle = self.arLeftTreeMap[strEpisodeKey]
					if wndMiddle ~= nil and wndMiddle:IsValid() then
						local wndBot = self.arLeftTreeMap[strQuestKey]
						if wndBot ~= nil and wndBot:IsValid() then
							local wndBottomLevelBtn = wndBot:FindChild("BottomLevelBtn")
							if wndBottomLevelBtn:IsChecked() then
								self:OnBottomLevelBtnCheck(wndBottomLevelBtn, wndBottomLevelBtn)
							end
						end
					end
				end
			else
				self:RedrawLeftTree()
			end
		
		
			if self.wndRightSide ~= nil and self.wndRightSide:IsShown() then
				local queCurrent = self.wndRightSide:GetData()
				if queCurrent ~= nil and  queCurrent == queUpdated then
					self:DrawRightSide(queCurrent)
					self:ResizeRight()
				end
			end
			
			self:ResizeTree()
		else
			local wndBottom = self.tTreeQuestsById[queUpdated:GetId()]
			if wndBottom ~= nil and wndBottom:IsValid() then
				self:HelperRemoveBottomLevelWindow(wndBot, queUpdated)
			end
			
			if self.wndRightSide ~= nil and self.wndRightSide:IsShown() then
				local queCurrent = self.wndRightSide:GetData()
				if queCurrent ~= nil and  queCurrent == queUpdated then
					self.wndRightSide:Show(false)
					self.wndQuestInfoControls:Show(false)
				end
			end
		end
	end

	if ktChatNotificationStrings[eState] then
		ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_System, String_GetWeaselString(ktChatNotificationStrings[eState], queUpdated:GetTitle()))
	end
end

function QuestLog:OnQuestTrackedChanged(queUpdated, bTracked)
	if not self.tTreeQuestsById then
		return
	end
	
	local wndBottom = self.tTreeQuestsById[queUpdated:GetId()]
	
	if wndBottom == nil or not wndBottom:IsShown() then
		return
	end
	
	wndBottom:FindChild("BottomLevelTrackQuestBtn"):SetCheck(bTracked)
end

function QuestLog:OnQuestObjectiveUpdated(queUpdated)
	if self.wndRightSide == nil or not self.wndRightSide:IsShown() then
		return
	end
	
	local queCurrent = self.wndRightSide:GetData()
	if queCurrent ~= nil and queCurrent == queUpdated then
		self:DrawRightSide(queCurrent)
		self:ResizeRight()
	end
end

-----------------------------------------------------------------------------------------------
-- Quest Sharing
-----------------------------------------------------------------------------------------------

function QuestLog:OnDialog_QuestShare(queToShare, unitTarget)
	if self.wndShare == nil then
		self.wndShare = Apollo.LoadForm(self.xmlDoc, "ShareQuestNotice", nil, self)
	end
	self.wndShare:ToFront()
	self.wndShare:Show(true)
	self.wndShare:SetData(queToShare)
	self.wndShare:FindChild("NoticeText"):SetText(String_GetWeaselString(Apollo.GetString("QuestLog_ShareAQuest"), unitTarget:GetName(), queToShare:GetTitle()))

	Apollo.CreateTimer("ShareTimeout", Quest.kQuestShareAcceptTimeoutMs / 1000.0, false)
	Apollo.StartTimer("ShareTimeout")
end

function QuestLog:OnShareCancel(wndHandler, wndControl)
	local queToShare = self.wndShare:GetData()
	if queToShare then
		queToShare:RejectShare()
	end
	if self.wndShare then
		self.wndShare:Destroy()
		self.wndShare = nil
	end
	Apollo.StopTimer("ShareTimeout")
end

function QuestLog:OnShareAccept(wndHandler, wndControl)
	local queToShare = self.wndShare:GetData()
	if queToShare then
		queToShare:AcceptShare()
	end
	if self.wndShare then
		self.wndShare:Destroy()
		self.wndShare = nil
	end
	Apollo.StopTimer("ShareTimeout")
end

function QuestLog:OnShareTimeout()
	self:OnShareCancel()
end

-----------------------------------------------------------------------------------------------
-- Reward Building Helpers
-----------------------------------------------------------------------------------------------

function QuestLog:HelperBuildRewardsRec(wndReward, tRewardData, bReceived)
	if not tRewardData then
		return
	end

	local strText = ""
	local strSprite = ""

	if tRewardData.eType == Quest.Quest2RewardType_Item then
		if not tRewardData.itemReward then
			wndReward:Destroy()
			return
		end
		strText = tRewardData.itemReward:GetName()
		strSprite = tRewardData.itemReward:GetIcon()
		Tooltip.GetItemTooltipForm(self, wndReward, tRewardData.itemReward, {bPrimary = true, bSelling = false, itemCompare = tRewardData.itemReward:GetEquippedItemForItemType()})
		wndReward:FindChild("RewardItemCantUse"):Show(self:HelperPrereqFailed(tRewardData.itemReward))
		wndReward:FindChild("RewardItemText"):SetTextColor(karEvalColors[tRewardData.itemReward:GetItemQuality()])
		wndReward:FindChild("RewardIcon"):SetText(tRewardData.nAmount > 1 and tRewardData.nAmount or "")
		wndReward:FindChild("RewardIcon"):SetData(tRewardData.itemReward)
	elseif tRewardData.eType == Quest.Quest2RewardType_Reputation then
		strText = String_GetWeaselString(Apollo.GetString("Dialog_FactionRepReward"), tRewardData.nAmount, tRewardData.strFactionName)
		strSprite = "Icon_ItemMisc_UI_Item_Parchment"
		wndReward:SetTooltip(strText)
	elseif tRewardData.eType == Quest.Quest2RewardType_TradeSkillXp then
		strText = String_GetWeaselString(Apollo.GetString("Dialog_TradeskillXPReward"), tRewardData.nXP, tRewardData.strTradeskill)
		strSprite = "Icon_ItemMisc_tool_0001"
		wndReward:SetTooltip(strText)
	elseif tRewardData.eType == Quest.Quest2RewardType_Money then
		if tRewardData.eCurrencyType == Money.CodeEnumCurrencyType.Credits then
			local nInCopper = tRewardData.nAmount
			if nInCopper >= 1000000 then
				strText = String_GetWeaselString(Apollo.GetString("CRB_Platinum"), math.floor(nInCopper / 1000000))
			end
			if nInCopper >= 10000 then
				strText = strText .. " " .. String_GetWeaselString(Apollo.GetString("CRB_Gold"), math.floor(nInCopper % 1000000 / 10000))
			end
			if nInCopper >= 100 then
				strText = strText .. " " .. String_GetWeaselString(Apollo.GetString("CRB_Silver"), math.floor(nInCopper % 10000 / 100))
			end
			strText = strText .. " " .. String_GetWeaselString(Apollo.GetString("CRB_Copper"), math.floor(nInCopper % 100))
			strSprite = "ClientSprites:Icon_ItemMisc_bag_0001"
			wndReward:SetTooltip(strText)
		else
			local tDenomInfo = GameLib.GetPlayerCurrency(tRewardData.eCurrencyType or tRewardData.idObject):GetDenomInfo()
			if tDenomInfo ~= nil then
				strText = tRewardData.nAmount .. " " .. tDenomInfo[1].strName
				strSprite = "ClientSprites:Icon_ItemMisc_bag_0001"
				wndReward:SetTooltip(strText)
			end
		end
	end

	wndReward:FindChild("RewardIcon"):SetSprite(strSprite)
	wndReward:FindChild("RewardItemText"):SetText(strText)
end

function QuestLog:HelperBuildXPRewardsRec(wndReward, bReceived)
	if not bReceived then
		return
	end

	local strText = String_GetWeaselString(Apollo.GetString("CRB_XPAmountInteger"), bReceived)
	local strSprite = "IconSprites:Icon_Modifier_xp_001"

	wndReward:FindChild("RewardIcon"):SetSprite(strSprite)
	wndReward:FindChild("RewardItemText"):SetText(strText)
	wndReward:SetTooltip(strText)
end

function QuestLog:OnRewardIconMouseUp(wndHandler, wndControl, eMouseButton)
	if eMouseButton == GameLib.CodeEnumInputMouse.Right and wndHandler:GetData() then
		Event_FireGenericEvent("GenericEvent_ContextMenuItem", wndHandler:GetData())
	end
end

-----------------------------------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------------------------------

function QuestLog:HelperBuildObjectiveTitleString(queQuest, tObjective, bIsTooltip)
	local strResult = string.format("<T Font=\"CRB_InterfaceMedium\" TextColor=\"UI_TextHoloBody\">%s</T>", tObjective.strDescription)

	-- Prefix Optional or Progress if it hasn't been finished yet
	if tObjective.nCompleted < tObjective.nNeeded then
		if tObjective and not tObjective.bIsRequired then
			strResult = string.format("<T Font=\"CRB_InterfaceMedium_B\" TextColor=\"UI_TextHoloBody\">%s</T>%s", Apollo.GetString("QuestLog_Optional"), strResult)
		end
		local bQuestIsNotCompleted = queQuest:GetState() ~= Quest.QuestState_Completed -- if quest is complete, hide the % readouts.
		if tObjective.nNeeded > 1 and queQuest:DisplayObjectiveProgressBar(tObjective.nIndex) and bQuestIsNotCompleted then
			local nCompleted = queQuest:GetState() == Quest.QuestState_Completed and tObjective.nNeeded or tObjective.nCompleted
			local nPercentText = String_GetWeaselString(Apollo.GetString("CRB_Percent"), math.floor(nCompleted / tObjective.nNeeded * 100))
			strResult = string.format("<T Font=\"CRB_InterfaceMedium_B\" TextColor=\"UI_TextHoloBody\">%s </T>%s", nPercentText, strResult)
		elseif tObjective.nNeeded > 1 and bQuestIsNotCompleted then
			local nCompleted = queQuest:GetState() == Quest.QuestState_Completed and tObjective.nNeeded or tObjective.nCompleted
			local nPercentText = String_GetWeaselString(Apollo.GetString("QuestTracker_ValueComplete"), Apollo.FormatNumber(nCompleted, 0, true), Apollo.FormatNumber(tObjective.nNeeded, 0, true))
			strResult = string.format("<T Font=\"CRB_InterfaceMedium_B\" TextColor=\"UI_TextHoloBody\">%s </T>%s", nPercentText, strResult)
		end
	end

	return strResult
end

function QuestLog:HelperBuildObjectiveProgBar(queQuest, tObjective, wndObjective, bComplete)
	if tObjective.nNeeded > 1 and queQuest:DisplayObjectiveProgressBar(tObjective.nIndex) then
		local wndObjectiveProg = self:FactoryCacheProduce(wndObjective, "QuestProgressItem", "QuestProgressItem")
		local nCompleted = bComplete and tObjective.nNeeded or tObjective.nCompleted
		local nNeeded = tObjective.nNeeded
		wndObjectiveProg:FindChild("QuestProgressBar"):SetMax(nNeeded)
		wndObjectiveProg:FindChild("QuestProgressBar"):SetProgress(nCompleted)
		wndObjectiveProg:FindChild("QuestProgressBar"):EnableGlow(nCompleted > 0 and nCompleted ~= nNeeded)
	end
end

function QuestLog:CheckLeftSideFilters(queQuest)
	local bCompleteState = queQuest:GetState() == Quest.QuestState_Completed
	local bResult1 = self.wndLeftFilterActive:IsChecked() and not bCompleteState and not queQuest:IsIgnored() and queQuest:IsKnown()
	local bResult2 = self.wndLeftFilterFinished:IsChecked() and bCompleteState
	local bResult3 = self.wndLeftFilterHidden:IsChecked() and queQuest:IsIgnored()

	return bResult1 or bResult2 or bResult3
end

function QuestLog:HelperPrereqFailed(tCurrItem)
	return tCurrItem and tCurrItem:IsEquippable() and not tCurrItem:CanEquip()
end

function QuestLog:HelperPrefixTimeString(fTime, strAppend, strColorOverride)
	local fSeconds = fTime % 60
	local fMinutes = fTime / 60
	local strColor = "fffffc00"
	if strColorOverride then
		strColor = strColorOverride
	elseif fMinutes < 1 and fSeconds <= 30 then
		strColor = "ffff0000"
	end
	return string.format("<T Font=\"CRB_InterfaceMedium_B\" TextColor=\"%s\">(%d:%.02d) </T>%s", strColor, fMinutes, fSeconds, strAppend)
end

function QuestLog:FactoryCacheProduce(wndParent, strFormName, strKey)
	local wnd = self.arLeftTreeMap[strKey]
	if not wnd or not wnd:IsValid() then
		wnd = Apollo.LoadForm(self.xmlDoc, strFormName, wndParent, self)
		wnd:SetData(strKey)
		self.arLeftTreeMap[strKey] = wnd

		for strKey, wndCached in pairs(self.arLeftTreeMap) do
			if not self.arLeftTreeMap[strKey]:IsValid() then
				self.arLeftTreeMap[strKey] = nil
			end
		end
	end
	return wnd
end

local QuestLogInst = QuestLog:new()
QuestLogInst:Init()
