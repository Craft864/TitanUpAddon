# Titan Up v0.46.0

A guild toolkit for World of Warcraft (Midnight), made for Titan Up on Medivh-US.

**Install:** get Titan Up from WoWUp or CurseForge.

## What's in it

- **Raid Info**
  - **TitanBoard**: a live strategy board the raid can draw on together. `/tb`.
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

## Getting around

- `/tu` (or the minimap button) opens Titan Up on **Home**. Pick a module from the rail on the left; Settings is at the bottom.
- Modules with several pages show tabs across the top.
- The search box in the title bar finds any setting.
- `/tu help` lists every command.

## Death Roll

- `/tu roll`, set a wager, and challenge someone in your group or open it to anyone.
- Each roll is a real `/roll` from 1 to the last result. Whoever rolls a 1 pays the wager.
- Payment is a normal trade, detected automatically. The winner can also mark a debt paid.
- **Standings** show everyone's wins, losses and unpaid gold. Only games both players agree on count, so nobody can fake a result.
- Both players must be in the same group. **Practice solo** plays against a bot.

## Raid Check

`/tu raidcheck`. Heroic and Mythic raids only.

- On every ready check, and on a typed `/pull`, it checks everyone's buffs, flask, food, weapon enchant, Vantus Rune, potions, healthstone and durability.
- If someone's missing something, the leader gets a list with **Pull anyway** or **Cancel**.
- Only a typed `/pull` is checked. Boss mod pull buttons can't be stopped.

## Loot

`/tu loot`.

- Records raid drops with everyone's rolls, bonus rolls, Mythic+ loot, and trades until the item is equipped.
- Search by player, item or boss.
- **Roll window** (Loot settings, off by default): every roll in one window, with BIS / Sidegrade / set tags and notes the raid can see. Closing it hands your rolls back to Blizzard's pop-ups. `/tu rolls` reopens it.
- **Wishlist** tab: browse any raid or dungeon and mark items BIS, Sidegrade or Want. Click a drop to see who in the guild wants it.

## Wheel of Fortune

`/tu wheel`.

- **Play together** with random puzzles, or **Host a game** with your own.
- Spin, call consonants, buy vowels for $250, or solve. Most money after the last round wins.
- Optional **Bonus round** for the leader at the end.
- **Practice solo** plays against bots.

## Chess

`/tu chess`.

- Challenge any guildmate. They don't need to be online: guildmates running Titan Up pass your moves along.
- Optional timers: days per move, or a live clock that only runs while you're both online.
- Full chess rules. Games are saved until they end, and follow you to your other characters.
- The **Watch** tab lets you follow the guild's other games.
- The **History** tab shows your win/loss record and your last 200 games. Click one to replay it.

## TitanBoard

`/tb` opens the board, `/tb help` lists its commands.

- Left: draw. Right-drag: pan. Right-click: delete. Wheel: zoom.
- Ctrl+drag: move an item. Ctrl+wheel: resize it. Alt+drag: laser. Ctrl+Z: undo.
- Only the raid leader moves the view and switches bosses for everyone. Assistants can still draw.
- Paste a Raidstrats string into Import to bring in a plan.

## Crafters

- Open a profession window once and the guild can see what you can make.
- Search for a recipe or item to see who can craft it, the best quality they can make, and whisper them.
- Anyone can add a crafter from outside the guild for items nobody in the guild makes.

## Characters

- Your characters in the guild are linked (Settings > Titan Up). Standings show one row per player under their main, and Death Roll debts can be paid from any of your characters.
- Titan Up asks which character is your main. You can change it in Settings.

## Planned

- Fury of the Dead is still matched by its English name in Raid Check.

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

## Changes in 0.44.0

- Crafters: see the best quality rank each crafter can make, with and without Concentration.

## Changes in 0.43.0

- Chess: your games follow you to your other characters.

## Changes in 0.42.0

- Closing the Loot Rolls window now gives unmade rolls back to Blizzard's pop-ups.
- Roll buttons match Blizzard's: Need, Greed or Transmog, and Pass. Greyed buttons say why.
- Items you pass on shrink to one line.
- After you roll, the item shows who it's still waiting on.
- Bonus roll protection has its own big Yes button.

