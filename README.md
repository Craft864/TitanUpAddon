# Titan Up v0.47.0

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
- The **Watch** tab lets you follow the guild's other games, with games in progress at the top and finished ones below.
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

## Older versions

Changes before 0.30.0 are in the in-game What's new (`/tu new`, back to 0.25.0) and on CurseForge.

Bundled libraries: LibStub (public domain), LibSharedMedia-3.0 (LGPL 2.1), CallbackHandler-1.0 (BSD).
