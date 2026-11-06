# Eternal Table v0.50.0

A raid and games toolkit for the Eternal Table guild. Runs on World of Warcraft (Midnight) and WoW Forever. Works with your guild, your group and your friends.

**Install:** get Eternal Table from WoWUp or CurseForge.

## What's in it

- **Raid Info**
  - **TitanBoard**: a live strategy board the raid can draw on together. `/etb`.
  - **Reports**: the Pull Report (who died each pull and what they had ready) and the weekly Raid Scorecard.
  - **Loot**: every raid drop, roll and trade, Mythic+ loot, an optional roll window, and a guild loot wishlist.
  - **Raid Check**: buffs and consumables on every ready check and typed /pull.
- **Tools**
  - **UI Tweaks**: Combat Timer, Release protection, Death alerts, Stack splitter, Battle rez tracker and Bonus roll protection.
  - **Keystone Roulette**: spin a wheel or vote on the group's keys, then teleport.
  - **Macro Workstation**: build macros step by step and share them with your group.
  - **Consumables**: your raid shopping list, checked against your bags.
- **Guild**
  - **Games**: Death Roll, Wheel of Fortune, Wowdle and Chess.
  - **Crafters**: who in the guild can craft what.

## Guild, group and friends

- Your guild gets everything, like always.
- Raid and party features (TitanBoard, Raid Check, Loot Rolls, Keystone Roulette, Wheel, Macro Share) work with anyone in your group who has Eternal Table, guild or not.
- Chess, Wowdle, Death Roll standings, Crafters and wishlists also reach your online friends running Eternal Table. Battle.net friends work on any realm; character friends only on your realm and connected realms. You only see your own friends. Turn it off in Settings > Friends.

## WoW Forever