## Changes in 0.41.0

- Wowdle standings were reset. Death Roll is unchanged.
- A new pop-up asks which character is your main.

## Changes in 0.40.1

- Keystone Roulette is off in raid groups.

## Changes in 0.40.0

- New: Consumables, your raid shopping list.
- Optional reminder when you zone into a raid short on something (off by default).

## Changes in 0.39.0

- The rail is now Raid Info, Tools and Guild.
- Combat Timer moved into UI Tweaks. Click a recent fight for its details.

## Changes in 0.38.0

- Death Roll, Wheel of Fortune, Wowdle and Chess are one Games entry.
- Pages show as tabs across the top and as a list on the rail.

## Changes in 0.37.0

- New: Crafters.
- New: Loot Wishlist.
- Your characters are linked in the guild games.
- Raid Check works on non-English clients.

## Changes in 0.36.0

- Wheel of Fortune: optional bonus round, and a faster wheel.

## Changes in 0.35.0

- Chess: moves slide, captured pieces show, guildmates are listed to challenge, and optional timers.

## Changes in 0.34.0

- New game: Chess, playable with guildmates even when you're not online together.

## Changes in 0.33.0

- A search box in the title bar finds any setting.

## Changes in 0.32.0

- A large round of bug fixes across every module.
- TitanBoard: only the raid leader moves the view for everyone.

## Changes in 0.31.1

- A wider rail so long names fit.

## Changes in 0.31.0

- Macro Share is now Macro Workstation, with a step-by-step macro Builder.
- Anyone can send a macro to one person in their group.

## Changes in 0.30.1

- Bonus rolls sit inside the Loot Rolls window while it's open.

## Changes in 0.30.0

- New UI Tweak: Bonus roll protection (off by default).
- Loot shows bonus roll wins.
- Combat Timer: choose which fights get a chat line.

## Changes in 0.29.2

- Raid Check: weapon oils are detected again.
- Pull Report: defensives updated for Midnight.

## Changes in 0.29.1

- Layout fixes for Home, Reports, Macro Share and Death Roll.

## Changes in 0.29.0

- Titan Up is now one window with a rail of modules and a Home page.
- Pull Report and Raid Scorecard are now Reports.
- Pop-ups stack in one movable spot.

## Changes in 0.28.0

- Version check lists just your group and fills in as people answer.

## Changes in 0.27.0

- Loot: a new roll window (off by default).

## Changes in 0.26.0

- Death Roll: the spectator list shows again.
- Removed testing-only commands.

## Changes in 0.25.3

- Pull Report ignores pulls under 20 seconds that aren't kills.
- Death Roll fixes.

## Changes in 0.25.2

- `/tu mem` shows a breakdown.
- Pull Report pop-ups are off by default.

## Changes in 0.25.1

- Macro Share: drag a macro in to share it.

## Changes in 0.25.0

- New: Macro Share.

## Changes in 0.24.5

- Fixes for patch 12.1.5.

## Changes in 0.24.4

- Raid Scorecard: a cleaner "No data" message.

## Changes in 0.24.3

- Settings opens beside the window you came from.
- What's new lists every version since you last played.

## Changes in 0.24.2

- Settings fixes and a tidier page order.

## Changes in 0.24.1

- Settings is now pages, with a cog on each module to open its page.

## Changes in 0.24.0

- New: Settings, Version check and What's new.
- Key bindings and Blizzard's addon menu.
- Raid Scorecard: potion and healthstone columns, and a boss filter.
- Pull Report: a suggested wipe call.

## Changes in 0.23.0

- New: Raid Scorecard.
- Pull Report: the raid leader can mark where the wipe was called.

## Changes in 0.22.2

- Pull Report testing commands.

## Changes in 0.22.1

- Pull Report: more accurate "ready" checks, and a cooldowns section for each death.
- Release protection no longer covers battle rez Accept.

## Changes in 0.22.0

- New UI Tweak: Battle rez tracker (off by default).

## Changes in 0.21.0

- Wheel of Fortune: Play together or Host a game, with a turn timer.
- Pull Report: shows active defensives, and an optional death summary.

