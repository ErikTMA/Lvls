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
  It finishes the zone you are in before sending you elsewhere, picks up quests on
  the way, and when it has to travel it goes where the most quests wait for the
  trip (flight paths included), not to the nearest lone one. Right-click a line to skip its quest: the route leaves it out.
- **Travel.** The arrow takes the fastest way: to the flight master and onto a flight
  path you know, the boat or zeppelin, your hearthstone, the entrance of a cave. It
  learns as you play: how long your flights take, the boats you ride, the way into
  every cave you walk into. Flight points you have not found yet are picked up on the
  way ("Get the Lakeshire flight path").

- **Dungeon guides.** Pick a dungeon (the viewer's Guides button, the settings, or
  `/lvls guide deadmines`) and Lvls! finds every quest for it and every quest that
  leads up to them (prerequisites, chains, breadcrumbs), routes you through them and
  ends at the dungeon's entrance with the objectives to do inside. When you come
  out, it hands them in and goes back to leveling.
- **Quests that start from an item.** When you loot an item that starts a quest worth
  doing, the next step is "Use <item>" and the quest joins your route. While you kill
  mobs that drop such an item anyway, the step says so ("Loot Nibbled-On Book from
  Kobold Vermin"). Uses QuestieDB's data for the newer Forever quests.
- **The Guides menu.** Dungeons at your level come first, the rest are grouped per ten
  levels with raids apart; class quests are split into ready now, coming up and later.
  Each entry shows levels, quest count and zone, and its tooltip lists the quests with
  who gives them, where, and whether you can take them yet.
- **Class quest guides.** When a class quest chain becomes possible (the warrior's
  weapon quests at level 10, the druid's bear form, the hunter's pet), Lvls! asks
  whether to focus on it: **Focus** routes you through it, **Later** keeps it in the
  Guides menu (and `/lvls guide class`) for when you want it. The guide takes the
  chain one quest after another and says what comes next, from whom, and when.
- **Learns what is hard for you.** Lvls! keeps track of your solo fights: how long they
  take, how much health they cost, the rest you need afterwards, deaths, and the
  level and type of what you fought. When fights against mobs of a certain level
  are hard again and again (never because of one bad pull), it plans quests a bit
  further below your level for a while, and when the only quests left close by are
  too hard, it may suggest finishing the level on easy mobs nearby first ("Kill
  Young Goretusk until level 14"). It also learns how long a kill takes you.
  `/lvls fights` shows what it learned.
- **Questing together.** Group members who run Lvls! share which quests they have
  done. When a friend has done quests you have not (or has ones in their log you
  could share), Lvls! asks whether to catch up with them: it then routes you through
  those quests and every quest you need before them. Your friend is asked whether to
  follow your route to help, and their arrow and viewer go where you go. Both of
  you need the same Lvls! version.
- **Hands-free questing (each part can be switched off).** Accepts the quests your
  route or guide tells you to pick up (others are left to you) and hands quests in
  when you talk to the npc, takes the reward that is the best upgrade for
  your class and spec (or the one that sells for most when none is), and can put on
  upgrades from your bags out of combat. Items that bind when equipped are only put
  on up to a quality you choose: a blue that drops stays in your bags unless you
  allow blues. Hold Shift while talking to an npc to do it yourself. Your spec is the
  talent tree with the most points (or the one you pick); gear is judged with Lvls'
  own stat weights, or with your Pawn scale for that spec if you use Pawn.
- **Talents from your build.** Pick your spec (the tree with the most points is
  preselected, you decide) and a build, and Lvls! learns its points as you level,
  in its order. Make your own builds in its talent window: click the talents in the
  order you want them, move a point earlier or later, and Lvls! only lets you put a
  point where the tree allows it at that level. When you reset your talents it asks
  again; Turn off leaves your talents alone. `/lvls talents`

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
| `/lvls settings` | Open the settings (also under Options, AddOns, Lvls!) |
| `/lvls guide`, `/lvls guide <dungeon>`, `/lvls guide off` | List dungeons with quests for you, start a dungeon guide, back to leveling |
| `/lvls guide class`, `/lvls guide class <name>` | List your class quest chains, start one |
| `/lvls classask` | Ask about class quests when they become possible: on or off |
| `/lvls fights`, `/lvls fights reset` | What Lvls! learned from your fights; start over |
| `/lvls sync`, `/lvls sync <name>`, `/lvls sync follow <name>`, `/lvls sync off` | Group members with Lvls! and what you could catch up on; catch up with one; follow one's route to help; stop |
| `/lvls learn`, `/lvls grind` | Learn from fights; suggest grinding a level: on or off |
| `/lvls accept`, `/lvls deliver`, `/lvls reward`, `/lvls gold` | Accept quests, hand them in, take the best reward, otherwise the most gold: on or off |
| `/lvls equip`, `/lvls bind`, `/lvls quality <white\|green\|blue\|epic>` | Put on upgrades; also ones that bind when equipped, up to this quality |
| `/lvls talents [off\|learn]` | Spec and talent build window; off: leave your talents alone; learn: spend your points now |
| `/lvls spec [auto\|<spec>]`, `/lvls weights <auto\|pawn\|lvls>`, `/lvls gear` | Spec for gear (auto: from talents), whose stat weights, and what is used now |
| `/lvls route` | Re-plan from here |
| `/lvls next` | Point the arrow back at the current step |
| `/lvls skip <quest>`, `/lvls skip` | Skip quests whose name contains the text (or id); without text, list skipped quests |
| `/lvls unskip <quest>`, `/lvls unskip all` | Take skipped quests back |
| `/lvls zone` | Finish the current zone first (on by default) or not |
| `/lvls arrow` | Arrow on or off (with Profs! installed too, the two share one arrow) |
| `/lvls nearby` | List the nearest quests you can pick up |
| `/lvls travel` | How the arrow gets you there, leg by leg |
| `/lvls record <title>`, `/lvls record stop` | Record a path you walk (to share a way up a hill) |
| `/lvls note <text>`, `/lvls note`, `/lvls note clear` | A note on where your target (or the current step's quest giver) stands, such as "At the top of the tower". It shows on the step and under the arrow. Without text: show it. `clear`: remove yours |
| `/lvls map`, `/lvls minimap` | Quest pins on the world map / minimap on or off |
| `/lvls objectives` | Objective areas on or off |
| `/lvls low`, `/lvls trivial`, `/lvls dungeon`, `/lvls repeatable` | Also show quests you are too low for, grey quests, dungeon quests, dailies |
| `/lvls status` | Data and QuestieDB status |

In the viewer, `<` and `>` browse the steps ahead, and clicking a line points the arrow
at it. The addon compartment button (minimap) opens the viewer; right-click re-plans.

## License

All rights reserved.
