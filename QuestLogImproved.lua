local QuestLogImproved = {}



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
  -- self.xmlDoc:RegisterCallback("OnDocumentReady", self)
  -- Apollo.RegisterSlashCommand("hacksbyaramunn", "LoadMainWindow", self)
end

local QuestLogImprovedInst = QuestLogImproved:new()
QuestLogImprovedInst:Init()
