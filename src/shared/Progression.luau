--!strict
-- Level curve and XP helpers (Amendment A4). Nothing here changes combat stats.

local Config = require(script.Parent.Config)

local Progression = {}

function Progression.xpToNext(level: number): number
	return Config.Progression.LevelBase + Config.Progression.LevelPerLevel * level
end

-- Apply XP to a (level, xp) pair. Returns new level, new xp, levels gained.
function Progression.addXP(level: number, xp: number, gained: number): (number, number, number)
	local cap = Config.Progression.LevelCap
	local startLevel = level
	xp += math.max(0, gained)
	while level < cap and xp >= Progression.xpToNext(level) do
		xp -= Progression.xpToNext(level)
		level += 1
	end
	if level >= cap then
		xp = 0
	end
	return level, xp, level - startLevel
end

return Progression
