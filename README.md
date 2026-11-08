# Lvls!

A World of Warcraft addon for questing and leveling on **WoW Forever**.

- **Quest helper.** Quests your character can pick up are marked on the world map and
  the minimap where their givers stand. Accepted quests show where their objectives
  are (the creatures that actually drop what you need, not every creature that ever
  did) and where to hand them in.
- **Step by step.** Lvls! plans a route for *your* character from where you stand and
  shows it one step at a time: talk to this npc (hand in, pick up), or do these
  objectives together. Lines tick off with their progress as you play, the next step
  is shown below, and an arrow points the way with the distance and time to go. It
  follows quest chains, respects your quest log size and re-plans when it has to.
  It finishes the zone you are in before sending you elsewhere and picks up quests
  on the way. Right-click a line to skip its quest: the route leaves it out.
- **Travel.** The arrow takes the fastest way: to the flight master and onto a flight
  path you know, the boat or zeppelin, your hearthstone, the entrance of a cave. It
  learns as you play: how long your flights take, the boats you ride, the way into
  every cave you walk into. Flight points you have not found yet are picked up on the
  way ("Get the Lakeshire flight path").

## Install

1. Download `Lvls-<version>.zip` from the latest release and unzip it into
   `World of Warcraft/_forever_/Interface/AddOns/`. It contains the `Lvls` folder.
2. Recommended: install **QuestieDB** as well. Lvls! reads quest prerequisites,
   breadcrumbs and mutually exclusive quests from it, so it only shows quests you
   can really take. Without it, Lvls! falls back to quest chains and tells you so.

## Use

| Command | What it does |
|---|---|
| `/lvls` | Show or hide the step viewer |
| `/lvls route` | Re-plan from here |
| `/lvls next` | Point the arrow back at the current step |
| `/lvls skip <quest>`, `/lvls skip` | Skip quests whose name contains the text (or id); without text, list skipped quests |
| `/lvls unskip <quest>`, `/lvls unskip all` | Take skipped quests back |
| `/lvls zone` | Finish the current zone first (on by default) or not |
| `/lvls arrow` | Arrow on or off |
| `/lvls nearby` | List the nearest quests you can pick up |
| `/lvls travel` | How the arrow gets you there, leg by leg |
| `/lvls record <title>`, `/lvls record stop` | Record a path you walk (to share a way up a hill) |
| `/lvls map`, `/lvls minimap` | Quest pins on the world map / minimap on or off |
| `/lvls objectives` | Objective areas on or off |
| `/lvls low`, `/lvls trivial`, `/lvls dungeon`, `/lvls repeatable` | Also show quests you are too low for, grey quests, dungeon quests, dailies |
| `/lvls status` | Data and QuestieDB status |

In the viewer, `<` and `>` browse the steps ahead, and clicking a line points the arrow
at it. The addon compartment button (minimap) opens the viewer; right-click re-plans.

## License

All rights reserved.
