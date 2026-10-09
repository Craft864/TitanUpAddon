# Titan Up v0.35.0

The Titan Up guild toolkit for World of Warcraft (Midnight), made for Titan Up on Medivh-US. Modules:

- **Raid tools**
  - **TitanBoard**: live raid strategy board - draw on boss rooms with the raid, plans and slides, laser pointer, Raidstrats import. `/tb`.
  - **Reports**: the **Pull Report** (who died each pull and what they had ready) and the **Raid Scorecard** (weekly death stats), as two tabs of one entry.
  - **Loot**: every raid drop and roll, Mythic+ loot, and who it was traded to until it's equipped; optional roll window with BIS / Sidegrade / set tags shared with the raid.
  - **Combat Timer**: a combat timer you can style and move.
  - **Raid Check**: raid buffs and personal readiness on every ready check and typed /pull (Heroic and Mythic raids).
  - **Macro Workstation**: the **Builder** helps anyone make a macro step by step (pick an ability, choose where it lands, add trinkets, then save it or share it), and **Share** lets the leader or an assist send macros to the raid, a role or a class, and anyone send one to a person in their group.
- **UI tweaks**
  - **UI Tweaks**: Release protection, Death alerts, Stack splitter and Battle rez tracker, each with its options beside its switch.
  - **Keystone Roulette**: a wheel or a vote over the group's keys, then teleport.
- **Games**
  - **Death Roll**: challenge a guildmate to a gold death roll with real /rolls, spectators and a tamper-proof guild ledger.
  - **Wheel of Fortune**: a host runs a puzzle game for three players (or practise with bots).
  - **Wowdle**: the daily guild word game, with guild standings.
  - **Chess**: play a guildmate at your own pace. Games are saved until they end, and moves reach offline players through guildmates running Titan Up.

**Getting around:** `/tu` (or the minimap button, or Blizzard's addon menu) opens the Titan Up window on **Home**: what happened last pull, tonight's Raid Check, loot to trade, and your games at a glance. The **rail** down the left side lists every module by section (Raid, UI Tweaks, Games) with **Settings** at the bottom; click one and it replaces what's showing, in the same spot. The **<** button narrows the rail to icons. A cog in the title bar opens that module's settings, and Settings has a "Back" button to where you were. The **search box** in the middle of the title bar finds any setting: type a few letters, pick a result, and Titan Up opens the page it's on and flashes it (`/tu set <words>` does the same from chat). Pop-ups (Pull Report summary, Raid Check alert, game invites, what's new) stack in one place on screen and can be dragged together. `/tb` still opens TitanBoard directly, `/tu roll` Death Roll, `/tu settings` Settings, `/tu help` lists everything, and `/tu mem` shows how much memory Titan Up is using.

## Installing / upgrading from TitanBoard

1. Close WoW.
2. Delete the old `Interface/AddOns/TitanBoard` folder and copy in the `TitanUp` folder.
3. To keep your saved board plans: in `WTF/Account/<YOUR ACCOUNT>/SavedVariables/`, copy `TitanBoard.lua` and name the copy `TitanUp.lua`. (WoW stores saved data per addon folder name; the data inside is unchanged.)
4. Start WoW. If the old TitanBoard is still enabled, Titan Up tells you in chat.

Everyone in the raid should switch to Titan Up. Board syncing is compatible with TitanBoard 0.8.x, but having both installed causes conflicts.

## Death Roll

Rules: the first roll is 1 to N (N is the wager unless you set a different first roll). Each next roll is 1 up to the previous result. Whoever rolls a 1 loses the wager.

