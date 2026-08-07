extends Node2D

const W=1280.0
const H=720.0
const PATH=[Vector2(-30,300),Vector2(180,300),Vector2(180,470),Vector2(430,470),Vector2(430,210),Vector2(720,210),Vector2(720,420),Vector2(980,420),Vector2(980,280),Vector2(1310,280)]
const TYPES={
 "ARC":{"cost":90,"range":165.0,"rate":0.65,"dmg":18.0,"c":Color("d5f06a")},
 "FROST":{"cost":120,"range":145.0,"rate":0.9,"dmg":12.0,"c":Color("72d8ff")},
 "RIFT":{"cost":160,"range":195.0,"rate":1.25,"dmg":36.0,"c":Color("d681ff")}
}

var mode="menu"
var gold=300
var lives=20
var wave=1
var selected_kind=""
var selected_tower=-1
var towers=[]
var enemies=[]
var beams=[]
var spawn_left=0
var spawn_cd=0.0
var wave_active=false
var paused=false
var banner=""
var banner_t=0.0

func _ready():
 set_process(true)
 queue_redraw()

func _process(dt):
 if mode=="battle" and not paused:
  _update_battle(dt)
 if banner_t>0.0:
  banner_t-=dt
 queue_redraw()

func _update_battle(dt):
 if wave_active and spawn_left>0:
  spawn_cd-=dt
  if spawn_cd<=0.0:
   _spawn_enemy()
   spawn_left-=1
   spawn_cd=max(0.32,0.85-wave*0.035)
 for i in range(enemies.size()-1,-1,-1):
  var e=enemies[i]
  if e.seg>=PATH.size()-1:
   enemies.remove_at(i)
   lives-=1
   if lives<=0: mode="defeat"
   continue
  var target=PATH[e.seg+1]
  var dist=e.pos.distance_to(target)
  var speed=e.speed*(0.62 if e.slow>0.0 else 1.0)
  e.slow=max(0.0,e.slow-dt)
  var step=speed*dt
  if step>=dist:
   e.pos=target
   e.seg+=1
  elif dist>0.0:
   e.pos+=e.pos.direction_to(target)*step
  enemies[i]=e
 for ti in range(towers.size()):
  var t=towers[ti]
  t.cd-=dt
  if t.cd<=0.0:
   var best=-1
   var best_progress=-1
   for ei in range(enemies.size()):
    if t.pos.distance_to(enemies[ei].pos)<=t.range:
     var prog=enemies[ei].seg*10000-int(enemies[ei].pos.distance_to(PATH[min(enemies[ei].seg+1,PATH.size()-1)]))
     if prog>best_progress:
      best_progress=prog
      best=ei
   if best>=0:
    var e=enemies[best]
    e.hp-=t.dmg
    if t.kind=="FROST": e.slow=max(e.slow,1.3)
    beams.append({"a":t.pos,"b":e.pos,"ttl":0.12,"c":TYPES[t.kind].c})
    t.cd=t.rate
    if e.hp<=0.0:
     gold+=e.reward
     enemies.remove_at(best)
    else:
     enemies[best]=e
  towers[ti]=t
 for i in range(beams.size()-1,-1,-1):
  beams[i].ttl-=dt
  if beams[i].ttl<=0.0: beams.remove_at(i)
 if wave_active and spawn_left==0 and enemies.is_empty():
  wave_active=false
  if wave>=10:
   mode="victory"
  else:
   gold+=40+wave*8
   wave+=1
   _say("Wave cleared  +%d shards"%(40+(wave-1)*8))

func _spawn_enemy():
 var elite=(wave%3==0 and spawn_left==1)
 var hp=62.0+wave*24.0
 if elite: hp*=2.4
 enemies.append({"pos":PATH[0],"seg":0,"hp":hp,"max":hp,"speed":70.0+wave*3.0,"reward":18+wave*2+(25 if elite else 0),"slow":0.0,"elite":elite})

func _start_wave():
 if wave_active or mode!="battle": return
 spawn_left=6+wave*2
 spawn_cd=0.05
 wave_active=true
 selected_tower=-1
 _say("Wave %d incoming"%wave)

