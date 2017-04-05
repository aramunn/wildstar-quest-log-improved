local QuestLogImproved = {}

function QuestLogImproved:HookQuestLogAddon()
  self.addonQuestLog = Apollo.GetAddon("QuestLog")
  if not self.addonQuestLog then
    Print("addonQuestLog is nil")
    return
  end
  
  local funcRedrawLeftTree = self.addonQuestLog.RedrawLeftTree
  self.addonQuestLog.RedrawLeftTree = function(ref, ...)
    funcRedrawLeftTree(ref, ...)
    self:PostRedrawLeftTree(ref)
  end
  
  self.addonQuestLog.OnCollapseAllQuestsBtn = function(ref)
    self:SetCheckAllLeftSide(false)
  end
  
  self.addonQuestLog.OnExpandAllQuestsBtn = function(ref)
    self:SetCheckAllLeftSide(true)
  end
end

function QuestLogImproved:PostRedrawLeftTree(addonQuestLog)
  local nQuestCount = QuestLib.GetCount()
  local strColor = "UI_BtnTextGreenNormal"
  if nQuestCount + 3 >= addonQuestLog.nQuestCountMax then
    strColor = "ffff0000"
  elseif nQuestCount + 10 >= addonQuestLog.nQuestCountMax then
    strColor = "ffffb62e"
  end
  local strActiveQuests = string.format("Active Quests (%d/%d)", nQuestCount, addonQuestLog.nQuestCountMax)
  addonQuestLog.wndLeftFilterActive:SetText(strActiveQuests)
  local activeQuestsProgressBar = addonQuestLog.wndLeftFilterActive:FindChild("ActiveQuestsProgressBar")
  activeQuestsProgressBar:SetMax(addonQuestLog.nQuestCountMax)
  activeQuestsProgressBar:SetProgress(nQuestCount)
  activeQuestsProgressBar:SetBarColor(strColor)
end

function QuestLogImproved:SetCheckAllLeftSide(bChecked)
  for idx, wnd in pairs(self.addonQuestLog.wndLeftSideScroll:GetChildren()) do
    local wndTopLevelBtn = wnd:FindChild("TopLevelBtn")
    wndTopLevelBtn:SetCheck(bChecked)
    if bChecked then
      self.addonQuestLog:OnTopLevelBtnCheck(wndTopLevelBtn, wndTopLevelBtn)
    end
  end
  self.addonQuestLog:RedrawLeftTree()
  self.addonQuestLog.wndLeftSideScroll:SetVScrollPos(0)
  self.addonQuestLog:ResizeTree()
end

function QuestLogImproved:HookApolloLoadForm()
  local funcLoadForm = Apollo.LoadForm
  Apollo.LoadForm = function(xmlDoc, strForm, wndParent, addon, ...)
    if addon == self.addonQuestLog then
      if strForm == "QuestLogForm" then
        local wnd = funcLoadForm(xmlDoc, strForm, wndParent, addon, ...)
        local wndOldButtons = wnd:FindChild("LeftSideFilterBtnsBG")
        wndOldButtons:SetName("OldLeftSideFilterBtnsBG")
        wndOldButtons:Destroy()
        local buttons = funcLoadForm(self.xmlDoc, "LeftSideFilterBtnsBG", wnd, addon)
        return wnd
      end
      if strForm == "TopLevelItem" then
        local wnd = funcLoadForm(xmlDoc, strForm, wndParent, addon, ...)
        -- wnd:SetAnchorOffsets(0, 0, 0, 25)
        -- wnd:FindChild("TopLevelBtn"):SetAnchorOffsets(0, 0, 0, 25)
        -- wnd:FindChild("TopLevelBtn"):SetFont("CRB_HeaderSmall")
        -- wnd:FindChild("TopLevelBtn"):ChangeArt("BK3:btnMetal_ExpandMenu_LargeClean")
        -- wnd:FindChild("TopLevelItems"):SetAnchorOffsets(3, 26, -3, 0)
        local wndBtn = wnd:FindChild("TopLevelBtn")
        local nLP, nTP, nRP, nBP = wndBtn:GetAnchorPoints()
        local nLO, nTO, nRO, nBO = wndBtn:GetAnchorOffsets()
        wndBtn:SetAnchorPoints(nLP, 0, nRP, 0)
        wndBtn:SetAnchorOffsets(nLO, 5, nRO, 35)
        local wndItems = wnd:FindChild("TopLevelItems")
        nLP, nTP, nRP, nBP = wndItems:GetAnchorPoints()
        nLO, nTO, nRO, nBO = wndItems:GetAnchorOffsets()
        wndItems:SetAnchorPoints(nLP, 0, nRP, nBP)
        wndItems:SetAnchorOffsets(nLO, 35, nRO, nBO)
        nLP, nTP, nRP, nBP = wnd:GetAnchorPoints()
        nLO, nTO, nRO, nBO = wnd:GetAnchorOffsets()
        wnd:SetAnchorPoints(nLP, nTP, nRP, 0)
        wnd:SetAnchorOffsets(nLO, nTO, nRO, 40)
        return wnd
      end
    end
    return funcLoadForm(xmlDoc, strForm, wndParent, addon, ...)
  end
end

function QuestLogImproved:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function QuestLogImproved:Init()
  Apollo.RegisterAddon(self)
end

function QuestLogImproved:OnLoad()
  self.xmlDoc = XmlDoc.CreateFromFile("QuestLogImproved.xml")
  self.xmlDoc:RegisterCallback("OnDocumentReady", self)
end

function QuestLogImproved:OnDocumentReady()
  self:HookQuestLogAddon()
  self:HookApolloLoadForm()
end

local QuestLogImprovedInst = QuestLogImproved:new()
QuestLogImprovedInst:Init()
