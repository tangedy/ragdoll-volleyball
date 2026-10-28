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

	local function chestIndex(tier: string): number
		for i, spot in Config.Chest.Spots do
			if spot.Tier == tier then
				return i
			end
		end
		error("no chest of tier " .. tier)
	end
	local function atChest(c, index)
		c.root = { Position = S.ChestService.position(index), Parent = true }
	end
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
	end)

	test("config: every chest spot names a tier, and every tier can fill its wheel", function()
		local pool = S.SpinService.pool()
		for i, spot in Config.Chest.Spots do
			local tier = Config.Chest.Tiers[spot.Tier]
			check(tier ~= nil, "spot " .. i .. " has unknown tier " .. tostring(spot.Tier))
			local total = 0
			for r, w in tier.RarityWeights do
				if w > 0 then
					check(#pool[r] > 0, spot.Tier .. " can drop " .. r .. " but there are none")
					total += w
				end
			end
			check(total > 0, spot.Tier .. " has no weights")
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
		check(v1.LoginStreak and v1.Spin and v1.ChestDaily and v1.Receipts, "v1 missing fields")
		check(v1.OwnedCosmetics.Skin_Lime, "v1 lost a cosmetic")
		local v3 = D.migrate({ SchemaVersion = 3, Pts = 1234 })
		eq(v3.Coins, 1234, "v3 Pts became coins")
		check(v3.Pts == nil, "Pts left behind")
		local v8 = D.migrate({ SchemaVersion = 8, Coins = 9, Matches = 5, Receipts = { "a" } })
		eq(v8.Coins, 9, "v8 coins")
		eq(v8.Receipts[1], "a", "v8 receipts")
		check(v8.PlaySeconds >= Config.CoinShop.RobuxAfterSeconds, "returning player has to wait for Robux again")
		eq(v8.CoinBoostForever, false, "v8 boost flag")
		local v9 = D.migrate({ SchemaVersion = 9, CoinBoostForever = true, CoinBoostUntil = 77, PlaySeconds = 30 })
		eq(v9.CoinBoostForever, true, "v9 lifetime boost kept")
		eq(v9.CoinBoostUntil, 77, "v9 timed boost kept")
		eq(v9.PlaySeconds, 30, "v9 play time kept")
		check(type(v9.ChestDaily) == "table", "v9 got no ChestDaily")
		-- migrating twice changes nothing
		local again = D.migrate(H.deepCopy(v9))
		eq(again.CoinBoostUntil, 77, "second migration")
		eq(again.PlaySeconds, 30, "second migration play time")
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

	test("rewards: a match pays once, boosts double it, and it counts toward free chests", function()
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
		eq(S.ChestService.daily(c).matches, 1, "free-chest match count")
		-- with a boost, the next match pays double
		c.profile.CoinBoostForever = true
		c.stats = H.stats()
		c.stats.throws = 1
		S.RewardService.awardMatch({ c }, ctx("Red"))
		eq(c.profile.Coins, Config.Coins.WinAlive + 2 * Config.Coins.WinAlive, "boosted payout")
		local results = H.eventsNamed("Results")
		eq(results[#results].payload.boost, 2, "results card boost")
	end)

	test("rewards: aborted or idle matches don't count toward free chests", function()
		local c = H.combatant()
		c.team = "Red"
		S.RewardService.awardMatch({ c }, ctx("Red")) -- idle: no actions
		c.stats.throws = 3
		S.RewardService.awardMatch({ c }, ctx(nil, { aborted = true }))
		eq(S.ChestService.daily(c).matches, 0, "matches counted")
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

	-- Chests ----------------------------------------------------------------------------------------

	test("chests: each tier's wheels hold only its rarities, in about its odds", function()
		local order = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }
		for i, spot in Config.Chest.Spots do
			local tier = Config.Chest.Tiers[spot.Tier]
			local counts, total = {}, 0
			for n = 1, 400 do
				local c = { id = 100000 + n, profile = { ChestOpens = n } }
				for _, id in S.ChestService.wheel(c, i) do
					local r = Catalog.rarity(Catalog.get(id))
					check((tier.RarityWeights[r] or 0) > 0, spot.Tier .. " wheel holds a " .. r)
					counts[r] = (counts[r] or 0) + 1
					total += 1
				end
			end
			local sum = 0
			for _, w in tier.RarityWeights do
				sum += w
			end
			for r, w in tier.RarityWeights do
				local got, want = (counts[r] or 0) / total, w / sum
				check(
					math.abs(got - want) < 0.04,
					("%s: %s is %.1f%% of slots, want %.1f%%"):format(spot.Tier, r, got * 100, want * 100)
				)
			end
			check(order[next(counts)] ~= nil, "no prizes")
		end
	end)

	test("chests: the prize is a slot of the wheel the player was shown", function()
		local c = H.combatant()
		local i = chestIndex("Rare")
		atChest(c, i)
		c.profile.Coins = 100000
		for _ = 1, 20 do
			local shown = S.ChestService.wheel(c, i)
			local r = S.ChestService.open(c, i)
			check(r and r.ok, "open refused")
			eq(shown[r.index], r.id, "prize vs shown wheel")
		end
	end)

	test("chests: paid opens cost the tier price; you must be in the hub and at the chest", function()
		local c = H.combatant()
		local i = chestIndex("Epic")
		local cost = Config.Chest.Tiers.Epic.Cost
		atChest(c, i)
		c.profile.Coins = cost - 1
		check(S.ChestService.open(c, i) == nil, "opened without enough coins")
		eq(c.profile.Coins, cost - 1, "refused open cost coins")
		c.profile.Coins = cost
		c.status, c.inMatch = "Active", true
		check(S.ChestService.open(c, i) == nil, "opened during a match")
		c.status, c.inMatch = "Lobby", false
		c.root = { Position = H.Vector3.new(9999, 0, 9999) }
		check(S.ChestService.open(c, i) == nil, "opened from across the map")
		atChest(c, i)
		local r = S.ChestService.open(c, i)
		check(r and r.ok and not r.free, "paid open refused")
		eq(c.profile.Coins, r.coins, "coins after the open (only a duplicate refund may remain)")
	end)

	test("chests: free Common after 1 match, free Rare after 3, once a day, back the next day", function()
		local c = H.combatant()
		local common, rare = chestIndex("Common"), chestIndex("Rare")
		check(not S.ChestService.isFree(c, "Common"), "free before any match")
		S.ChestService.matchPlayed(c)
		check(#H.eventsNamed("Hint") == 1, "no hint when the free Common unlocked")
		check(S.ChestService.isFree(c, "Common") and not S.ChestService.isFree(c, "Rare"), "after 1 match")
		atChest(c, common)
		local r = S.ChestService.open(c, common)
		check(r and r.free, "free Common refused")
		eq(c.profile.Coins, r.coins, "free open cost coins")
		check(not S.ChestService.isFree(c, "Common"), "Common free twice")
		S.ChestService.matchPlayed(c)
		S.ChestService.matchPlayed(c)
		check(S.ChestService.isFree(c, "Rare"), "Rare not free after 3")
		atChest(c, rare)
		check(S.ChestService.open(c, rare).free, "free Rare refused")
		check(not S.ChestService.isFree(c, "Rare"), "Rare free twice")
		check(not S.ChestService.isFree(c, "Epic"), "Epic was free")
		-- the status the panel reads
		local st = S.ChestService.status(c)
		eq(st.matches, 3, "status matches")
		eq(#st.free, 2, "free tiers listed")
		check(st.free[1].claimed and st.free[2].claimed, "claimed flags")
		-- next UTC day
		H.now = os.time() + 86400
		check(not S.ChestService.isFree(c, "Common"), "yesterday's matches carried over")
		S.ChestService.matchPlayed(c)
		check(S.ChestService.isFree(c, "Common"), "free Common didn't come back")
	end)

	test("chests: restricted regions can't pay for chests but still get free ones", function()
		local c = H.combatant()
		c.paidRandomRestricted = true
		local i = chestIndex("Common")
		atChest(c, i)
		c.profile.Coins = 100000
		local r, why = S.ChestService.open(c, i)
		check(r == nil and why ~= nil, "paid chest for a restricted player")
		eq(c.profile.Coins, 100000, "refused open cost coins")
		check(S.ChestService.status(c).restricted, "status not restricted")
		S.ChestService.matchPlayed(c)
		local free = S.ChestService.open(c, i)
		check(free and free.free, "free chest blocked for a restricted player")
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

	test("Robux buttons unlock after the tutorial plus play time", function()
		local c = H.combatant()
		check(not S.PurchaseService.robuxUnlocked(c), "new player")
		c.profile.TutorialStep = S.TutorialService.Done
		check(not S.PurchaseService.robuxUnlocked(c), "right after the tutorial")
		c.profile.PlaySeconds = Config.CoinShop.RobuxAfterSeconds
		check(S.PurchaseService.robuxUnlocked(c), "after the tutorial and play time")
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

	test("shop: event items sell only during their event", function()
		local c = H.combatant()
		local item
		for _, it in Catalog.Items do
			if it.Event == "Halloween" then
				item = it
			end
		end
		check(item, "no Halloween item")
		c.profile.Coins = item.Price
		H.game:GetService("ReplicatedStorage"):SetAttribute("Halloween", false)
		check(not S.ShopService.buy(c, item.Id), "event item sold outside its event")
		H.game:GetService("ReplicatedStorage"):SetAttribute("Halloween", true)
		check(S.ShopService.buy(c, item.Id), "event item refused during its event")
	end)

	test("daily reward: once per UTC day, ladder advances, a missed day resets", function()
		local L = Config.DailyRewards.Ladder
		local c = H.combatant()
		check(S.ShopService.claimDaily(c), "first claim")
		eq(c.profile.Coins, L[1], "day 1")
		check(not S.ShopService.claimDaily(c), "second claim the same day")
		H.now = os.time() + 86400
		check(S.ShopService.claimDaily(c), "next day")
		eq(c.profile.Coins, L[1] + L[2], "day 2")
		H.now = os.time() + 4 * 86400
		check(S.ShopService.claimDaily(c), "after a gap")
		eq(c.profile.LoginStreak.day, 1, "missed day resets")
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