func _tap(raw):
 var vs=get_viewport_rect().size
 var p=Vector2(raw.x*W/max(vs.x,1.0),raw.y*H/max(vs.y,1.0))
 if mode=="menu":
  if Rect2(470,390,340,88).has_point(p): _new_game()
  return
 if mode=="victory" or mode=="defeat":
  if Rect2(470,520,340,76).has_point(p): mode="menu"
  return
 if Rect2(1160,18,95,55).has_point(p):
  paused=!paused
  return
 if paused:
  if Rect2(480,330,320,70).has_point(p): paused=false
  if Rect2(480,420,320,70).has_point(p): mode="menu"
  return
 if not wave_active and Rect2(1040,625,210,62).has_point(p):
  _start_wave(); return
 if selected_tower>=0:
  if Rect2(890,625,135,62).has_point(p): _upgrade_selected(); return
  if Rect2(745,625,130,62).has_point(p): _sell_selected(); return
 for i in range(3):
  var r=Rect2(25+i*180,625,165,62)
  if r.has_point(p):
   selected_kind=["ARC","FROST","RIFT"][i]
   selected_tower=-1
   return
 for i in range(towers.size()):
  if towers[i].pos.distance_to(p)<38.0:
   selected_tower=i
   selected_kind=""
   return
 if selected_kind!="": _place_tower(p)

func _place_tower(p):
 var d=TYPES[selected_kind]
 if p.y>595 or p.y<90:
  _say("Build inside the battlefield"); return
 if gold<d.cost:
  _say("Not enough shards"); return
 if _path_distance(p)<62.0:
  _say("Too close to the enemy route"); return
 for t in towers:
  if t.pos.distance_to(p)<65.0:
   _say("Tower spacing too tight"); return
 gold-=d.cost
 towers.append({"pos":p,"kind":selected_kind,"level":1,"range":d.range,"rate":d.rate,"dmg":d.dmg,"cd":0.0,"spent":d.cost})
 _say(selected_kind+" tower deployed")

func _upgrade_selected():
 if selected_tower<0 or selected_tower>=towers.size(): return
 var t=towers[selected_tower]
 var cost=70*t.level
 if gold<cost:
  _say("Need %d shards"%cost); return
 gold-=cost
 t.spent+=cost
 t.level+=1
 t.dmg*=1.38
 t.range+=12.0
 t.rate=max(0.28,t.rate*0.9)
 towers[selected_tower]=t
 _say("Tower upgraded to Lv.%d"%t.level)

func _sell_selected():
 if selected_tower<0 or selected_tower>=towers.size(): return
 gold+=int(towers[selected_tower].spent*0.65)
 towers.remove_at(selected_tower)
 selected_tower=-1
 _say("Tower salvaged")

func _path_distance(p):
 var best=99999.0
 for i in range(PATH.size()-1):
  var a=PATH[i]; var b=PATH[i+1]; var ab=b-a
  var q=a
  if ab.length_squared()>0.0:
   q=a+ab*clamp((p-a).dot(ab)/ab.length_squared(),0.0,1.0)
  best=min(best,p.distance_to(q))
 return best

func _new_game():
 gold=300; lives=20; wave=1
 towers.clear(); enemies.clear(); beams.clear()
 selected_kind="ARC"; selected_tower=-1
 spawn_left=0; wave_active=false; paused=false
 mode="battle"
 _say("Tap a tower card, then place it")

func _say(s):
 banner=s; banner_t=2.2

func _input(e):
 if e is InputEventScreenTouch and e.pressed: _tap(e.position)
 elif e is InputEventMouseButton and e.button_index==MOUSE_BUTTON_LEFT and e.pressed: _tap(e.position)

func _txt(pos,s,size=24,col=Color.WHITE):
 draw_string(ThemeDB.fallback_font,pos,str(s),HORIZONTAL_ALIGNMENT_LEFT,-1,size,col)

