-- Timeline data management and interpolation

---@class PushMasterTimeline
---Manages timeline data for runs - storing progression over time

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Create Timeline module
PushMaster.Data = PushMaster.Data or {}
local Timeline = {}
PushMaster.Data.Timeline = Timeline

-- Constants
local MAX_SAMPLES = 100       -- Maximum timeline samples to store
local SAMPLE_INTERVAL = 5     -- Minimum seconds between samples
local COMPRESSION_RATIO = 0.2 -- Keep 20% of samples when compressing

-- Current timeline being recorded
local currentTimeline = {
  samples = {},
  lastSampleTime = 0,
  startTime = 0
}

---Initialize timeline module
function Timeline:Initialize()
  PushMaster:DebugPrint("Timeline module initialized")
end

---Start recording a new timeline
function Timeline:StartRecording()
  currentTimeline.samples = {}
  currentTimeline.startTime = GetTime()
  currentTimeline.lastSampleTime = 0

  -- Add initial sample
  self:AddSample(0, 0, 0)
end

---Add a sample to the current timeline
---@param trash number Trash percentage (0-100)
---@param bosses number Boss count
---@param deaths number Death count
function Timeline:AddSample(trash, bosses, deaths)
  local now = GetTime()
  local elapsedTime = now - currentTimeline.startTime

  -- Throttle samples
  if elapsedTime - currentTimeline.lastSampleTime < SAMPLE_INTERVAL then
    return
  end

  local sample = {
    time = elapsedTime,
    trash = trash or 0,
    bosses = bosses or 0,
    deaths = deaths or 0
  }

  table.insert(currentTimeline.samples, sample)
  currentTimeline.lastSampleTime = elapsedTime

  -- Compress if too many samples
  if #currentTimeline.samples > MAX_SAMPLES then
    self:CompressTimeline(currentTimeline.samples)
  end
end

---Get the current timeline
---@return table timeline Current timeline samples
function Timeline:GetCurrent()
  return currentTimeline.samples
end

---Compress timeline to reduce storage size
---@param samples table Timeline samples to compress
---@return table compressed Compressed timeline
function Timeline:CompressTimeline(samples)
  if not samples or #samples <= MAX_SAMPLES * COMPRESSION_RATIO then
    return samples
  end

  local compressed = {}
  local targetCount = math.floor(MAX_SAMPLES * COMPRESSION_RATIO)

  -- Always keep first and last
  table.insert(compressed, samples[1])

  -- Calculate step size for even distribution
  local step = (#samples - 2) / (targetCount - 2)

  -- Add evenly distributed samples
  for i = 1, targetCount - 2 do
    local index = math.floor(1 + i * step)
    if index > 1 and index < #samples then
      table.insert(compressed, samples[index])
    end
  end

  -- Always keep last
  table.insert(compressed, samples[#samples])

  -- Replace original samples
  currentTimeline.samples = compressed

  return compressed
end

---Create timeline from run data for storage
---@param runData table Complete run data
---@return table timeline Optimized timeline for storage
function Timeline:CreateForStorage(runData)
  if not runData or not currentTimeline.samples then
    return {}
  end

  -- Clone and compress current timeline
  local timeline = {}
  for _, sample in ipairs(currentTimeline.samples) do
    table.insert(timeline, {
      time = sample.time,
      trash = sample.trash,
      bosses = sample.bosses,
      deaths = sample.deaths
    })
  end

  -- Final compression for storage
  if #timeline > 20 then
    timeline = self:CompressTimeline(timeline)
  end

  return timeline
end

---Interpolate timeline data at specific time
---@param timeline table Timeline samples
---@param targetTime number Target time in seconds
---@return table|nil data Interpolated data at target time
function Timeline:InterpolateAtTime(timeline, targetTime)
  if not timeline or #timeline == 0 then
    return nil
  end

  -- Edge cases
  if targetTime <= timeline[1].time then
    return timeline[1]
  elseif targetTime >= timeline[#timeline].time then
    return timeline[#timeline]
  end

  -- Find surrounding samples
  local before, after = nil, nil
  for i = 1, #timeline - 1 do
    if timeline[i].time <= targetTime and timeline[i + 1].time > targetTime then
      before = timeline[i]
      after = timeline[i + 1]
      break
    end
  end

  if not before or not after then
    return nil
  end

  -- Linear interpolation
  local timeDiff = after.time - before.time
  if timeDiff == 0 then
    return before
  end

  local ratio = (targetTime - before.time) / timeDiff

  return {
    time = targetTime,
    trash = before.trash + (after.trash - before.trash) * ratio,
    bosses = before.bosses, -- Bosses don't interpolate (discrete values)
    deaths = before.deaths  -- Deaths don't interpolate
  }
end

---Reset timeline
function Timeline:Reset()
  currentTimeline.samples = {}
  currentTimeline.lastSampleTime = 0
  currentTimeline.startTime = 0
end

return Timeline