- Same addon, same download. Pick the Forever version in WoWUp or CurseForge.
- Retail-only parts are hidden on Forever: Keystone Roulette, Bonus roll protection, the Battle rez tracker, Mythic+ options, Vantus Rune and weekly buff checks, the Raidstrats import, and retail's What's new history.
- Forever gets its own lists: classic raid buffs and consumables in Raid Check and Consumables, classic defensives in the Pull Report, and classic spells and interrupts in Macro Workstation.
- Crafters reads Forever's professions (skill 1-300, First Aid included, no quality ranks).
- Raid Check, the Pull Report archive and the Raid Scorecard run in every Forever raid (there's one difficulty).

## Getting around

- `/et` (or the minimap button) opens Eternal Table on **Home**. Pick a module from the rail on the left; Settings is at the bottom.
- Modules with several pages show tabs across the top.
- The search box in the title bar finds any setting.
- `/et help` lists every command. The old `/tu` and `/tb` still work.

## Death Roll

- `/et roll`, set a wager, and challenge someone in your group or open it to anyone.
- Each roll is a real `/roll` from 1 to the last result. Whoever rolls a 1 pays the wager.
- Payment is a normal trade, detected automatically. The winner can also mark a debt paid.
- **Standings** show everyone's wins, losses and unpaid gold. Only games both players agree on count, so nobody can fake a result.
- Both players must be in the same group. **Practice solo** plays against a bot.

## Raid Check

`/et raidcheck`. Heroic and Mythic raids only (every raid on Forever).

- On every ready check, and on a typed `/pull`, it checks everyone's buffs, flask, food, weapon enchant, Vantus Rune, potions, healthstone and durability.
- If someone's missing something, the leader gets a list with **Pull anyway** or **Cancel**.
- Only a typed `/pull` is checked. Boss mod pull buttons can't be stopped.

## Loot

`/et loot`.

- Records raid drops with everyone's rolls, bonus rolls, Mythic+ loot, and trades until the item is equipped.
- Search by player, item or boss.
- **Roll window** (Loot settings, off by default): every roll in one window, with BIS / Sidegrade / set tags and notes the raid can see. Closing it hands your rolls back to Blizzard's pop-ups. `/et rolls` reopens it.
- **Dungeon roll bars** (Loot settings, off by default): in a party, small bars replace Blizzard's roll pop-ups, with a breakdown beside them of who's waiting, who picked Need or Greed, and who passed. Drag the breakdown to move them.
- **Wishlist** tab: browse any raid or dungeon and mark items BIS, Sidegrade or Want. Click a drop to see who in the guild wants it.

## Wheel of Fortune

`/et wheel`.

- **Play together** with random puzzles, or **Host a game** with your own.
- Spin, call consonants, buy vowels for $250, or solve. Most money after the last round wins.
- Optional **Bonus round** for the leader at the end.
- **Practice solo** plays against bots.

## Chess

`/et chess`.

- Challenge a guildmate, a friend or anyone in your group. Guildmates don't need to be online: other guildmates running Eternal Table pass your moves along.
- Playing someone you were only grouped with? When the group ends you get an **Add friend** button so you can keep playing.
- Optional timers: days per move, or a live clock that only runs while you're both online.
- Full chess rules. Games are saved until they end, and follow you to your other characters.
- The **Watch** tab lets you follow the guild's other games, with games in progress at the top and finished ones below.
- The **History** tab shows your win/loss record and your last 200 games. Click one to replay it.

## TitanBoard

`/etb` opens the board, `/etb help` lists its commands.

- Left: draw. Right-drag: pan. Right-click: delete. Wheel: zoom.
- Ctrl+drag: move an item. Ctrl+wheel: resize it. Alt+drag: laser. Ctrl+Z: undo.
- Only the raid leader moves the view and switches bosses for everyone. Assistants can still draw.
- Paste a Raidstrats string into Import to bring in a plan.

## Crafters

- Open a profession window once and the guild can see what you can make.
- Search for a recipe or item to see who can craft it, the best quality they can make, and whisper them.
- Anyone can add a crafter from outside the guild for items nobody in the guild makes.

## Characters

- Your characters in the guild are linked (Settings > Eternal Table). Standings show one row per player under their main, and Death Roll debts can be paid from any of your characters.
- Eternal Table asks which character is your main. You can change it in Settings.

## Planned

- Fury of the Dead is still matched by its English name in Raid Check.

## Changes in 0.50.0

- **Dungeon roll bars** (Loot settings): compact roll bars for parties, with a who's-rolling breakdown on the side. On Forever it reads the game's roll lines, so everyone shows, addon or not.
- WoW Forever: retail-only parts hidden, and Forever's own buffs, consumables, defensives and spells.
- WoW Forever: Crafters reads the 1-300 professions, including First Aid.
- WoW Forever: Raid Check, the Pull Report archive and the Raid Scorecard now run in raids. Fixed Raid Check marking everyone missing Skyfury when a Shaman was in the raid.

## Changes in 0.49.0

- Titan Up is now **Eternal Table**.
- Works on WoW Forever as well as Midnight. Keystone Roulette and Bonus roll protection are hidden on Forever.
- Commands are now `/et` and `/etb` for the board. `/tu` and `/tb` still work.
- New placeholder logo.

## Changes in 0.48.0

- Titan Up works without a guild: raid and party features work with everyone in your group, and Chess, Wowdle, Death Roll standings, Crafters and wishlists reach your friends who run Titan Up.
- In a guild, everything still works with your guild, plus pugs in your group and friends outside it.
- Chess: challenge anyone in your group. If the group ends mid-game, an Add friend button lets you keep playing.
- The version check now lists pugs in your raid too.
- New Settings > Friends page.

## Changes in 0.47.1

- Reports: This week can be filtered by difficulty (Heroic or Mythic) as well as by boss.
- Reports: the short-pull count no longer overlaps the note at the bottom of This week.

## Changes in 0.47.0

- Bonus roll protection: the green Yes button works properly when combat starts.
- Loot Rolls: closing the window mid-fight brings Blizzard's pop-ups back once combat ends.
- Chess: other players can't end or change your games with fake messages.
- Death Roll: a seat nobody starts closes after 5 minutes, and finished games send much less guild traffic.
- Stack splitter stops with a message if the stack moves mid-split.
- Fixes for dragging Keystone Roulette in combat, Wheel of Fortune games left behind when the host reloads, and macro names on non-English clients.
- Lots of smaller stability fixes.

## Changes in 0.46.1

- Chess: the Watch tab now splits games in progress from finished ones.

## Changes in 0.46.0

- Chess: new History tab with your win/loss record and past games. Click a game to step through its moves.

## Changes in 0.45.2

- Fixed a thin line under rail pages that ran down to the bottom of the screen.

## Changes in 0.45.1

- The README is shorter and easier to read.

## Changes in 0.45.0

- Chess: a Watch tab to follow the guild's other games live.
- Chess: an optional "your move" pop-up (Settings > Chess, off by default).
- Chess: the latest move's squares are yellow.

## Older versions

Changes before 0.45.0 are in the in-game What's new (`/et new`) and on CurseForge.

Bundled libraries: LibStub (public domain), LibSharedMedia-3.0 (LGPL 2.1), CallbackHandler-1.0 (BSD).
