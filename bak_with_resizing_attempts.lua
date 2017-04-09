local QuestLogImproved = {}

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
  
  -- local funcHelperSetupBottomLevelWindow = self.addonQuestLog.HelperSetupBottomLevelWindow
  -- self.addonQuestLog.HelperSetupBottomLevelWindow = function (ref, wndBot, ...)
    -- funcHelperSetupBottomLevelWindow(ref, wndBot, ...)
    -- local wndBottomLevelBtn = wndBot:FindChild("BottomLevelBtn")
    -- local wndBottomLevelBtnText = wndBot:FindChild("BottomLevelBtnText")
    -- local strText = wndBottomLevelBtnText:GetText().." blah blah blah blah blah blah blah blah blah blah"
    -- wndBottomLevelBtnText:SetText(strText)
    -- wndBottomLevelBtn:SetText(strText)
  -- end
  
  -- local funcResizeTree = self.addonQuestLog.ResizeTree
  -- self.addonQuestLog.ResizeTree = function (ref, ...)
    -- funcResizeTree(ref, ...)
    -- for _, wndTop in pairs(ref.wndLeftSideScroll:GetChildren()) do
      -- for _, wndMid in pairs(wndTop:FindChild("TopLevelItems"):GetChildren()) do
        -- local wndMidLevelItems = wndMid:FindChild("MiddleLevelItems")
        -- local nMidLeft, nMidTop, nMidRight, nMidBottom = wndMid:GetAnchorOffsets()
        -- for _, wndBot in pairs(wndMid:FindChild("MiddleLevelItems"):GetChildren()) do
          -- local nBotHeight = wndBot:GetHeight()
          -- if nBotHeight == 40 or nBotHeight == 55 then
            -- local nBotLeft, nBotTop, nBotRight, nBotBottom = wndBot:GetAnchorOffsets()
            -- wndBot:SetAnchorOffsets(nBotLeft, nBotTop, nBotRight, nBotTop + nBotHeight + 20)
            -- Print(tostring(nBotHeight).." -> "..tostring(wndBot:GetHeight()))
          -- end
        -- end
        -- local nMidItemHeights = wndMidLevelItems:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop)
        -- if nMidItemHeights > 0 then
          -- nMidItemHeights = nMidItemHeights + 4
        -- end
        -- wndMid:SetAnchorOffsets(nMidLeft, nMidTop, nMidRight, nMidTop + ref.knMiddleLevelHeight + nMidItemHeights)
      -- end
    -- end
  -- end
  
  self.addonQuestLog.OnCollapseAllQuestsBtn = function (ref)
    self:SetCheckAllLeftSide(false)
  end
  
  self.addonQuestLog.OnExpandAllQuestsBtn = function (ref)
    self:SetCheckAllLeftSide(true)
  end
  
  self.addonQuestLog.OnQuestItemMouseButtonUp = function (ref, wndHandler, wndControl)
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
  -- self.tWnds = {}
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
        local wnd = funcLoadForm(self.xmlDoc, strForm, wndParent, addon, ...)
        -- if strForm == "MiddleLevelItem" then
          -- self:HookSetAnchorOffsets(wnd, 0)
        -- elseif strForm == "BottomLevelItem" then
          -- self:HookSetAnchorOffsets(wnd, -6)
        -- end
        return wnd
      end
    end
    return funcLoadForm(xmlDoc, strForm, wndParent, addon, ...)
  end
end

-- function QuestLogImproved:HookSetAnchorOffsets(wnd, nOffset)
  -- self:CleanWnds()
  -- self.tWnds[wnd] = nOffset
  -- if not self.bHookedSetAnchorOffsets then
    -- local funcSetAnchorOffsets = wnd.SetAnchorOffsets
    -- wnd.__index.SetAnchorOffsets = function (ref, nL, nT, nR, nB, ...)
      -- return funcSetAnchorOffsets(ref, nL, nT, nR, nB + self:GetWndOffset(ref), ...)
    -- end
    -- self.bHookedSetAnchorOffsets = true
  -- end
-- end

-- function QuestLogImproved:CleanWnds()
  -- for wnd in pairs(self.tWnds) do
    -- if not wnd:IsValid() then
      -- self.tWnds[wnd] = nil
    -- end
  -- end
-- end

-- function QuestLogImproved:GetWndOffset(ref)
  -- for wnd, nOffset in pairs(self.tWnds) do
    -- if wnd == ref then
      -- return nOffset
    -- end
  -- end
  -- return 0
-- end

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
