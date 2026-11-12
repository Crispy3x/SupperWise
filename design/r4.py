import re
p='build_mockup.py'; s=open(p).read()
def R(a,b):
    global s
    assert a in s, a[:70]; s=s.replace(a,b)
# icon: sprig lower-left, creases
s=re.sub(r'      <circle cx="440" cy="600" r="92" fill="#E9A07F"/>.*?</g>', '''      <circle cx="560" cy="470" r="92" fill="#E9A07F"/>
      <circle cx="660" cy="610" r="86" fill="#E9A07F"/>
      <circle cx="500" cy="620" r="88" fill="#E9A07F"/>
      <path d="M520 430 a 50 50 0 0 1 52 -14" fill="none" stroke="#FFF5EC" stroke-width="10" stroke-linecap="round"/>
      <path d="M622 572 a 48 48 0 0 1 50 -12" fill="none" stroke="#FFF5EC" stroke-width="10" stroke-linecap="round"/>
      <path d="M460 582 a 48 48 0 0 1 50 -12" fill="none" stroke="#FFF5EC" stroke-width="10" stroke-linecap="round"/>
      <g transform="translate(330 700) rotate(200) scale(1.5)" fill="#4D581C">
        <path d="M0 0 C -40 -10, -60 -60, -30 -90 C 0 -70, 10 -30, 0 0 Z"/>
        <path d="M0 0 C 10 -40, 50 -70, 90 -50 C 70 -20, 30 -2, 0 0 Z"/>
        <path d="M0 0 C 40 0, 80 30, 70 70 C 30 66, 6 34, 0 0 Z"/>
        <path d="M0 0 L -40 70" stroke="#4D581C" stroke-width="10" stroke-linecap="round"/>
      </g>''', s, flags=re.S)
# paywall break + tomato CTA
R('<h1 class="serif">Five dinners for <span class="tnum">$83.40</span>, at Hillside Market.</h1>','<h1 class="serif">Five dinners for <span class="tnum">$83.40</span>,<br>at Hillside Market.</h1>')
R('<div class="btn wide dark">Try 7 days free</div>','<div class="btn wide tomato">Try 7 days free</div>')
# plan glyph = onion half
R('<svg class="mini-cut" viewBox="0 0 90 60" aria-hidden="true"><path d="M10 54 C 6 30, 20 10, 46 2 C 36 20, 32 38, 36 58 C 28 62, 14 62, 10 54 Z" style="fill: var(--accent)"/><circle cx="64" cy="40" r="11" style="fill:#E07A5C"/></svg>',
  '<svg class="mini-cut" viewBox="0 0 90 60" aria-hidden="true"><path d="M30 58 a 52 52 0 0 1 52 -52 l 0 52 z" style="fill: var(--accent)"/><path d="M46 58 a 36 36 0 0 1 36 -36" style="fill:none; stroke: var(--ground); stroke-width: 3"/><path d="M62 58 a 20 20 0 0 1 20 -20" style="fill:none; stroke: var(--ground); stroke-width: 3"/><circle cx="12" cy="48" r="9" style="fill:#E07A5C"/></svg>')
# groceries: a row passing under the glass
R('''    {grow("Garam masala","2 oz jar","Wed","3.49", note="You use 1 tbsp. The jar lasts about 9 more dinners.")}''',
  '''    {grow("Garam masala","2 oz jar","Wed","3.49", note="You use 1 tbsp. The jar lasts about 9 more dinners.")}
    {grow("Crushed tomatoes","28 oz can","Wed","1.89")}''')
# spin: sliver of new dish
R('''plate = (f'<div class="plate spinning"><img src="{IMG["wed"]}" alt=""><span class="smear"></span></div>')''',
  '''plate = (f'<div class="plate spinning"><img src="{IMG["wed"]}" alt=""><img class="sliver" src="{IMG["swap"]}" alt=""><span class="smear"></span></div>')''')
open(p,'w').write(s); print("ok")
