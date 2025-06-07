---@class PushMasterExtrapolation
---Handles key level scaling and run extrapolation

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Create Extrapolation module
PushMaster.Data = PushMaster.Data or {}
local Extrapolation = {}
PushMaster.Data.Extrapolation = Extrapolation

-- Local references
local Constants = nil

---Initialize extrapolation module
function Extrapolation:Initialize()
  Constants = PushMaster.Core.Constants
  PushMaster:DebugPrint("Extrapolation module initialized")
end

---Extrapolate a run from one key level to another
---@param sourceRun table Source run data
---@param sourceLevel number Source key level
---@param targetLevel number Target key level
---@return table|nil extrapolatedRun Extrapolated run data or nil
function Extrapolation:ExtrapolateRun(sourceRun, sourceLevel, targetLevel)
  if not sourceRun or not sourceLevel or not targetLevel then
    return nil
  end

  if sourceLevel == targetLevel then
    return sourceRun     -- No extrapolation needed
  end

  if not Constants then
    return nil
  end

  -- Get scaling ratio
  local scalingRatio = Constants:GetMythicPlusScalingRatio(sourceLevel, targetLevel)
  if not scalingRatio or scalingRatio <= 0 then
    return nil
  end

  PushMaster:DebugPrint(string.format("Extrapolating +%d to +%d (ratio: %.2fx)",
    sourceLevel, targetLevel, scalingRatio))

  -- Create extrapolated run
  local extrapolated = {
    totalTime = sourceRun.totalTime * scalingRatio,
    timeLimit = sourceRun.timeLimit,     -- Timer doesn't scale
    timeline = self:ExtrapolateTimeline(sourceRun.timeline, scalingRatio),
    bossFights = self:ExtrapolateBossFights(sourceRun.bossFights, scalingRatio),
    isExtrapolated = true,
    sourceLevel = sourceLevel,
    targetLevel = targetLevel,
    scalingRatio = scalingRatio
  }

  return extrapolated
end

---Extrapolate timeline data
---@param timeline table Source timeline
---@param ratio number Scaling ratio
---@return table extrapolatedTimeline
function Extrapolation:ExtrapolateTimeline(timeline, ratio)
  if not timeline then
    return {}
  end

  local extrapolated = {}

  for _, sample in ipairs(timeline) do
    table.insert(extrapolated, {
      time = sample.time * ratio,
      trash = sample.trash,       -- Progress percentages don't scale
      bosses = sample.bosses,
      deaths = sample.deaths
    })
  end

  return extrapolated
end

---Extrapolate boss fight durations
---@param bossFights table Source boss fights
---@param ratio number Scaling ratio
---@return table extrapolatedBosses
function Extrapolation:ExtrapolateBossFights(bossFights, ratio)
  if not bossFights then
    return {}
  end

  local extrapolated = {}

  for i, fight in ipairs(bossFights) do
    table.insert(extrapolated, {
      name = fight.name,
      duration = fight.duration * ratio,
      killTime = fight.killTime * ratio
    })
  end

  return extrapolated
end

---Calculate confidence for extrapolation
---@param sourceLevel number Source key level
---@param targetLevel number Target key level
---@return number confidence Confidence percentage (0-100)
function Extrapolation:CalculateConfidence(sourceLevel, targetLevel)
  local levelDiff = math.abs(targetLevel - sourceLevel)

  -- Base confidence
  local confidence = 100

  -- Reduce confidence by 10% per level difference
  confidence = confidence - (levelDiff * 10)

  -- Minimum 20% confidence
  confidence = math.max(20, confidence)

  return confidence
end

---Check if extrapolation would result in depleted key
---@param sourceRun table Source run data
---@param sourceLevel number Source key level
---@param targetLevel number Target key level
---@return boolean isDepleted Whether extrapolated run would be over time
---@return number|nil overtimeSeconds Seconds over timer if depleted
function Extrapolation:WouldBeDepleted(sourceRun, sourceLevel, targetLevel)
  if not sourceRun or not sourceRun.totalTime or not sourceRun.timeLimit then
    return false, nil
  end

  local extrapolated = self:ExtrapolateRun(sourceRun, sourceLevel, targetLevel)
  if not extrapolated then
    return false, nil
  end

  local isDepleted = extrapolated.totalTime > extrapolated.timeLimit
  local overtimeSeconds = isDepleted and (extrapolated.totalTime - extrapolated.timeLimit) or nil

  return isDepleted, overtimeSeconds
end

return Extrapolation