1. `/tu roll`, enter a wager, pick "Anyone" or a specific person, and **Create challenge**. With "Announce in chat" on, a line goes to party/raid chat.
2. Everyone with Titan Up gets a pop-up with **Join** / **Watch** (and a clickable chat link). The first to join gets the seat (or only the person you challenged).
3. The joiner presses **Accept**, the game starts, and the challenger rolls first.
4. Press **ROLL**. It's a real `/roll`: every client reads the result from the game's own system message, so nobody can fake one. Rolls out of turn or with the wrong range are ignored (with a warning).
5. When someone rolls a 1 the game ends. The loser gets **Open trade** with the winner (addons can't move gold, so the payment is a normal trade).
6. **Payments are detected:** when a trade completes, the winner's addon credits the gold to what the loser owes (oldest debt first; partial payments count), and shares it. **Mark paid** (winner only) is there for gold sent another way (mail, etc.).

### Ledger and standings

- Every game is saved by both players under the same id. Your own games are your source of truth.
- Everyone compares a small summary of their games with their group **and with online guildmates** (over the guild's hidden addon channel), and fetches whatever's missing or changed, so the standings fill in without needing to group up.
- **In a raid instance the ledger stays quiet:** the only traffic is the record of a death roll that just finished, sent once to the raid. Summaries, the guild refresh, answering other people's requests and payment updates wait until you leave the instance.
- **Standings** (beside the lobby) shows everyone's wins, losses, net gold and unpaid amounts, plus a scrollable list of recent games. Hover a game for details.
- Rules (anti-tampering):
  - Players can only share games they played in, and WoW stamps every addon message with the real sender, so nobody can pose as someone else.
  - A game is **confirmed** once both players' copies match exactly, and from then on it's **locked**: later copies that disagree (someone edited their saved data) are ignored and shown as a red `!` in the history.
  - If the two copies disagree *before* confirmation, the game is **disputed** and never counts.
  - **Only confirmed games count** in the standings; one-sided games show as **pending**.
  - **Only the winner confirms payment** (trade detection on their side, or their Mark paid). The loser's side shows "sent - waiting for them to confirm". Paid amounts only go up.
  - Limit: editing your own saved data can only change what your own screen shows, never anyone else's.

Notes:
- Both players must be in the same party or raid, since roll results only reach your group.
- WoW's `/roll` maxes out at 1,000,000, so bigger wagers start at 1-1,000,000.
- `/tu roll sim` (or "Practice solo") plays against a fake opponent; your rolls are real, practice games don't count in your record.
- Nothing is sent during an encounter lockdown.
- **Delay rolls in chat** (lobby toggle, on by default): while a game is rolling, its roll lines are held back from your chat until the roll lands on screen, then posted normally. Only that game's rolls are affected - loot rolls and other /rolls show instantly - and the filter is removed the moment the game ends or is cancelled. People without Titan Up still see rolls in chat immediately.
- **Combat:** the Roll button pauses in combat and encounters (rolls can't be read there) and comes back afterwards. A roll the addon couldn't read doesn't count; that player just rolls again. After combat the two players compare roll lists automatically.
- **/reload mid-game:** your game is saved and picked back up after the reload, then resynced with your opponent.

## Raid Check

`/tu raidcheck`. Runs only in **Heroic and Mythic raids** (never Normal or LFR).

- Every Titan Up player's addon reports on its own character: raid buffs, flask, food, weapon enchant (oil, stone or a class imbue like Flametongue or the Lightsmith rites), Vantus Rune, Fury of the Dead, combat potions (Light's Potential + Potion of Recklessness, all qualities), healthstones, and the lowest item durability.
- **Ready check:** reports go out automatically; the person who started it and the raid leader get the results window.
- **/pull (DBM or BigWigs):** when the leader or an assist types `/pull 7`, Titan Up collects fresh reports for about a second. Everyone ready: the pull goes ahead. Anything missing (or someone without Titan Up): an alert lists who's missing what, with **Pull anyway** / **Cancel**. The raid leader also gets the results window when an assist pulls. Pulls started from a DBM/BigWigs button or Blizzard's countdown button can't be intercepted - only the typed command. Toggle: "Check before /pull" in the window.
- **Raid buffs** show as x / raid size, and only for buffs a class in the raid provides. Hover any row for the names.
- **Rules:** a current-tier flask, a food buff, weapon enchant, Vantus Rune, Fury of the Dead, 10+ combat potions, a healthstone (only if a warlock is in the raid), durability 20%+.
- **Flask and food:** any current-tier flask (any quality, including the cauldron flasks) and any food buff count.

## Loot tracker

`/tu loot` (or Loot on the rail).

- **Raid drops (group loot):** recorded automatically when a roll finishes, from WoW's own loot history - item, item level, boss, raid and difficulty, the winner with their roll (Need / Need off-spec / Transmog / Greed), and everyone else's rolls (hover a drop).
- **Raid bonus rolls:** recorded from the "receives bonus loot" chat line, under the boss just killed, marked "bonus roll" (yours and everyone else's in the raid).
- **Mythic+ and dungeons (personal loot):** there are no rolls - the game assigns items - so it records who received what, including the end-of-run chest.
- **Trades:** when a tracked item changes hands in a trade, the hop is added to its history and shared with the group, so everyone's copy shows the same chain. Needs Titan Up on at least one side of the trade (trades between two people without it can't be seen).
- **Equipped:** when the current owner equips the item, tracking ends (it's soulbound for good). Needs Titan Up on the owner's side.
- Only the two people in a trade can report it, and only the owner can report equipping it.
- Left side: raid nights and runs by date; filters All / Raid / Mythic+; search by player, item or boss (finds anyone in an item's history). Tracks Epic+ by default (toggle Rare+). Keeps the newest 1,500 drops.
- Only people who were in the group record the drops (loot history isn't synced through the guild).
- **Roll window** (Loot settings, off by default): one window for every group-loot roll instead of Blizzard's pop-ups - Need / Greed / Transmog / Pass, BIS / Sidegrade / 2pc / 4pc tags and a note per item, and (click an item) what the rest of the raid tagged and rolled and who won. Close it and any roll you haven't made goes back to a Blizzard pop-up; `/tu rolls` reopens it. "Preview the roll window" shows it with sample items.

## Wheel of Fortune

`/tu wheel` (or Wheel of Fortune on the rail).

**Hosting:** enter 1-5 rounds (category + puzzle; puzzles must fit a 4 x 14 board, words aren't split - "Random" fills a round with a ready-made one and "Fill all" fills every round; "Random from" picks the theme - WoW, pop culture, or both - and puzzles never repeat within a game) and **Open game**. Players in your group get a pop-up to take one of the three seats. You see the answer in the host panel (only on your screen) and have **Start game**, **Next round**, **Skip turn** (for AFK players) and **End game**. The host doesn't play.

**Playing:** on your turn
- **SPIN** - the wheel spins for everyone. Dollar wedge: call a consonant; you earn the value for each one in the puzzle and keep your turn. BANKRUPT loses your round money; LOSE A TURN passes.
- **Buy a vowel** for $250 of your round money.
- **SOLVE** - type the whole answer (case and punctuation don't matter).
A letter that isn't there (or was already called), a vowel that isn't there, or a wrong solve passes the turn. Solving banks your round money (at least $1,000). Most money after the last round wins. No bonus round (yet).

The host's addon is the referee: it spins, checks letters and only ever sends the board with unrevealed letters hidden, so nobody can read the answer from addon traffic. `/tu wheel sim` (or **Practice solo**) plays a game against two bots with a fake host.

## Chess

`/tu chess` (or Chess on the rail).

**Starting:** **Challenge a guildmate** and pick them from the list of guildmates who have Titan Up's Chess (online first, then by when they were last seen; class colours), or type a name if they aren't listed yet (your target is picked or filled in). They don't need to be online: the challenge waits for them. Colours are picked at random. You can have up to 20 games going at once.

**Timer (optional, off by default):** pick one in the challenge window. **Days per move** (1, 3 or 7 days): if your opponent hasn't moved in time, a **Claim the win on time** button appears. **Live clock** (5, 10 or 30 minutes each): a normal chess clock that only runs while you're both online, and pauses while either of you is offline. Run out and you lose on time.

**Playing:** click one of your pieces and the squares it can reach are marked (a dot, or a ring around a piece you can take); click one to move. A pawn reaching the last rank asks what to promote to. Each move slides across the board so you can see what just happened, and if your opponent moves while you're in another Titan Up window, the Chess entry on the rail blinks. Pieces each side has taken show next to their names (with who's ahead on material), and the move list shows which piece each capture took. Your pieces are always at the bottom. **Offer a draw** (it stands until the next move), **Accept the draw**, and **Resign** (click twice) are on the right with the move list. A finished game stays in your list until you **Remove** it (the newest 20 are kept).

**Rules:** the full rules, checked on both players' computers: castling, en passant, promotion, check and checkmate, stalemate. Threefold repetition, the 50-move rule and positions where nobody can mate are automatic draws. An illegal move is never accepted.

**Saved:** every game is saved until it's won, drawn or resigned, through /reload, logout and patches.

**When you're not on together:** everything goes over the guild's private addon channel, so every guildmate running Titan Up quietly keeps a small copy of the guild's games (a few hundred bytes each). When your opponent logs in, whoever has the newest copy (you, or any guildmate who's online) hands it over, so your move, challenge, resignation or draw reaches them even if you two are never online at the same time. As long as one guildmate with Titan Up overlaps with each of you, moves get through.

**Honesty:** a guildmate passing a game on can't slip in a move for you: your own moves always win, and your opponent's moves can only be replaced by your opponent. If a guildmate ever hands over a move your opponent didn't make, it's put back to the real move when your opponent's own game arrives, and you're told who delivered it. Nothing can stop someone asking a chess engine for help.

## TitanBoard quick reference

`/tb` opens the board, `/tb help` lists its commands.
Left: draw - Right-drag: pan - Right-click: delete - Wheel: zoom - Ctrl+drag: move an item - Ctrl+wheel: resize an item - Alt+drag: laser - Ctrl+Z: undo.

## Custom room images

See the comments at the top of `Rooms.lua`. Short version: put a .blp or .tga into `Media/Rooms/`, run `/tb ids` on that boss for its encounter ID, and add an entry to `Rooms.lua`. An encounter can have several images (one per phase); each slide picks one with the Room button.

## Planned

- Match by ID instead of English names, so non-English clients work too: potion / flask / food / healthstone item IDs (Raid Check, Pull Report) and the cheat-death auras (Pull Report). The defensives themselves already match by spell ID (checked against 12.1.5 in 0.29.2).

## Changes in 0.35.0

- **Chess: move slide.** Each new move (yours or your opponent's) slides the piece from its old square to the new one over 0.3 s (ease out; one `slider` texture over the board, the landing square stays empty until it lands). An opponent's move while the window is closed blinks the Chess rail button 3 times as well as the chat line.
- **Chess: captured pieces.** `R.Step` records what each ply took in `game.taken[n]` (en passant included); `R.Material`. The player rows show the captured pieces (grouped with counts) and a +N material lead; each capture in the move list ends with a small icon of the piece taken.
- **Chess: challenge list.** The challenge window is now a list of guildmates heard running Chess (`TitanUpDB.chess.known`, name -> last heard, any `TitanUpCH` message; dropped after 30 days or when they leave the guild), online first with class colours and "seen X ago", plus the old name box for anyone not listed.
- **Chess: timers** (Ryan chose "Both"; off by default). `game.tc`: `d1` / `d3` / `d7` (days per move) or `l5` / `l10` / `l30` (live clock, minutes each). Timed games add fields to the end of the messages: `C id w b tc`, `A id startAt`, `M id n uci at clock`, `E id T n` (claim on time; checked against your own copy, 1 h grace), `E id F n` (your own clock ran out), and `S ... tc times start clocks`. Untimed games send exactly what 0.34.0 sent. Days per move counts from the last move's time (a time from the future is taken as now). The live clock only ticks while the opponent is online (heard in the last 2 minutes, or online in the guild roster, refreshed every 15 s while a live game runs); a reported clock can't be higher than what you measured plus 5 s; each client flags its own player when their clock runs out. Couriers carry the timer fields.
- Tests: `testChess0350.lua`.

## Changes in 0.34.0

- **Chess** (new module `Chess/`, rail key `chess`, Games section after Wowdle; `/tu chess`). Ryan picked option B (guild couriers) on 2026-10-09.
  - `Rules.lua` (`ns.ChessRules`): the full rules on a 0..63 board (a1 = 0), legal move generation (castling through / out of check, en passant, promotions, pins), standard algebraic notation with disambiguation and +/#, mate, stalemate, threefold repetition (position key includes castling rights and the en passant square only when a capture is possible), 50-move rule and insufficient material, all automatic. Games grow one move at a time (`R.Begin` / `R.Step`), so a new move costs one position; `R.Play` replays a whole list (a 200-move game in about 0.1 s in Lua 5.1). Perft-tested against the standard positions (start, kiwipete, positions 3-6).
  - `Chess.lua` (`ns.Chess`): games in `TitanUpDB.chess.games` keyed by id (`<Challenger>-<servertime><2 digits>`): `w`, `b`, `by` (challenger), `status` invited / active / over, `moves` (comma-joined UCI), `result` w / b / d, `reason`, `offer`, `via` (plies a courier delivered and the opponent hasn't confirmed). Up to 20 games in progress; the newest 20 finished games kept; unanswered challenges dropped after 30 days.
  - Messages on the new `TitanUpCH` prefix (GUILD channel, any guildmate): `C id white black`, `A id`, `D id`, `M id n uci`, `E id R|O|Y n` (resign / offer / accept a draw), `H id:n:hash:state,...` (hello: login after 15 s, opening the window, max every 30 s), `S id w b by state result reason moves` (a whole game), `U key part n chunk` (an S over 250 bytes, 200-byte parts). Every incoming move or game is replayed against the rules; ids must start with the challenger's name; a claimed rules ending that the moves don't produce is ignored.
  - Couriers: every client keeps other people's games it overhears in `TitanUpDB.chess.carry` (max 60, finished ones 3 days, others 60 days). When a player's hello shows they're behind, a courier sends its copy after 1.5-5 s unless the opponent or another courier sends one with at least as much first. A courier copy never replaces your own moves, never adds moves for you (copies are cut at the first move of yours you don't have), and your opponent's moves are only replaced by your opponent; a replaced courier-delivered move is announced with the courier's name. Hellos carry a djb2 hash of the move list, so matching plies are confirmed and a mismatch makes both players send their game.
  - `ChessUI.lua`: 880 x 570 module window: your games (waiting-on-you first), the board (52 px squares, high contrast: near-white / deep blue, white pieces with a dark outline and black pieces with a light outline, `Media/Chess/*.tga` 128 px), last move / selection / check tints, move dots and capture rings, promotion picker, coordinates, player names with online / offline (guild roster) and whose move, the move list (mouse wheel scrolls), and the action buttons. The rail badge counts games waiting on you. A challenge, acceptance, resignation, draw offer or result shows a chat line and the docked notice when the window is closed; an opponent's move shows a chat line. Login prints how many games are waiting on you.
  - Saves only the games; no options (nothing happens unless you play or someone challenges you).
- Tests: `testChess0340.lua` (74 checks), plus a three-client run (challenger, opponent, courier passing a challenge, its acceptance and a move while the two players are never online together).

## Changes in 0.33.0

- **Settings search** (`Search.lua`, new; loaded after `Settings.lua`):
  - A search box (200 px) centered in every Titan Up title bar (`Nav:CreateHeader` calls `ns.Search:Attach(h)`); the module title now stops before the box instead of before the tabs. Hidden with the title bar (TitanBoard mini / viewer mode).
  - Typing drops one shared result list (`TitanUpSearchResults`, FULLSCREEN_DIALOG strata, up to 10 rows) under the box: each row is the setting's name (matched letters in the accent colour) and where it lives ("Settings > Loot", "UI Tweaks > Death alerts", "Combat Timer"); hovering shows its tooltip. Up / Down / Tab move the selection, Enter or a click opens it, Esc clears. The list closes with its window.
  - Matching: every word must appear in the name, tooltip or place (case-insensitive, colour codes and leading spaces stripped). Names holding every word come first (those starting with the first word ahead), then names starting with the first word, then tooltip matches; ties keep the settings' own order.
  - Opening a result opens its window / page (`S:Open`, `TweaksUI:Open`, `Nav:Switch("timer")`), scrolls the pager so the row is in view, and flashes a 1.6 s accent outline around it (fades from 0.9 s).
  - The index is built the first time someone types and kept; nothing is kept by hand. Sources: the Settings pages' toggle / cycle / button rows (`S:Pages`), each `TW.LIST` tweak (name + description), and rows the hand-built pages tag as they build with `ns.Search.Tag(mod, label, tip, region, y, w)` (Death alerts, Stack splitter, Battle rez tracker, Combat Timer). The tweak pages are prebuilt hidden (`Pager:Prebuild`) on the first search so their rows exist; `Pager:Build` now records each row's offset (`r.y`) and the tweak host's (`content.hostY`).
  - `/tu set <words>` (or `/tu search`) opens Settings with the search typed in; `/tu set` alone opens Settings. Listed in `/tu help`.
  - Saves nothing; no option needed (it's only a box in the Titan Up window).
- Tests: `testSearch0330.lua` (48 checks).

## Changes in 0.32.0

Fixes everything in the full code review of 0.30.1 (`reviews/titanup-code-review-0.30.1.md` in the project files; details per area in `reviews/details/`). PR Craft864/TitanUpAddon#7.

- **Core messaging** (`Core.lua`):
  - `ns.Send` holds every queue while `C_ChatInfo.InChatMessagingLockdown()` is true and sends when the encounter ends, instead of losing queued messages. The refill is 1 message/s per prefix (the server allowance; was 2), burst 10, at most 200 waiting per prefix.
  - `ns.TrySend` (true / "throttle" / false) is shared by the core queue and TitanBoard.
  - `ns.SendFields` sends nil fields as empty (`ns.Join`).
  - `ns.Listen` is one `CHAT_MSG_ADDON` dispatcher; a scope function returning nil ignores the message.
  - Event handlers run through `ns.Try` (xpcall with the failing handler's stack where the client allows).
- **New shared helpers:** `ns.Chunks` / `ns.Reassemble` (split messages; the clock restarts on every part, part numbers are validated), `ns.CleanField` / `ns.Truncate` (UTF-8-safe), `ns.Debounce`, `ns.Now`, `UI.ScrollArea` (Settings and the pop-up panels), `UI.Toast` (Death Roll, Wheel, Macro Share), `UI.ClassRGB`. `UI.Prompt` honours `max`.
- **Roster cache:** `ns.InMyGroup`, `ns.UnitForName`, `ns.ClassOf` (cached per name), `ns.LeaderName` and `ns.CanDraw` no longer rescan the group per call. The cache is rebuilt after `GROUP_ROSTER_UPDATE` / `PARTY_LEADER_CHANGED`, a size change, or 2 s.
- **Version check** (`Updates.lua`):
  - Players outside your group answer only askers older than 0.28.0, and answers to checks close together are merged.
  - "Check again" waits for the running check. No check runs during a boss fight; without a guild, rows say so.
  - The update reminder needs two guildmates reporting the newer version and waits until you're out of combat and out of a raid.
- **TitanBoard:**
  - Split messages over ~9 KB now arrive.
  - A followed leader's plan is never saved over your own (`plan.remote`; the first edit as owner saves a copy named "Name (Leader)").
  - `Board:CancelGesture()` on mini/hide finishes the stroke and stops the laser. Live strokes from others are pruned after 10 s.
  - Snapshots go out at most once per 15 s and queue behind live messages.
  - Raidstrats import is guarded end to end and uses `C_EncodingUtil.DecodeBase64` / `DeserializeJSON` (the Lua decoders moved into the test harness mock).
  - **Only the group leader** sends or is obeyed for the view (`V`), context (`C`) and follow (`F`) messages. Assistants and granted players still draw.
  - Laser at 1 msg/s. "NO GUILD" pill when nothing can sync. UTF-8-safe labels. EJ cache fix. Save on logout. Paste and decompress size caps.
  - Performance: canvas-only redraws on pan/zoom (0 roster reads per frame in a 40-man raid, was ~1,400), cached map art and laser colours, cached op serialization, incremental pen segments, an eraser that hit-tests only when the mouse moves.
  - The window build and layout moved to `Board/BoardFrame.lua`. `Model.Serialize` must stay byte-identical (comment added).
- **Death Roll:**
  - State messages are accepted only for known rooms, from the recorded host/opponent.
  - A roll counts only once this client has seen its `/roll` line (the `K` echo can no longer pick a roll; Ryan chose this over trusting reports). N/S/G are validated.
  - Ledger records can only be changed by their winner or loser. Debt and trade credit count confirmed games only. Dates and amounts are validated. Unconfirmed records are dropped after 7 days.
  - The digest window matches the archive window. `H` has a 4th field (`from`), and a re-share to the same asker waits 30 min.
  - States over 255 bytes go out as the new kind `U^id^part^n^chunk`.
  - Rolling rooms expire after 30 min idle or 120 s with the opponent offline.
  - `DR.Fmt` formats negatives correctly.
  - The chat filter matches connected-realm names.
- **Wheel of Fortune / Keys / Macro Share / Wowdle:**
  - Wheel: players' games end if the host goes silent, and reloaders rejoin. The prize is dropped from an over-long state message.
  - Keys: the teleport button hides with its pop-up (or says where it goes in combat). Vote length is 5-60 s and votes expire. Teleport lookups are cached. Party chat goes through `ns.GroupChannel()`.
  - Macro Share: received text is shown with `|` escaped, script macros are tagged, only character macros are created or updated, and it doesn't report "Shared" during lockdown.
  - Wowdle: refreshes are debounced and the standings scroll.
- **Raid tools and tweaks:**
  - Pull Report:
    - The wipe-window crash is fixed (shadowed `short`).
    - Feign Death is filtered via `UnitIsDead` (shared `PR.GroupDeath`, also used by Death Alerts).
    - Health strips are no longer saved.
    - Stale pulls close at login. The outbox is a list. Overkill and cooldown reads are secret-safe. Spec reads try `C_SpecializationInfo` first.
  - Loot:
    - A drop seen again within 12 h reuses its record (no duplicates across 00:00 UTC; ids unchanged).
    - BoP Need/Greed is marked rolled only after the bind confirmation (`CONFIRM_LOOT_ROLL` + `ConfirmLootRoll` hook).
    - Drops older than 7 days keep only the winner's roll and yours (`LT:SlimOld`, in batches after login).
    - Newest copy wins for picks. The roll ticker runs only while rolls are open.
  - Battle rez: shown for the whole raid encounter / key, in or out of combat.
  - Death Alerts don't reset on your own death mid-encounter.
  - Raid Check:
    - `Q` is only answered from the leader or an assist, and malformed ids are ignored.
    - One bag pass per snapshot.
    - The `/pull` scan is throttled.
  - Scorecard sync: requests are merged, one reply a minute, held through fights, and bounds-checked parts.
  - Stack Splitter steps aside in combat. Bonus roll docking never moves anything in combat and restores Blizzard's current anchors. Hidden windows don't redraw on every report.
  - `TW.MoveControls` is shared by the Timer, Battle rez and Death Alerts pages.
- **Shell:** removed `Nav:AddCog`, `Hub.LootToTrade` and `ns.skippedEvents`. `Nav:Place` skips a window with restricted anchoring in combat. `/tb rate` is clamped to 0.2-5. A one-time chat note appears if your guild rank can't talk in guild chat.
- **Compatibility:** no wire format changed incompatibly (new: Death Roll `U`, a trailing field on the ledger `H`; receivers are stricter). No saved keys were renamed.
- **Tests:** `testCoreFixes.lua` (33 checks), `testBoardFixes.lua` (70), `testGamesFixes.lua` (95), `testRaidFixes.lua` (123). `testVersions0280` waits 0.5 s for the merged answer; `testRefactor0260` waits 150 s for 150 ledger records at 1 msg/s.

## Changes in 0.31.1

- **Wider rail** (`Nav.RAIL_W` 150 -> 190): long module names were cut off on the rail ("Macro Works...", "Keystone Rou...", "Wheel of Fort..."). Rail labels now get about 122 pixels instead of 82, so every name shows in full. The window's saved top-left spot is unchanged; the rail and title bar hang 40 pixels further left (the window is still kept on screen by its clamp insets). The narrow (icons only) rail is unchanged.

## Changes in 0.31.0

- **Macro Workstation** (Raid Tools): Macro Share is now one rail entry, "Macro Workstation", with two title-bar tabs: **Builder** (new, `Share/MacroBuilder.lua`, module key `macrobuilder`, opened first) and **Share** (the old window, key `macroshare`, unchanged prefix and saved data). Both use the shared-rail mechanism Reports uses (`rail = "macros"`).
- **Builder** (`ns.MacroBuilder`, `ns.MacroBuilderUI`):
  - Pick an ability: your spellbook (`C_SpellBook` skill lines, active, non-passive, non-off-spec spells, so talents you've taken are included), a search box, and 12 per page. A class menu shows any class's hand-picked list instead (`MB.SPELLS`, talents included, e.g. Shaman Wind Rush Totem and Poison Cleansing Totem), for building a macro to send to someone.
  - Your class's interrupt is pinned above the list ("YOUR INTERRUPT"): the first one you know from `MB.INTERRUPTS` (Muzzle for Survival, Solar Beam for Balance, Silence for Shadow; Spell Lock notes it needs the Felhunter). It defaults to focus, then mouseover, then target, with /stopcasting.
  - Where it lands: whoever I'm hovering, my focus, the ground under my mouse, myself, my target, tried top to bottom. Only the options that fit the ability can be ticked: enemy (`harm,nodead`), helpful (`help,nodead`), battle rez (`help,dead`), ground (`@cursor`), self (none). Spells not in our lists use `C_Spell.IsSpellHarmful` / `IsSpellHelpful`, else every option is offered (`exists`).
  - Extras: hold Alt / Shift / Ctrl to cast it on myself / focus / target / mouseover (`[mod:x,@unit]` first), stop casting first, `#showtooltip`.
  - Trinkets: both trinket slots are shown (passive ones disabled via `C_Item.GetItemSpell`). Click one or both to add `/use 13` / `/use 14` before or after the ability (a before/after button), or click the chosen ability again to make a trinket-only macro, which can be aimed too. With a trinket first, `#showtooltip` names the ability so the button shows it. Slots, not names, so the macro survives a trinket swap.
  - Drag in a spell (it becomes the ability), a trinket you're wearing (adds its slot), or any usable bag item such as a potion or Healthstone (`/use <name>`).
  - Live preview with a 255-character count, and a numbered plain-English "What it does". **Save to my macros** creates or updates a character macro of that name and puts it on the cursor (`MS:PickUp`; disabled in combat or over 255; the icon is the question mark so `#showtooltip` drives it). **Send to Share tab** fills in the Share form.
  - The builder saves nothing; it starts from scratch each session.
- **Share to one person**: anyone in a party or raid with a guild can send a macro to one guildmate in their group (the target menu then lists people only). These go out as a new message kind `D^id^part^n^chunk` on `TitanUpMS`; recipients accept a `D` only when it's addressed to them by name and the sender is in their group, and older versions ignore it (so the recipient needs 0.31.0). Raid leaders and assistants still send `M` messages, including to one person, so older versions keep receiving those. `MS.CanSend(target)` takes the target now.
- Tests: `testMacroBuilder0310.lua` (68 checks). The before/after comparison differs only by the new window, the rail and Home name ("Macro Workstation"), and a one-second shift of every timestamp (one more window opened in the scenario).

## Changes in 0.30.1

- **Bonus roll docked in the Loot Rolls window** (`Tweaks/BonusRollGuard.lua`, `BG:Dock` / `BG:Place` / `BG:Undock`). While the roll window is shown and a bonus roll is up, Blizzard's real `BonusRollFrame` is anchored into a "Bonus roll" strip: a separate `LOW`-strata frame hung off the window's bottom edge and skinned to match, so Blizzard's frame always draws above it. Only its position changes (`ClearAllPoints` / `SetPoint`). It is never reparented, never given scripts, and keeps its strata, so its Roll and Pass buttons stay Blizzard's own (the bonus roll API is protected). Its original points are saved and restored when the window hides or the bonus roll ends. Blizzard's re-layouts are followed through `hooksecurefunc("GroupLootContainer_Update")` and `GroupLootContainer_AddFrame`. It never docks in combat; it docks on `PLAYER_REGEN_ENABLED` instead. Docking follows the roll window, not the protection tweak; with protection on, the covers and confirm panels follow the buttons as before. With the roll window closed or off, nothing changes.

## Changes in 0.30.0

- **New UI Tweak: Bonus roll protection** (`Tweaks/BonusRollGuard.lua`, `TitanUpDB.tweaks.bonusGuard`, off by default). `AcceptSpellConfirmationPrompt` / `DeclineSpellConfirmationPrompt` have been protected since 10.0.7, so only Blizzard's own buttons can spend or pass a bonus roll. Titan Up therefore never rolls itself and never modifies `BonusRollFrame` (no `SetScript`, no taint). It covers `BonusRollFrame.PromptFrame.RollButton` / `PassButton` with its own buttons, the same approach as Release protection. Clicking a cover opens a panel above the frame: green "Spend a bonus roll?" (loot spec, from `GetLootSpecialization` or the current spec, and coins left, from the prompt's currency through `C_CurrencyInfo.GetCurrencyInfo`) with Cancel, or red "Give up this bonus roll?" with a big "Keep my roll". That cover lifts and the real button glows; clicking the real button is the confirm. After 15 seconds with no click the covers come back. Triggered by `SPELL_CONFIRMATION_PROMPT` with the bonus-roll confirm type and `BonusRollFrame` OnShow (`HookScript`). Cleared by `BONUS_ROLL_STARTED`, `BONUS_ROLL_RESULT`, `SPELL_CONFIRMATION_TIMEOUT` and the frame's OnHide. If the frame's layout is unknown it does nothing. It never checks for other addons.
- **Loot: raid bonus rolls in the drops list.** Bonus-roll loot isn't in `C_LootHistory` (there's no group roll), so `CHAT_MSG_LOOT` in raid instances now matches `LOOT_ITEM_BONUS_ROLL` / `LOOT_ITEM_BONUS_ROLL_SELF` (with English fallbacks). The drop is recorded as `kind = "raid", bonus = true`, under the boss from the last `ENCOUNTER_END` (within 10 minutes), with id `B-date-encounterID-winner-itemID`. The Loot window shows "bonus roll" in place of a Need/Greed roll. Plain raid loot messages are still ignored (the loot history covers them).
- **Combat Timer: chat line choices.** New `timer.chatWhere` (`raid`, `mplus`, `dungeon`, `world`; default raid only) and `timer.chatMin` (0 / 10 / 30 / 60 / 120 seconds; default 30). The "Combat lasted" line prints only when `chatSummary` is on, the fight's kind is picked, and the fight lasted at least the minimum. The kind is decided at the start: a boss encounter in a raid instance is `raid`; a party instance is `mplus` with an active key (or difficulty 8), otherwise `dungeon`; anything else is `world`. Timing, the display and the history are unchanged. The settings page has two new rows, which grey out while the summary is off. Existing installs pick up the new defaults, so dungeon and open-world lines stop until those kinds are turned back on.
- **Loot roll window:** each item stores the roll's full length (`total`, from `START_LOOT_ROLL`'s `rollTime`), and the time bar runs down over that length instead of the last 60 seconds. The preview's rolls now finish at 45 seconds, matching its countdown (they finished at 20).

## Changes in 0.29.2

- **Raid Check: weapon oil / sharpening stone column fixed.** `GetWeaponEnchantInfo` was removed in 12.1.0, so the column read "missing" for everyone. It now uses `C_PaperDollInfo.GetTemporaryEnchantmentInfo(INVSLOT_MAINHAND)` (a table, or nothing when there's no temporary enchant), called through `pcall`, with the old function kept as a fallback for clients that still have it. The `weapon` field in the Raid Check message is unchanged (1 or 0), so mixed versions still read each other.
- **Pull Report: defensive list reviewed for Midnight 12.1.5** (`Report/Defensives.lua`). Every ID was checked against the 12.1.5 talent trees and class spell lists in the game data. Changes:
  - Fixed: Monk Fortifying Brew is 115203 (243435 no longer exists, so Monks never got credit for it).
  - Removed (gone or now passive since 12.0): Renewing Blaze (a passive on Obsidian Scales; it read as "ready" on every Evoker death), Netherwalk, Renewal, Dampen Harm, Diffuse Magic, Stone Bulwark Totem, Bitter Immunity, Shield of Vengeance, Eye for an Eye, Riposte (199754), and Greater Invisibility (no damage reduction since 12.0).
  - Added, major: Paladin Lay on Hands (633) and Blessing of Protection (1022); healer saves cast on yourself: Pain Suppression (33206), Guardian Spirit (47788), Ironbark (102342), Life Cocoon (116849).
  - Added, minor: Arms Ignore Pain (1277297), Rallying Cry (97462).
  - Earth Elemental is now minor and only counts with Primordial Bond (1279819). New optional `requires` field on an entry: a talent that must also be known.
  - Cheat deaths: Evoker Defy Fate is recognised by its lockout debuff "Empty Hourglass" (the old "Defy Fate" name never matched).

## Changes in 0.29.1

Fixes from the first in-game look at the 0.29.0 layout:
- Home: the cards and module tiles ran past the window's right edge (3 x 284 and 6 x 136 didn't fit between the margins). Now 3 x 272 cards with 16px gaps and 6 x 134 tiles, both filling the 848px between 16px margins.
- Title bar: tabs (Reports: Tonight / This week) are right-aligned just left of the cog (or the X), instead of chained after the title, where they ran into the cog. The title is left-justified after the section name ("Raid Tools  >  REPORTS") rather than centred in the bar.
- Macro Share: the macro text box collapsed to one line (a multi-line EditBox with one anchor sizes itself to its text). It is now pinned at both corners so it keeps its full height.
- Death Roll: the standings note is shorter so it isn't cut off in the narrower right-hand column.

## Changes in 0.29.0

- **One Titan Up window with a side rail** (replaces the hub, the tab above each window and the module icons). Every module opens in the same frame: a title bar on top (emblem, "Section > MODULE", tabs, the module's cog, X) and a rail on the left (Home first, then Raid, UI Tweaks and Games, Settings at the bottom). Picking a module closes the one that was showing and opens the new one with the rail in the same place. The window remembers where you dragged it (saved as the top-left corner of the whole frame, `TitanUpDB.nav.pos`). The **<** / **>** button narrows the rail to icons (`nav.railMin`); TitanBoard always uses the narrow rail so its large window still fits.
- **Home** is the default: `/tu`, the minimap button (left-click) and the "Titan Up" key binding open Home, or close whatever Titan Up module is open. Home has six cards (last pull, Raid Check, loot to trade, version check, Wowdle, Death Roll) and a tile for every module.
- **Two sizes:** every module is now 880 x 570 (Standard), TitanBoard keeps its own large size, and the Wheel of Fortune game screen is 880 x 610. Modules use the extra width:
  - Pull Report: pulls, deaths and details are three columns side by side (no more resizing).
  - Raid Scorecard: the pull list and pull details open as a panel over the right side of the table.
  - Raid Check: results and your own checks side by side. Loot, Macro Share, Combat Timer (recent fights on the right), Keystone Roulette (two-column history) and Settings are wider.
  - Wowdle: board and keyboard on the left, guild standings always visible on the right ("Refresh" asks for new results).
  - Death Roll: the game on the left; the guild standings beside the lobby and the spectator list beside a game (no more floating panel next to the window).
  - Wheel of Fortune: the setup screen is the standard size (taller if its list needs it).
- **Reports:** the Pull Report and Raid Scorecard share one rail entry, with "Tonight" and "This week" tabs in the title bar.
- **UI Tweaks keeps its own window**, now a list of switches on the left with the selected tweak's options on the right. Those options moved out of Settings.
- **Settings** is a module on the rail (cog, `/tu settings`, right-click the addon menu entry). Opened from a cog, it shows "< Back to MODULE".
- **Alert dock:** pop-ups (Pull Report summary, Raid Check alert, Macro Share toast, Death Roll and Wheel invites, what's new, version panels) stack at one spot, newest on top; dragging one moves the stack (`TitanUpDB.dock.pos`). "Reset alert position" is on the Titan Up page in Settings. The Keystone Roulette key pop-up stays where it was (its Teleport button is a protected button that can't be moved in combat).
- **No stolen screens:** the Pull Report after a pull and Raid Check results only open by themselves when the Titan Up window is closed or on Home (or already on that module). Otherwise a small notice ("Pull 4 report is ready. [Open]") appears in the dock.
- **TitanBoard:** the mini view and viewer mode still stand alone (no title bar or rail). Picking TitanBoard on the rail while it's mini opens the full board. After combat, the board leaves its automatic mini view only if you didn't open another module during the fight.
- Code: `Nav.lua` rewritten (rail, title bar, Home, dock); `UI.ResizeKeepTab` keeps the top-left corner; `RegisterModule` takes `rail`, `railName`, `tab`, `badge` and `onSwitch`. New saved keys `nav` and `dock` (defaults in `SUITE_DEFAULTS`).
- README intro rewritten for the current module list.

## Changes in 0.28.0

- **Version check is live and group-only.** "Check raid versions" (Settings > Titan Up) or `/tu versions` opens the "RAID VERSIONS" window immediately, listing everyone in your party / raid (alphabetical, so rows don't jump) as "waiting...". Each row fills in as that person's answer arrives: green for the newest version seen, orange "(behind)" for older ones. After 5 seconds, anyone who hasn't answered shows "no Titan Up"; offline players and group members outside the guild (the guild addon channel can't reach them) are marked as such. Late answers still fill in. A summary line counts who has it, who's behind, and who's still pending; "Check again" re-asks. Solo, it asks you to join a group first.
  - Speed: groupmates now answer the moment they're asked (before, every guildmate waited a random 0-4 seconds and the results only showed after 8). Checks from someone outside your group (older versions still ask the whole guild) are answered after the old random wait, so their guild-wide checks keep working. The wire format is unchanged (`Q^version` / `V^version`); older versions in your group answer within 4 seconds, inside the 5-second window.
  - Each player's Titan Up reports its own installed version (no addon can see another player's addon folder).

## Changes in 0.27.0

- **Loot roll window (new, Loot settings, off by default).** When group-loot rolls start, one window ("LOOT ROLLS", drag to move, position saved) lists every item instead of Blizzard's separate pop-ups. Each item has Need / Greed / Transmog / Pass (sent with `RollOnLoot`, exactly like Blizzard's buttons; unavailable choices are greyed out with the reason), a time-left bar, tags (BIS, Sidegrade, Completes 2pc, Completes 4pc; any combination) and a note (40 characters). Clicking an item shows, for that drop: every raider's tags, note and roll as they come in (Titan Up users' picks, plus the game's live loot-history rolls for everyone), then the winner, and a hint when someone tagged it BIS but the winner didn't ("a trade could help, 2 hours to trade"). Rolls stay listed for 2 hours; a new boss's loot starts a fresh list.
  - Blizzard's pop-ups are hidden only while this window is open. Closing it (X or Esc) or turning the setting off hands every roll you haven't made back to a Blizzard pop-up, so a roll can't be missed; `/tu rolls` reopens the window (and takes them back).
  - Shared on a new prefix `TitanUpLR` (guildmates in your group): `P^itemID^rollID^tags^roll^note`, sent a second after your last change. Older versions ignore it. Picks that arrive before your client sees the roll are kept for 2 minutes.
  - "Preview the roll window" (Loot settings) opens it with sample items and raiders; nothing is rolled or sent, and the sample rolls finish after 20 seconds.
- **Death Roll: no spoilers while a roll spins.** The action button shows "Rolling..." (disabled), the new roll-history line is held back, and the player cards don't show WINNER / ROLLED A 1 until the animation lands.

## Changes in 0.26.0

- **Code cleanup (about 1,550 lines of code removed, ~9.6%; nothing meant to look or work differently).** Every window is built by one shared helper (`UI.Window` / `Nav:Window`, plus `ns.View` for the show/hide plumbing and `RegisterModule{ view = V }`); shared edit boxes, list rows, tooltips, drag-to-move with saved position (`UI.Draggable`: Combat Timer, Death Alerts, Battle Rez), dropdown carets and class-coloured names; one-line text labels (`UI.Text(parent, font, color, text, point...)`). Addon messages go through `ns.Listen` (register + readable + not yourself + guild / group check), `ns.SendFields` and `ns.SayGroup`; Loot and the Death Roll ledger share one trade watcher (`ns.WatchTrades`). All module defaults live in one table in Core.lua. Dead code removed (unused functions, fields and counters, and old saved-data migrations from 0.9-0.16). TitanBoard: shared drawing geometry, row builders and slide-list refresh. Wire formats are unchanged except the Pull Report record's unused last field (older versions read it as before).
- **Removed testing-only commands:** `/tb sim` (Board/Sim.lua) and `/tb sim lockdown`, `/tb loop`, `/tu deaths test / fake / clear / check`, `/tu keys art`, `/tu split debug`.
- **Death Roll spectator list fixed:** it was created but never given a position (the window's own show handler replaced the hook that placed it), so it never appeared. It now opens flush against the right edge of the game window (left edge if there's no room on screen), top edges lined up, and sizes itself to its names.
- **Death Roll ledger:** records are queued every 0.6s (was 0.25s, faster than the guild channel's ~2 a second), so sharing a long history no longer holds up a live game's messages on the same channel.
- **One health-potion list:** the Pull Report uses Raid Check's list (and its bag scan), so a new tier is one edit.
- **Half-received messages expire:** Macro Share and Pull Report drop message parts that never completed after 60 seconds.

## Changes in 0.25.3

- Pull Report: a pull shorter than 20 seconds that isn't a kill (a reset or a bad pull) isn't counted anywhere: it's dropped from tonight's pulls and the Raid Scorecard, and it gives its pull number back. It's only tallied: "N short pulls not counted" shows in the Pull Report (tonight) and the Raid Scorecard (per week and boss). Quick kills still count; debug test pulls are always kept.
- Death Roll: the "Announce in chat" checkbox shows its check again (the mark was drawn underneath the box), and announcements post in any group, not only when everyone is in the guild.
- Death Roll: the "< Lobby" button was placed off the window (it was anchored to a settings cog Death Roll no longer has), so Standings and games had no way back without /reload. It now sits beside the X.

## Changes in 0.25.2

- `/tu mem` shows a breakdown: the total (after a cleanup pass), saved data per area largest first (TitanBoard plans, loot history, raid history, Death Roll ledger, Pull Report and so on), the windows opened this session (they stay built until /reload), and the rest (code and everything else), so the parts add up to the total.
- Pull Report pop-ups are off by default: "Opens after a raid pull" starts at Never; "My death summary" stays off. One time only, a saved "When I'm raid leader" (the old default) becomes Never; anything you pick afterwards is kept, and "Always" is left alone.

## Changes in 0.25.1

- Macro Share: drag a macro from your macro book or an action bar onto the "Share a macro" side (the drop area lights up while you hold one) to fill in its name, text and icon; then pick who gets it and Send. Shared macros keep their real icon (any game icon), which recipients' copies use too.

## Changes in 0.25.0

- **Macro Share** (new, Raid Tools): in a raid, the raid leader or an assistant writes a macro (name, icon, text with a 255-character counter) and sends it to the whole raid, a role, a class or one person. Recipients get a toast; the macro is listed in Macro Share with who sent it and its full text, and dragging its icon onto a bar creates it as a character macro (or updates one with the same name) and places it in one go. Only works in a raid, only from the leader / assistants (re-checked by every recipient); can't be made in combat (it says "after combat"); full macro slots are reported. The received list lasts until you log out (X removes one).
- Fix: messages from group members are now matched to the group even when they arrive without "-Realm" (affects every group-only feature).

## Changes in 0.24.5

- Patch 12.1.5: the Loot tracker reads item quality through C_Item.GetItemInfo (12.1.5 removed the old GetItemInfo; the link colour is still the last fallback). Keystone Roulette's teleport cooldown sweeps now sit on the plain icon frame instead of the protected spell button (12.1.5 blocks addons from setting cooldowns on protected cooldown frames).

## Changes in 0.24.4

- Raid Scorecard: a week with no pulls shows a short bold "No data for this week" in the bottom-right corner (or "...for that week", "...for this boss this week", "No data yet") instead of a long message that repeated the footer. The stat column headers sit on two lines, centred over their columns, so they no longer crowd each other or run off the edge.

## Changes in 0.24.3

- Settings opens docked beside the window you opened it from (its left, tops lined up; its right if there's no room; centred if no Titan Up window is open). It docks again each time it opens and can be dragged while open.
- What's new shows on the Titan Up page in Settings, under the buttons - every version, newest first. After an update, the pop-up lists every version since you last played.
- Pop-ups (What's new, guild versions, the update reminder) size themselves to their text, so nothing runs under the OK button; very long ones scroll.

## Changes in 0.24.2

- Settings: a change made anywhere now shows everywhere at once - flip a tweak in the UI Tweaks window and an open Settings page updates immediately (it already worked the other way).
- Settings pages follow the tools' order (Titan Up, then Loot, Raid Check, Pull Report, then each UI Tweak).
- Keystone Roulette and Death Roll no longer have Settings pages or cogs - their choices are per game, in their own windows. Death Roll: rolls are always held back from chat until they land (no longer optional), and "Announce in chat" is a checkbox on the lobby under Create challenge.
- Tweak pages show their description once; the UI Tweaks intro line no longer runs into the cog.

## Changes in 0.24.1

- **Settings is now pages**: a list of modules on the left (Titan Up, the raid tools, each UI Tweak, Keystone Roulette, Death Roll), each module's options on its own page; tall pages have a scroll bar (mouse wheel or drag). Every UI Tweak's full settings now live here (Death Alerts' sounds and banner, Battle rez size and anchor, Stack splitter presets, ...).
- **Cogs everywhere**: the cog on each module (Loot, Raid Check, Death Roll, Pull Report, UI Tweaks, Keystone Roulette, and one beside each tweak) opens Settings straight on that module's page. The small option panels are gone.
- **UI Tweaks** is now just the on/off list, with a cog beside each tweak for its settings. The Combat Timer keeps its own window as before.

## Changes in 0.24.0

- **Settings** - every module's options on one page, a section per module (cog on the hub, `/tu settings`, or right-click Titan Up in Blizzard's addon menu). The cogs on each module still work and show the same settings.
- **Version check** (in Settings, or `/tu versions`): lists everyone's Titan Up version and who's behind; anyone running an older version gets a one-time "please update" pop-up. (Since 0.28.0 this is "Check raid versions": it lists just your party or raid and fills in live.)
- **What's new** pop-up once after an update (`/tu new` to see it again).
- **Blizzard's addon menu** (by the minimap): left-click the hub, right-click Settings. **Key bindings** for the hub, TitanBoard and the Pull Report (Options > Keybindings > AddOns).
- **Raid Scorecard**: "Died w/ potion" and "Died w/ healthstone" columns (count, %, click-through), and a **boss filter** (also applies to the CSV export).
- **Pull Report**: a **suggested wipe call** - when half the raid dies within a few seconds, the first death of that cascade is suggested; the raid leader confirms with one click.
- **Colour-blind friendly**: lit D / P / H squares carry a check mark (a "waiting" mark for a minor-only defensive), and Kill / Wipe tags carry a symbol.
- Behind the scenes: addon messages go through a small queue per feature that waits its turn and retries anything WoW throttles (nothing lost on busy nights); Death Roll games older than 3 months that are settled are folded into everyone's totals (standings unchanged, unpaid games kept); Wowdle standings drop players who haven't played in 30 days; shared helpers for reading values Midnight may hide; the TitanBoard code is split into two files.

## Changes in 0.23.0

- **Raid Scorecard** (new, Raid Tools): over a raid week (Tuesday reset) or all kept weeks - per player: **first to die**, **in the first 3 dead**, and **died with a defensive available**, as counts and percentages of the pulls they were in. Click any number for the pulls it happened on, then a pull for its full death order with times and what killed them. Heroic & Mythic only; close calls and deaths after the wipe call don't count. Keeps 4 weeks (Clear a week or all). **Sync from raid leader** gets the leader's complete copy of the week (out of combat, merged without duplicates). **Export CSV**: one row per death for Google Sheets / Excel.
- Pull Report: the raid leader can mark **"Wipe called here"** on a death - later deaths show as "after wipe" and don't count against anyone; the mark is shared with the raid.
- Pull Report: **Earth Elemental** counts as a Shaman defensive. New **"Other cooldowns ready"** line (every 1-5 minute spell in your spellbook that isn't a defensive, like Analysis Mode tracks) - shown, but doesn't light the D square; those spells also get "used at / ready since" history.
- Pull Report: a fake death no longer shows an old death's hits, and a real death never reuses a previous recap. D / P / H letters sit above the squares; the reminder is at the bottom of the deaths column.
- My death summary: the health strip now uses Midnight's health-percentage API and draws even when the game hides the number.

## Changes in 0.22.2

- Pull Report test mode (for testing only - not listed in /tu help): `/tu deaths test` starts a test pull anywhere that acts like a raid boss fight (run it again to end it, counted as a wipe); `/tu deaths fake` records a death snapshot without dying; `/tu deaths clear` removes test pulls. Test pulls are marked TEST, always open the report when they end, and are never sent to the guild. Note: outside real boss fights the game doesn't hide cooldowns or health, so this tests the flow and display, not the hidden-value handling.

## Changes in 0.22.1

- Pull Report: "ready" now uses the cooldown's **on-cooldown / global-cooldown flags**, which Midnight still shares mid-fight (the start time and duration are hidden - which is why Astral Shift showed as not ready). Health potions and healthstones are checked through their spells' cooldowns (Demonic Healthstone when talented). If the game hides even the flags, the defensive is listed as "couldn't tell" instead of silently "not ready".
- Pull Report: each death now has a **COOLDOWNS** section - when each of your defensives was used and when it came back ("Astral Shift: ready since 1:10 - unused", "Ice Cold: on cooldown (used at 0:52)", "active when they died"); also in your own death summary. The D / P / H reminder moved to the bottom of the window.
- Release protection: no longer covers the **Accept** button when a battle rez is offered (the game reuses the same pop-up) - the cover only ever sits on the Release Spirit dialog.
- Death alerts: the banner has no background - just the role icon and outlined text, each line as wide as its content, centred.

## Changes in 0.22.0

- **Battle rez tracker** (UI Tweaks, off until you turn it on): the Rebirth icon with the group's battle-rez charges, shown while you're in combat in a Mythic+ key or a raid boss fight. At zero it greys out, with a cooldown sweep and a countdown to the next charge. Its settings page has the size (small / medium / large), an anchor to drag it into place, and Reset position. It only updates while it's showing.

## Changes in 0.21.0

- **Wheel of Fortune - two ways to play.** **Play together** (the default): everyone plays, including whoever starts it; random built-in puzzles (pick the theme and 1-5 rounds); nobody sees the answer, and rounds move on by themselves. **Host a game**: the host writes custom puzzles and runs it - now with an optional **Prize** (a number shows as gold, e.g. 10000 -> 10,000g; anything else shows as written) on every player's board and in the winner line.
- **Wheel of Fortune - 25-second turn timer** in both modes: a countdown beside the board; if a player doesn't act in time, the turn passes ("Brakk ran out of time").
- **Pull Report - active defensives:** each death also notes which defensives were running at the moment of death (shown in blue), separately from what was ready but unused.
- **Pull Report - my death summary** (off by default; turn it on with the cog): when you die in a raid, a small box shows what killed you, every hit from the last 5 seconds, a 5-second health strip, defensives active / ready, and potions / healthstones. If the raid has a battle rez ready, it waits and shows once when the pull ends.

## Changes in 0.20.0

- **Pull Report** (Raid Tools, raids only): after each raid pull, who died and when - and whether they had a **defensive**, a **health potion** or a **healthstone** ready. Each player's Titan Up records only its own player (the defensive list is the guild's Class Info sheet cross-checked against Open Raid Library's Midnight data and Wowhead; talent replacements like Ice Block / Ice Cold are resolved, tanks skipped, missing spells skipped) plus their last hits from the death recap, and sends it over the guild channel after the fight, out of combat. Cheat-death saves show as orange "close calls". Raiders without Titan Up show as "no data".
  - Pull list -> click a pull for its deaths -> hover a death for a summary, click it for the details. D / P / H lights: green = ready and unused (yellow D = only a minor defensive ready).
  - Pops up for the raid leader after each pull (cog: always / when raid leader / never). Tonight's pulls are kept until the daily reset, with a **Scorecard** and **Copy for Discord**.
  - `/tu deaths check` lists your character's defensives (with spell IDs and cooldowns), what's skipped, and your potions / healthstones.
- Fix: in TitanBoard, clicking an expanded instance in the encounter list now collapses it again.

## Changes in 0.19.8

- Fix (for real this time): opening Keystone Roulette no longer raises "Cannot anchor protected frames to regions". WoW checks the whole attachment chain, and the frame the teleport buttons attached to was itself attached to the icon texture. The icon's frame is now placed on the row directly, and the icon texture attaches to it instead.

## Changes in 0.19.7

- Fix: opening Keystone Roulette raised "Cannot anchor protected frames to regions". The click-to-teleport buttons were attached to the dungeon icon texture, which the game doesn't allow for spell buttons; they now attach to a frame over the icon.

## Changes in 0.19.6

- Stack splitter: fixed the real cause of slow / scattered guild bank splits. The game fires its "guild bank changed" event instantly, in the middle of a split or drop; the splitter reacted to it by starting the next move before the current one was even recorded, so one click sent a burst of splits to several slots. Each step now finishes before another can start, and the pending move is recorded before asking the game - one split per move, filling the slots in order.
- Stack splitter: the status message wraps to fit inside the window (two lines at most), and the messages are shorter.

## Changes in 0.19.5

- Stack splitter, guild bank: a short settle pause (0.4s) after each move, because the guild bank can show the stack as unlocked a moment before it will take the next split. A split the server ignores is detected (the stack never locks) and safely asked again, and the pause grows a little each time that happens (up to 1.5s), so it settles into the pace your guild bank accepts.
- `/tu split debug` prints each move's timing (when the split was asked, when the stack locked, when it landed, the pause before the next) and a summary at the end. Run it again to turn it off.

## Changes in 0.19.4

- Stack splitter, guild bank: now works the way the game expects - split, then drop straight into the next slot, then wait for the source stack to drop. It no longer checks the cursor right after a guild bank split (the server fills it a moment later, which looked like a failure and caused a second split request), never re-uses a slot it already chose (so nothing is dropped onto an existing stack), counts a move as done once the source has dropped by at least the amount, and on a timeout waits once more instead of asking again. Fixes the slow splits and stacks landing in odd slots.

## Changes in 0.19.3

- Stack splitter is fast again: a move now counts as done as soon as the source stack drops by the amount moved (checked every frame while splitting), instead of also waiting for the new slot to update - which in the guild bank happens late, so each split was waiting out a timeout. The fixed pause and per-move guild bank refresh are gone; a split the server wasn't ready for is simply retried a moment later.
- New stacks fill in neatly: starting right after the original slot and following the game's slot order (in the guild bank, down each column then the next), wrapping around only if needed.

## Changes in 0.19.2

- Stack splitter, guild bank: splits no longer stop after the first move. The guild bank is slower than your bags and ignores a split asked for too soon after the last move, so guild bank moves are now paced (about one per second), each split is checked to have really picked the items up (retrying if not), the tab is refreshed after each move, and a move that times out is re-checked and retried before giving up. A stop part-way now says the guild bank is responding slowly (permissions are only blamed if the very first move fails), and a **Continue** button finishes the rest.

## Changes in 0.19.1

- Performance pass: about 12% less memory at login. TitanBoard import/export now uses the game's built-in compression instead of the bundled LibDeflate library (200 KB of Lua no longer loaded every session); export strings are unchanged, so strings shared by earlier versions still import and new ones work with older versions. Idle cost was already zero (nothing updates or ticks while you're not using a feature) and stays that way.
- Cleanup: removed a stray build file and an unused function; folded three small files into their natural homes (room images into Board/Content.lua, the board invite into Board/Presence.lua, the hub into Nav.lua).

## Changes in 0.19.0

- **Stack splitter** (UI Tweaks, off until you turn it on): Shift-click a stack in your bags, bank, Warband bank or guild bank for a Titan Up dialog instead of the game's little box. **Take** N onto your cursor, split the whole stack into **stacks of N**, or into **K equal stacks**, or **Combine** that item's partial stacks. Type the amount, scroll, use -/+ or presets (with "Half"). A preview shows the result and whether there are enough free slots (it does as many as fit); a progress bar and Stop show while it works. New stacks stay in the same storage (bags + reagent bag, the bank, one Warband tab, one guild bank tab). Settings: which tab it opens on, remember the last amount, your presets. At vendors the game's own box is used.
- **Keystone Roulette:** click a key's dungeon icon to teleport there (greyed out if you haven't unlocked it; shows the cooldown). Set up out of combat, as the game requires.

## Changes in 0.18.3

- Keystone Roulette popup: the dungeon art is now cropped to the measured scene, so it fills the popup edge to edge, centered, with no frame or padding showing.

## Changes in 0.18.2

- Keystone Roulette: the level range can be typed (`[-] [12] [+]`; blank = any, 2-30, a minimum above the maximum swaps). Popup art uses a better crop of the dungeon picture, and `/tu keys art` shows the whole picture with a labeled 10% grid to fine-tune it.
- Tab: the "<- NAME" title is centered in the space between the two sides (the Tools dropdown is narrower), and long names drop to a smaller font - and are shortened as a last resort - so they never run into the dropdown or icons.

## Changes in 0.18.1

- Keystone Roulette popup: the dungeon art now fills the popup edge to edge (the picture's painted frame is cropped off), with a darker band at the bottom so the Teleport button stays readable.
- The faded Titan Up logo behind each window now always fits inside it (it was spilling past the bottom of short windows like the UI Tweaks list) and re-fits when a window changes size.

## Changes in 0.18.0

- **Death alerts** (UI Tweaks, off until you turn it on): when someone in your group dies, a banner slides in with their role icon, class-colored name and the fight time from the Combat Timer; up to three stack. Tanks, healers and you get a bigger line and your own sounds. Several deaths in a few seconds collapse into one "Wipe likely - 6 dead" banner and one sound. Choose where it runs (raids & dungeons / raids / everywhere), tanks & healers only in raids, size, duration, chat line and sound channel. Sounds: WoW's built-in alerts plus every LibSharedMedia sound (from BigWigs, DBM, sound packs...), with a scrollable picker and preview. Shows your last pull's deaths. Open it from UI Tweaks -> Death alerts -> Settings.
- **Keystone Roulette** (UI Tweaks section, `/tu keys`): a spinning wheel of your group's keys. Keys come from you, Titan Up guildmates, and BigWigs / Details for everyone else (read locally). Level range, leave dungeons out, equal chances or favor higher keys. **Vote** mode: Titan Up users click Vote, anyone can type the number or short name in party chat; ties are settled by a spin. The winner is posted to party chat, and Titan Up users get a popup with a **Teleport** button for that dungeon (found in your spellbook; set up after combat if needed). Keeps your last 10 picks.
- **Raid Check:** Concentrated Silvermoon Health Potion counts as a health potion; Liquid Luster counts as a combat potion.
- Bundles LibSharedMedia-3.0 (LGPL 2.1) and CallbackHandler-1.0 (BSD) for the sound list.

## Changes in 0.17.0

- **Wowdle** (Games): a daily guild word game - the same 5-letter word for everyone each day (new word at the US daily reset), mixing WoW terms with everyday words. Six guesses, real words only, on-screen keyboard (click the board to type with your keyboard; Esc stops). **Standings** are shared guild-wide - today's board plus wins, streaks and average guesses; only guess counts are shared, never guesses. The guess dictionary (public-domain ENABLE list) is checked in place, with no word table built in memory.
- **UI Tweaks** (new section, with the tools): **Release protection** - in raid instances, Release Spirit only works after holding Alt for 3 seconds (off by default; turn it on in UI Tweaks).
- **Combat Timer:** a history of the last 10 fights in its settings window, with a green Kill / grey Wipe tag on boss pulls.
- **Death Roll:** the result announcement waits until the final roll has landed on screen, and Rematch (and the other end buttons) appear only after that reveal.
- **Tab:** a side with five or more modules becomes one dropdown (the left side is now "Tools", listing Raid Tools and UI Tweaks under headings).

## Changes in 0.16.6

- Slimmer tab (32px, one row): Raid Tools icons on the left, "<- NAME" in the center, Games icons on the right - the RAID TOOLS / GAMES labels and the small TITAN UP line are gone (hover an icon for its name and section; the hub still shows the full names and headings).
- If a side ever has more than five modules, it automatically turns into a dropdown named after its section ("Games v") listing its modules, so the tab never gets crowded.

## Changes in 0.16.5

- Fix: the hub window's background was only 32px tall (its height calculation was broken in 0.16.4), so the tiles floated over the game and the version overlapped the RAID TOOLS heading.
- The tab now matches the narrowest window (the hub, 420px), so it never overhangs any window.

## Changes in 0.16.4

- **The tab never moves:** every window is now positioned from its top-center - where the tab sits - so switching modules (bar icons, back arrow, hub tiles) and Wheel of Fortune's setup/game screens keep the tab exactly in place and the window extends down from it. The tab is the same 620px on every window (narrow windows get a slightly overhanging tab, which still counts for keeping the window on screen).
- **Hub:** the tab's center is just "TITAN UP" (no emblem or grey line); the version moved to the bottom-center of the hub.

## Changes in 0.16.3

- Settings cogs: Loot tracker, Raid Check and Death Roll each have a cog beside the X (same size, thin separator between) that opens a small options panel. Loot's panel holds **Tracking: Epic+ / Rare+** (the search box got wider); Raid Check's holds **Check before /pull**.
- Raid Check: **Check now** is centered at the bottom; the "runs in Heroic and Mythic raids" note is small grey help text in the bottom-left corner (it explains the guild requirement instead when you're not in a guild).

## Changes in 0.16.2

- **No more title row.** Each window's content moves up; the X sits in the window's top-right corner on its first row. The tab's center shows just the back arrow and the module name (the highlighted icon already shows where you are; the hub keeps its emblem).
- **TitanBoard:** the options row now holds everything - the plan name at its left end, then colors and size; Undo, Clear, LOCAL, Viewer mode, Mini and the X at its right end (the plan name shrinks to fit when the row is busy). Live Viewers starts below that row. The slide arrows moved to the bottom-center of the map. Mini view and viewer mode keep their compact title row.
- **Combat Timer:** times boss encounters inside raids and any combat everywhere else - automatically (the "Time" option is gone). New options: a chat summary after each fight ("Combat lasted 3:42 (Sszorak)", on by default) and "Only in dungeons & raids". The switch reads **Timer: On / Off** in green/red, and the preview shows dimmed with "Timer is OFF" when it's off. `/tu timer test` runs it for 10 seconds; `/tu timer debug` prints what it does with each combat/boss event. Settings window is wider so its tab fits.
- **Death Roll:** the wager label no longer runs into "Opponent" ("also the first roll" is in its tooltip).
- **Sturdier startup:** each module starts on its own, so one failing can't stop the others (it's named in chat), and an event the game no longer has is skipped instead of breaking startup.

## Changes in 0.16.1

- **New navigation tab:** a trapezoid tab sits on top of every window - Raid Tools icons on the left, "TITAN UP" with the back arrow and the module's name in the center, Games icons on the right. Each window's own title row is back to a slim 32px with just its controls and the X. The tab fits narrow windows and hides in TitanBoard's mini view and viewer mode.
- **Wheel of Fortune setup screen** is smaller (660px wide) and grows as you add rounds and as open games appear. The game screen keeps its full size; switching between them keeps the window's top-right corner in place.

## Changes in 0.16.0

- **Titan Up works for any guild.** The members-only check is gone. All addon data still travels only over your **own guild's** private addon channel, so each guild's data stays inside that guild: other guilds (and pugs in your raid) never receive it and can't send you any. Group features only listen to guildmates in your group.
- **No guild:** everything local still works (Combat Timer, Loot tracker, the board on your own, practice/solo games); nothing is sent or received. Playing with others (Death Roll, Wheel of Fortune, Raid Check) explains that it needs a guild. A one-time note appears after a minute if you're not in a guild.
- Leaving a guild no longer switches Titan Up off - it keeps working and just stops syncing; joining a guild starts syncing with it.
- Chat announcements (Wheel invites, the board's join link) post only when everyone in the group is in your guild. Death Roll announcements (when "Announce in chat" is ticked) post in any group.

## Changes in 0.15.4

- TitanBoard pane arrows moved again: the left pane's arrow sits at the top-right of the Encounters header (where Locate was) and the right pane's at the top-right of Live Viewers - no more overlap with Send full plan. When a pane is collapsed its arrow stays at the top: above the tool column (left) or at the end of the options bar (right). **Locate** moved to the bottom-right of Encounters, just above the separator before Plan.
- Every window: the **X** is in the far top-right corner, and a thin separator line runs between the Raid Tools and Games icon rows.

## Changes in 0.15.3

- Every window: a taller title bar (48px) with a **back arrow** by the title (to the Titan Up hub) and the module icons in **two rows** - Raid Tools on top, Games below. The home icon is gone (the back arrow replaces it). TitanBoard keeps a compact title in mini view and viewer mode.
- TitanBoard: the pane collapse arrows moved to the bottom of each pane's inner edge, pointing toward the edge they collapse to; when collapsed they sit at the window edge pointing back in.
- Death Roll: the button(s) under the main button are centered (Cancel game on its own is centered).
- Wheel of Fortune setup: smaller help text; "Random from" is a dropdown next to **Fill all** on the heading line; each round has a **dice** icon for a random puzzle and an **X** that removes the round; **+ Add round** (up to 5); **Open game** centered with **Play solo** under it.
- Wheel of Fortune solo games: the bot host starts the next round by itself a few seconds after each solve, through to the final winner.

## Changes in 0.15.2

- Death Roll ledger: a debt **Check** that reaches the winner mid-combat is answered as soon as their fight ends (nothing is sent during combat). If there's no answer within a few seconds you're told they may be offline or in combat, and your addon keeps listening for 10 minutes - when the answer arrives you're told whether the payment was confirmed.

## Changes in 0.15.1

- Raid Check: the "Learn approved buffs" and "Reset" buttons are gone. Any current-tier flask (any quality or cauldron) and any food buff count. Old learned lists are cleared.
- Combat Timer settings: font is now a dropdown; size is **[-] [box v] [+]** - type any size (10-96), pick from a list in steps of 6, or nudge by 1. "Move timer" is now an anchor icon under the close button (click to unlock and drag, click again to lock). "Reset position" is a small button in the bottom-right corner.
- Combat Timer defaults: times **boss encounters** and keeps the last time on screen (**Always**); default size 30. Applied once to existing installs.

## Changes in 0.15.0

- **Hub redesign:** one window with inline sections - **Raid Tools** (TitanBoard, Loot, Combat Timer, Raid Check) and **Games** (Death Roll, Wheel of Fortune). No more separate Games page. The module bar shows every module, with a divider between Raid Tools and Games.
- **New: Combat Timer** (`/tu timer`). An on-screen timer for your combat or for boss encounters (pull to kill/wipe). Font, size, color, outline, tenths of a second, how long to keep the final time after combat; "Move timer" to drag it anywhere. Shows a live preview while its settings are open.
- **Raid Check:** combat potions warn below 5 (was 10) and now include Potion of Zealotry; new **Health potions** row (Silvermoon Health Potion, all qualities) warns below 5.
- **Death Roll ledger:** debts you owe now have a **Check** button that asks the winner's addon for its record - the winner stays the only source of truth. You're told whether they've confirmed payment, haven't yet, or didn't answer (offline). Not available mid-combat.

## Changes in 0.14.5

- Raid Check: combat potions now count - crafted potions carry their quality icon inside the item name, which broke the name match.
- Raid Check: the results window only opens for the raid leader (ready checks and /pull). Whoever types /pull still gets the pull alert. "Pull anyway" closes the alert and the results window, and both close by themselves when the boss is engaged.
- Death Roll ledger: a finished game and a confirmed payment are sent to the other player straight away, so the loser's debt clears within a second or two of the trade (it used to wait for a refresh, up to 10 minutes).
- Quiet mode is now "during combat" instead of "inside raid instances": between pulls the ledger works normally; while you're in combat or an encounter nothing is sent and incoming ledger records wait until the fight ends. TitanBoard's presence check-ins also pause during combat.

## Changes in 0.14.4

- Death Roll fix: rolls from players on a connected realm weren't recognized by the other player's addon (WoW prints the roll line without the realm, so it was matched against the wrong server) - the opponent's screen stayed on the roller's turn. Roll lines are now matched by character name when the realm is missing, and player links/color codes in the line are handled.
- Safety net: each player's addon also sends a short report of its own roll; if someone's client can't read that roll from chat within ~1.5s, it uses the report (only players can report their own roll, and it has to fit the rules).
- `/tu roll debug` lists roll lines that couldn't be read and any time the fallback was used.

## Changes in 0.14.3

- Death Roll: declining a challenge no longer cancels it. The challenged player can Decline (from the pop-up or the game window, or after joining at the Accept step); the challenger sees who declined and can **Open to anyone** - everyone else in the group then gets a pop-up - or cancel. The challenger can also open a reserved challenge early. Only the challenged player can join or decline a reserved challenge.
- The first roll is always the wager (the "First roll" box is gone).
- Lobby: "Announce in chat" and "Delay rolls in chat" moved into an options panel behind a settings cog in the title bar; Practice is a small button in the bottom-right corner; the rest of the lobby moved up.

## Changes in 0.14.2

- Death Roll: a spectator list on the side of the game window. Opening someone else's game tells the challenger you're watching (repeated every 30s while you watch); the challenger's addon keeps the list and shares it, dropping anyone who goes quiet for ~75s, leaves the group, or takes the seat. Practice games show no spectators.

## Changes in 0.14.1

- Death Roll: clicking the [Open death roll] chat link now also asks the challenger for the latest state (like the Watch button), so someone who reloaded or zoned mid-game catches up on missed rolls.

## Changes in 0.14.0

- Guild members only: Titan Up runs only for members of <Titan Up> on Medivh, and all addon data goes over the guild addon channel, so players outside the guild (pugs included) never receive it and can't send any. Group features only listen to guildmates in your group; the Death Roll ledger and loot trade updates are guild-wide. Public chat announcements only post when everyone in the group is in the guild. Everyone needs 0.14.0 or later.

## Changes in 0.13.0

- New top-level section: Raid Check (ready check + /pull readiness for Heroic/Mythic raids). Hub and module bar: TitanBoard, Raid Check, Loot, Games.

## Changes in 0.12.0

- New top-level section: Loot tracker (raid drops + rolls, Mythic+ loot, trade chains, equipped). Hub and module bar: TitanBoard, Loot, Games.

## Changes in 0.11.2

- Death Roll ledger quiet mode inside raid instances (see Ledger and standings).
- Per-player ledger summaries are cached instead of recomputed for every incoming summary; an open Death Roll window redraws at most twice a second while records stream in.

## Changes in 0.11.1 (performance)

- Windows are built the first time you open them instead of at login (TitanBoard, Death Roll, Wheel of Fortune, the hub and the Games launcher). At login Titan Up only creates the minimap button. Pop-ups and syncing still work with every window closed.
- Background timers only run while they have work: laser pointer sending, ledger sending and the board's status refresh used to tick constantly (about 26 callbacks a second while idle); now it's about one every three seconds.
- Roster changes and system messages return immediately when no game is running; the ledger shares with your group at most once a minute.
- Data kept in check: all of your own Death Roll games are kept, plus the newest 1,000 games between other players; finished Wheel of Fortune games are cleared after 30 minutes.
- New `/tu mem` command.

## Changes in 0.11.0

- The hub now has two sections: TitanBoard and Games. Games opens its own launcher with Death Roll and Wheel of Fortune; the module bar shows home, TitanBoard and Games.
- Modules can belong to a section (`group = "games"`); new games appear in the Games launcher automatically. `/tu games` opens it.

## Changes in 0.10.3

- Wheel of Fortune: 141 ready-made puzzles (85 WoW, 56 pop culture) across categories like Phrase, Place, Character, Movie Title, TV Show, What Are You Doing?, Before & After and Rhyme Time. New "Random from" theme picker and "Fill all"; Random never repeats a puzzle already in the game.

## Changes in 0.10.2

- Death Roll: Rematch after a practice game now starts another practice game (it used to try a real one). Practice games are never recorded in the ledger or history (now also enforced inside the ledger itself).

## Changes in 0.10.1

- Death Roll ledger hardening: confirmed games are locked against later edits, only exactly-matching copies confirm a game, standings count confirmed games only, and only the winner can confirm a payment.

## Changes in 0.10.0

- New module: Wheel of Fortune (see above).
- Death Roll ledger also syncs with online guildmates over the guild channel (refreshed every 10 minutes and after every game/payment), not just your group.
- `/tu <module> sim` starts any module's practice mode.

## Changes in 0.9.5

- Death Roll ledger: games recorded by both players with a shared id, completed trades automatically credited against debts (including partial payments), group-based syncing of everyone's games, and a Standings view with recent games. Old 0.9.x records carry over.

## Changes in 0.9.4

- Standard title bar for every window (hub, TitanBoard, Death Roll): name and icon top-left, module icons + close top-right. Module-specific buttons sit to the left of the module icons.
- Switching modules keeps the window's top-right corner in place, so the module icons stay put.
- The hub has the same title bar, with home highlighted.

## Changes in 0.9.3

- Module bar in every module's title bar: home (hub) plus one icon per module; switching opens the other module and closes the current one. Hidden in TitanBoard's mini view and viewer mode.
- `/tu <module>` opens any module (`/tu board`, `/tu deathroll`).
- Modules now register themselves; the hub tiles and module bars are built from that list.

## Adding a module (for developers)

Create the module's files, add them to `TitanUp.toc` (after `Nav.lua`, before `Hub.lua`), and register it once at the end of its UI file (add `group = "games"` for a game, so it lives in the Games launcher):

```lua
ns.RegisterModule({
    key = "mymodule", name = "My Module", icon = ns.MEDIA .. "MyIcon",
    desc = "One line for the hub tile.",
    show = function() MyWindow:Show() end,
    hide = function() MyWindow:Hide() end,
    isShown = function() return MyWindow:IsShown() end,
})
```

Give the window the standard title bar: `local header = ns.Nav:CreateHeader(MyWindow, "mymodule", { title = "MY MODULE", icon = ns.MEDIA .. "MyIcon" })`, and include `frame = function() return MyWindow end` in the registration so switching can line windows up. Put any module-specific title buttons to the left of `header.bar`. The hub tile, every other module's bar, and `/tu mymodule` pick it up automatically.

## Changes in 0.9.2

- Death Roll: the roll list scrolls with the mouse wheel when a game has more rolls than fit, with a scroll indicator and a "showing X-Y of Z" counter. If you're scrolled back when a new roll lands, the list stays where you are.

## Changes in 0.9.1

- Titan Up logo: emblem on the minimap button, hub, TitanBoard title bar and addon list; faint full logo behind the hub, the Death Roll window and blank boards.
- Death Roll: chat delay for roll lines, combat pause/resume, lost-roll handling, roll-list resync, /reload recovery (see Death Roll notes).

## Changes in 0.9.0

- TitanBoard is now part of Titan Up, with a hub window (`/tu`) and a minimap button (left-click: hub, right-click: board, drag to move, `/tu minimap` hides it).
- New module: Death Roll (see above).

# TitanBoard history

## Changes in 0.8.3

- Moving items with any tool is now Ctrl + drag (replaces Tab + drag, which the board couldn't detect reliably). The Tab key is no longer touched by the board at all.

## Changes in 0.8.2

- Fixed Tab+drag: the key handler relied on an old Blizzard helper function (`MouseIsOver`) that may no longer exist; it now uses the frame's own check.
- A "MOVE (Tab held)" badge appears in the board's top-left corner while Tab is held.
- Fixed: after pressing Tab or Ctrl+Z over the board, entering combat before pressing another key could leave the board swallowing your keypresses for the fight. Key capture is now released on key-up, when combat starts, and when the board closes.
- `/tb debug` now logs key presses and Tab+click results, for troubleshooting.

## Changes in 0.8.1

- Mini view: hold the right mouse button to pan (mouse wheel still zooms). Panning in mini view only moves your own view and never deletes anything.
- Hold Tab and drag an item to move it with any tool selected. Tab is only captured while the mouse is over the board, so Tab-targeting still works elsewhere.

## Changes in 0.8.0

- Import Raidstrats.gg plans: paste a `!raidstrats-addon-...` string into the Import box. Each Raidstrats scene becomes a slide (name and zoom kept). Player icons become stamps with names (class icons included), lines/arrows/circles/donuts/cones/rectangles/text carry over, movement paths become arrows along the route, frontal sweeps become pie slices, tethers become lines. Cosmetic effects (pulse, fade) are dropped. The boss is matched by name; if it isn't found, the plan goes on the board you have open.

## Changes in 0.7.1

- Room images converted to BLP (DXT1, WoW's own compressed texture format) with mipmaps: same 2048x1024 size, 44 MB -> 9.8 MB, slightly smoother when zoomed out.

## Changes in 0.7.0

- Laser pointer: raiders who can't draw just hold the left mouse button on the board to point; drawers use the Laser tool or hold Alt while dragging. Everyone sees a dot in the pointer's class color with their name and a short trail. Pointers use their own channel, send only the newest position (up to ~7 per second), and never delay drawing. Nothing is sent during encounter lockdown.
- The viewer list shows the whole raid roster, grouped by raid group, in a fixed order. People light up in place when they open the board ("tuned in" for a few seconds), and offline members are marked. The header shows watching / total.
- Fixed: hovering a soak zone, a resized stamp or a long text label only registered within 12 pixels of its center, so Ctrl+wheel resized your stroke size instead. They now register across their whole drawn area (also for right-click delete and Move).

## Changes in 0.6.0

- Collapsible side panels: the arrow buttons at either end of the title bar hide the left panel (encounters, plans, slides) or the right panel (viewers, sharing). While the left panel is hidden, slide arrows appear in the title bar. Remembered between sessions.
- Viewer mode: full screen, map only. Slide arrows stay in the title bar and drawers can still draw with the current tool. Esc or "Exit viewer mode" leaves it. Combat doesn't shrink it to the mini view.
- Hover any item and Ctrl+mouse wheel to resize it: stamps, text and soak zones change size (up to twice the old maximum); shapes and strokes scale around their center, pies around their tip. A burst of wheel clicks undoes in one step. Ctrl+wheel over empty board still sets the stroke size.
- Encounters and plans open fully zoomed out (the first slide's framing is reset to the whole room; other slides keep theirs).

## Changes in 0.5.0

- Custom room images for The Venomous Abyss: Sszorak, The Twin Fangs, The Coiled Altar, and Ula'tek (P1, P2 Left, P2 Right, P3).
- Per-slide backgrounds: when an encounter has custom images, the "Room" button above the map picks which one the current slide shows (or Blizzard's map). New slides start with the same room. Room choices sync to the raid and are saved and exported with the plan.
- `/tb ids all` lists every boss in the current instance with its encounter ID.

## Changes in 0.4.0

- Icon tool buttons (hover for names); the soak zone has its own Zones section.
- Saved plans: several named plans per encounter. Switch with the plan button, New / Save as / Delete below it. Plans save automatically as you draw.
- Slides replace the 4 fixed phases: up to 20 per plan, add / rename / copy / reorder / delete. Clicking a slide shows it to everyone - including the zoom and pan you set on it.
- Plans from earlier versions convert automatically (phases become slides "Phase 1..n"). Old export strings still import.
- Managing plans and slides is leader-only in a group; granted players can still draw and switch slides.

## Changes in 0.3.0

- Photoshop-style layout: tools and stamps in a vertical strip left of the map; the bar above the map holds only the active tool's settings (color, size, pie angle / donut hole) plus Undo and Clear. The map gets more height.
- Invite, Export and Import moved to a Share section at the bottom of the viewer panel, with Send full plan.
- Tank/healer/DPS stamps use Blizzard's role icons (fixes the cropped icons).
- World bosses ("Midnight") moved out of Raids into their own section.

## Changes in 0.2.0

- New Pie (cone / frontal) and Donut (ring) shapes: translucent fill in the selected color with an outline at the stroke size. Right-clicking anywhere inside the fill deletes them. Everyone in the group needs 0.2.0 to see them.

## Custom room images

See the comments at the top of `Rooms.lua`. Short version: put a .blp or .tga into `Media/Rooms/`, run `/tb ids` on that boss for its encounter ID, and add an entry to `Rooms.lua`. An encounter can have several images (one per phase); each slide picks one with the Room button.

## Known limits in v0.1

- Nothing is sent during an encounter (Blizzard lockdown). Changes queue and go out after the pull; the mini view keeps showing what was already received.
- Viewers follow the leader's board in a group and can't browse other bosses or slides meanwhile.
- If the leader doesn't have TitanBoard, nobody answers resync requests.
- The send rate defaults to a conservative 10-message burst refilling 1/second. Tune with `/tb rate` after a real raid test.
- The board doesn't auto-switch on pull; pick the boss before you pull.

Bundled libraries: LibStub (public domain), LibDeflate (zlib license, see `Libs/LibDeflate/LICENSE.txt`).
