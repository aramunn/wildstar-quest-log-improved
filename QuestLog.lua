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
	Apollo.RegisterEventHandler("QuestStateChanged", 	"OnQuestStateChanged", self) -- Routes to OnDestroyQuestObject if completed/botched
	Apollo.RegisterEventHandler("Group_Join",			"OnGroupUpdate", self)
	Apollo.RegisterEventHandler("Group_Left",			"OnGroupUpdate", self)

	self:Initialize()
end

function QuestLog:OnInterfaceMenuListHasLoaded()
	Event_FireGenericEvent("InterfaceMenuList_NewAddOn", Apollo.GetString("InterfaceMenu_QuestLog"), {"ToggleQuestLog", "Codex", "Icon_Windows32_UI_CRB_InterfaceMenu_QuestLog"})
end

function QuestLog:Initialize()
	if (self.wndMain and self.wndMain:IsValid()) or not g_wndProgressLog then
		return
	end

	Apollo.RegisterEventHandler("EpisodeStateChanged", 			"DestroyAndRedraw", self) -- Not sure if this can be made stricter
	Apollo.RegisterEventHandler("QuestObjectiveUpdated", 		"OnQuestObjectiveUpdated", self)
	Apollo.RegisterEventHandler("QuestTrackedChanged",			"OnQuestTrackedChanged", self)
	Apollo.RegisterEventHandler("GenericEvent_ShowQuestLog", 	"OnGenericEvent_ShowQuestLog", self)
	Apollo.RegisterTimerHandler("RedrawQuestLogInOneSec", 		"DestroyAndRedraw", self) -- TODO Remove if possible

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

	local qcTop = queTarget:GetCategory()
	local epiMid = queTarget:GetEpisode()

	self:RedrawLeftTree() -- Add categories

	if queTarget:GetState() == Quest.QuestState_Unknown then
		self.wndQuestInfoControls:Show(false)

		self:DrawUnknownRightSide(queTarget)
		self:ResizeRight()
		self:ResizeTree()
		return
	end

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
		if wndTop then
			wndTop:FindChild("TopLevelBtn"):SetCheck(true)
			self:RedrawLeftTree() -- Add episodes

			if epiMid then
				local wndMiddle = self.arLeftTreeMap[strEpisodeKey]
				if wndMiddle then
					wndMiddle:FindChild("MiddleLevelBtn"):SetCheck(true)
					self:RedrawLeftTree() -- Add quests

					local wndBot = self.arLeftTreeMap[strQuestKey]
					if wndBot then
						wndBot:FindChild("BottomLevelBtn"):SetCheck(true)
						self:OnBottomLevelBtnCheck(wndBot:FindChild("BottomLevelBtn"), wndBot:FindChild("BottomLevelBtn"))
					end
				end
			end
		end
	end

	self:ResizeTree()
	self:RedrawRight()
end

function QuestLog:DestroyAndRedraw() -- TODO, remove as much as possible that calls this
	if self.wndMain and self.wndMain:IsValid() then
		self.wndLeftSideScroll:DestroyChildren()
		self.wndLeftSideScroll:SetVScrollPos(0)
	end

	self.arLeftTreeMap = {}

	self:RedrawLeftTree() -- Add categories

	-- Start with all expanded
	self:OnExpandAllQuestsBtn(nil, nil)

	self:RedrawRight()

	-- Start with no quests checked
	self.wndQuestInfoControls:Show(false)
	self.wndRightSide:Show(false)
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

