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

---Calculate overall efficiency percentage
---@param current table Current run state {elapsedTime, trash, bosses, deaths}
---@param best table Best run data at same time point {trash, bosses, deaths}
---@param bossWeights table|nil Boss weights for the dungeon
---@return number efficiency Efficiency percentage (0 = on pace, >0 = ahead, <0 = behind)
function Efficiency:Calculate(current, best)
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

  -- Calculate component differences
  local trashDiff = current.trash - bestAtTime.trash
  local bossDiff = current.bosses - bestAtTime.bosses

  -- Simple efficiency calculation: average of trash and boss progress
  -- Positive = ahead, negative = behind
  local efficiency = (trashDiff + (bossDiff * 20)) / 2 -- Boss worth ~20% trash

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
    -- Before first sample - interpolate from zero
    local firstSample = timeline[1]
    if firstSample.time > 0 then
      local ratio = targetTime / firstSample.time
      return {
        trash = firstSample.trash * ratio,
        bosses = 0, -- No bosses killed yet at very early times
        deaths = 0  -- Assume no deaths at start
      }
    else
      return { trash = 0, bosses = 0, deaths = 0 }
    end
  elseif not after then
    return timeline[#timeline] -- After last sample
  end

  -- Linear interpolation
  local timeDiff = after.time - before.time
  if timeDiff == 0 then
    return before
  end

  local ratio = (targetTime - before.time) / timeDiff

  return {
    trash = before.trash + (after.trash - before.trash) * ratio,
    bosses = before.bosses + (after.bosses - before.bosses) * ratio,
    deaths = before.deaths -- Deaths don't interpolate
  }
end

---Calculate individual component differences
---@param current table Current run state
---@param best table Best run data at same time
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

  local trashDiff = current.trash - bestAtTime.trash
  local bossDiff = current.bosses - bestAtTime.bosses
  local deathDiff = current.deaths - bestAtTime.deaths

  return trashDiff, bossDiff, deathDiff
end

---Calculate time delta (ahead/behind in seconds)
---@param current table Current run state
---@param best table Best run timeline
---@return number|nil timeDelta Seconds ahead (negative) or behind (positive)
---@return number confidence Confidence level 0-100
function Efficiency:CalculateTimeDelta(current, best)
  if not current or not best or not best.timeline then
    return nil, 0
  end

  local timeline = best.timeline
  if #timeline < 2 then
    return nil, 0
  end

  -- Account for death penalty in current effective time
  local currentEffectiveTime = current.elapsedTime + (current.deaths * DEATH_PENALTY_SECONDS)

  -- Find where in best run timeline we would be with current progress
  local currentProgress = current.trash + (current.bosses * 20) -- Rough combined progress
  local targetTime = nil
  local confidence = 0

  -- Handle early game edge case
  if currentProgress == 0 and current.elapsedTime < 30 then
    -- Very early in the run, use simple time comparison
    local firstSample = timeline[1]
    if firstSample.time > 0 then
      local bestProgressAtTime = (firstSample.trash + firstSample.bosses * 20) * (current.elapsedTime / firstSample.time)
      local progressDiff = bestProgressAtTime - currentProgress
      -- Rough estimate: 1% progress = ~18 seconds in a 30-minute dungeon
      targetTime = current.elapsedTime - (progressDiff * 18)
      confidence = 30 -- Low confidence for early estimates
    else
      return 0, 10
    end
  else
    -- Search timeline for matching progress
    for i = 2, #timeline do
      local prev = timeline[i - 1]
      local curr = timeline[i]

      local prevProgress = prev.trash + (prev.bosses * 20)
      local currProgress = curr.trash + (curr.bosses * 20)

      if currentProgress >= prevProgress and currentProgress <= currProgress then
        -- Interpolate time
        local progressDiff = currProgress - prevProgress
        if progressDiff > 0 then
          local ratio = (currentProgress - prevProgress) / progressDiff
          targetTime = prev.time + (curr.time - prev.time) * ratio

          -- Higher confidence with more progress and smaller interpolation gaps
          local timeDiff = curr.time - prev.time
          confidence = math.max(50, math.min(90, 70 - (timeDiff / 30)))
          break
        end
      end
    end
  end

  if not targetTime then
    -- Edge cases
    local firstProgress = timeline[1].trash + timeline[1].bosses * 20
    local lastProgress = timeline[#timeline].trash + timeline[#timeline].bosses * 20

    if currentProgress < firstProgress then
      -- We're behind the first timeline point
      if firstProgress > 0 then
        targetTime = timeline[1].time * (currentProgress / firstProgress)
      else
        targetTime = 0
      end
      confidence = 40
    else
      -- We're ahead of the last timeline point (exceptional pace)
      if best.totalTime and lastProgress > 0 then
        -- Extrapolate based on final pace
        targetTime = best.totalTime * (currentProgress / lastProgress)
      else
        targetTime = timeline[#timeline].time
      end
      confidence = 60
    end
  end

  -- Calculate delta (positive = behind, negative = ahead)
  -- Use effective time (including death penalty) vs target time
  local timeDelta = currentEffectiveTime - targetTime

  return timeDelta, confidence
end

return Efficiency
