-- Efficiency calculations and pace comparison

---@class PushMasterEfficiency
---Calculate efficiency percentage compared to best run

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Create Efficiency module
PushMaster.Calculations = PushMaster.Calculations or {}
local Efficiency = {}
PushMaster.Calculations.Efficiency = Efficiency

-- Death penalty constant (15 seconds per death)
local DEATH_PENALTY_SECONDS = 15

-- Default boss weights (can be overridden per dungeon)
local DEFAULT_BOSS_WEIGHTS = {
  [1] = 1.0, -- First boss: 60s fight = weight 1.0
  [2] = 2.0, -- Second boss: 120s fight = weight 2.0
  [3] = 3.0, -- Third boss: 180s fight = weight 3.0
  [4] = 4.0  -- Fourth boss: 240s fight = weight 4.0
}

---Calculate overall efficiency percentage
---@param current table Current run state {elapsedTime, trash, bosses, deaths}
---@param best table Best run data with timeline
---@param bossWeights table|nil Boss weights for the dungeon
---@return number efficiency Efficiency percentage (0 = on pace, >0 = ahead, <0 = behind)
function Efficiency:Calculate(current, best, bossWeights)
  if not current or not best then
    return 0
  end

  -- Calculate effective time (actual time + death penalties)
  local effectiveTime = current.elapsedTime + (current.deaths * DEATH_PENALTY_SECONDS)

  -- Get best run data at effective time
  local bestAtTime = self:GetBestRunAtTime(best, effectiveTime)
  if not bestAtTime then
    return 0
  end

  -- Calculate flat differences
  local trashDiff = current.trash - bestAtTime.trash
  local bossDiff = current.bosses - bestAtTime.bosses

  -- Simple efficiency calculation as per logic doc
  -- Trash has base weight 1.0, bosses have higher weight based on duration
  -- For now, use simple 3x multiplier for bosses (average boss weight)
  local efficiency = (trashDiff + (bossDiff * 3)) / 2

  return efficiency
end

---Get best run data interpolated at specific time
---@param bestRun table Best run timeline data
---@param targetTime number Target time in seconds
---@return table|nil interpolated Interpolated data {trash, bosses, deaths}
function Efficiency:GetBestRunAtTime(bestRun, targetTime)
  if not bestRun or not bestRun.timeline then
    return nil
  end

  local timeline = bestRun.timeline
  if #timeline == 0 then
    return nil
  end

  -- Find surrounding samples
  local before, after = nil, nil
  for i, sample in ipairs(timeline) do
    if sample.time <= targetTime then
      before = sample
    else
      after = sample
      break
    end
  end

  -- Edge cases
  if not before then
    -- Before first sample - start from zero
    return { trash = 0, bosses = 0, deaths = 0 }
  elseif not after then
    -- After last sample - use last values
    return {
      trash = timeline[#timeline].trash,
      bosses = timeline[#timeline].bosses,
      deaths = timeline[#timeline].deaths
    }
  end

  -- Linear interpolation between samples
  local timeDiff = after.time - before.time
  if timeDiff == 0 then
    return before
  end

  local ratio = (targetTime - before.time) / timeDiff

  return {
    trash = before.trash + (after.trash - before.trash) * ratio,
    bosses = before.bosses + (after.bosses - before.bosses) * ratio,
    deaths = before.deaths -- Deaths don't interpolate linearly
  }
end

---Calculate individual component differences (flat differences as per logic doc)
---@param current table Current run state
---@param best table Best run data
---@return number, number, number trashDiff, bossDiff, deathDiff
function Efficiency:GetComponentDifferences(current, best)
  if not current or not best then
    return 0, 0, 0
  end

  -- Calculate effective time with death penalty
  local effectiveTime = current.elapsedTime + (current.deaths * DEATH_PENALTY_SECONDS)

  -- Get best run at effective time
  local bestAtTime = self:GetBestRunAtTime(best, effectiveTime)
  if not bestAtTime then
    return 0, 0, 0
  end

  -- Return flat differences as specified in logic doc
  local trashDiff = current.trash - bestAtTime.trash
  local bossDiff = current.bosses - bestAtTime.bosses
  local deathDiff = current.deaths - bestAtTime.deaths

  return trashDiff, bossDiff, deathDiff
end

---Calculate time delta (ahead/behind in seconds) - SIMPLIFIED VERSION
---@param current table Current run state
---@param best table Best run timeline
---@return number|nil timeDelta Seconds ahead (negative) or behind (positive)
---@return number confidence Confidence level 0-100
function Efficiency:CalculateTimeDelta(current, best)
  if not current or not best or not best.timeline then
    return nil, 0
  end

  local timeline = best.timeline
  if #timeline == 0 then
    return nil, 0
  end

  -- Calculate effective time (current time + death penalty)
  local currentEffectiveTime = current.elapsedTime + (current.deaths * DEATH_PENALTY_SECONDS)

  -- Get what the best run had at our current effective time
  local bestAtEffectiveTime = self:GetBestRunAtTime(best, currentEffectiveTime)
  if not bestAtEffectiveTime then
    return nil, 0
  end

  -- Simple comparison: just look at trash progress difference
  -- Each 1% trash difference ≈ 18 seconds in a 30-minute dungeon
  local trashDiff = current.trash - bestAtEffectiveTime.trash
  local bossDiff = current.bosses - bestAtEffectiveTime.bosses

  -- Convert to time: trash is 1% = 18s, each boss ≈ 5 minutes = 300s
  local trashTimeDelta = -(trashDiff * 18) -- Negative = ahead
  local bossTimeDelta = -(bossDiff * 300)  -- Negative = ahead

  -- Combine with simple average
  local estimatedTimeDelta = (trashTimeDelta + bossTimeDelta) / 2

  -- Confidence based on how much data we have
  local confidence = 50
  if current.elapsedTime > 300 then -- After 5 minutes
    confidence = 70
  end
  if current.elapsedTime > 600 then -- After 10 minutes
    confidence = 85
  end

  return estimatedTimeDelta, confidence
end

return Efficiency