function QuestLog:RedrawLeftTree()
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

	local activeQuestsProgressBar = self.wndLeftFilterActive:FindChild("ActiveQuestsProgressBar")
	activeQuestsProgressBar:SetMax(self.nQuestCountMax)
	activeQuestsProgressBar:SetProgress(nQuestCount)
	activeQuestsProgressBar:SetBarColor(strColor)

	local tCategoryEpisodeHaveQuestsCache = {}
	local tCategoryHaveQuestsCache = {}

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

	local arCategories = {}
	local arEpisodes = {}
	local arQuests = {}
	local bHasTasks = {}

	local bShowCompleted = self.wndLeftFilterFinished:IsChecked()
	local arAllEpisodes = QuestLib.GetAllEpisodes(bShowCompleted, true)

	-- Build data for world story
	local bWorldStoryHasData = false
	for idx, epiEpisode in pairs(arAllEpisodes) do
		if epiEpisode:IsWorldStory() then
			for idx2, qcCategory in pairs(QuestLib.GetKnownCategories()) do
				for idx3, queQuest in pairs(epiEpisode:GetAllQuests(qcCategory:GetId())) do
					if self:CheckLeftSideFilters(queQuest) then
						bWorldStoryHasData = true
						break
					end
				end
			end
		end
		if bWorldStoryHasData then
			break
		end
	end

	if bWorldStoryHasData then
		local strCategoryKey = "CWorldStory" -- Why can't we have nice things :(
		local wndTop = self.arLeftTreeMap[strCategoryKey]
		if wndTop ~= nil and wndTop:IsValid() and wndTop:FindChild("TopLevelBtn"):IsChecked() then
			for idx, epiEpisode in pairs(arAllEpisodes) do
				if epiEpisode:IsWorldStory() then

					local strEpisodeKey = strCategoryKey.."E"..epiEpisode:GetId()
					local wndMiddle = self.arLeftTreeMap[strEpisodeKey]
					local bAddQuests = wndMiddle ~= nil and wndMiddle:IsValid() and wndMiddle:FindChild("MiddleLevelBtn"):IsChecked()
					local bEpHasQuests = false
					for idx2, qcCategory in pairs(QuestLib.GetKnownCategories()) do
						for idx3, queQuest in pairs(epiEpisode:GetAllQuests(qcCategory:GetId())) do
							if self:CheckLeftSideFilters(queQuest) then
								bEpHasQuests = true
								if bAddQuests then
									arQuests[strEpisodeKey] = arQuests[strEpisodeKey] or {}
									table.insert(arQuests[strEpisodeKey], queQuest)
								else
									break
								end
							end
						end
						
						if bEpHasQuests and not bAddQuests then
							break
						end
					end
					
					arEpisodes[strCategoryKey] = arEpisodes[strCategoryKey] or {}
					if bEpHasQuests then
						table.insert(arEpisodes[strCategoryKey], epiEpisode)
					end
				end
			end
		end
	end

	-- Build data
	for idx1, qcCategory in pairs(QuestLib.GetKnownCategories()) do
		if fnDoesCategoryHaveQuests(qcCategory) then
			table.insert(arCategories, qcCategory)

			local strCategoryKey = "C"..qcCategory:GetId()
			local wndTop = self.arLeftTreeMap[strCategoryKey]
			if wndTop ~= nil and wndTop:IsValid() and wndTop:FindChild("TopLevelBtn"):IsChecked() then
				for idx2, epiEpisode in pairs(qcCategory:GetEpisodes()) do
					if not epiEpisode:IsWorldStory() and fnDoesCategoryEpisodeHaveQuests(qcCategory, epiEpisode) then
						local arQuestTableToUse
						local strEpisodeKey

						if epiEpisode:IsZoneStory() or epiEpisode:IsRegionalStory() then
							arEpisodes[strCategoryKey] = arEpisodes[strCategoryKey] or {}
							table.insert(arEpisodes[strCategoryKey], epiEpisode)
							strEpisodeKey = strCategoryKey.."E"..epiEpisode:GetId()
						else -- task
							bHasTasks[strCategoryKey] = true
							strEpisodeKey = strCategoryKey.."ETasks"
						end

						local wndMiddle = self.arLeftTreeMap[strEpisodeKey]
						if wndMiddle ~= nil and wndMiddle:IsValid() and wndMiddle:FindChild("MiddleLevelBtn"):IsChecked() then
							for idx3, queQuest in pairs(epiEpisode:GetAllQuests(qcCategory:GetId())) do
								if self:CheckLeftSideFilters(queQuest) then
									arQuests[strEpisodeKey] = arQuests[strEpisodeKey] or {}
									table.insert(arQuests[strEpisodeKey], queQuest)
								end
							end
						end
					end
				end
			end
		end
	end

	-- Build windows from data
	local fnBuildCategoryEpisodeQuests = function(strEpisodeKey, wndMiddle)
		if wndMiddle:FindChild("MiddleLevelBtn"):IsChecked() then
			local wndMiddleLevelItems = wndMiddle:FindChild("MiddleLevelItems")
			arQuests[strEpisodeKey] = arQuests[strEpisodeKey] or {}
			for idx3, queQuest in pairs(arQuests[strEpisodeKey]) do
				local strQuestKey = strEpisodeKey.."Q"..queQuest:GetId()
				local wndBot = self:FactoryCacheProduce(wndMiddleLevelItems, "BottomLevelItem", strQuestKey)
				self:HelperSetupBottomLevelWindow(wndBot, queQuest)
			end
		end
	end

	local fnBuildCategoryEpisodes = function(strCategoryKey, wndTop)
		if wndTop:FindChild("TopLevelBtn"):IsChecked() then
			local wndTopLevelItems = wndTop:FindChild("TopLevelItems")

			arEpisodes[strCategoryKey] = arEpisodes[strCategoryKey] or {}
			if #arEpisodes[strCategoryKey] > 0 then
				for idx2, epiEpisode in pairs(arEpisodes[strCategoryKey]) do
					local strEpisodeKey = strCategoryKey.."E"..epiEpisode:GetId()
					local wndMiddle = self:FactoryCacheProduce(wndTopLevelItems, "MiddleLevelItem", strEpisodeKey)
					self:HelperSetupMiddleLevelWindow(wndMiddle, epiEpisode)

					if epiEpisode:IsZoneStory() then
						wndMiddle:SetData("Z"..wndMiddle:GetData()) -- Needed for current sorting method so these are top
					end

					fnBuildCategoryEpisodeQuests(strEpisodeKey, wndMiddle)
				end
			end

			if bHasTasks[strCategoryKey] then
				local strEpisodeKey = strCategoryKey.."ETasks"
				local wndMiddle = self:FactoryCacheProduce(wndTopLevelItems, "MiddleLevelItem", strEpisodeKey)
				self:HelperSetupFakeMiddleLevelWindow(wndMiddle, Apollo.GetString("QuestLog_Tasks"))
				wndMiddle:SetData("")

				fnBuildCategoryEpisodeQuests(strEpisodeKey, wndMiddle)
			end
		end
	end

	if bWorldStoryHasData then
		local strCategoryKey = "CWorldStory"
		local wndTop = self:FactoryCacheProduce(self.wndLeftSideScroll, "TopLevelItem", strCategoryKey)
		wndTop:FindChild("TopLevelBtn"):SetText(Apollo.GetString("QuestLog_WorldStory"))
		fnBuildCategoryEpisodes(strCategoryKey, wndTop)
	end

	for idx1, qcCategory in pairs(arCategories) do
		local strCategoryKey = "C"..qcCategory:GetId()
		local wndTop = self:FactoryCacheProduce(self.wndLeftSideScroll, "TopLevelItem", strCategoryKey)
		wndTop:FindChild("TopLevelBtn"):SetText(qcCategory:GetTitle())
		fnBuildCategoryEpisodes(strCategoryKey, wndTop)
	end
