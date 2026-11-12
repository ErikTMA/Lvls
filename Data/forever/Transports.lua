-- GENERATED transports for Lvls!. Do not edit.
-- From the forever client's TaxiPathNode, AreaTrigger, UiMapAssignment and UiMap
-- tables (build 1.60.1.70862) and the quest dataset: boats, zeppelins (side H), the
-- Deeprun Tram and walk-in portals (where they lead: a server's areatrigger_teleport)
-- as Engine/Travel transit links.
local _, ns = ...
ns.TravelTransports = {
  {kind="boat",a={map=1413,x=63.6,y=38.6},b={map=1434,x=26.0,y=73.2},title_ab="Take the boat to Stranglethorn Vale",title_ba="Take the boat to The Barrens"},
  {kind="zeppelin",a={map=1434,x=31.2,y=30.4},b={map=1411,x=50.5,y=12.7},side="H",title_ab="Take the zeppelin to Durotar",title_ba="Take the zeppelin to Stranglethorn Vale"},
  {kind="boat",a={map=1437,x=5.6,y=63.5},b={map=1445,x=71.3,y=56.6},title_ab="Take the boat to Dustwallow Marsh",title_ba="Take the boat to Wetlands"},
  {kind="boat",a={map=1438,x=54.9,y=96.6},b={map=1439,x=33.0,y=41.0},title_ab="Take the boat to Darkshore",title_ba="Take the boat to Teldrassil"},
  {kind="boat",a={map=1437,x=4.7,y=57.6},b={map=1439,x=32.6,y=43.3},title_ab="Take the boat to Darkshore",title_ba="Take the boat to Wetlands"},
  {kind="zeppelin",a={map=1434,x=31.5,y=29.1},b={map=1420,x=61.9,y=58.9},side="H",title_ab="Take the zeppelin to Tirisfal Glades",title_ba="Take the zeppelin to Stranglethorn Vale"},
  {kind="zeppelin",a={map=1411,x=51.0,y=13.9},b={map=1420,x=60.6,y=58.9},side="H",title_ab="Take the zeppelin to Tirisfal Glades",title_ba="Take the zeppelin to Durotar"},
  {kind="boat",a={map=1444,x=31.0,y=39.5},b={map=1444,x=43.1,y=42.8},title_ab="Take the boat to Feralas",title_ba="Take the boat to Feralas"},
  {kind="boat",a={map=1437,x=4.7,y=57.6},b={map=1424,x=50.6,y=68.6},title_ab="Take the boat to Hillsbrad Foothills",title_ba="Take the boat to Wetlands"},
  {kind="boat",a={map=1424,x=50.6,y=68.6},b={map=1439,x=32.6,y=43.3},title_ab="Take the boat to Darkshore",title_ba="Take the boat to Hillsbrad Foothills"},
  {kind="boat",a={map=1446,x=68.3,y=22.9},b={map=2548,x=80.0,y=54.2},title_ab="Take the boat to Riverglades",title_ba="Take the boat to Tanaris"},
  {kind="boat",a={map=1439,x=31.0,y=41.0},b={map=1453,x=23.8,y=56.0},title_ab="Take the boat to Stormwind City",title_ba="Take the boat to Darkshore"},
  {kind="tram",a={map=1453,x=69.6,y=30.3},b={map=1455,x=78.0,y=51.4},title_ab="Take the Deeprun Tram to Ironforge",title_ba="Take the Deeprun Tram to Stormwind City"},
  {kind="portal",a={map=1457,x=29.1,y=41.2},b={map=1438,x=55.9,y=89.3},secs=5,title_ab="Take the portal to Teldrassil",title_ba="Take the portal to Darnassus"},
}
