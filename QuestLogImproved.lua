local QuestLogImproved = {}

function QuestLogImproved:MeasureWindows()
  local wndMeasure = Apollo.LoadForm(self.xmlDoc, "ContextMenuQuestLogForm", nil, self)
  self.knContextMenuWidth = wndMeasure:GetWidth()
  self.knContextMenuHeight = wndMeasure:GetHeight()
  wndMeasure:Destroy()
end

function QuestLogImproved:HookQuestLogAddon()
  self.addonQuestLog = Apollo.GetAddon("QuestLog")
  if not self.addonQuestLog then
    Print("addonQuestLog is nil")
    return
  end
  
  local funcRedrawLeftTree = self.addonQuestLog.RedrawLeftTree
  self.addonQuestLog.RedrawLeftTree = function (ref, ...)
    funcRedrawLeftTree(ref, ...)
    self:PostRedrawLeftTree(ref)
  end
  
  self.addonQuestLog.OnCollapseAllQuestsBtn = function (ref)
    self:SetCheckAllLeftSide(false)
  end
  
  self.addonQuestLog.OnExpandAllQuestsBtn = function (ref)
    self:SetCheckAllLeftSide(true)
  end
  
  self.addonQuestLog.OnBotMouseButtonUp = function (ref, wndHandler, wndControl, eMouseButton)
    if eMouseButton == GameLib.CodeEnumInputMouse.Right then self:ShowContextMenu(wndControl, 1) end
  end
  
  self.addonQuestLog.OnMidMouseButtonUp = function (ref, wndHandler, wndControl, eMouseButton)
    if eMouseButton == GameLib.CodeEnumInputMouse.Right then self:ShowContextMenu(wndControl, 2) end
  end
  
  self.addonQuestLog.OnTopMouseButtonUp = function (ref, wndHandler, wndControl, eMouseButton)
    if eMouseButton == GameLib.CodeEnumInputMouse.Right then self:ShowContextMenu(wndControl, 3) end
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

function QuestLogImproved:ShowContextMenu(wnd, nLevel)
  if self.wndContextMenu and self.wndContextMenu:IsValid() then
    self.wndContextMenu:Destroy()
  end
  self.wndContextMenu = Apollo.LoadForm(self.xmlDoc, "ContextMenuQuestLogForm", "TooltipStratum", self)
  local wndButtonList = self.wndContextMenu:FindChild("ButtonList")
  self.wndContextMenu:SetData({ level = nLevel, window = wnd })
  self.wndContextMenu:Invoke()
  local tCursor = Apollo.GetMouse()
  local tPos = { x = (tCursor.x - 10), y = (tCursor.y - 25) }
  local tScreen = Apollo.GetDisplaySize()
  if tPos.x + self.knContextMenuWidth > tScreen.nWidth then tPos.x = tPos.x - self.knContextMenuWidth + 10*2 end
  if tPos.y + self.knContextMenuHeight > tScreen.nHeight then tPos.y = tPos.y - self.knContextMenuHeight + 25*2 end
  self.wndContextMenu:Move(tPos.x, tPos.y, self.knContextMenuWidth, self.knContextMenuHeight)
end

function QuestLogImproved:OnRegularBtn(wndHandler, wndControl)
  local tData = self.wndContextMenu:GetData()
  local strButtonName = wndHandler:GetName()
  self:HandleContextMenuButton(strButtonName, tData.window, tData.level)
  if strButtonName == "BtnAbandon" then
    self.wndContextMenu:FindChild("Confirm:List"):ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop)
    self.wndContextMenu:FindChild("Confirm:List"):RecalculateContentExtents()
    self.wndContextMenu:FindChild("Confirm:Header"):SetText("Abandon these quests?")
    self.wndContextMenu:FindChild("Confirm:ConfirmBtn"):SetName("BtnAbandonConfirm")
    self.wndContextMenu:FindChild("Confirm"):Show(true)
  else
    self.wndContextMenu:Destroy()
    self.addonQuestLog:RedrawLeftTree()
  end
  local bDelayedRedraw = false
  bDelayedRedraw = bDelayedRedraw or strButtonName == "BtnAbandonConfirm"
  bDelayedRedraw = bDelayedRedraw or strButtonName == "BtnIgnore"
  if bDelayedRedraw then
    ApolloTimer.Create(.5, false, "DelayedDestroyAndRedraw", self)
  end
end

function QuestLogImproved:HandleContextMenuButton(strButtonName, wnd, nLevel)
  if nLevel == 1 then
    local quest = wnd:GetData()
    local eState = quest:GetState()
    if strButtonName == "BtnAbandon" and quest:CanAbandon() then
      local wndQuestTitle = Apollo.LoadForm(self.xmlDoc, "ContextMenuConfirmListItem", self.wndContextMenu:FindChild("Confirm:List"), self)
      wndQuestTitle:FindChild("Text"):SetText(quest:GetTitle())
    end
    if strButtonName == "BtnAbandonConfirm" and quest:CanAbandon() then quest:Abandon() end
    if strButtonName == "BtnIgnore" and (eState == Quest.QuestState_Abandoned or eState == Quest.QuestState_Mentioned) then quest:ToggleIgnored() end
    if strButtonName == "BtnTrack" then quest:SetTracked(true) end
    if strButtonName == "BtnUntrack" then quest:SetTracked(false) end
  else
    local tWindowNames
    if nLevel == 2 then tWindowNames = { items = "MiddleLevelItems", button = "BottomLevelBtn" } end
    if nLevel == 3 then tWindowNames = { items = "TopLevelItems", button = "MiddleLevelTitle" } end
    if not tWindowNames then return end
    for idx, wndItem in pairs(wnd:GetParent():FindChild(tWindowNames.items):GetChildren()) do
      self:HandleContextMenuButton(strButtonName, wndItem:FindChild(tWindowNames.button), nLevel - 1)
    end
  end
end

function QuestLogImproved:DelayedDestroyAndRedraw()
  local wndScroll = self.addonQuestLog.wndLeftSideScroll
  local nVScrollPos = wndScroll:GetVScrollPos()
  local tChecked = {}
  for _, wndTop in pairs(wndScroll:GetChildren()) do
    local wndTopBtn = wndTop:FindChild("TopLevelBtn")
    if wndTopBtn:IsChecked() then
      tChecked[wndTopBtn:GetText()] = true
    end
  end
  self.addonQuestLog:DestroyAndRedraw()
  for _, wndTop in pairs(wndScroll:GetChildren()) do
    local wndTopBtn = wndTop:FindChild("TopLevelBtn")
    local bChecked = tChecked[wndTopBtn:GetText()] or false
    wndTopBtn:SetCheck(bChecked)
    if bChecked then
      self.addonQuestLog:OnTopLevelBtnCheck(wndTopBtn, wndTopBtn)
    else
      self.addonQuestLog:OnTopLevelBtnUncheck(wndTopBtn, wndTopBtn)
    end
  end
  wndScroll:SetVScrollPos(nVScrollPos)
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
  self:MeasureWindows()
  self:HookQuestLogAddon()
  self:HookApolloLoadForm()
end

local QuestLogImprovedInst = QuestLogImproved:new()
QuestLogImprovedInst:Init()