end

function QuestLog:HelperSetupMiddleLevelWindow(wndMiddle, epiEpisode)
	local tEpisodeProgress = epiEpisode:GetProgress()
	wndMiddle:FindChild("MiddleLevelBtnText"):SetText(epiEpisode:GetTitle())
	wndMiddle:FindChild("MiddleLevelProgBar"):SetMax(tEpisodeProgress.nTotal)
	wndMiddle:FindChild("MiddleLevelProgBar"):SetProgress(tEpisodeProgress.nCompleted)
	wndMiddle:FindChild("MiddleLevelIcon"):SetTooltip(self.wndLeftFilterFinished:IsChecked() and "" or Apollo.GetString("QuestLog_MoreQuestsToComplete"))
	wndMiddle:FindChild("MiddleLevelIcon"):SetSprite("kitIcon_Holo_Checkbox")
end

function QuestLog:HelperSetupFakeMiddleLevelWindow(wndMiddle, strText)
	local tEpisodeProgress = { nTotal = 100, nCompleted = 0 }
	wndMiddle:FindChild("MiddleLevelBtnText"):SetText(strText)
	wndMiddle:FindChild("MiddleLevelProgBar"):SetMax(tEpisodeProgress.nTotal)
	wndMiddle:FindChild("MiddleLevelProgBar"):SetProgress(tEpisodeProgress.nCompleted)
	wndMiddle:FindChild("MiddleLevelIcon"):SetTooltip(self.wndLeftFilterFinished:IsChecked() and "" or Apollo.GetString("QuestLog_MoreQuestsToComplete"))
	wndMiddle:FindChild("MiddleLevelIcon"):SetSprite(self.wndLeftFilterFinished:IsChecked() and "kitIcon_Holo_Checkbox" or "kitIcon_Holo_Exclamation")
