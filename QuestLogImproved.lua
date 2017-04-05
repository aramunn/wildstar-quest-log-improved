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
    local nQuestCount = QuestLib.GetCount()
    local strColor = "UI_BtnTextGreenNormal"
    if nQuestCount + 3 >= ref.nQuestCountMax then
      strColor = "ffff0000"
    elseif nQuestCount + 10 >= ref.nQuestCountMax then
      strColor = "ffffb62e"
    end
    ref.wndLeftFilterActive:SetText(string.format("Active Quests (%d/%d)", nQuestCount, ref.nQuestCountMax))
    local activeQuestsProgressBar = ref.wndLeftFilterActive:FindChild("ActiveQuestsProgressBar")
    activeQuestsProgressBar:SetMax(ref.nQuestCountMax)
    activeQuestsProgressBar:SetProgress(nQuestCount)
    activeQuestsProgressBar:SetBarColor(strColor)
  end
  
  self.addonQuestLog.OnCollapseAllQuestsBtn = function(ref)
    for _, wnd in pairs(ref.wndLeftSideScroll:GetChildren()) do
      wnd:FindChild("TopLevelBtn"):SetCheck(false)
    end
    ref:RedrawLeftTree()
    ref.wndLeftSideScroll:SetVScrollPos(0)
    ref:ResizeTree()
  end
  
  self.addonQuestLog.OnExpandAllQuestsBtn = function(ref)
    for _, wnd in pairs(ref.wndLeftSideScroll:GetChildren()) do
      local wndTopLevelBtn = wnd:FindChild("TopLevelBtn")
      wndTopLevelBtn:SetCheck(true)
      ref:OnTopLevelBtnCheck(wndTopLevelBtn, wndTopLevelBtn)
    end
    ref:RedrawLeftTree()
    ref.wndLeftSideScroll:SetVScrollPos(0)
    ref:ResizeTree()
  end
  
  -- for idx1, wndTop in pairs(self.wndLeftSideScroll:GetChildren()) do
    -- local wndTopLevelBtn = wndTop:FindChild("TopLevelBtn")
    -- local wndTopLevelItems = wndTop:FindChild("TopLevelItems")
    -- wndTopLevelBtn:SetCheck(set)
    -- for idx2, wndMiddle in pairs(wndTopLevelItems:GetChildren()) do
      -- local wndMiddleLevelBtn = wndMiddle:FindChild("MiddleLevelBtn")
      -- wndMiddleLevelBtn:SetCheck(set)
    -- end
  -- end
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
