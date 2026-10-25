--!strict
-- Match rewards. Coins (the one currency) follow the designer's win tiers, highest tier only:
--   600 scored the match-ending knockout · 500 never eliminated all match · 300 on the court at
--   the win · 200 won · 50 played on the losing team. XP and level (Amendment A4) and win streaks
-- are unchanged. Rewards are granted once per match id per player and shown only in the results
-- overlay, never during combat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)

local RewardService = {}

local S: any
local P = Config.Coins
local X = Config.Progression.XP

function RewardService.init(services: any)
	S = services
end

export type MatchContext = {
	matchId: number,
	winner: string?,
	aborted: boolean,
	casual: boolean,
	duration: number,
	finalEliminator: any?, -- combatant credited with the match-ending knockout
}

-- Pure coins rule, exposed for tests. Returns coins and the tier name shown in the results overlay.
function RewardService.coins(c: any, ctx: MatchContext): (number, string)
	local s = c.stats
	local won = ctx.winner ~= nil and c.team == ctx.winner and not ctx.aborted
	-- anti-AFK: every coins payout needs at least one real action (spec v0.1 §13)
	local participated = (s.throws + s.catches + s.botCatches + s.dodges) >= P.MinParticipationActions
	if not participated then
		return 0, if ctx.aborted then "MATCH ABORTED" else "NO REWARD (IDLE)"
	end
	if won then
		if ctx.finalEliminator == c then
			return P.WinLastElimination, "FINAL KNOCKOUT"
		elseif (c.matchEliminations or 0) == 0 and not c.lateJoin then
			return P.WinFlawless, "FLAWLESS WIN"
		elseif c.aliveAtWin then
			return P.WinAlive, "SURVIVED THE WIN"
		end
		return P.Win, "WIN"
	end
	if not ctx.aborted and ctx.winner ~= nil then
		return P.LossParticipation, "GOOD GAME"
	end
	return 0, if ctx.aborted then "MATCH ABORTED" else "NO REWARD"
end

function RewardService.xp(c: any, ctx: MatchContext): number
	local s = c.stats
	local botRate = Config.Bots.RewardMultiplier
	local won = ctx.winner ~= nil and c.team == ctx.winner and not ctx.aborted
	local participated = (s.throws + s.catches + s.botCatches + s.dodges) >= P.MinParticipationActions
	local xp = 0
	if participated and not ctx.aborted then
		xp += X.Complete
		if won then
			xp += X.Win
		end
	end
	xp += s.hits * X.Hit
		+ math.floor(s.botHits * X.Hit * botRate)
		+ s.catches * X.Catch
		+ math.floor(s.botCatches * X.Catch * botRate)
		+ s.knockouts * X.Knockout
		+ math.floor(s.botKnockouts * X.Knockout * botRate)
		+ s.revenges * X.Revenge
	return math.min(xp, Config.Progression.MaxXPPerMatch)
end

function RewardService.awardMatch(roster: { any }, ctx: MatchContext)
	-- "STREAK ENDED!": a losing real player on a 5+ streak in a non-casual match.
	if ctx.winner and not ctx.casual then
		for _, c in roster do
			if c.player and c.profile and c.team ~= ctx.winner and c.profile.CurrentWinStreak >= Config.Rewards.StreakEndMin then
				S.NetService.broadcast("Feed", {
					text = ("🔥 STREAK ENDED! %s's %d-win streak is over!"):format(S.MatchService.tag(c), c.profile.CurrentWinStreak),
				})
			end
		end
	end
	for _, c in roster do
		if c.player and c.player.Parent and c.profile and c.rewardedMatch ~= ctx.matchId then
			c.rewardedMatch = ctx.matchId
			local coins, tier = RewardService.coins(c, ctx)
			local xp = RewardService.xp(c, ctx)
			local won = ctx.winner ~= nil and c.team == ctx.winner and not ctx.aborted
			local p = c.profile
			p.Coins += coins
			local oldLevel = p.Level
			p.Level, p.XP = Progression.addXP(p.Level, p.XP, xp)
			if not ctx.aborted then
				p.Matches += 1
			end
			if won then
				p.Wins += 1
			end
			p.Knockouts += c.stats.knockouts + c.stats.botKnockouts
			-- bot-heavy (casual) matches neither advance nor break streaks
			if not ctx.casual and not ctx.aborted and ctx.winner then
				if won then
					p.CurrentWinStreak += 1
					p.BestWinStreak = math.max(p.BestWinStreak, p.CurrentWinStreak)
				else
					p.CurrentWinStreak = 0
				end
			end
			S.NetService.send(c.player, "Results", {
				winner = ctx.winner,
				aborted = ctx.aborted,
				won = won,
				casual = ctx.casual,
				-- everything earned this match: the tier payout plus the instant elimination coins
				coins = coins + (c.stats.eliminationCoins or 0),
				tier = tier,
				xp = xp,
				level = p.Level,
				leveledUp = p.Level > oldLevel,
				streak = p.CurrentWinStreak,
				stats = {
					hits = c.stats.hits + c.stats.botHits,
					catches = c.stats.catches + c.stats.botCatches,
					knockouts = c.stats.knockouts + c.stats.botKnockouts,
					revenges = c.stats.revenges,
				},
				persistent = c.persistent,
			})
			S.DataService.push(c)
			task.spawn(S.DataService.save, c, false)
		end
	end
end

return RewardService