end

function QuestLog:HelperSetupBottomLevelWindow(wndBot, queQuest)
	local wndBottomLevelBtn = wndBot:FindChild("BottomLevelBtn")
	local wndBottomLevelBtnText = wndBot:FindChild("BottomLevelBtnText")

	local bOptionalQuest = queQuest:IsOptionalForEpisode(queQuest:GetEpisode():GetId())
	wndBottomLevelBtn:SetData(queQuest)
	questText = bOptionalQuest and String_GetWeaselString(Apollo.GetString("QuestLog_OptionalAppend"), queQuest:GetTitle()) or queQuest:GetTitle()
	questText = " ["..queQuest:GetConLevel().."] "..questText
	wndBottomLevelBtnText:SetText(questText)
	wndBottomLevelBtn:SetText(questText)

	local strBottomLevelIconSprite = ""
	local bHasCall = queQuest:GetContactInfo()
	local eState = queQuest:GetState()
	if eState == Quest.QuestState_Botched then
		strBottomLevelIconSprite = "CRB_Basekit:kitIcon_Metal_CircleX"
	elseif eState == Quest.QuestState_Abandoned or eState == Quest.QuestState_Mentioned then
		strBottomLevelIconSprite = "CRB_Basekit:kitIcon_Metal_CircleExclamation"
	elseif eState == Quest.QuestState_Achieved and bHasCall then
		strBottomLevelIconSprite = "CRB_Basekit:kitIcon_Metal_CircleCheckmarkAccent"
	elseif eState == Quest.QuestState_Achieved and not bHasCall then
		strBottomLevelIconSprite = "CRB_Basekit:kitIcon_Metal_CircleCheckmark"
	end
	wndBot:FindChild("BottomLevelBtnIcon"):SetSprite(strBottomLevelIconSprite)

	local wndQuickTrackBtn = wndBot:FindChild("QuickTrackBtn")
	local wndBottomItemTree = wndBot:FindChild("Tree")
	local bIsTracked = queQuest:IsTracked()
	wndQuickTrackBtn:SetCheck(bIsTracked)
	wndQuickTrackBtn:Enable(eState ~= Quest.QuestState_Botched)
	-- Only show if quest is active
	if eState == Quest.QuestState_Accepted or eState == Quest.QuestState_Achieved or eState == Quest.QuestState_Botched then
		wndQuickTrackBtn:Show(true)
		wndBottomItemTree:Show(false)
	else
		wndQuickTrackBtn:Show(false)
		wndBottomItemTree:Show(true)
	end
end

