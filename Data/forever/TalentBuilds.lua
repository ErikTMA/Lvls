-- Lvls!'s own talent builds, one per tree: for leveling, written from Forever's
-- trait trees (Data/forever/Talents.lua: the talents' names, ranks, rows and what
-- each one does). Each order is talent name, points, talent name, points, ... in
-- the order they are learned (one point per level from 10); a talent can come back
-- later for more points. 31 points reach the tree's last talent; the other 20 go
-- where they help leveling most. Engine/Talents.lua (T.Shipped) turns the names
-- into the tree's talents; the tests check that every build fits its tree.
local _, ns = ...

ns.TalentBuilds = {
  [1] = { -- Warrior
    { spec = 1, order = {
      "Improved Heroic Strike", 3, "Improved Rend", 2, "Improved Charge", 2, "Improved Rend", 1,
      "Improved Tactical Mastery", 3, "Anger Management", 1, "Deep Wounds", 3,
      "Two-Handed Weapon Specialization", 3, "Impale", 2, "Sweeping Strikes", 1, "Weaponmaster", 5,
      "Improved Slam", 2, "Improved Overpower", 2, "Mortal Strike", 1,
      "Cruelty", 5, "Unbridled Wrath", 5, "Blood Craze", 3, "Enrage", 2, "Improved Execute", 2,
      "Reckless Swings", 1, "Enrage", 2 } },
    { spec = 2, order = {
      "Cruelty", 5, "Unbridled Wrath", 5, "Blood Craze", 3, "Enrage", 2,
      "Dual Wield Specialization", 5, "Death Wish", 1, "Gore Drinker", 2, "Reckless Swings", 1,
      "Enrage", 1, "Flurry", 3, "Improved Whirlwind", 2, "Bloodthirst", 1,
      "Improved Heroic Strike", 3, "Improved Rend", 2, "Improved Charge", 2,
      "Improved Tactical Mastery", 3, "Improved Rend", 1, "Anger Management", 1, "Deep Wounds", 3,
      "Impale", 2, "Improved Overpower", 2, "Deflection", 1 } },
    { spec = 3, order = {
      "Shield Specialization", 5, "Improved Revenge", 3, "Improved Thunder Clap", 2,
      "Master of Defense", 2, "Last Stand", 1, "Defiance", 2, "Vanguard", 1, "Improved Sunder Armor", 3,
      "Improved Bloodrage", 1, "Concussion Blow", 1, "Focused Rage", 3, "Improved Bloodrage", 1,
      "Bastion", 5, "Shield Slam", 1,
      "Cruelty", 5, "Unbridled Wrath", 5, "Blood Craze", 3, "Enrage", 2, "Improved Execute", 2,
      "Reckless Swings", 1, "Enrage", 2 } },
  },
  [2] = { -- Paladin
    { spec = 1, order = {
      "Divine Strength", 5, "Improved Seals", 5, "Reverence", 2, "Holy Conduit", 2, "Divine Favor", 1,
      "Divine Precision", 2, "Infusion of Light", 2, "Oath of Light", 1, "Holy Shock", 1,
      "Consecrated Ground", 2, "Boundless Light", 2, "Holy Power", 5, "Light's Vigil", 1,
      "Benediction", 5, "Conviction", 3, "Improved Judgement", 2, "Seal of Command", 1,
      "Pursuit of Justice", 2, "Sanctified Judgement", 2, "Sacred Arbiter", 1,
      "Two-Handed Weapon Specialization", 3, "Deflection", 1 } },
    { spec = 2, order = {
      "Redoubt", 5, "Precision", 3, "Sacred Duty", 2, "Shield Specialization", 2, "Toughness", 3,
      "Improved Righteous Fury", 3, "Templar's Bulwark", 1, "Swift Judgement", 1, "Holy Shield", 1,
      "Reckoning", 4, "Iron Creed", 3, "Toughness", 2, "Shieldsworn", 1,
      "Benediction", 5, "Conviction", 3, "Improved Judgement", 2, "Pursuit of Justice", 2,
      "Seal of Command", 1, "Sanctified Judgement", 2, "Sacred Arbiter", 1, "Vindication", 3,
      "Deflection", 1 } },
    { spec = 3, order = {
      "Benediction", 5, "Conviction", 3, "Improved Judgement", 2, "Seal of Command", 1,
      "Pursuit of Justice", 2, "Vindication", 2, "Two-Handed Weapon Specialization", 3,
      "Sacred Arbiter", 1, "Sanctified Judgement", 1, "Vengeance", 3, "Repentance", 1,
      "Sanctified Judgement", 1, "Champion of the Light", 5, "Unsealed Wrath", 1,
      "Divine Strength", 5, "Improved Seals", 5, "Purifying Power", 2, "Holy Conduit", 2,
      "Divine Favor", 1, "Divine Precision", 2, "Reverence", 2, "Healing Light", 1 } },
  },
  [3] = { -- Hunter
    { spec = 1, order = {
      "Deadly Aspects", 5, "Focused Fire", 2, "Endurance Training", 3, "Pathfinding", 2,
      "Unleashed Fury", 5, "Bestial Swiftness", 1, "Ferocity", 5, "Intimidation", 1, "Spirit Bond", 2,
      "Frenzy", 5, "Bestial Wrath", 1,
      "Lethal Attacks", 5, "Careful Aim", 5, "Efficiency", 5, "Mortal Shots", 4 } },
    { spec = 2, order = {
      "Lethal Attacks", 5, "Careful Aim", 5, "Rapid Killing", 2, "Improved Arcane Shot", 3,
      "Mortal Shots", 5, "Trueshot Aura", 1, "Barrage", 3, "Efficiency", 1,
      "Ranged Weapon Specialization", 5, "Sniper Shot", 1,
      "Deadly Aspects", 5, "Focused Fire", 2, "Endurance Training", 3, "Pathfinding", 2,
      "Unleashed Fury", 3, "Ferocity", 5 } },
    { spec = 3, order = {
      "Improved Tracking", 5, "Survivalist", 5, "Savage Strikes", 2, "Surefooted", 3, "Deterrence", 1,
      "Predator's Edge", 5, "Expose Prey", 2, "Resourcefulness", 2, "Lightning Reflexes", 5,
      "Lacerating Strikes", 1,
      "Lethal Attacks", 5, "Careful Aim", 5, "Improved Arcane Shot", 3, "Efficiency", 2,
      "Mortal Shots", 5 } },
  },
  [4] = { -- Rogue
    { spec = 1, order = {
      "Malice", 5, "Ruthlessness", 3, "Improved Slice and Dice", 2, "Lethality", 2, "Vigor", 2,
      "Blood Splatter", 1, "Improved Poisons", 5, "Cold Blood", 1, "Venom", 1, "Relentless Strikes", 3,
      "Seal Fate", 3, "Vile Poisons", 2, "Mutilate", 1,
      "Coup de Grace", 3, "Efficient Strikes", 2, "Precision", 3, "Puncturing Wounds", 3,
      "Endurance", 2, "Lightning Reflexes", 2, "Weapon Expertise", 2, "Aggression", 3 } },
    { spec = 2, order = {
      "Efficient Strikes", 2, "Coup de Grace", 3, "Precision", 3, "Lightning Reflexes", 2, "Endurance", 2,
      "Lightning Reflexes", 3, "Weapon Expertise", 2, "Aggression", 3, "Flawless Execution", 1,
      "Blade Flurry", 1, "Dual Wield Specialization", 2, "Hack and Slash", 5, "Flash of Steel", 1,
      "Adrenaline Rush", 1,
      "Malice", 5, "Ruthlessness", 3, "Improved Slice and Dice", 2, "Lethality", 2, "Vigor", 2,
      "Remorseless Attacks", 1, "Improved Poisons", 5 } },
    { spec = 3, order = {
      "Opportunity", 5, "Improved Ambush", 3, "Dirty Deeds", 2, "Initiative", 3, "Premeditation", 1,
      "Serrated Blades", 3, "Ghostly Strike", 1, "Elusiveness", 2, "Hemorrhage", 1, "Preparation", 1,
      "Heightened Senses", 2, "Master of Deception", 1, "Boot Knife", 5, "Death Mark", 1,
      "Efficient Strikes", 2, "Coup de Grace", 3, "Precision", 3, "Lightning Reflexes", 2,
      "Endurance", 2, "Lightning Reflexes", 3, "Weapon Expertise", 2, "Aggression", 3 } },
  },
  [5] = { -- Priest
    { spec = 1, order = {
      "Wand Specialization", 2, "Twin Disciplines", 3, "Mental Strength", 5, "Mental Agility", 3,
      "Improved Power Word: Shield", 3, "Soul Warding", 1, "Improved Inner Fire", 3, "Penance", 1,
      "Power in Light", 4, "Divine Aegis", 3, "Twin Disciplines", 2, "Power Infusion", 1,
      "Spirit Tap", 5, "Improved Shadow Word: Pain", 2, "Improved Mind Blast", 3, "Mind Flay", 1,
      "Improved Mind Flay", 2, "Shadow Focus", 2, "Shadow Weaving", 3, "Vampiric Embrace", 1,
      "Shadow Focus", 1 } },
    { spec = 2, order = {
      "Holy Specialization", 3, "Improved Renew", 2, "Divine Fury", 5, "Holy Nova", 1,
      "Blessed Recovery", 3, "Twilight Focus", 1, "Searing Light", 2, "Improved Healing", 3,
      "Spiritual Guidance", 5, "Spirit of Redemption", 1, "Spiritual Healing", 3,
      "Holy Specialization", 1, "Prayer of Mending", 1,
      "Wand Specialization", 2, "Twin Disciplines", 3, "Mental Strength", 5, "Mental Agility", 3,
      "Improved Power Word: Shield", 3, "Soul Warding", 1, "Improved Inner Fire", 3 } },
    { spec = 3, order = {
      "Spirit Tap", 5, "Improved Shadow Word: Pain", 2, "Improved Mind Blast", 3, "Mind Flay", 1,
      "Improved Mind Flay", 2, "Shadow Focus", 2, "Shadow Weaving", 3, "Vampiric Embrace", 1,
      "Dark Inspiration", 1, "Devouring Contagion", 2, "Improved Mind Blast", 2, "Shadow Focus", 1,
      "Darkness", 5, "Shadowform", 1,
      "Wand Specialization", 2, "Twin Disciplines", 3, "Mental Strength", 5, "Mental Agility", 3,
      "Improved Power Word: Shield", 2, "Improved Inner Fire", 3, "Twin Disciplines", 2 } },
  },
  [7] = { -- Shaman
    { spec = 1, order = {
      "Concussion", 5, "Call of Flame", 3, "Elemental Alacrity", 2, "Elemental Focus", 1,
      "Elemental Alacrity", 1, "Convection", 3, "Eye of the Storm", 3, "Convection", 2,
      "Call of Thunder", 1, "Lightning Overload", 3, "Reverberation", 1, "Elemental Fury", 5,
      "Lightning Mastery", 1,
      "Tidal Focus", 5, "Mindfulness", 3, "Totemic Focus", 2, "Water Shield", 1, "Totemic Focus", 3,
      "Improved Reincarnation", 1, "Mana Tide Totem", 1, "Restorative Totems", 4 } },
    { spec = 2, order = {
      "Thundering Strikes", 5, "Mental Dexterity", 3, "Ancestral Knowledge", 2, "Elemental Weapons", 3,
      "Shamanistic Focus", 1, "Anticipation", 1, "Stormstrike", 1, "Flurry", 5, "Improved Ghost Wolf", 2,
      "Mental Quickness", 2, "Maelstrom Weapon", 5, "Rage of the Farseer", 1,
      "Concussion", 5, "Call of Flame", 3, "Reverberation", 2, "Elemental Focus", 1,
      "Elemental Devastation", 3, "Reverberation", 1, "Eye of the Storm", 3, "Reverberation", 2 } },
    { spec = 3, order = {
      "Tidal Focus", 5, "Mindfulness", 3, "Totemic Focus", 2, "Water Shield", 1, "Healing Focus", 3,
      "Improved Reincarnation", 1, "Mana Tide Totem", 1, "Restorative Totems", 4, "Nature's Swiftness", 1,
      "Healing Way", 3, "Improved Healing Wave", 1, "Purification", 5, "Riptide", 1,
      "Concussion", 5, "Call of Flame", 3, "Reverberation", 2, "Elemental Focus", 1,
      "Elemental Alacrity", 3, "Convection", 1, "Eye of the Storm", 3, "Convection", 2 } },
  },
  [8] = { -- Mage
    { spec = 1, order = {
      "Arcane Resilience", 3, "Improved Channeling", 2, "Arcane Concentration", 5, "Arcane Blast", 1,
      "Arcane Impact", 3, "Missile Barrage", 1, "Arcane Meditation", 3, "Arcane Wrath", 1,
      "Missile Barrage", 1, "Presence of Mind", 1, "Arcane Mind", 4, "Arcane Instability", 3,
      "Arcane Mind", 1, "Arcane Subtlety", 1, "Arcane Power", 1,
      "Accelerant", 5, "Ignite", 5, "Improved Fire Blast", 2, "Incineration", 3,
      "Master of Elements", 3, "Incineration", 2 } },
    { spec = 2, order = {
      "Accelerant", 5, "Ignite", 5, "Improved Fire Blast", 2, "Pyroblast", 1, "Burning Soul", 2,
      "Heating Up", 1, "Master of Elements", 3, "Impact", 1, "Critical Mass", 3, "Blast Wave", 1,
      "Incineration", 1, "Fire Power", 3, "Incineration", 2, "Combustion", 1,
      "Arcane Resilience", 3, "Improved Channeling", 2, "Arcane Concentration", 5, "Missile Barrage", 2,
      "Arcane Blast", 1, "Arcane Subtlety", 2, "Arcane Meditation", 3, "Arcane Shielding", 2 } },
    { spec = 3, order = {
      "Improved Frostbolt", 5, "Ice Shards", 5, "Frost Channeling", 3, "Ice Lance", 1, "Precision", 1,
      "Ice Block", 1, "Shatter", 3, "Arctic Reach", 1, "Cold Snap", 1, "Fingers of Frost", 2,
      "Improved Cone of Cold", 2, "Winter's Chill", 5, "Ice Barrier", 1,
      "Arcane Resilience", 3, "Improved Channeling", 2, "Arcane Concentration", 5, "Arcane Blast", 1,
      "Missile Barrage", 2, "Arcane Subtlety", 2, "Arcane Meditation", 3, "Arcane Shielding", 2 } },
  },
  [9] = { -- Warlock
    { spec = 1, order = {
      "Improved Corruption", 5, "Improved Drains", 3, "Soul Harvest", 2, "Improved Bane of Agony", 2,
      "Amplify Curse", 1, "Pandemic", 2, "Nightfall", 2, "Malevolence", 3, "Siphon Life", 1,
      "Soul Siphon", 3, "Fel Concentration", 1, "Shadow Mastery", 5, "Wrack", 1,
      "Demonic Embrace", 5, "Fel Vitality", 3, "Demonic Energies", 2, "Demonic Sacrifice", 1,
      "Master Summoner", 2, "Improved Health Funnel", 2, "Fel Domination", 1, "Unholy Power", 4 } },
    { spec = 2, order = {
      "Demonic Embrace", 3, "Unholy Power", 2, "Fel Vitality", 3, "Demonic Energies", 2,
      "Master Summoner", 2, "Demonic Sacrifice", 1, "Unholy Power", 2, "Fel Domination", 1,
      "Demonic Brand", 3, "Improved Voidwalker", 1, "Soul Link", 1, "Demonic Knowledge", 3,
      "Unholy Power", 1, "Master Demonologist", 5, "Demonic Pact", 1,
      "Improved Corruption", 5, "Improved Drains", 3, "Soul Harvest", 2, "Improved Bane of Agony", 2,
      "Amplify Curse", 1, "Pandemic", 2, "Malevolence", 5 } },
    { spec = 3, order = {
      "Bane", 5, "Cataclysm", 3, "Molten Skin", 2, "Ruin", 5, "Agonizing Flames", 3, "Conflagrate", 1,
      "Shadowburn", 1, "Bane of Havoc", 1, "Fire and Brimstone", 3, "Intensity", 1,
      "Shadow and Flame", 5, "Incinerate", 1,
      "Demonic Embrace", 5, "Fel Vitality", 3, "Demonic Energies", 2, "Demonic Sacrifice", 1,
      "Master Summoner", 2, "Improved Health Funnel", 2, "Fel Domination", 1, "Unholy Power", 4 } },
  },
  [11] = { -- Druid
    { spec = 1, order = {
      "Improved Wrath", 5, "Moonglow", 3, "Nature's Majesty", 2, "Nature's Splendor", 1,
      "Improved Moonfire", 2, "Nature's Reach", 2, "Vengeance", 5, "Nature's Grace", 1, "Eclipse", 3,
      "Insect Swarm", 1, "Moonfury", 5, "Moonkin Form", 1,
      "Heart of the Wild", 5, "Reflection", 3, "Naturalist", 2, "Bloom", 1, "Gift of Nature", 4,
      "Improved Rejuvenation", 3, "Swiftmend", 1, "Naturalist", 1 } },
    { spec = 2, order = {
      "Ferocity", 5, "Feral Swiftness", 2, "Thick Hide", 3, "Savage Fury", 2, "Sharpened Claws", 2,
      "Feral Charge", 1, "Predatory Strikes", 3, "Blood Frenzy", 2, "Leader of the Pack", 1,
      "Natural Instinct", 2, "Shredding Attacks", 2, "Rend and Tear", 5, "Primal Bite", 1,
      "Heart of the Wild", 5, "Naturalist", 5, "Natural Shapeshifter", 3, "Gift of Nature", 2,
      "Swiftmend", 1, "Improved Rejuvenation", 3, "Reflection", 1 } },
    { spec = 3, order = {
      "Heart of the Wild", 5, "Naturalist", 5, "Reflection", 3, "Gift of Nature", 2, "Swiftmend", 1,
      "Improved Rejuvenation", 3, "Bloom", 1, "Nature's Swiftness", 1, "Living Spirit", 3,
      "Gift of Nature", 1, "Improved Regrowth", 5, "Wild Growth", 1,
      "Improved Wrath", 5, "Moonglow", 3, "Nature's Majesty", 2, "Nature's Splendor", 1,
      "Improved Moonfire", 2, "Nature's Reach", 2, "Insect Swarm", 1, "Vengeance", 4 } },
  },
}
