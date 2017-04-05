local QuestLogImproved = {}

function QuestLogImproved:HookApolloLoadForm()
  local addonQuestLog = Apollo.GetAddon("QuestLog")
  if not addonQuestLog then
    Print("addonQuestLog is nil")
    return
  end
  local funcLoadForm = Apollo.LoadForm
  Apollo.LoadForm = function(xmlDoc, strForm, wndParent, addon, ...)
    if addon == addonQuestLog then
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
      elseif strForm == "QuestLogForm" then
        local wnd = funcLoadForm(xmlDoc, strForm, wndParent, addon, ...)
        wnd:FindChild("LeftSideFilterBtnsBG"):Destroy()
        local buttons = funcLoadForm(self.xmlDoc, "LeftSideFilterBtnsBG", wnd, addon)
        return wnd
      end
    end
    return funcLoadForm(xmlDoc, strForm, wndParent, addon, ...)
  end
end

function QuestLogImproved:MakeQuestLogXmlModifications()
  local addon = Apollo.GetAddon("QuestLog")
  if not addon then
    Print("addon is nil")
    return
  end
  if not addon.xmlDoc:IsLoaded() then
    Print("not loaded")
    return
  end
  local tXml = addon.xmlDoc:ToTable()
  for idx, tForm in pairs(tXml) do
    if tForm.Name == "TopLevelItem" then
      Print("was: "..tForm.Sprite)
      -- tForm.Sprite = "BasicSprites:WhiteFill"
      -- Print("now: "..tForm.Sprite)
    end
  end
  addon.xmlDoc = XmlDoc.CreateFromTable(tXml)
end

function QuestLogImproved:MakeQuestLogModifications()
  local addon = Apollo.GetAddon("QuestLog")
  if not addon then return end
  for idx, wndTop in ipairs(addon.wndLeftSideScroll:GetChildren()) do
    Print("was: "..tostring(wndTop:GetSprite()))
    wndTop:SetSprite("WhiteFill")
    Print("now: "..tostring(wndTop:GetSprite()))
  end
end

function QuestLogImproved:OnSave(eLevel)
  if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Account then
    return
  end
  local tSave = {}
  return tSave
end

function QuestLogImproved:OnRestore(eLevel, tSave)
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
  Apollo.RegisterSlashCommand("testqli", "MakeQuestLogModifications", self)
  Apollo.RegisterSlashCommand("testqli2", "MakeQuestLogXmlModifications", self)
end

function QuestLogImproved:OnDocumentReady()
  Apollo.RegisterSlashCommand("testqli3", "HookApolloLoadForm", self)
end

local QuestLogImprovedInst = QuestLogImproved:new()
QuestLogImprovedInst:Init()