function QuestLog:ResizeTree()
	local wndDeepestSelected = nil

	for idx1, wndTop in pairs(self.wndLeftSideScroll:GetChildren()) do
		local wndTopLevelBtn = wndTop:FindChild("TopLevelBtn")
		local wndTopLevelItems = wndTop:FindChild("TopLevelItems")

		if wndTopLevelBtn:IsChecked() then
			wndDeepestSelected = wndTop
			for idx2, wndMiddle in pairs(wndTopLevelItems:GetChildren()) do
				local wndMiddleLevelItems = wndMiddle:FindChild("MiddleLevelItems")

				if not wndMiddle:FindChild("MiddleLevelBtn"):IsChecked() then
					wndMiddleLevelItems:DestroyChildren()
				else
					wndDeepestSelected = wndMiddle
				end

				for idx3, wndBot in pairs(wndMiddleLevelItems:GetChildren()) do
					if wndBot:FindChild("BottomLevelBtn"):IsChecked() then
						wndDeepestSelected = wndBot
					end
				end

				local nItemHeights = wndMiddleLevelItems:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop)
				if nItemHeights > 0 then
					nItemHeights = nItemHeights + 3
				end

				local nMiddleLeft, nMiddleTop, nMiddleRight, nMiddleBottom = wndMiddle:GetAnchorOffsets()
				wndMiddle:SetAnchorOffsets(nMiddleLeft, nMiddleTop, nMiddleRight, nMiddleTop + self.knMiddleLevelHeight + nItemHeights)
			end
		else
			wndTopLevelItems:DestroyChildren()
		end

		local nItemHeights = wndTopLevelItems:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop, function(a,b) return a:GetData() > b:GetData() end) -- Tasks to bottom
		local nTopLeft, nTopTop, nTopRight, nTopBottom = wndTop:GetAnchorOffsets()
		wndTop:SetAnchorOffsets(nTopLeft, nTopTop, nTopRight, nTopTop + self.knTopLevelHeight + nItemHeights)
	end

	self.wndLeftSideScroll:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop)
	self.wndLeftSideScroll:RecalculateContentExtents()

	if wndDeepestSelected ~= nil then
		self.wndLeftSideScroll:EnsureChildVisible(wndDeepestSelected)
	end
end