func _draw():
 draw_rect(Rect2(0,0,W,H),Color("101827"))
 if mode=="menu":
  _draw_menu(); return
 if mode=="victory" or mode=="defeat":
  _draw_end(); return
 draw_rect(Rect2(0,0,W,90),Color("172239"))
 draw_rect(Rect2(0,600,W,120),Color("121b2d"))
 draw_polyline(PackedVector2Array(PATH),Color("2b3950"),82.0,true)
 draw_polyline(PackedVector2Array(PATH),Color("62708a"),5.0,true)
 for i in range(towers.size()): _draw_tower(i,towers[i])
 for e in enemies: _draw_enemy(e)
 for b in beams: draw_line(b.a,b.b,b.c,5.0,true)
 _txt(Vector2(28,44),"SHARDGUARD  •  FRACTURED SKIES",28,Color("e8f2ff"))
 _txt(Vector2(28,75),"Shards %d    Core %d    Wave %d/10"%[gold,lives,wave],20,Color("9fc5e8"))
 draw_rect(Rect2(1160,18,95,55),Color("263751"),true)
 _txt(Vector2(1181,54),"PAUSE",18)
 var names=["ARC","FROST","RIFT"]
 for i in range(3):
  var k=names[i]; var r=Rect2(25+i*180,625,165,62)
  draw_rect(r,Color("31435f") if selected_kind==k else Color("23324a"),true)
  draw_circle(Vector2(r.position.x+28,r.position.y+31),14,TYPES[k].c)
  _txt(Vector2(r.position.x+52,r.position.y+27),k,18)
  _txt(Vector2(r.position.x+52,r.position.y+50),"%d shards"%TYPES[k].cost,14,Color("aebdd1"))
 if selected_tower>=0 and selected_tower<towers.size():
  var t=towers[selected_tower]
  draw_rect(Rect2(745,625,130,62),Color("4c3445"),true); _txt(Vector2(765,662),"SELL",18)
  draw_rect(Rect2(890,625,135,62),Color("344d42"),true); _txt(Vector2(906,650),"UPGRADE",15); _txt(Vector2(918,672),"%d"%(70*t.level),14)
 elif not wave_active:
  draw_rect(Rect2(1040,625,210,62),Color("4c673c"),true); _txt(Vector2(1067,663),"START WAVE",20)
 if banner_t>0:
  draw_rect(Rect2(390,105,500,48),Color(0.05,0.08,0.13,0.92),true)
  _txt(Vector2(412,137),banner,18,Color("d8e6ff"))
 if paused:
  draw_rect(Rect2(0,0,W,H),Color(0,0,0,0.66),true)
  _txt(Vector2(548,270),"PAUSED",38)
  draw_rect(Rect2(480,330,320,70),Color("36526f"),true); _txt(Vector2(585,374),"RESUME",22)
  draw_rect(Rect2(480,420,320,70),Color("4a3540"),true); _txt(Vector2(565,464),"MAIN MENU",22)

func _draw_tower(i,t):
 var c=TYPES[t.kind].c
 if i==selected_tower: draw_circle(t.pos,t.range,Color(c,0.07))
 draw_circle(t.pos,29,Color("0b111d")); draw_circle(t.pos,23,c)
 draw_circle(t.pos,10,Color("e9f3ff"))
 _txt(t.pos+Vector2(-9,6),str(t.level),15,Color("111827"))

func _draw_enemy(e):
 var c=Color("ff7c6e") if not e.elite else Color("ffc857")
 draw_circle(e.pos,22 if not e.elite else 29,Color("151a25"))
 draw_circle(e.pos,17 if not e.elite else 23,c)
 var ratio=clamp(e.hp/e.max,0.0,1.0)
 draw_rect(Rect2(e.pos+Vector2(-24,-34),Vector2(48,6)),Color("402b36"),true)
 draw_rect(Rect2(e.pos+Vector2(-24,-34),Vector2(48*ratio,6)),Color("72e38f"),true)

func _draw_menu():
 for i in range(9):
  draw_circle(Vector2(100+i*145,120+(i%3)*78),3+(i%2)*2,Color(0.45,0.7,1,0.5))
 _txt(Vector2(355,220),"SHARDGUARD",62,Color("e8f2ff"))
 _txt(Vector2(405,268),"FRACTURED SKIES",31,Color("83b7e6"))
 _txt(Vector2(390,325),"Defend the Aether Core across ten escalating waves.",19,Color("aabbd0"))
 draw_rect(Rect2(470,390,340,88),Color("365e48"),true)
 _txt(Vector2(555,445),"BEGIN RUN",27)
 _txt(Vector2(418,545),"Touch-first Android compatibility build",17,Color("7186a0"))

func _draw_end():
 var win=mode=="victory"
 _txt(Vector2(430,245),"SKYLINE SECURED" if win else "CORE SHATTERED",43,Color("80e2a7") if win else Color("ff8175"))
 _txt(Vector2(438,310),"Ten waves survived." if win else "The fracture consumed the core.",22,Color("b4c5d9"))
 draw_rect(Rect2(470,520,340,76),Color("344d65"),true)
 _txt(Vector2(560,568),"MAIN MENU",22)
