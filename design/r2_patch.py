import re
p='build_mockup.py'; s=open(p).read()
Q="'''"
new_cuts = 'CUTS = ' + Q + '''<svg class="cut" viewBox="0 0 402 270" aria-hidden="true">
  <path d="M30 200 C 22 146, 48 92, 100 70 C 82 108, 72 156, 84 206 C 68 218, 40 218, 30 200 Z" style="fill: var(--deep)"/>
  <path d="M98 66 c 4 -12 14 -18 26 -16" style="fill:none; stroke: var(--cut2); stroke-width: 7; stroke-linecap: round"/>
  <path d="M322 24 a 70 70 0 0 1 70 70 l -70 0 z" style="fill: var(--deep)"/>
  <path d="M322 46 a 48 48 0 0 1 48 48" style="fill:none; stroke: var(--ground); stroke-width: 4"/>
  <path d="M322 68 a 26 26 0 0 1 26 26" style="fill:none; stroke: var(--ground); stroke-width: 4"/>
  <circle cx="54" cy="246" r="13" style="fill: var(--cut2)"/>
  <circle cx="80" cy="254" r="11" style="fill: var(--cut2)"/>
  <circle cx="66" cy="226" r="10" style="fill: var(--cut2)"/>
  <circle cx="370" cy="236" r="12" style="fill: var(--cut2)"/>
  <g transform="translate(330 178) rotate(-20)" style="fill: var(--deep)">
    <circle cx="0" cy="0" r="16"/><circle cx="22" cy="-8" r="14"/><circle cx="18" cy="16" r="13"/>
    <path d="M10 6 L -16 44" style="stroke: var(--deep); stroke-width: 4; stroke-linecap: round"/>
  </g>
</svg>''' + Q
s=re.sub(r"CUTS = '''.*?'''", lambda m: new_cuts, s, flags=re.S)
new_icon = 'ICONSEC = ' + Q + '''<section class="app-icon" data-name="icon">
  <div class="ic">
    <svg viewBox="0 0 1032 1032">
      <rect width="1032" height="1032" fill="#AD321C"/>
      <circle cx="516" cy="540" r="330" fill="#FFF5EC"/>
      <circle cx="430" cy="600" r="70" fill="#C98A1E"/>
      <circle cx="560" cy="650" r="60" fill="#C98A1E"/>
      <circle cx="500" cy="480" r="64" fill="#C98A1E"/>
      <g transform="translate(640 450) rotate(-25)" fill="#4D581C">
        <circle cx="0" cy="0" r="62"/><circle cx="84" cy="-30" r="54"/><circle cx="70" cy="62" r="50"/>
      </g>
      <path d="M740 120 a 210 210 0 0 1 210 210 l -170 0 a 40 40 0 0 1 -40 -40 z" fill="#741A0E"/>
    </svg>
  </div>
</section>''' + Q
s=re.sub(r"ICONSEC = '''.*?'''", lambda m: new_icon, s, flags=re.S)
rep = [
 ('<span>Dinner 3 of 5</span>','<span>Episode 3 of 5</span>'),
 ('''  <div class="strip">{strip}</div>
  {tabbar("week")}''','''  <div class="strip">{strip}</div>
  <div class="nextep"><span class="chip-thu">Next episode</span><span>Thursday · Penne arrabbiata · 25 min</span></div>
  {tabbar("week")}'''),
 ('''f'<div class="dd {s}">''','''f'<div class="dd {s} r-{k}">'''),
 ('<div class="days"><b class="on">M</b><b class="on">T</b><b class="on">W</b><b class="on">T</b><b class="on">F</b><b>S</b><b>S</b></div>',
  '<div class="days"><b class="on g-mon">M</b><b class="on g-tue">T</b><b class="on g-wed">W</b><b class="on g-thu">T</b><b class="on g-fri">F</b><b>S</b><b>S</b></div>'),
 ('<div class="eyebrow">Your first week is ready</div>','<div class="eyebrow">Season one · five episodes · ready</div>'),
 ('    {grow("Olive oil","","Mon to Fri","", have=True)}\n',''),
 ('price="2.0", total="8.1", under="11.2", side="", extra_cls="mid"','price="2.0<i class=roll>5</i>", total="8.<i class=roll>2</i>", under="11.<i class=roll>3</i>", side="", extra_cls="mid"'),
 ('<p class="tnum">40 min · serves 4 · $7.84 · vegetarian</p>','<p class="tnum">40 min · serves 4<br>$7.84 · vegetarian</p>'),
 ('<div class="big serif tnum">$83.40</div>','<div class="bigrow"><div class="big serif tnum">$83.40</div><svg class="mini-cut" viewBox="0 0 90 60" aria-hidden="true"><circle cx="18" cy="38" r="12" style="fill:#C98A1E"/><circle cx="40" cy="46" r="10" style="fill:#C98A1E"/><path d="M50 6 a 36 36 0 0 1 36 36 l -36 0 z" style="fill: var(--accent)"/></svg></div>'),
 ('<div class="big serif tnum">$95</div>','<div class="bigrow"><div class="big serif tnum">$95</div><svg class="mini-cut" viewBox="0 0 90 60" aria-hidden="true"><path d="M10 54 C 6 30, 20 10, 46 2 C 36 20, 32 38, 36 58 C 28 62, 14 62, 10 54 Z" style="fill: var(--accent)"/><circle cx="64" cy="40" r="11" style="fill:#4D581C"/></svg></div>'),
]
for a,b in rep:
    assert a in s, a[:60]
    s=s.replace(a,b)
for d in ["mon","tue","wed","thu","fri"]:
    a=f'<div class="pl"><img src="{{IMG["{d}"]}}"'; assert a in s; s=s.replace(a, f'<div class="pl r-{d}"><img src="{{IMG["{d}"]}}"')
open(p,'w').write(s)
c=open('mockup.css').read()
for a,b in [('.day-wed { --ground:#AD321C; --deep:#741A0E;','.day-wed { --ground:#AD321C; --deep:#741A0E; --cut2:#C98A1E;'),
            ('.day-wed[data-theme="dark"] { --ground:#4A160C; --deep:#2E0B05;','.day-wed[data-theme="dark"] { --ground:#4A160C; --deep:#7A2614; --cut2:#9A6A1A;')]:
    assert a in c; c=c.replace(a,b)
c+=open('r2.css').read()
open('mockup.css','w').write(c)
print("patched")