function QuestLog:ResizeRight()
	local nWidth, nHeight, nLeft, nTop, nRight, nBottom

	-- Objectives Content
	for key, wndObj in pairs(self.wndMain:FindChild("QuestInfoObjectivesList"):GetChildren()) do
		nWidth, nHeight = wndObj:FindChild("ObjectivesItemText"):SetHeightToContentHeight()
		nHeight = wndObj:FindChild("QuestProgressItem") and nHeight + wndObj:FindChild("QuestProgressItem"):GetHeight() or nHeight
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
	if eQuestState == Quest.QuestState_Completed and string.len(queSelected:GetCompletedSummary()) > 0 then
		strQuestSummary = queSelected:GetCompletedSummary()
	elseif string.len(queSelected:GetSummary()) > 0 then
		strQuestSummary = queSelected:GetSummary()
	end
	
	local nDifficultyLevel = queSelected:GetColoredDifficulty() or 1
	local tConData = ktConToUI[nDifficultyLevel]
	local strDifficulty = String_GetWeaselString(Apollo.GetString("QuestLog_Difficulty"), 
		"<T Font=\"CRB_InterfaceMedium\" TextColor=\""..tConData[2].."\"> "
		..String_GetWeaselString(Apollo.GetString("QuestLog_DifficultyTextAndNumber"), tConData[3], nDifficultyLevel).."</T>")
	wndRight:FindChild("QuestInfoDifficultyPic"):SetSprite(tConData[1])
	wndRight:FindChild("QuestInfoDifficultyPic"):SetTooltip(String_GetWeaselString(Apollo.GetString("QuestLog_IntendedLevel"), queSelected:GetTitle(), queSelected:GetConLevel()))
	wndRight:FindChild("QuestInfoDifficultyText"):SetAML("<P Font=\"CRB_InterfaceMedium_BB\" TextColor=\"UI_TextHoloBodyHighlight\">"..strDifficulty.."</P>")

	local bOptionalQuest = queSelected:IsOptionalForEpisode(epiParent:GetId())
	wndRight:FindChild("QuestInfoTitle"):SetTextColor(ApolloColor.new("UI_TextHoloTitle"))
	local strTitle = bOptionalQuest and String_GetWeaselString(Apollo.GetString("QuestLog_OptionalAppend"), queSelected:GetTitle()) or queSelected:GetTitle()
	wndRight:FindChild("QuestInfoTitle"):SetText(strTitle)

	if eQuestState == Quest.QuestState_Completed then
		wndRight:FindChild("QuestInfoTitleIcon"):SetTooltip(Apollo.GetString("QuestLog_HasBeenCompleted"))
		wndRight:FindChild("QuestInfoTitleIcon"):SetSprite("CRB_Basekit:kitIcon_Green_Checkmark")
		wndRight:FindChild("QuestInfoTitle"):SetText(String_GetWeaselString(Apollo.GetString("QuestLog_Completed"), strTitle))
		wndRight:FindChild("QuestInfoTitle"):SetTextColor(ApolloColor.new("UI_WindowTextChallengeGreenFlash"))
	elseif eQuestState == Quest.QuestState_Achieved then
		wndRight:FindChild("QuestInfoTitleIcon"):SetTooltip(Apollo.GetString("QuestLog_QuestReadyToTurnIn"))
		wndRight:FindChild("QuestInfoTitleIcon"):SetSprite("CRB_Basekit:kitIcon_Green_Checkmark")
	else
		wndRight:FindChild("QuestInfoTitleIcon"):SetTooltip(Apollo.GetString("QuestLog_ObjectivesNotComplete"))
		wndRight:FindChild("QuestInfoTitleIcon"):SetSprite("CRB_Basekit:kitIcon_Gold_Checkbox")
	end

	wndRight:FindChild("QuestInfoDescriptionText"):SetAML("<P Font=\"CRB_InterfaceMedium\" TextColor=\"UI_TextHoloBodyCyan\">"..strQuestSummary.."</P>")
	wndRight:FindChild("QuestInfoDescriptionText"):SetHeightToContentHeight()

	-- More Info
	local strMoreInfo = ""
	local tMoreInfoText = queSelected:GetMoreInfoText()
	if #tMoreInfoText > 0 then
		for idx, tValues in pairs(tMoreInfoText) do
			if string.len(tValues.strSay) > 0 or string.len(tValues.strResponse) > 0 then
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
		end
		wndRight:FindChild("QuestInfoObjectivesTitle"):SetText(Apollo.GetString("QuestLog_Objectives"))
	end

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
		local bIsTracked = queSelected:IsTracked()
		self.wndMain:FindChild("QuestAbandonPopoutBtn"):Enable(queSelected:CanAbandon())
		self.wndMain:FindChild("QuestTrackBtn"):Enable(eQuestState ~= Quest.QuestState_Botched)
		self.wndMain:FindChild("QuestTrackBtn"):SetText(bIsTracked and Apollo.GetString("QuestLog_Untrack") or Apollo.GetString("QuestLog_Track"))
		self.wndMain:FindChild("QuestTrackBtn"):SetTooltip(bIsTracked and Apollo.GetString("QuestLog_RemoveFromTracker") or Apollo.GetString("QuestLog_AddToTracker"))
	end
	--self.wndMain:FindChild("QuestInfoControlButtons"):ArrangeChildrenHorz(Window.CodeEnumArrangeOrigin.Middle)

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
		self.wndMain:FindChild("QuestInfoControlsBGShare"):Show(bCanShare)
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
	if epiParent then
		bIsTasks = epiParent:GetId() == 1
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
	if eQuestState == Quest.QuestState_Completed and string.len(queSelected:GetCompletedSummary()) > 0 then
		strQuestSummary = queSelected:GetCompletedSummary()
	elseif string.len(queSelected:GetSummary()) > 0 then
		strQuestSummary = queSelected:GetSummary()
	end

	local tConData = ktConToUI[queSelected:GetColoredDifficulty() or 1]
	local strDifficulty = String_GetWeaselString(Apollo.GetString("QuestLog_Difficulty"), "<T Font=\"CRB_InterfaceMedium\" TextColor=\""..tConData[2].."\"> "..tConData[3].."</T>")
	wndRight:FindChild("QuestInfoDifficultyPic"):SetSprite(tConData[1])
	wndRight:FindChild("QuestInfoDifficultyPic"):SetTooltip(String_GetWeaselString(Apollo.GetString("QuestLog_IntendedLevel"), queSelected:GetTitle(), queSelected:GetConLevel()))
	wndRight:FindChild("QuestInfoDifficultyText"):SetAML("<P Font=\"CRB_InterfaceMedium_B\" TextColor=\"UI_TextHoloBodyHighlight\">"..strDifficulty.."</P>")

	local bOptionalQuest = epiParent and queSelected:IsOptionalForEpisode(epiParent:GetId()) or false
	wndRight:FindChild("QuestInfoTitle"):SetTextColor(ApolloColor.new("white"))
	local strTitle = bOptionalQuest and String_GetWeaselString(Apollo.GetString("QuestLog_OptionalAppend"), queSelected:GetTitle()) or queSelected:GetTitle()
	wndRight:FindChild("QuestInfoTitle"):SetText(strTitle)

	wndRight:FindChild("QuestInfoTitleIcon"):SetTooltip(Apollo.GetString("QuestLog_ObjectivesNotComplete"))
	wndRight:FindChild("QuestInfoTitleIcon"):SetSprite("CRB_Basekit:kitIcon_Gold_Checkbox")

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
	self:RedrawLeftTree()
	self:ResizeTree()
