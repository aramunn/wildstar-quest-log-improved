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
  
  self.addonQuestLog.OnQuestItemMouseButtonUp = function(ref, wndHandler, wndControl)
    self:ShowContextMenu(wndControl)
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

function QuestLogImproved:ShowContextMenu(wnd)
  Print("here with: "..tostring(wnd:GetName()))
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
      local bIsQuestListItem = false
      bIsQuestListItem = bIsQuestListItem or strForm == "TopLevelItem"
      bIsQuestListItem = bIsQuestListItem or strForm == "MiddleLevelItem"
      bIsQuestListItem = bIsQuestListItem or strForm == "BottomLevelItem"
      if bIsQuestListItem then
        return funcLoadForm(self.xmlDoc, strForm, wndParent, addon, ...)
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
