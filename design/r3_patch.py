p='build_mockup.py'; s=open(p).read()
def R(a,b):
    global s
    assert a in s, a[:70]; s=s.replace(a,b)
# 5. move chilli + cilantro outward
R('<path d="M30 200 C 22 146, 48 92, 100 70 C 82 108, 72 156, 84 206 C 68 218, 40 218, 30 200 Z"','<path d="M8 190 C 0 136, 26 82, 78 60 C 60 98, 50 146, 62 196 C 46 208, 18 208, 8 190 Z"')
R('<path d="M98 66 c 4 -12 14 -18 26 -16"','<path d="M76 56 c 4 -12 14 -18 26 -16"')
R('<g transform="translate(330 178) rotate(-20)"','<g transform="translate(354 176) rotate(-20)"')
# 3. spin mid frame
R('''plate = (f'<div class="plate spinning"><img class="out" src="{IMG["wed"]}" alt=""><img class="in" src="{IMG["swap"]}" alt=""></div>')''',
  '''plate = (f'<div class="plate spinning"><img src="{IMG["wed"]}" alt=""><span class="smear"></span></div>')''')
RD=lambda a,b: f'<span class=rd><span>{a}</span><span>{b}</span></span>'
R('title="", price="2.0<i class=roll>5</i>", total="8.<i class=roll>2</i>", under="11.<i class=roll>3</i>", side="", extra_cls="mid"',
  'price="'+RD("1.96","2.14").replace('"',"'")+'", total="'+RD("7.84","8.56").replace('"',"'")+'", under="'+RD("11.60","10.88").replace('"',"'")+'", extra_cls="mid"')
# 2. groceries serif headers + onion glyph
ON='<svg class="hglyph" viewBox="0 0 24 24" aria-hidden="true"><path d="M2 20 a 18 18 0 0 1 18 -18 l 0 18 z" style="fill: var(--accent)"/><path d="M8 20 a 12 12 0 0 1 12 -12" style="fill:none; stroke: var(--ground); stroke-width: 1.6"/><path d="M14 20 a 6 6 0 0 1 6 -6" style="fill:none; stroke: var(--ground); stroke-width: 1.6"/></svg>'
CAN='<svg class="hglyph" viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="3" width="14" height="18" rx="3" style="fill: var(--accent)"/><path d="M5 8h14M5 16h14" style="stroke: var(--ground); stroke-width: 1.6"/></svg>'
R('<h3>Produce <span class="tnum">$11.86</span></h3>', f'<h3><span class="hl serif">{ON}Produce</span><span class="tnum">$11.86</span></h3>')
R('<h3>Cans and jars <span class="tnum">$9.02</span></h3>', f'<h3><span class="hl serif">{CAN}Cans and jars</span><span class="tnum">$9.02</span></h3>')
R('<svg class="mini-cut" viewBox="0 0 90 60" aria-hidden="true"><circle cx="18" cy="38" r="12" style="fill:#E07A5C"/><circle cx="40" cy="46" r="10" style="fill:#E07A5C"/><path d="M50 6 a 36 36 0 0 1 36 36 l -36 0 z" style="fill: var(--accent)"/></svg>',
  '<svg class="mini-cut" viewBox="0 0 90 60" aria-hidden="true"><path d="M30 58 a 52 52 0 0 1 52 -52 l 0 52 z" style="fill: var(--accent)"/><path d="M46 58 a 36 36 0 0 1 36 -36" style="fill:none; stroke: var(--ground); stroke-width: 3"/><path d="M62 58 a 20 20 0 0 1 20 -20" style="fill:none; stroke: var(--ground); stroke-width: 3"/><circle cx="12" cy="48" r="9" style="fill:#E07A5C"/></svg>')
R('    {grow("Lemons","2 count","Fri","1.18")}\n','')
# 1. paywall band + shapes, push CTA down
R('''  <div class="plates">
    <div class="pl r-mon">''','''  <div class="band"><svg class="bandcut" viewBox="0 0 402 150" aria-hidden="true"><path d="M318 4 a 56 56 0 0 1 56 56 l -56 0 z" style="fill:#741A0E"/><path d="M318 22 a 38 38 0 0 1 38 38" style="fill:none; stroke:#AD321C; stroke-width:3"/><circle cx="34" cy="128" r="10" style="fill:#E07A5C"/><circle cx="54" cy="136" r="8" style="fill:#E07A5C"/><circle cx="44" cy="114" r="7" style="fill:#E07A5C"/></svg>
  <div class="plates">
    <div class="pl r-mon">''')
R('''    <div class="pl r-fri"><img src="{IMG["fri"]}" alt=""><span>Fri</span></div>
  </div>''','''    <div class="pl r-fri"><img src="{IMG["fri"]}" alt=""><span>Fri</span></div>
  </div></div>''')
R('<div class="offer">','<div class="offer push">')
# icon
R('''      <circle cx="430" cy="600" r="70" fill="#E9A07F"/>
      <circle cx="560" cy="650" r="60" fill="#E9A07F"/>
      <circle cx="500" cy="480" r="64" fill="#E9A07F"/>
      <g transform="translate(640 450) rotate(-25)" fill="#4D581C">
        <circle cx="0" cy="0" r="62"/><circle cx="84" cy="-30" r="54"/><circle cx="70" cy="62" r="50"/>
      </g>''','''      <circle cx="440" cy="600" r="92" fill="#E9A07F"/>
      <circle cx="600" cy="610" r="84" fill="#E9A07F"/>
      <circle cx="520" cy="470" r="88" fill="#E9A07F"/>
      <g transform="translate(700 390) rotate(-30)" fill="#4D581C">
        <path d="M0 0 C -40 -10, -60 -60, -30 -90 C 0 -70, 10 -30, 0 0 Z"/>
        <path d="M0 0 C 10 -40, 50 -70, 90 -50 C 70 -20, 30 -2, 0 0 Z"/>
        <path d="M0 0 C 40 0, 80 30, 70 70 C 30 66, 6 34, 0 0 Z"/>
        <path d="M0 0 L -50 90" stroke="#4D581C" stroke-width="16" stroke-linecap="round"/>
      </g>''')
open(p,'w').write(s); print("ok")