end

function QuestLog:OnTopLevelBtnUncheck(wndHandler, wndControl)
	self:ResizeTree()
end

function QuestLog:OnMiddleLevelBtnCheck(wndHandler, wndControl)
	local nScrollPos = self.wndLeftSideScroll:GetVScrollPos()
	wndHandler:SetCheck(true)
	self:RedrawLeftTree()
	self:ResizeTree()
	self.wndLeftSideScroll:SetVScrollPos(nScrollPos)
end

function QuestLog:OnMiddleLevelBtnUncheck(wndHandler, wndControl)
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

function QuestLog:OnQuickTrackBtnCheck(wndHandler, wndControl)
  local queQuest = wndHandler:GetParent():FindChild("BottomLevelBtn"):GetData()
  queQuest:SetTracked(true)
  Event_FireGenericEvent("GenericEvent_QuestLog_TrackBtnClicked", queQuest)
  wndHandler:SetTooltip(Apollo.GetString("QuestLog_RemoveFromTracker"))
end

function QuestLog:OnQuickTrackBtnUncheck(wndHandler, wndControl)
  local queQuest = wndHandler:GetParent():FindChild("BottomLevelBtn"):GetData()
  queQuest:SetTracked(false)
  Event_FireGenericEvent("GenericEvent_QuestLog_TrackBtnClicked", queQuest)
  wndHandler:SetTooltip(Apollo.GetString("QuestLog_AddToTracker"))
end

-----------------------------------------------------------------------------------------------
-- Bottom Buttons and Quest Update Events
-----------------------------------------------------------------------------------------------

function QuestLog:OnQuestTrackBtn(wndHandler, wndControl) -- QuestTrackBtn
	local queSelected = self.wndRightSide:GetData()
	local bNewTrackValue = not queSelected:IsTracked()
	queSelected:SetTracked(bNewTrackValue)
	self.wndMain:FindChild("QuestTrackBtn"):SetText(bNewTrackValue and Apollo.GetString("QuestLog_Untrack") or Apollo.GetString("QuestLog_Track"))
	self.wndMain:FindChild("QuestTrackBtn"):SetTooltip(bNewTrackValue and Apollo.GetString("QuestLog_RemoveFromTracker") or Apollo.GetString("QuestLog_AddToTracker"))
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

function QuestLog:OnQuestAbandonBtn(wndHandler, wndControl) -- QuestAbandonBtn
	local queSelected = self.wndRightSide:GetData()
	queSelected:Abandon()
	self:OnDestroyQuestObject(queUpdated)
	self:DestroyAndRedraw()
	self.wndRightSide:Show(false)
	self.wndQuestInfoControls:Show(false)
end

function QuestLog:OnQuestHideBtn(wndHandler, wndControl) -- QuestInfoControlsHideBtn
	local queSelected = self.wndRightSide:GetData()
	queSelected:ToggleIgnored()
	self:OnDestroyQuestObject(queSelected)
	self:DestroyAndRedraw()
	self.wndRightSide:Show(false)
	self.wndQuestInfoControls:Show(false)
	Apollo.CreateTimer("RedrawQuestLogInOneSec", 1, false) -- TODO TEMP HACK, since Quest:ToggleIgnored() takes a while
