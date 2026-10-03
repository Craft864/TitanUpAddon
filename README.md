# Titan Up v0.13.0

The Titan Up guild toolkit for World of Warcraft. Modules:

- **TitanBoard**: live raid strategy board (draw on boss rooms, slides, plans, laser pointer, Raidstrats import).
- **Raid Check**: raid buffs and personal readiness on every ready check and /pull (Heroic/Mythic raids).
- **Loot**: every raid drop and roll, Mythic+ loot, and who it was traded to until it's equipped.
- **Games**:
  - **Death Roll**: challenge a guildmate to a death roll with on-screen rolls, with a guild-wide ledger.
  - **Wheel of Fortune**: a host runs a game for three players.

`/tu mem` shows how much memory Titan Up is using. `/tu` opens the hub (or click the minimap button): **TitanBoard** and **Games**. Games opens a second page with every game. `/tu games` goes straight there. Every Titan Up window shares the same title bar: the module's name on the left, and in the top-right corner the **module icons** (Titan Up emblem = hub, TitanBoard, Games; the one you're in is highlighted - inside any game that's Games, which takes you back to the games list) right next to the close button. Switching modules opens the new window with its top-right corner exactly where the old one's was, so the icons never move under your mouse. `/tb` still opens TitanBoard directly, `/tu roll` opens Death Roll, `/tu help` lists everything.

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
- **Standings** (button in the lobby) shows everyone's wins, losses, net gold and unpaid amounts, plus a scrollable list of recent games. Hover a game for details.
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
- **Rules:** approved flask, Hearty feast food, weapon enchant, Vantus Rune, Fury of the Dead, 10+ combat potions, a healthstone (only if a warlock is in the raid), durability 20%+.
- **Approved flask/food:** eat the Hearty feast, take a cauldron flask and/or a high-quality flask, then click **Learn approved buffs** - only those exact buffs count from then on. Until you do, any current-tier flask and any food buff count.

## Loot tracker

`/tu loot` (or the hub / module bar).

- **Raid drops (group loot):** recorded automatically when a roll finishes, from WoW's own loot history - item, item level, boss, raid and difficulty, the winner with their roll (Need / Need off-spec / Transmog / Greed), and everyone else's rolls (hover a drop).
- **Mythic+ and dungeons (personal loot):** there are no rolls - the game assigns items - so it records who received what, including the end-of-run chest.
- **Trades:** when a tracked item changes hands in a trade, the hop is added to its history and shared with the group, so everyone's copy shows the same chain. Needs Titan Up on at least one side of the trade (trades between two people without it can't be seen).
- **Equipped:** when the current owner equips the item, tracking ends (it's soulbound for good). Needs Titan Up on the owner's side.
- Only the two people in a trade can report it, and only the owner can report equipping it.
- Left side: raid nights and runs by date; filters All / Raid / Mythic+; search by player, item or boss (finds anyone in an item's history). Tracks Epic+ by default (toggle Rare+). Keeps the newest 1,500 drops.
- Only people who were in the group record the drops (loot history isn't synced through the guild).

## Wheel of Fortune

`/tu wheel` (or the hub / module bar).

**Hosting:** enter 1-5 rounds (category + puzzle; puzzles must fit a 4 x 14 board, words aren't split - "Random" fills a round with a ready-made one and "Fill all" fills every round; "Random from" picks the theme - WoW, pop culture, or both - and puzzles never repeat within a game) and **Open game**. Players in your group get a pop-up to take one of the three seats. You see the answer in the host panel (only on your screen) and have **Start game**, **Next round**, **Skip turn** (for AFK players) and **End game**. The host doesn't play.

**Playing:** on your turn
- **SPIN** - the wheel spins for everyone. Dollar wedge: call a consonant; you earn the value for each one in the puzzle and keep your turn. BANKRUPT loses your round money; LOSE A TURN passes.
- **Buy a vowel** for $250 of your round money.
- **SOLVE** - type the whole answer (case and punctuation don't matter).
A letter that isn't there (or was already called), a vowel that isn't there, or a wrong solve passes the turn. Solving banks your round money (at least $1,000). Most money after the last round wins. No bonus round (yet).

The host's addon is the referee: it spins, checks letters and only ever sends the board with unrevealed letters hidden, so nobody can read the answer from addon traffic. `/tu wheel sim` (or **Practice solo**) plays a game against two bots with a fake host.

## TitanBoard quick reference

`/tb` opens the board, `/tb help` lists its commands, `/tb sim` runs a fake raid for testing.
Left: draw - Right-drag: pan - Right-click: delete - Wheel: zoom - Ctrl+drag: move an item - Ctrl+wheel: resize an item - Alt+drag: laser - Ctrl+Z: undo.

## Custom room images

See the comments at the top of `Rooms.lua`. Short version: put a .blp or .tga into `Media/Rooms/`, run `/tb ids` on that boss for its encounter ID, and add an entry to `Rooms.lua`. An encounter can have several images (one per phase); each slide picks one with the Room button.

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