## Changes in 0.20.0

- New: Pull Report.

## Changes in 0.19.8

- Keystone Roulette: fixed an error when opening it.

## Changes in 0.19.7

- Keystone Roulette: fixed an error when opening it.

## Changes in 0.19.6

- Stack splitter: guild bank splits are reliable.

## Changes in 0.19.5

- Stack splitter: guild bank fixes.

## Changes in 0.19.4

- Stack splitter: guild bank fixes.

## Changes in 0.19.3

- Stack splitter is faster and fills new stacks in order.

## Changes in 0.19.2

- Stack splitter: guild bank splits no longer stop after one move.

## Changes in 0.19.1

- Less memory at login.

## Changes in 0.19.0

- New UI Tweak: Stack splitter (off by default).
- Keystone Roulette: click a dungeon to teleport there.

## Changes in 0.18.3

- Keystone Roulette: better dungeon art.

## Changes in 0.18.2

- Keystone Roulette: type the key level range.

## Changes in 0.18.1

- Keystone Roulette art and logo fixes.

## Changes in 0.18.0

- New UI Tweak: Death alerts (off by default).
- New: Keystone Roulette.

## Changes in 0.17.0

- New game: Wowdle.
- New: UI Tweaks, starting with Release protection.
- Combat Timer keeps a history of recent fights.

## Changes in 0.16.6

- A slimmer navigation tab.

## Changes in 0.16.5

- Hub window fixes.

## Changes in 0.16.4

- Windows stay in place when you switch modules.

## Changes in 0.16.3

- Settings cogs on Loot, Raid Check and Death Roll.

## Changes in 0.16.2

- Windows lose their title row.
- Combat Timer can post fight length in chat.

## Changes in 0.16.1

- A new navigation tab on every window.

## Changes in 0.16.0

- Titan Up works for any guild. Data stays inside your own guild.

## Changes in 0.15.4

- TitanBoard layout fixes.

## Changes in 0.15.3

- A taller title bar with a back arrow.
- Wheel of Fortune setup improvements.

## Changes in 0.15.2

- Death Roll: debt checks work after combat.

## Changes in 0.15.1

- Raid Check accepts any current flask and food.
- Combat Timer settings improvements.

## Changes in 0.15.0

- New: Combat Timer.
- A redesigned hub.
- Raid Check tracks health potions.

## Changes in 0.14.5

- Raid Check: combat potions are counted again.
- Death Roll debts clear right after the trade.

## Changes in 0.14.4

- Death Roll: fixed rolls from connected realms.

## Changes in 0.14.3

- Death Roll: declining a challenge no longer cancels it.

## Changes in 0.14.2

- Death Roll: a spectator list.

## Changes in 0.14.1

- Death Roll: the chat link catches you up on missed rolls.

## Changes in 0.14.0

- Addon data stays inside the guild.

## Changes in 0.13.0

- New: Raid Check.

## Changes in 0.12.0

- New: Loot tracker.

## Changes in 0.11.2

- Death Roll performance improvements.

## Changes in 0.11.1

- Faster login and less background work.

## Changes in 0.11.0

- Games has its own launcher.

## Changes in 0.10.3

- Wheel of Fortune: 141 ready-made puzzles.

## Changes in 0.10.2

- Death Roll: Rematch after practice stays in practice.

## Changes in 0.10.1

- Death Roll: results can't be tampered with.

## Changes in 0.10.0

- New game: Wheel of Fortune.
- Death Roll standings sync with the guild.

## Changes in 0.9.5

- Death Roll: a shared ledger and standings.

## Changes in 0.9.4

- The same title bar on every window.

## Changes in 0.9.3

- A module bar in every window.

## Changes in 0.9.2

- Death Roll: the roll list scrolls.

## Changes in 0.9.1

- The Titan Up logo.
- Death Roll handles combat and reloads.

## Changes in 0.9.0

- Titan Up is born, with TitanBoard, a hub and a minimap button.
- New game: Death Roll.

Bundled libraries: LibStub (public domain), LibSharedMedia-3.0 (LGPL 2.1), CallbackHandler-1.0 (BSD).