end

function QuestLog:OnQuestAbandonPopoutClose(wndHandler, wndControl) -- QuestAbandonPopoutClose
	self.wndMain:FindChild("QuestAbandonConfirm"):Show(false)
end

-----------------------------------------------------------------------------------------------
-- State Updates
-----------------------------------------------------------------------------------------------

function QuestLog:OnQuestStateChanged(queUpdated, eState)
	if self.wndMain and self.wndMain:IsValid() then
		if eState == Quest.QuestState_Abandoned or eState == Quest.QuestState_Completed or eState == Quest.QuestState_Accepted or eState == Quest.QuestState_Achieved then
			self:OnDestroyQuestObject(queUpdated)
			self:DestroyAndRedraw()
		else -- Botched, Mentioned, Ignored, Unknown
			self:RedrawEverything()

			local queCurrent = self.wndRightSide:GetData()
			if queCurrent and queCurrent:GetId() == queUpdated:GetId() then
				self.wndRightSide:Show(false)
				self.wndQuestInfoControls:Show(false)
			end
		end
	end

	if ktChatNotificationStrings[eState] then
		ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_System, String_GetWeaselString(ktChatNotificationStrings[eState], queUpdated:GetTitle()))
	end
end

function QuestLog:OnQuestObjectiveUpdated(queUpdated)
	local queCurrent = self.wndRightSide:GetData()
	if queCurrent and queCurrent:GetId() == queUpdated:GetId() then
		self:RedrawEverything()
	end

	if queCurrent and queCurrent:GetState() == Quest.QuestState_Achieved then -- For some reason OnQuestStateChanged doesn't get called
		self:OnDestroyQuestObject(queUpdated)
		self:RedrawEverything()
	end
end

function QuestLog:OnDestroyQuestObject(queTarget) -- QuestStateChanged, QuestObjectiveUpdated
	if self.wndMain and self.wndMain:IsValid() and queTarget then
		local wndBot = self.wndLeftSideScroll:FindChildByUserData("Q"..queTarget:GetId())
		if wndBot then
			wndBot:Destroy()
			self:RedrawEverything()
		end
	end
end

function QuestLog:OnQuestTrackedChanged(queUpdated, bTracked)
	if self.wndRightSide:IsShown()
		and self.wndRightSide:GetData()
		and self.wndRightSide:GetData() == queUpdated then

		self:DrawRightSide(self.wndRightSide:GetData())
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
	local bResult1 = self.wndLeftFilterActive:IsChecked() and not bCompleteState and not queQuest:IsIgnored()
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

function QuestLog:ChangeAllLeftSideScrollChecks(set)
  for idx1, wndTop in pairs(self.wndLeftSideScroll:GetChildren()) do
    local wndTopLevelBtn = wndTop:FindChild("TopLevelBtn")
    local wndTopLevelItems = wndTop:FindChild("TopLevelItems")
    wndTopLevelBtn:SetCheck(set)
    for idx2, wndMiddle in pairs(wndTopLevelItems:GetChildren()) do
      local wndMiddleLevelBtn = wndMiddle:FindChild("MiddleLevelBtn")
      wndMiddleLevelBtn:SetCheck(set)
    end
  end
end

function QuestLog:OnExpandAllQuestsBtn(wndHandler, wndControl)
  self:ChangeAllLeftSideScrollChecks(true)
  self:RedrawLeftTree()
  self:ChangeAllLeftSideScrollChecks(true)
  self:RedrawLeftTree()
  self.wndLeftSideScroll:SetVScrollPos(0)
  self:ResizeTree()
end

function QuestLog:OnCollapseAllQuestsBtn(wndHandler, wndControl)
  self:ChangeAllLeftSideScrollChecks(false)
  self:RedrawLeftTree()
  self.wndLeftSideScroll:SetVScrollPos(0)
  self:ResizeTree()
end

local QuestLogInst = QuestLog:new()
QuestLogInst:Init()
