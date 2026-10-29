--!nocheck
-- Offline tests: they drive the real server modules through the harness's fakes. Each test starts
-- from H.reset() (no players, empty events, Studio on, real time).

return function(H)
	local S, Config, Catalog = H.S, H.Config, H.Catalog
	local Enum = H.Enum
	local Granted = Enum.ProductPurchaseDecision.PurchaseGranted
	local Later = Enum.ProductPurchaseDecision.NotProcessedYet
	local test, check, eq = H.test, H.check, H.eq
	local DateTime = H.DateTime

	local nextReceipt = 0
	local function receipt(c, productId: number, purchaseId: string?)
		nextReceipt += 1
		return {
			PlayerId = c.player.UserId,
			ProductId = productId,
			PurchaseId = purchaseId or ("R%d"):format(nextReceipt),
			CurrencySpent = 0,
		}
	end

	-- Catalog and config ---------------------------------------------------------------------------

	test("catalog: unique ids, one free default per category, everything else priced", function()
		local seen, defaults = {}, {}
		for _, item in Catalog.Items do
			check(not seen[item.Id], "duplicate id " .. item.Id)
			seen[item.Id] = true
			if item.Default then
				eq(item.Price, 0, item.Id .. " default price")
				defaults[item.Category] = (defaults[item.Category] or 0) + 1
			else
				check(item.Price > 0, item.Id .. " is neither default nor priced")
			end
			if item.Event then
				check(item.Limited == true, item.Id .. " is an event item but not Limited")
			end
		end
		for _, cat in Catalog.Categories do
			eq(defaults[cat] or 0, 1, "defaults in " .. tostring(cat))
		end
	end)

	test("catalog: every prize has a rarity and sells at its rarity's flat price", function()
		for _, item in Catalog.Items do
			if not item.Default then
				check(Config.Economy.PriceByRarity[item.Rarity] ~= nil, item.Id .. " has no rarity")
				eq(Catalog.rarity(item), item.Rarity, item.Id .. " rarity")
				-- bundle items are never sold for coins
				if not item.Bundle then
					eq(item.Price, Config.Economy.PriceByRarity[item.Rarity], item.Id .. " price")
				end
			end
		end
		eq(Catalog.rarity(Catalog.get("Finisher_DestinyArrives")), "Legendary", "Destiny Arrives")
		eq(Catalog.rarity(Catalog.get("Finisher_PurpleFlash")), "Epic", "Purple Flash re-tiered")
		eq(Catalog.get("Title_Rookie").Price, 500, "Rookie at the Common price")
	end)

	test("config: every Robux product id is set and distinct", function()
		local ids = {}
		local function add(id, what)
			check(id > 0, what .. " has no product id")
			check(not ids[id], what .. " reuses product id " .. id)
			ids[id] = true
		end
		for _, b in Config.CoinShop.Bundles do
			add(b.ProductId, b.Id)
		end
		for _, b in Config.CoinShop.Boosts do
			add(b.ProductId, b.Id)
		end
		add(Config.Spin.RobuxProductId, "extra spin")
		-- limited-time bundles may still be at the placeholder 0, but a real id must be distinct
		for _, o in Config.CoinShop.Offers do
			if o.ProductId ~= 0 then
				add(o.ProductId, o.Id)
			end
		end
	end)

	test("config: every limited offer has a window and names bundle-only catalog items", function()
		local ids = {}
		for _, o in Config.CoinShop.Offers do
			check(not ids[o.Id], "duplicate offer " .. o.Id)
			ids[o.Id] = true
			local from, to = DateTime.fromIsoDate(o.Start).UnixTimestamp, DateTime.fromIsoDate(o.End).UnixTimestamp
			check(to > from, o.Id .. " window")
			check(o.Coins >= 0 and #o.Items > 0, o.Id .. " is empty")
			for _, id in o.Items do
				local item = Catalog.get(id)
				check(item ~= nil, o.Id .. " names unknown item " .. id)
				eq(item.Bundle, o.Id, id .. " Bundle tag")
			end
		end
		for _, item in Catalog.Items do
			if item.Bundle then
				check(ids[item.Bundle], item.Id .. " belongs to no offer")
			end
		end
	end)

	test("config: the Halloween bundle runs Oct 28 through Nov 3 UTC", function()
		local o
		for _, it in Config.CoinShop.Offers do
			if it.Id == "Halloween2026" then
				o = it
			end
		end
		check(o, "no Halloween2026 offer")
		local function at(iso)
			return Catalog.offerLive(o, DateTime.fromIsoDate(iso).UnixTimestamp)
		end
		check(not at("2026-10-27T23:59:59Z"), "on before Oct 28")
		check(at("2026-10-28T00:00:00Z"), "off at the start")
		check(at("2026-11-03T23:59:59Z"), "off on Nov 3")
		check(not at("2026-11-04T00:00:00Z"), "still on after Nov 3")
	end)

	test("config: every quest names a chest that can drop something, with odds adding up to 1", function()
		for _, q in Config.Quests.List do
			local def = Config.Quests.Chests[q.Chest]
			check(def ~= nil, q.Id .. " names unknown chest " .. tostring(q.Chest))
			check(q.Goal >= 1, q.Id .. " has no goal")
			check(S.RewardService.valid({ Kind = "Chest", Chest = q.Chest }), q.Id .. "'s chest isn't a valid reward")
			local sum = 0
			for r, p in S.RewardService.chestOdds(q.Chest) do
				check(p == 0 or #S.RewardService.chestPool(q.Chest)[r] > 0, q.Chest .. " can roll an empty " .. r)
				sum += p
			end
			check(math.abs(sum - 1) < 1e-9, q.Chest .. " odds add up to " .. sum)
		end
		check(not S.RewardService.valid({ Kind = "Chest", Chest = "Nope" }), "unknown chest is valid")
		-- every chest has items in every rarity, so its odds are exactly its configured weights
		local f = S.RewardService.chestOdds("Finisher")
		check(math.abs(f.Common - 0.6) < 1e-9 and math.abs(f.Legendary - 0.01) < 1e-9, "finisher odds")
	end)

	test("catalog: every quest chest has a spread of items in every rarity", function()
		for _, q in Config.Quests.List do
			local pool = S.RewardService.chestPool(q.Chest)
			for _, r in { "Common", "Rare", "Epic", "Legendary" } do
				check(#pool[r] >= 1, ("%s has no %s items"):format(q.Chest, r))
			end
			local n = #pool.Common + #pool.Rare + #pool.Epic + #pool.Legendary
			check(n >= 10, ("%s has only %d items"):format(q.Chest, n))
		end
	end)

	test("catalog: the new coin gestures and finisher refill the chests", function()
		eq(Catalog.get("Pose_PowerUp").Exclusive, nil, "Power Up is a coin item")
		eq(Catalog.get("Finisher_Supernova").Exclusive, nil, "Supernova is a coin item")
		local gestures = S.RewardService.chestPool("Gesture")
		local finishers = S.RewardService.chestPool("Finisher")
		eq(#gestures.Epic, 3, "Gesture Chest Epics (Take a Bow, The Floss, Heart Hands)")
		eq(gestures.Legendary[1] and gestures.Legendary[1].Id, "Pose_PowerUp", "Gesture Chest Legendary")
		eq(finishers.Legendary[1] and finishers.Legendary[1].Id, "Finisher_Supernova", "Finisher Chest Legendary")
		local icons = H.require("shared/IntroPoses").Poses
		eq(icons.PowerUp.Fx, "Aura", "Power Up's aura")
	end)

	test("catalog: every gesture has its frames and every finisher its module", function()
		local IntroPoses = H.require("shared/IntroPoses")
		for _, item in Catalog.inCategory("Pose") do
			local pose = IntroPoses.Poses[item.Data.Pose]
			check(pose ~= nil, item.Id .. " names an unknown pose")
			eq(pose.Name, item.Name, item.Id .. " pose name")
			for _, step in pose.Frames do
				check(IntroPoses.Frames[step.frame] ~= nil, item.Id .. " uses unknown frame " .. step.frame)
			end
		end
		for _, item in Catalog.inCategory("Finisher") do
			local ok, def = pcall(H.require, "shared/Finishers/" .. item.Data.Module)
			check(ok and type(def) == "table", item.Id .. " module doesn't load: " .. tostring(def))
			eq(def.Id, item.Data.Module, item.Id .. " module Id")
			check(type(def.play) == "function", item.Id .. " has no play")
		end
	end)

	test("config: Halloween window parses and ends after it starts", function()
		local H2 = Config.Halloween
		local a = DateTime.fromIsoDate(H2.Start).UnixTimestamp
		local b = DateTime.fromIsoDate(H2.End).UnixTimestamp
		check(b > a, "Halloween ends before it starts")
	end)

	-- Saving ---------------------------------------------------------------------------------------

	test("save migration: v1, v3 Pts, v8 and v9 saves all reach the current schema intact", function()
		local D = S.DataService
		local v1 = D.migrate({ SchemaVersion = 1, Coins = 5, OwnedCosmetics = { Skin_Lime = true } })
		eq(v1.SchemaVersion, Config.Data.SchemaVersion, "v1 schema")
		check(v1.LoginStreak and v1.Spin and v1.DailyQuests and v1.Receipts, "v1 missing fields")
		check(v1.OwnedCosmetics.Skin_Lime, "v1 lost a cosmetic")
		local v3 = D.migrate({ SchemaVersion = 3, Pts = 1234 })
		eq(v3.Coins, 1234, "v3 Pts became coins")
		check(v3.Pts == nil, "Pts left behind")
		local v8 = D.migrate({ SchemaVersion = 8, Coins = 9, Matches = 5, Receipts = { "a" } })
		eq(v8.Coins, 9, "v8 coins")
		eq(v8.Receipts[1], "a", "v8 receipts")
		check(S.PurchaseService.robuxUnlocked({ profileLoaded = true, profile = v8 }), "returning player is locked out of Robux again")
		eq(v8.CoinBoostForever, false, "v8 boost flag")
		local v9 = D.migrate({ SchemaVersion = 9, CoinBoostForever = true, CoinBoostUntil = 77, PlaySeconds = 30 })
		eq(v9.CoinBoostForever, true, "v9 lifetime boost kept")
		eq(v9.CoinBoostUntil, 77, "v9 timed boost kept")
		eq(v9.PlaySeconds, 30, "v9 play time kept")
		check(type(v9.DailyQuests) == "table" and v9.ChestDaily == nil, "v9 quests/chests")
		-- migrating twice changes nothing
		local again = D.migrate(H.deepCopy(v9))
		eq(again.CoinBoostUntil, 77, "second migration")
		eq(again.PlaySeconds, 30, "second migration play time")
	end)

	test("save migration v11: login streaks carry over to the typed ladder; damage is repaired", function()
		local D = S.DataService
		local today = os.date("!%Y-%m-%d", os.time())
		local yesterday = os.date("!%Y-%m-%d", os.time() - 86400)
		-- mid-streak yesterday: today is the next rung, nothing lost
		local v10 = D.migrate({
			SchemaVersion = 10,
			Coins = 300,
			LoginStreak = { day = 4, lastDate = yesterday, claimedDate = yesterday },
		})
		eq(v10.SchemaVersion, Config.Data.SchemaVersion, "schema")
		eq(v10.LoginStreak.day, 4, "streak day")
		eq(v10.LoginStreak.claimedDate, yesterday, "claimed date")
		eq(v10.Coins, 300, "coins")
		check(type(v10.BonusSpins) == "table" and type(v10.RewardPicks) == "table", "new fields")
		local c = H.combatant()
		c.profile = v10
		local status = S.ShopService.dailyStatus(c)
		check(status.day == 5 and not status.claimed, "streak didn't continue at day 5")
		-- already claimed today under the old ladder: no second claim after the update
		c.profile = D.migrate({ SchemaVersion = 10, LoginStreak = { day = 2, lastDate = today, claimedDate = today } })
		check(not S.ShopService.claimDaily(c), "claimed twice on update day")
		-- damaged entries are repaired, not reset
		local bad = D.migrate({ SchemaVersion = 10, LoginStreak = { day = "3", claimedDate = yesterday } })
		check(bad.LoginStreak.day == 3 and bad.LoginStreak.lastDate == yesterday, "string day lost")
		eq(D.migrate({ SchemaVersion = 10, LoginStreak = { day = 9, claimedDate = "" } }).LoginStreak.day, 2, "wrap")
		local gone = D.migrate({ SchemaVersion = 10, LoginStreak = "oops", BonusSpins = 5 })
		check(gone.LoginStreak.day == 0 and gone.LoginStreak.claimedDate == "", "unreadable streak")
		eq(#gone.BonusSpins, 0, "bad bonus spins")
		-- v11 data survives another migration
		local v11 = D.migrate({ SchemaVersion = 11, BonusSpins = { "RarePlus" }, RewardPicks = { { ids = { "a" } } } })
		eq(v11.BonusSpins[1], "RarePlus", "bonus spins kept")
		eq(v11.RewardPicks[1].ids[1], "a", "picks kept")
	end)

	test("saving: load takes the lock, save writes, release drops the lock", function()
		local c = H.combatant()
		S.DataService.load(c)
		check(c.persistent, "fresh profile not persistent")
		local key = "u_" .. c.player.UserId
		check(H.store[key] and H.store[key].Lock and H.store[key].Lock.JobId == "offline-job", "no lock taken")
		c.profile.Coins = 321
		check(S.DataService.save(c, false), "save failed")
		eq(H.store[key].Coins, 321, "saved coins")
		check(S.DataService.save(c, true), "release save failed")
		check(H.store[key].Lock == nil, "lock not released")
		-- after the release, a late autosave is refused and doesn't lock the profile again
		check(not S.DataService.save(c, false), "autosave ran after the release")
		check(H.store[key].Lock == nil, "late autosave re-locked the profile")
	end)

	test("saving: a profile another server holds isn't overwritten", function()
		local c = H.combatant()
		S.DataService.load(c)
		local key = "u_" .. c.player.UserId
		H.store[key].Lock = { JobId = "other-server", Time = os.time() }
		H.store[key].Coins = 999
		c.profile.Coins = 1
		check(not S.DataService.save(c, false), "save over another server's session reported success")
		eq(H.store[key].Coins, 999, "the newer server's coins")
	end)

	test("saving: a joiner whose old server never lets go plays unsaved, without clobbering it", function()
		local p = H.player()
		local key = "u_" .. p.UserId
		H.store[key] = S.DataService.migrate({ SchemaVersion = 10, Coins = 500 })
		H.store[key].Lock = { JobId = "other-server", Time = os.time() }
		local c = H.combatant(false)
		c.player = p
		S.DataService.load(c)
		check(not c.persistent, "took over a live session")
		eq(H.store[key].Coins, 500, "stored coins")
		check(H.store[key].Lock.JobId == "other-server", "stole the lock")
	end)

	test("saving: a stale lock (old server crashed) is taken over", function()
		local p = H.player()
		local key = "u_" .. p.UserId
		H.store[key] = S.DataService.migrate({ SchemaVersion = 10, Coins = 500 })
		H.store[key].Lock = { JobId = "dead-server", Time = os.time() - Config.Data.SessionLockTimeout - 5 }
		local c = H.combatant(false)
		c.player = p
		S.DataService.load(c)
		check(c.persistent, "stale lock blocked the load")
		eq(c.profile.Coins, 500, "loaded coins")
	end)

	test("saving: leaving while the save loads still releases the lock", function()
		local c = H.combatant()
		c.released = true -- PlayerRemoving's release save already ran
		S.DataService.load(c)
		local saved = H.store["u_" .. c.player.UserId]
		check(saved ~= nil and saved.Lock == nil, "lock left behind after leaving mid-load")
	end)

	test("saving: DataStore down means an unsaved session, never a wiped save", function()
		local p = H.player()
		local key = "u_" .. p.UserId
		H.store[key] = S.DataService.migrate({ SchemaVersion = 10, Coins = 4321 })
		H.storeError = "502: API Services rejected request"
		local c = H.combatant(false)
		c.player = p
		S.DataService.load(c)
		check(not c.persistent and c.profileLoaded, "should play unsaved")
		eq(c.profile.Coins, 0, "unsaved session coins")
		H.storeError = nil
		check(not S.DataService.save(c, true), "unsaved session wrote to the store")
		eq(H.store[key].Coins, 4321, "the real save")
	end)

	-- Rewards ----------------------------------------------------------------------------------------

	local function ctx(winner, opts)
		local t = { matchId = math.random(1, 1e9), winner = winner, aborted = false, casual = true, duration = 60 }
		for k, v in opts or {} do
			t[k] = v
		end
		return t
	end

	test("rewards: tiers, idle players get nothing, aborted matches pay nothing", function()
		local P = Config.Coins
		local function fake(team, elims, alive, throws)
			local st = H.stats()
			st.throws = throws
			return { team = team, stats = st, matchEliminations = elims, aliveAtWin = alive, lateJoin = false }
		end
		local killer = fake("Red", 0, true, 3)
		local c = ctx("Red", { finalEliminator = killer })
		eq(S.RewardService.coins(killer, c), P.WinLastElimination, "final knockout")
		eq(S.RewardService.coins(fake("Red", 0, true, 3), c), P.WinFlawless, "flawless")
		eq(S.RewardService.coins(fake("Red", 1, true, 3), c), P.WinAlive, "alive")
		eq(S.RewardService.coins(fake("Red", 2, false, 3), c), P.Win, "win from jail")
		eq(S.RewardService.coins(fake("Blue", 1, false, 2), c), P.LossParticipation, "loser")
		eq(S.RewardService.coins(fake("Blue", 1, false, 0), c), 0, "idle loser")
		eq(S.RewardService.coins(killer, ctx("Red", { aborted = true, finalEliminator = killer })), 0, "aborted")
	end)

	test("rewards: a match pays once, boosts double it, and it counts toward the daily quests", function()
		local c = H.combatant()
		c.team = "Red"
		c.stats.throws = 2
		c.matchEliminations = 1
		c.aliveAtWin = true
		local m = ctx("Red")
		S.RewardService.awardMatch({ c }, m)
		eq(c.profile.Coins, Config.Coins.WinAlive, "first payout")
		S.RewardService.awardMatch({ c }, m)
		eq(c.profile.Coins, Config.Coins.WinAlive, "same match paid twice")
		local d = S.QuestService.daily(c)
		eq(d.progress.Played, 1, "played quest")
		eq(d.progress.Won, 1, "won quest")
		-- with a boost, the next match pays double
		c.profile.CoinBoostForever = true
		c.stats = H.stats()
		c.stats.throws = 1
		S.RewardService.awardMatch({ c }, ctx("Red"))
		eq(c.profile.Coins, Config.Coins.WinAlive + 2 * Config.Coins.WinAlive, "boosted payout")
		local results = H.eventsNamed("Results")
		eq(results[#results].payload.boost, 2, "results card boost")
	end)

	test("quests: a first claim comes back after the short cooldown, later ones wait for the reset", function()
		local c = H.combatant()
		local d = S.QuestService.daily(c)
		d.progress.Won = 1
		check(S.QuestService.claim(c, "Won") ~= nil, "first claim refused")
		local function won(): any
			for _, q in S.QuestService.status(c).quests do
				if q.id == "Won" then
					return q
				end
			end
			return nil
		end
		check(won().claimed and math.abs(won().nextAt - os.time() - Config.Quests.FirstCooldown) <= 1, "cooldown")
		check(S.QuestService.claim(c, "Won") == nil, "claimed again during the cooldown")
		d.backAt.Won = os.time() - 1 -- the cooldown has run out
		check(not won().claimed and won().progress == 0, "quest didn't come back fresh")
		d.progress.Won = 1
		check(S.QuestService.claim(c, "Won") ~= nil, "second claim refused")
		eq(won().nextAt, S.QuestService.status(c).resetsAt, "second claim waits for the reset")
	end)

	test("rewards: aborted or idle matches don't count toward the quests; a loss is played, not won", function()
		local c = H.combatant()
		c.team = "Red"
		S.RewardService.awardMatch({ c }, ctx("Red")) -- idle: no actions
		c.stats.throws = 3
		S.RewardService.awardMatch({ c }, ctx(nil, { aborted = true }))
		eq(S.QuestService.daily(c).progress.Played, nil, "matches counted")
		c.stats = H.stats()
		c.stats.throws = 1
		S.RewardService.awardMatch({ c }, ctx("Blue"))
		eq(S.QuestService.daily(c).progress.Played, 1, "a loss isn't played")
		eq(S.QuestService.daily(c).progress.Won, nil, "a loss counted as won")
	end)

	test("rewards: bot-heavy (casual) matches leave win streaks alone; real ones move them", function()
		local c = H.combatant()
		c.team = "Red"
		c.stats.throws = 1
		c.profile.CurrentWinStreak = 4
		S.RewardService.awardMatch({ c }, ctx("Blue", { casual = true }))
		eq(c.profile.CurrentWinStreak, 4, "casual loss broke the streak")
		c.stats = H.stats()
		c.stats.throws = 1
		S.RewardService.awardMatch({ c }, ctx("Red", { casual = false }))
		eq(c.profile.CurrentWinStreak, 5, "real win didn't advance the streak")
		c.stats = H.stats()
		c.stats.throws = 1
		S.RewardService.awardMatch({ c }, ctx("Blue", { casual = false }))
		eq(c.profile.CurrentWinStreak, 0, "real loss didn't end the streak")
		eq(c.profile.BestWinStreak, 5, "best streak")
	end)

	-- Daily quests ----------------------------------------------------------------------------------

	local function quest(c, id)
		for _, q in S.QuestService.status(c).quests do
			if q.id == id then
				return q
			end
		end
	end
	local function finish(c, id)
		for _, q in Config.Quests.List do
			if q.Id == id then
				S.QuestService.record(c, q.Event, q.Goal)
			end
		end
	end

	test("quests: knockouts, games and wins add up to each goal and stop there; bots don't track", function()
		local c = H.combatant()
		S.QuestService.record(c, "Knockout")
		S.QuestService.record(c, "Knockout")
		local q = quest(c, "Knockouts")
		check(q.progress == 2 and not q.ready, "2 of 3 knockouts")
		S.QuestService.record(c, "Knockout", 5)
		q = quest(c, "Knockouts")
		check(q.progress == 3 and q.ready and not q.claimed, "knockouts past the goal")
		eq(quest(c, "Played").progress, 0, "a knockout counted as a game")
		S.QuestService.record(c, "Played")
		eq(quest(c, "Played").progress, 1, "played")
		S.QuestService.record(c, "Won")
		check(quest(c, "Won").ready, "win quest not ready")
		local bot = H.combatant(false)
		S.QuestService.record(bot, "Knockout")
		eq(bot.profile.DailyQuests.date, "", "a bot's quests were touched")
	end)

	test("quests: progress and claims reset at UTC midnight", function()
		local day = 20000 * 86400
		H.now = day + 86400 - 2 -- two seconds before midnight UTC
		local c = H.combatant()
		finish(c, "Won")
		check(S.QuestService.claim(c, "Won"), "claim refused")
		S.QuestService.record(c, "Knockout")
		eq(S.QuestService.status(c).resetsAt, day + 86400, "reset time")
		H.now = day + 86400 -- midnight
		local st = S.QuestService.status(c)
		for _, q in st.quests do
			check(q.progress == 0 and not q.claimed and not q.ready, q.id .. " carried over midnight")
		end
		eq(st.resetsAt, day + 2 * 86400, "next reset time")
		check(not S.QuestService.claim(c, "Won"), "claimed before the new day's win")
		finish(c, "Won")
		check(S.QuestService.claim(c, "Won"), "the next day's chest refused")
	end)

	test("quests: each chest is claimed once a day, only when done, only in the hub, and saves", function()
		local c = H.combatant()
		local r, why = S.QuestService.claim(c, "Knockouts")
		check(r == nil and why, "claimed an unfinished quest")
		check(not S.QuestService.claim(c, "Nope"), "claimed an unknown quest")
		finish(c, "Knockouts")
		c.status, c.inMatch = "Active", true
		check(not S.QuestService.claim(c, "Knockouts"), "claimed during a match")
		c.status, c.inMatch = "Lobby", false
		c.paidRandomRestricted = true -- quest chests are free: allowed everywhere
		r = S.QuestService.claim(c, "Knockouts")
		check(r and r.ok and r.kind == "Chest" and r.quest == "Knockouts", "claim refused")
		eq(Catalog.get(r.id).Category, "Title", "Title Chest dropped a " .. Catalog.get(r.id).Category)
		check(c.profile.OwnedCosmetics[r.id] and not r.duplicate, "prize not owned")
		eq(r.slots[r.index], r.id, "the reveal wheel doesn't land on the prize")
		eq(#r.slots, Config.Quests.RevealSlots, "reveal slots")
		check(quest(c, "Knockouts").claimed, "not marked claimed")
		local coins = c.profile.Coins
		check(not S.QuestService.claim(c, "Knockouts"), "claimed twice")
		eq(c.profile.Coins, coins, "a refused claim paid")
		check(#H.eventsNamed("Profile") > 0, "claim didn't push the profile")
		-- an unloaded profile can't claim
		local early = H.combatant()
		finish(early, "Played")
		early.profileLoaded = false
		check(not S.QuestService.claim(early, "Played"), "claimed before the profile loaded")
	end)

	test("quests: a claim survives a save and reload, and stays claimed", function()
		local c = H.combatant()
		finish(c, "Played")
		check(S.QuestService.claim(c, "Played"), "claim refused")
		local reloaded = { profile = S.DataService.migrate(H.deepCopy(c.profile)), profileLoaded = true }
		local q
		for _, it in S.QuestService.status(reloaded).quests do
			if it.id == "Played" then
				q = it
			end
		end
		check(q.claimed and not q.ready, "claim lost on reload")
	end)

	test("quests: drops follow each chest's rarity odds and stay in its category", function()
		for _, def in Config.Quests.List do
			local odds = S.RewardService.chestOdds(def.Chest)
			local category = Config.Quests.Chests[def.Chest].Category
			local counts, n = {}, 2000
			for _ = 1, n do
				local c = H.combatant(false) -- a fresh profile owns nothing, so there are no duplicates
				local r = S.RewardService.grant(c, { Kind = "Chest", Chest = def.Chest }, "Test")
				eq(Catalog.get(r.id).Category, category, def.Chest .. " category")
				eq(Catalog.rarity(Catalog.get(r.id)), r.rarity, def.Chest .. " rarity")
				check(not r.duplicate, def.Chest .. " duplicate on an empty profile")
				counts[r.rarity] = (counts[r.rarity] or 0) + 1
			end
			for rarity, p in odds do
				local got = (counts[rarity] or 0) / n
				check(
					math.abs(got - p) < 0.035,
					("%s: %s is %.1f%%, want %.1f%%"):format(def.Chest, rarity, got * 100, p * 100)
				)
			end
		end
	end)

	test("quests: an owned item never drops while its rarity has unowned ones; all owned pays coins", function()
		local c = H.combatant()
		local pool = S.RewardService.chestPool("Gesture")
		-- own every gesture but one Rare: every Rare roll is that one, every other roll a duplicate
		local last = pool.Rare[1].Id
		for _, items in pool do
			for _, item in items do
				c.profile.OwnedCosmetics[item.Id] = item.Id ~= last or nil
			end
		end
		local sawRare, sawDup = false, false
		for _ = 1, 200 do
			c.profile.OwnedCosmetics[last] = nil
			local before = c.profile.Coins
			local r = S.RewardService.grant(c, { Kind = "Chest", Chest = "Gesture" }, "Test")
			if r.rarity == "Rare" then
				sawRare = true
				check(r.id == last and not r.duplicate and r.coins == 0, "rolled an owned Rare")
			else
				sawDup = true
				check(r.duplicate, "an owned " .. r.rarity .. " wasn't a duplicate")
				eq(r.coins, Config.Economy.DuplicateCoins[r.rarity], r.rarity .. " duplicate coins")
				eq(c.profile.Coins - before, r.coins, "duplicate coins not paid")
				eq(Catalog.rarity(Catalog.get(r.id)), r.rarity, "duplicate shows the wrong rarity")
			end
		end
		check(sawRare and sawDup, "200 rolls never hit both cases")
	end)

	test("quests: the panel status lists each chest's drops and odds", function()
		local c = H.combatant()
		local st = S.QuestService.status(c)
		eq(#st.quests, #Config.Quests.List, "quest count")
		for _, q in st.quests do
			local n = 0
			for r, ids in q.drops do
				for _, id in ids do
					eq(Catalog.rarity(Catalog.get(id)), r, id .. " listed under the wrong rarity")
					n += 1
				end
				check(#ids > 0 or q.odds[r] == 0, q.id .. " has odds for an empty " .. r)
			end
			check(n > 0, q.id .. " lists no drops")
		end
	end)

	test("save migration v12: today's unopened free chests become bonus spins; lobby chest data goes", function()
		local D = S.DataService
		local today = os.date("!%Y-%m-%d", os.time())
		local both = D.migrate({
			SchemaVersion = 11,
			Coins = 10,
			BonusSpins = { "Standard" },
			ChestOpens = 12,
			ChestDaily = { date = today, matches = 3, claimed = {} },
		})
		eq(both.SchemaVersion, Config.Data.SchemaVersion, "schema")
		eq(#both.BonusSpins, 3, "owed chests not converted")
		check(both.BonusSpins[1] == "Standard" and both.BonusSpins[2] == "Standard", "existing spin or Common lost")
		eq(both.BonusSpins[3], "RarePlus", "Rare chest became the wrong wheel")
		check(both.ChestDaily == nil and both.ChestOpens == nil, "lobby chest data left behind")
		eq(both.Coins, 10, "coins")
		check(type(both.DailyQuests.progress) == "table" and type(both.DailyQuests.claimed) == "table", "quests")
		-- one already used, the other not unlocked yet
		local used =
			D.migrate({ SchemaVersion = 11, ChestDaily = { date = today, matches = 1, claimed = { Common = true } } })
		eq(#used.BonusSpins, 0, "a used or locked free chest was granted")
		local partial = D.migrate({ SchemaVersion = 11, ChestDaily = { date = today, matches = 1, claimed = {} } })
		eq(#partial.BonusSpins, 1, "Common free chest not converted")
		-- yesterday's free opens had already expired
		local stale = D.migrate({ SchemaVersion = 11, ChestDaily = { date = "2000-01-01", matches = 9, claimed = {} } })
		eq(#stale.BonusSpins, 0, "an expired free chest was granted")
		-- a v12 save isn't converted again
		local again = D.migrate(H.deepCopy(both))
		eq(#again.BonusSpins, 3, "second migration")
	end)

	-- Spin, boosts, compliance ---------------------------------------------------------------------

	test("spin: one free a day, paid spins cost coins and stop at the daily cap", function()
		local SP = Config.Spin
		local c = H.combatant()
		check(S.SpinService.spin(c, "Free"), "free spin refused")
		check(not S.SpinService.spin(c, "Free"), "second free spin")
		check(not S.SpinService.spin(c, "Coins"), "paid spin with no coins")
		c.profile.Coins = SP.ExtraSpinCost * (SP.MaxPaidPerDay + 2)
		for n = 1, SP.MaxPaidPerDay do
			local before = c.profile.Coins
			local r = S.SpinService.spin(c, "Coins")
			check(r, "paid spin " .. n .. " refused")
			eq(c.profile.Coins, before - SP.ExtraSpinCost + r.coins, "paid spin cost")
		end
		check(not S.SpinService.spin(c, "Coins"), "paid spins aren't capped")
		H.now = os.time() + 86400
		check(S.SpinService.spin(c, "Free"), "free spin didn't come back the next day")
	end)

	test("spin: restricted players get the free spin but no paid ones", function()
		local c = H.combatant()
		c.paidRandomRestricted = true
		c.profile.Coins = 100000
		local st = S.SpinService.status(c)
		check(st.restricted and st.paidLeft == 0 and st.robux == 0, "status offers paid spins")
		check(S.SpinService.spin(c, "Free"), "free spin refused")
		check(not S.SpinService.spin(c, "Coins"), "paid spin allowed")
	end)

	test("boosts: none, timed, expired, lifetime; bots never boosted", function()
		local c = H.combatant()
		eq(S.BoostService.multiplier(c), 1, "no boost")
		c.profile.CoinBoostUntil = os.time() + 60
		eq(S.BoostService.multiplier(c), 2, "timed")
		c.profile.CoinBoostUntil = os.time() - 1
		eq(S.BoostService.multiplier(c), 1, "expired")
		c.profile.CoinBoostForever = true
		eq(S.BoostService.multiplier(c), 2, "lifetime")
		local bot = H.combatant(false)
		bot.profile.CoinBoostForever = true
		eq(S.BoostService.multiplier(bot), 1, "bot")
	end)

	test("compliance: policy lookup sets the flag; a failed lookup stays restricted", function()
		local c = H.combatant()
		c.paidRandomRestricted = nil
		check(S.ComplianceService.paidRandomRestricted(c), "unrestricted before the lookup")
		S.ComplianceService.load(c)
		check(not S.ComplianceService.paidRandomRestricted(c), "allowed player still restricted")
		local r = H.combatant()
		r.paidRandomRestricted = nil
		H.policy[r.player.UserId] = { ArePaidRandomItemsRestricted = true }
		S.ComplianceService.load(r)
		check(S.ComplianceService.paidRandomRestricted(r), "restricted player allowed")
		local f = H.combatant()
		f.paidRandomRestricted = nil
		H.policy[f.player.UserId] = "error"
		S.ComplianceService.load(f)
		check(S.ComplianceService.paidRandomRestricted(f), "failed lookup let paid items through")
	end)

	-- Purchases ------------------------------------------------------------------------------------

	test("purchases: bundles grant once; a retried receipt never grants twice", function()
		local c = H.combatant()
		local b = Config.CoinShop.Bundles[3]
		local r = receipt(c, b.ProductId)
		eq(S.PurchaseService.process(r), Granted, "first receipt")
		eq(c.profile.Coins, b.Coins, "coins")
		eq(S.PurchaseService.process(r), Granted, "retry")
		eq(c.profile.Coins, b.Coins, "coins after retry")
		eq(#H.eventsNamed("CoinsBought"), 1, "celebrations")
	end)

	test("purchases: a limited bundle grants its items and coins once, even after it ends", function()
		local c = H.combatant()
		local o = Config.CoinShop.Offers[1]
		-- the shipped id may still be the placeholder 0, so route a test id to the same grant
		local productId = 999000222
		S.PurchaseService.register(productId, function(cc)
			return S.PurchaseService.grantOffer(cc, o)
		end)
		H.now = DateTime.fromIsoDate(o.End).UnixTimestamp + 3600 -- a late receipt still grants
		local r = receipt(c, productId)
		eq(S.PurchaseService.process(r), Granted, "first receipt")
		eq(S.PurchaseService.process(r), Granted, "retry")
		eq(c.profile.Coins, o.Coins, "coins granted once")
		for _, id in o.Items do
			check(S.ShopService.owns(c, id), "missing " .. id)
		end
		eq(#H.eventsNamed("BundleBought"), 1, "celebrations")
	end)

	test("shop: bundle cosmetics never sell for coins and stay off the shelf until owned", function()
		local c = H.combatant()
		local id = Config.CoinShop.Offers[1].Items[1]
		H.game:GetService("ReplicatedStorage"):SetAttribute("Halloween", true)
		check(not Catalog.isOffered(Catalog.get(id)), "bundle item offered for coins")
		c.profile.Coins = 1e6
		check(not S.ShopService.buy(c, id), "bundle item sold for coins")
		eq(c.profile.Coins, 1e6, "coins spent")
	end)

	test("mastery: earn-only cosmetics are never sold, spun or rolled", function()
		local c = H.combatant()
		c.profile.Coins = 1e6
		local n = 0
		for _, item in Catalog.Items do
			if item.Unlock then
				n += 1
				check(not Catalog.isOffered(item), item.Id .. " offered for coins")
				check(not S.ShopService.buy(c, item.Id), item.Id .. " sold for coins")
				for _, list in S.SpinService.pool() do
					for _, it in list do
						check(it.Id ~= item.Id, item.Id .. " is on the wheels")
					end
				end
			end
		end
		check(n >= 4, "mastery items missing")
		eq(c.profile.Coins, 1e6, "coins spent")
	end)

	test("exclusives: Robux-only, priced by category, never spun, rolled or sold for coins", function()
		local c = H.combatant()
		c.profile.Coins = 1e6
		local E = Config.Economy
		local count: { [string]: number } = {}
		for _, item in Catalog.Items do
			if item.Exclusive then
				local rarity = Catalog.rarity(item)
				count[item.Category] = (count[item.Category] or 0) + 1
				check(rarity == "Epic" or rarity == "Legendary", item.Id .. " is " .. rarity)
				check(not Catalog.isOffered(item), item.Id .. " offered for coins")
				check(not S.ShopService.buy(c, item.Id), item.Id .. " sold for coins")
				local byCat = E.RobuxPriceByCategory[item.Category]
				eq(
					Catalog.robuxPrice(item),
					if byCat then byCat[rarity] else E.RobuxPriceByRarity[rarity],
					item.Id .. " price"
				)
				for _, list in S.SpinService.pool() do
					for _, it in list do
						check(it.Id ~= item.Id, item.Id .. " is on the wheels")
					end
				end
				for _, q in Config.Quests.List do
					for _, list in S.RewardService.chestPool(q.Chest) do
						for _, it in list do
							check(it.Id ~= item.Id, item.Id .. " is in a chest")
						end
					end
				end
			end
		end
		eq(count.BallSkin, 4, "exclusive ball skins")
		eq(count.Trail, 4, "exclusive trails")
		eq(count.Title, 4, "exclusive titles")
		eq(count.Finisher, 4, "exclusive finishers")
		eq(count.Pose, 3, "exclusive gestures")
		eq(Catalog.robuxPrice(Catalog.get("Finisher_DestinyArrives")), 199, "Legendary finisher price")
		eq(Catalog.robuxPrice(Catalog.get("Pose_Robot")), 39, "Epic gesture price")
		for _ = 1, 20 do
			check(not S.ShopService.pickBotFinisher().Exclusive, "a bot got an exclusive finisher")
		end
		eq(Catalog.robuxPrice(Catalog.get("Title_MainCharacter")), 99, "Legendary title price")
		eq(Catalog.robuxPrice(Catalog.get("Skin_Phoenix")), 199, "Legendary skin price")
		eq(Catalog.robuxPrice(Catalog.get("Skin_Lime")), nil, "a coin item has a Robux price")
		eq(c.profile.Coins, 1e6, "coins spent")
	end)

	test("titles: a gradient title colors each letter and escapes rich text", function()
		local TitleStyle = H.require("shared/TitleStyle")
		local cols = Catalog.get("Title_NeonAce").Data.Gradient
		local out = TitleStyle.render("A <b>", cols, 0)
		local _, fonts = string.gsub(out, "<font ", "")
		eq(fonts, 4, "one font tag per letter (the space bare)")
		check(string.find(out, "&lt;", 1, true) ~= nil, "< not escaped")
		check(string.find(out, "<b>", 1, true) == nil, "raw tag survived")
		check(TitleStyle.render("Ace", cols, 0) ~= TitleStyle.render("Ace", cols, 0.5), "phase does nothing")
	end)

	test("mastery: power-ball knockouts count by type, unlock at the goal, the featured ball doubles", function()
		local types = H.require("shared/BallDefinitions").PowerTypes
		-- freeze a day whose featured ball is Pop (types[3]): day % 3 == 2
		H.now = 2 * 86400 + 3600
		eq(S.ShopService.featuredBall(), "Pop", "featured ball")
		local c = H.combatant()
		S.ShopService.recordPowerKO(c, "Standard")
		S.ShopService.recordPowerKO(c, nil)
		S.ShopService.recordPowerKO(c, "Nope")
		eq(next(c.profile.PowerKOs), nil, "a Standard / unknown knockout counted")
		for i = 1, 9 do
			S.ShopService.recordPowerKO(c, "Heavy")
			eq(c.profile.PowerKOs.Heavy, i, "Heavy count")
		end
		check(not S.ShopService.owns(c, "Title_Heavyweight"), "unlocked before the goal")
		local got = S.ShopService.recordPowerKO(c, "Heavy")
		eq(got[1], "Title_Heavyweight", "unlock at the goal")
		check(S.ShopService.owns(c, "Title_Heavyweight"), "Heavyweight not owned")
		eq(#S.ShopService.recordPowerKO(c, "Heavy"), 0, "unlocked twice")
		-- featured: each Pop knockout counts double
		for _ = 1, 5 do
			S.ShopService.recordPowerKO(c, "Pop")
		end
		eq(c.profile.PowerKOs.Pop, 10, "featured double")
		check(S.ShopService.owns(c, "Title_PopStar"), "Pop Star not owned")
		-- the trail needs 25 of each type
		local trail = Catalog.get("Trail_PowerSurge")
		c.profile.PowerKOs = { Heavy = 30, Rocket = 24, Pop = 40 }
		local have, need = Catalog.unlockProgress(trail, c.profile.PowerKOs)
		eq(have, 24, "All progress is the lowest type")
		eq(need, 25, "All goal")
		S.ShopService.recordPowerKO(c, "Rocket")
		check(S.ShopService.owns(c, "Trail_PowerSurge"), "Power Surge not owned at 25 each")
		check(S.ShopService.owns(c, "Title_Rocketeer"), "Rocketeer not owned past its goal")
		-- bots and unloaded profiles don't track
		local bot = H.combatant(false)
		S.ShopService.recordPowerKO(bot, "Heavy")
		eq(next(bot.profile.PowerKOs), nil, "a bot counted")
		check(#types == 3, "power types")
	end)

	test("mastery: a save without PowerKOs gets an empty one; counts survive migration", function()
		local D = S.DataService
		eq(next(D.migrate({ SchemaVersion = 12 }).PowerKOs), nil, "missing PowerKOs")
		eq(next(D.migrate({ SchemaVersion = 12, PowerKOs = "bad" }).PowerKOs), nil, "damaged PowerKOs")
		eq(D.migrate({ SchemaVersion = 12, PowerKOs = { Heavy = 4 } }).PowerKOs.Heavy, 4, "PowerKOs lost")
	end)

	test("purchases: every configured product has a handler that grants", function()
		local c = H.combatant()
		for _, b in Config.CoinShop.Bundles do
			eq(S.PurchaseService.process(receipt(c, b.ProductId)), Granted, b.Id)
		end
		for _, b in Config.CoinShop.Boosts do
			eq(S.PurchaseService.process(receipt(c, b.ProductId)), Granted, b.Id)
		end
		eq(S.PurchaseService.process(receipt(c, Config.Spin.RobuxProductId)), Granted, "extra spin")
	end)

	test("purchases: timed boosts stack, lifetime boost sets the flag", function()
		local c = H.combatant()
		local timed, forever = Config.CoinShop.Boosts[1], Config.CoinShop.Boosts[2]
		S.PurchaseService.process(receipt(c, timed.ProductId))
		local first = c.profile.CoinBoostUntil
		check(math.abs(first - (os.time() + timed.Minutes * 60)) <= 2, "timed boost length")
		S.PurchaseService.process(receipt(c, timed.ProductId))
		eq(c.profile.CoinBoostUntil, first + timed.Minutes * 60, "second timed boost")
		S.PurchaseService.process(receipt(c, forever.ProductId))
		check(c.profile.CoinBoostForever, "lifetime flag")
		eq(S.DataService.migrate(H.deepCopy(c.profile)).CoinBoostForever, true, "lifetime survives a reload")
	end)

	test("purchases: a grant that throws is retried and lands exactly once", function()
		local c = H.combatant()
		local fail = true
		S.PurchaseService.register(777001, function(cc)
			if fail then
				error("boom")
			end
			cc.profile.Coins += 7
			return true
		end)
		local r = receipt(c, 777001)
		eq(S.PurchaseService.process(r), Later, "failed grant")
		eq(c.profile.Coins, 0, "failed grant left coins")
		fail = false
		eq(S.PurchaseService.process(r), Granted, "retry")
		eq(S.PurchaseService.process(r), Granted, "second retry")
		eq(c.profile.Coins, 7, "coins after retries")
	end)

	test("purchases: unknown products, absent players and unloaded profiles wait", function()
		local c = H.combatant()
		eq(S.PurchaseService.process(receipt(c, 4242)), Later, "unknown product")
		local away = receipt(c, Config.CoinShop.Bundles[1].ProductId)
		away.PlayerId = 1
		eq(S.PurchaseService.process(away), Later, "absent player")
		c.profileLoaded = false
		eq(S.PurchaseService.process(receipt(c, Config.CoinShop.Bundles[1].ProductId)), Later, "unloaded profile")
	end)

	test("purchases: a live server that can't save never says granted", function()
		H.studio = false
		local c = H.combatant()
		c.persistent = false -- playing unsaved (DataStore down)
		local b = Config.CoinShop.Bundles[1]
		eq(S.PurchaseService.process(receipt(c, b.ProductId)), Later, "unsaved server")
		eq(c.profile.Coins, 0, "coins granted on an unsaved server")
		-- loaded and saving: granted, and the receipt is on the saved profile
		S.DataService.load(c)
		check(c.persistent, "load failed")
		local r = receipt(c, b.ProductId)
		eq(S.PurchaseService.process(r), Granted, "saving server")
		local saved = H.store["u_" .. c.player.UserId]
		check(table.find(saved.Receipts, r.PurchaseId), "receipt not saved")
		eq(saved.Coins, b.Coins, "saved coins")
	end)

	test("purchases: a Robux spin for a restricted player isn't left unprocessed forever", function()
		local c = H.combatant()
		c.paidRandomRestricted = true
		local before = c.profile.Coins
		local decision = S.PurchaseService.process(receipt(c, Config.Spin.RobuxProductId))
		eq(decision, Granted, "decision")
		check(c.profile.Coins > before, "restricted buyer got nothing for their Robux")
	end)

	test("purchases: the receipt list stays capped", function()
		local c = H.combatant()
		local b = Config.CoinShop.Bundles[1]
		for _ = 1, 130 do
			S.PurchaseService.process(receipt(c, b.ProductId))
		end
		check(#c.profile.Receipts <= 100, "receipt list grew to " .. #c.profile.Receipts)
	end)

	test("Robux buttons unlock after the first finished match", function()
		local c = H.combatant()
		check(not S.PurchaseService.robuxUnlocked(c), "new player")
		c.profile.Matches = Config.CoinShop.RobuxAfterMatches
		check(S.PurchaseService.robuxUnlocked(c), "after a finished match")
	end)

	-- Shop, daily, Halloween -------------------------------------------------------------------------

	test("shop: buy and equip are checked on the server", function()
		local c = H.combatant()
		local item
		for _, it in Catalog.Items do
			if not it.Default and not it.Event then
				item = it
				break
			end
		end
		check(not S.ShopService.buy(c, item.Id), "bought with no coins")
		check(not S.ShopService.equip(c, item.Id), "equipped an unowned item")
		c.profile.Coins = item.Price
		c.status, c.inMatch = "Active", true
		check(not S.ShopService.buy(c, item.Id), "bought during a match")
		c.status, c.inMatch = "Lobby", false
		check(S.ShopService.buy(c, item.Id), "buy refused")
		eq(c.profile.Coins, 0, "coins after buying")
		check(not S.ShopService.buy(c, item.Id), "bought twice")
		check(not S.ShopService.buy(c, "Nope_Nothing"), "bought a made-up item")
	end)

	test("shop: event items sell only during their event; bundle items never", function()
		-- every Halloween item is in the Haunted Bundle now, so the event gate is checked on a stand-in
		local plain = { Id = "Test_Event", Event = "Halloween" } :: any
		check(not Catalog.isOffered(plain, { Halloween = false }), "event item offered outside its event")
		check(Catalog.isOffered(plain, { Halloween = true }), "event item not offered during its event")
		local c = H.combatant()
		H.game:GetService("ReplicatedStorage"):SetAttribute("Halloween", true)
		for _, it in Catalog.Items do
			if it.Event == "Halloween" then
				c.profile.Coins = it.Price
				if it.Bundle then
					check(not S.ShopService.buy(c, it.Id), it.Id .. " (bundle only) sold for coins")
				else
					check(S.ShopService.buy(c, it.Id), it.Id .. " refused during its event")
				end
			end
		end
	end)

	test("daily reward: once per UTC day, ladder advances, a missed day resets", function()
		local L = Config.DailyRewards.Ladder
		local c = H.combatant()
		local r1 = S.ShopService.claimDaily(c)
		check(r1 and r1.ok and r1.day == 1, "first claim")
		eq(r1.kind, "Spin", "day 1 kind")
		eq(c.profile.BonusSpins[1], L[1].Wheel, "day 1 bonus spin queued")
		local r2, why = S.ShopService.claimDaily(c)
		check(not r2 and why, "second claim the same day")
		eq(#c.profile.BonusSpins, 1, "a refused claim granted anyway")
		H.now = os.time() + 86400
		local r = S.ShopService.claimDaily(c)
		check(r and r.day == 2, "next day")
		eq(c.profile.Coins, L[2].Amount, "day 2 coins")
		H.now = os.time() + 4 * 86400
		check(S.ShopService.claimDaily(c), "after a gap")
		eq(c.profile.LoginStreak.day, 1, "missed day resets")
	end)

	test("daily reward: every rung is a valid typed reward; day 1 is a spin; the week loops", function()
		local L = Config.DailyRewards.Ladder
		eq(#L, 7, "ladder length")
		for i, reward in L do
			check(S.RewardService.valid(reward), "day " .. i .. " isn't a valid reward")
		end
		eq(L[1].Kind, "Spin", "day 1")
		-- claim a whole week, one day at a time: every kind lands, and day 8 is day 1 again
		local c = H.combatant()
		local t0 = os.time()
		local kinds = {}
		for day = 1, 8 do
			H.now = t0 + (day - 1) * 86400
			local r = S.ShopService.claimDaily(c)
			check(r and r.ok, "claim on day " .. day)
			eq(r.day, (day - 1) % 7 + 1, "ladder day")
			kinds[r.kind] = true
			if r.kind == "Boost" then
				check(c.profile.CoinBoostUntil > H.now, "the boost isn't running")
			elseif r.kind == "Pick" then
				check(S.RewardService.pick(c, r.ids[1]), "pick refused")
			end
		end
		check(kinds.Coins and kinds.Spin and kinds.Boost and kinds.Pick, "a reward kind never landed")
	end)

	test("rewards: grant gives every kind, and refuses bad rewards and unloaded profiles", function()
		local R = S.RewardService
		local c = H.combatant()
		eq(R.grant(c, { Kind = "Coins", Amount = 50 }, "T").coins, 50, "coins result")
		eq(c.profile.Coins, 50, "coins")
		R.grant(c, { Kind = "Spin", Wheel = "Standard" }, "T")
		eq(c.profile.BonusSpins[1], "Standard", "spin queued")
		R.grant(c, { Kind = "Boost", Id = "Boost30" }, "T")
		check(c.profile.CoinBoostUntil >= os.time() + 29 * 60, "boost")
		eq(#H.eventsNamed("BoostBought"), 1, "boost announced")
		local item = S.SpinService.pool().Common[1]
		local got = R.grant(c, { Kind = "Cosmetic", Id = item.Id, DuplicateCoins = 7 }, "T")
		check(got.kind == "Cosmetic" and not got.duplicate and c.profile.OwnedCosmetics[item.Id], "item")
		local dup = R.grant(c, { Kind = "Cosmetic", Id = item.Id, DuplicateCoins = 7 }, "T")
		check(dup.duplicate and dup.coins == 7 and c.profile.Coins == 57, "duplicate coins")
		local coins = c.profile.Coins
		check(not R.grant(c, { Kind = "Gems", Amount = 5 }, "T"), "unknown kind granted")
		check(not R.grant(c, { Kind = "Spin", Wheel = "Nope" }, "T"), "unknown wheel granted")
		check(not R.grant(c, { Kind = "Boost", Id = "Nope" }, "T"), "unknown boost granted")
		c.profileLoaded = false
		check(not R.grant(c, { Kind = "Coins", Amount = 5 }, "T"), "granted before the profile loaded")
		eq(c.profile.Coins, coins, "a refused grant paid")
	end)

	test("rewards: a pick offers unowned items of its rarity; one choice, once; all owned pays coins", function()
		local R = S.RewardService
		local reward = { Kind = "Cosmetic", Rarity = "Epic", Choices = 3, DuplicateCoins = 1000 }
		local c = H.combatant()
		local r = R.grant(c, reward, "Daily7")
		eq(r.kind, "Pick", "kind")
		eq(#r.ids, math.min(3, #S.SpinService.pool().Epic), "choices")
		for _, id in r.ids do
			local item = Catalog.get(id)
			check(Catalog.rarity(item) == "Epic" and not item.Event and not item.Bundle, id .. " not a plain Epic")
		end
		eq(S.ShopService.dailyStatus(c).pick.ids[1], r.ids[1], "pick in the daily status")
		check(not R.pick(c, "Skin_Lime"), "took something that wasn't offered")
		local got = R.pick(c, r.ids[2])
		check(got and got.ok and c.profile.OwnedCosmetics[r.ids[2]], "pick didn't grant")
		check(not R.pick(c, r.ids[2]), "the same pick granted twice")
		check(not R.pick(c, r.ids[1]), "a second choice from a spent pick")
		eq(#c.profile.RewardPicks, 0, "pick left waiting")
		-- owning every Epic: the duplicate coins instead of a pick
		for _, item in S.SpinService.pool().Epic do
			c.profile.OwnedCosmetics[item.Id] = true
		end
		local coins = c.profile.Coins
		local all = R.grant(c, reward, "Daily7")
		check(all.kind == "Cosmetic" and all.duplicate and all.coins == 1000, "all-owned result")
		eq(c.profile.Coins, coins + 1000, "all-owned coins")
		-- an offered item bought before picking pays the pick's duplicate coins
		local d = H.combatant()
		local p = R.grant(d, reward, "Daily7")
		d.profile.OwnedCosmetics[p.ids[1]] = true
		local late = R.pick(d, p.ids[1])
		check(late.duplicate and late.coins == 1000, "bought-meanwhile pick")
	end)

	test("spin: bonus spins go first on their own wheel, stack with the daily one, work when restricted", function()
		local c = H.combatant()
		c.paidRandomRestricted = true
		S.RewardService.grant(c, { Kind = "Spin", Wheel = "RarePlus" }, "T")
		local st = S.SpinService.status(c)
		eq(st.freeSpins, 2, "bonus + daily")
		eq(st.bonus, "RarePlus", "next wheel")
		for _, id in st.slots do
			check(Catalog.rarity(Catalog.get(id)) ~= "Common", "a Common on the Rare+ wheel")
		end
		local r = S.SpinService.spin(c, "Free")
		check(r and r.how == "Bonus" and r.wheel == "RarePlus", "bonus spin not used first")
		eq(r.slots[r.index], r.id, "prize isn't the slot shown")
		check(table.find(st.slots, r.id) ~= nil, "prize wasn't on the previewed wheel")
		eq(#c.profile.BonusSpins, 0, "bonus spin not spent")
		check(not c.profile.Spin.freeUsed, "bonus spin used up the daily one")
		local d = S.SpinService.spin(c, "Free")
		check(d and d.how == "Free", "daily spin after the bonus")
		check(not S.SpinService.spin(c, "Free"), "a third free spin")
		eq(S.SpinService.status(c).freeSpins, 0, "free spins left")
	end)

	test("Halloween: on inside its window, off outside, off when disabled", function()
		local HC = Config.Halloween
		local saved = { HC.Enabled, HC.Start, HC.End }
		local function iso(t)
			return DateTime.fromUnixTimestamp(t):ToIsoDate()
		end
		local t = os.time()
		HC.Enabled, HC.Start, HC.End = true, iso(t - 60), iso(t + 60)
		local inside = S.HalloweenService.scheduled()
		HC.Start, HC.End = iso(t - 120), iso(t - 60)
		local after = S.HalloweenService.scheduled()
		HC.Enabled, HC.Start, HC.End = false, iso(t - 60), iso(t + 60)
		local disabled = S.HalloweenService.scheduled()
		HC.Enabled, HC.Start, HC.End = saved[1], saved[2], saved[3]
		check(inside and not after and not disabled, "schedule wrong")
		-- the shipped window: this year's Oct 1 to Nov 2 UTC
		HC.Enabled = true
		H.now = DateTime.fromIsoDate("2026-11-03T00:00:00Z").UnixTimestamp
		check(not S.HalloweenService.scheduled(), "still on after Nov 2")
		H.now = DateTime.fromIsoDate("2026-10-31T20:00:00Z").UnixTimestamp
		check(S.HalloweenService.scheduled(), "off on Halloween night")
		HC.Enabled = saved[1]
	end)
end
