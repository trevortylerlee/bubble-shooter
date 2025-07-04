-- scoreManager.lua
local constants = require("constants")

local scoreManager = {
	total = 0,
	comboStreak = 0,
	lastShotTime = nil,
}

function scoreManager.addShotScore(groupSize, fallenCount, timeSinceLastShot)
	local base = constants.BASE_POINTS * groupSize
	local groupBonus = 0
	if groupSize > 3 then
		groupBonus = (groupSize - 3) * constants.GROUP_BONUS_PER_BUBBLE
	end
	local fallingBonus = (fallenCount or 0) * constants.FALLING_BONUS
	local speedBonus = 0
	if timeSinceLastShot and timeSinceLastShot <= constants.FAST_SHOT_WINDOW then
		speedBonus = constants.SPEED_BONUS
	end
	local shotRaw = base + groupBonus + fallingBonus + speedBonus
	local shotScore = shotRaw
	if shotRaw > 0 then
		scoreManager.comboStreak = scoreManager.comboStreak + 1
	else
		scoreManager.comboStreak = 0
	end
	local comboMultiplier = 1 + constants.COMBO_MULTIPLIER_STEP * math.max(0, scoreManager.comboStreak - 1)
	shotScore = math.floor(shotRaw * comboMultiplier)
	scoreManager.total = scoreManager.total + shotScore
	return shotScore, scoreManager.comboStreak
end

return scoreManager
