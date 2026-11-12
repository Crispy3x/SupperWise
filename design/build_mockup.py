# Generates mockup.html for Supperwise. Run: python3 build_mockup.py
IMG = {
    "mon": "img/1590412200988-a436970781fa.jpg",
    "tue": "img/1529042410759-befb1204b468.jpg",
    "wed": "img/1588166524941-3bf61a9c41db.jpg",
    "thu": "img/1621996346565-e3dbc646d9a9.jpg",
    "fri": "img/1598103442097-8b74394b95c6.jpg",
    "swap": "img/1617093727343-374698b1b08d.jpg",
}

ICON = {
    "week": '<svg class="icon" viewBox="0 0 24 24"><rect x="4" y="5" width="16" height="15" rx="3"/><path d="M4 10h16M9 3v4M15 3v4"/></svg>',
    "groc": '<svg class="icon" viewBox="0 0 24 24"><path d="M4 6h2l2 10h10l2-7H7.5"/><circle cx="10" cy="19.5" r="1.2"/><circle cx="17" cy="19.5" r="1.2"/></svg>',
    "kit": '<svg class="icon" viewBox="0 0 24 24"><rect x="5" y="3" width="14" height="18" rx="2.5"/><path d="M5 10h14M9 6.5v1.5M9 13v3"/></svg>',
    "swap": '<svg class="icon sm" viewBox="0 0 24 24"><path d="M20 8a8 8 0 0 0-14.5-2M4 4v4h4M4 16a8 8 0 0 0 14.5 2M20 20v-4h-4"/></svg>',
    "share": '<svg class="icon" viewBox="0 0 24 24"><path d="M12 15V3M8 7l4-4 4 4M6 11H5v10h14V11h-1"/></svg>',
    "back": '<svg class="icon" viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7"/></svg>',
    "check": '<svg class="icon xs" viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',
    "info": '<svg class="icon xs" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8v.01"/></svg>',
}

def tabbar(on="week"):
    t = lambda k, label, ic: f'<div class="t{" on" if on==k else ""}">{ICON[ic]}{label}</div>'
    return f'<nav class="tabbar glass" data-float>{t("week","Week","week")}{t("groc","Groceries","groc")}{t("kit","Kitchen","kit")}</nav>'

CUTS = '''<svg class="cut" viewBox="0 0 402 270" aria-hidden="true">
  <path d="M8 190 C 0 136, 26 82, 78 60 C 60 98, 50 146, 62 196 C 46 208, 18 208, 8 190 Z" style="fill: var(--deep)"/>
  <path d="M76 56 c 4 -12 14 -18 26 -16" style="fill:none; stroke: var(--cut2); stroke-width: 7; stroke-linecap: round"/>
  <path d="M322 24 a 70 70 0 0 1 70 70 l -70 0 z" style="fill: var(--deep)"/>
  <path d="M322 46 a 48 48 0 0 1 48 48" style="fill:none; stroke: var(--ground); stroke-width: 4"/>
  <path d="M322 68 a 26 26 0 0 1 26 26" style="fill:none; stroke: var(--ground); stroke-width: 4"/>
  <circle cx="54" cy="246" r="13" style="fill: var(--cut2)"/>
  <circle cx="80" cy="254" r="11" style="fill: var(--cut2)"/>
  <circle cx="66" cy="226" r="10" style="fill: var(--cut2)"/>
  <circle cx="370" cy="236" r="12" style="fill: var(--cut2)"/>
  <g transform="translate(354 176) rotate(-20)" style="fill: var(--deep)">
    <circle cx="0" cy="0" r="16"/><circle cx="22" cy="-8" r="14"/><circle cx="18" cy="16" r="13"/>
    <path d="M10 6 L -16 44" style="stroke: var(--deep); stroke-width: 4; stroke-linecap: round"/>
  </g>
</svg>'''

STRIP_DAYS = [("M", "mon", "done"), ("T", "tue", "done"), ("W", "wed", "now"), ("T", "thu", ""), ("F", "fri", "")]

def today(name="today", theme="", freeze="", spin="", title="Chickpea tikka masala",
          price="1.96", total="7.84", under="11.60", side="Basmati and charred red onion on the side.",
          mins="40 minutes", img="wed", extra_cls="", mini=False, day="wed", dayname="Wednesday", ep="3", nextep=("Next episode","Thu · Penne arrabbiata, 25 min"), strip_days=None):
    strip = "".join(
        f'<div class="dd {s} r-{k}"><div class="o"><img src="{IMG[k]}" alt="">{"<span class=tick>"+ICON["check"]+"</span>" if s=="done" else ""}</div><span>{d}</span></div>'
        for d, k, s in (strip_days or STRIP_DAYS))
    tag = "div" if mini else "section"
    cls = "mini-screen" if mini else "screen"
    attrs = f'data-name="{name}" ' if not mini else ""
    th = f' data-theme="{theme}"' if theme else ""
    fr = f' data-freeze="{freeze}"' if freeze else ""
    plate = f'<div class="plate {spin}"><img src="{IMG[img]}" alt="{title}"></div>'
    if spin == "spinning":
        plate = (f'<div class="plate spinning"><img src="{IMG["wed"]}" alt=""><img class="sliver" src="{IMG["swap"]}" alt=""><span class="smear"></span></div>')
    return f'''<{tag} class="{cls} day-{day} {extra_cls}" {attrs}data-chrome="light" data-time="17:42"{th}{fr}>
  <div class="top"><span>Episode {ep} of 5</span><span class="tnum">${under} under budget</span></div>
  <div class="dayname serif">{dayname}</div>
  <div class="stage">{CUTS}{plate}</div>
  <div class="ep">
    <div class="k">Tonight · {mins}</div>
    <h1 class="serif">{title}</h1>
    <p><b class="tnum">${total}</b> feeds all four, <span class="tnum">${price}</span> a plate. {side}</p>
  </div>
  <div class="row2">
    <div class="btn">Start cooking</div>
    <div class="btn ghost">{ICON["swap"]}Swap</div>
  </div>
  <div class="strip">{strip}</div>
  {"" if nextep is None else f'<div class="nextep"><span class="chip-thu">{nextep[0]}</span><span>{nextep[1]}</span></div>'}
  {tabbar("week")}
</{tag}>'''

RECIPE = f'''<section class="screen day-wed recipe" data-name="recipe" data-chrome="light" data-home="dark" data-time="17:44">
  <div class="rhead">
    <div class="navbtn glass">{ICON["back"]}</div>
    <div class="rplate"><img src="{IMG["wed"]}" alt="Chickpea tikka masala"></div>
    <h1 class="serif">Chickpea tikka masala</h1>
    <p class="tnum">40 min · serves 4<br>$7.84 · vegetarian</p>
  </div>
  <div class="sheet" data-scrolls>
    <div class="servings"><span>Servings</span><div class="stepper"><b>–</b><span class="tnum">4</span><b>+</b></div></div>
    <h2>You'll need</h2>
    <ul class="ing">
      <li><span class="q tnum">2 cans</span><span>chickpeas, 15 oz, drained</span></li>
      <li><span class="q tnum">1 can</span><span>crushed tomatoes, 28 oz</span></li>
      <li><span class="q tnum">¾ cup</span><span>plain whole-milk yogurt</span></li>
      <li><span class="q tnum">1</span><span>red onion, halved</span></li>
      <li><span class="q tnum">4 cloves</span><span>garlic, finely grated</span></li>
      <li><span class="q tnum">1 tbsp</span><span>garam masala</span></li>
      <li><span class="q tnum">1½ cups</span><span>basmati rice, rinsed twice</span></li>
    </ul>
    <h2>Step 1 of 6</h2>
    <p class="step">Cut one onion half into 8 thin wedges for charring. Finely dice the other half. Keep them apart.</p>
  </div>
  <div class="bottombar" data-float><div class="btn wide">Start step 1</div></div>
</section>'''

def grow(name, pack, used, price, done=False, have=False, note=""):
    c = " done" if done else ""
    p = f'<span class="have">You have it</span>' if have else f'<span class="pr tnum">${price}</span>'
    n = f'<span class="note">{note}</span>' if note else ""
    return f'<div class="gi{c}"><span class="box">{ICON["check"] if done else ""}</span><div class="gt"><span class="gn">{name}</span><span class="gm">{pack} · {used}</span>{n}</div>{p}</div>'

GROCERIES = f'''<section class="screen paper groceries" data-name="groceries" data-time="17:46">
  <div class="phead"><h1 class="serif">Groceries</h1><div class="navbtn plain">{ICON["share"]}</div></div>
  <div class="total">
    <div class="bigrow"><div class="big serif tnum">$83.40</div><svg class="mini-cut" viewBox="0 0 90 60" aria-hidden="true"><path d="M30 58 a 52 52 0 0 1 52 -52 l 0 52 z" style="fill: var(--accent)"/><path d="M46 58 a 36 36 0 0 1 36 -36" style="fill:none; stroke: var(--ground); stroke-width: 3"/><path d="M62 58 a 20 20 0 0 1 20 -20" style="fill:none; stroke: var(--ground); stroke-width: 3"/><circle cx="12" cy="48" r="9" style="fill:#E07A5C"/></svg></div>
    <p>of $95 at Hillside Market, Cincinnati. Priced by the pack you buy, not the spoonful you use.</p>
    <div class="how">{ICON["info"]}How we price this</div>
  </div>
  <div class="glist" data-scrolls>
    <h3><span class="hl serif"><svg class="hglyph" viewBox="0 0 24 24" aria-hidden="true"><path d="M2 20 a 18 18 0 0 1 18 -18 l 0 18 z" style="fill: var(--accent)"/><path d="M8 20 a 12 12 0 0 1 12 -12" style="fill:none; stroke: var(--ground); stroke-width: 1.6"/><path d="M14 20 a 6 6 0 0 1 6 -6" style="fill:none; stroke: var(--ground); stroke-width: 1.6"/></svg>Produce</span><span class="tnum">$11.86</span></h3>
    {grow("Red onions","3 lb bag","Wed, Thu","2.99",done=True)}
    {grow("Cilantro","1 bunch","Wed","0.99", note="Half left over. It keeps 5 days in a jar of water.")}
    <h3><span class="hl serif"><svg class="hglyph" viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="3" width="14" height="18" rx="3" style="fill: var(--accent)"/><path d="M5 8h14M5 16h14" style="stroke: var(--ground); stroke-width: 1.6"/></svg>Cans and jars</span><span class="tnum">$9.02</span></h3>
    {grow("Chickpeas","2 × 15 oz cans","Wed","1.78")}
    {grow("Garam masala","2 oz jar","Wed","3.49", note="You use 1 tbsp. The jar lasts about 9 more dinners.")}
    {grow("Crushed tomatoes","28 oz can","Wed","1.89")}
  </div>
  {tabbar("groc")}
</section>'''

def person(n, tags, age=""):
    a = f'<span class="age">{age}</span>' if age else ""
    t = "".join(f'<span class="chip">{x}</span>' for x in tags) if tags else '<span class="chip quiet">Eats everything</span>'
    return f'<div class="pp"><div class="pn">{n}{a}</div><div class="chips">{t}</div></div>'

PLAN = f'''<section class="screen paper plan" data-name="plan" data-time="17:50">
  <div class="phead"><h1 class="serif">Next week</h1><span class="dates">Nov 16 to 20</span></div>
  <div class="budget">
    <div class="lbl">Grocery budget</div>
    <div class="bigrow"><div class="big serif tnum">$95</div><svg class="mini-cut" viewBox="0 0 90 60" aria-hidden="true"><path d="M30 58 a 52 52 0 0 1 52 -52 l 0 52 z" style="fill: var(--accent)"/><path d="M46 58 a 36 36 0 0 1 36 -36" style="fill:none; stroke: var(--ground); stroke-width: 3"/><path d="M62 58 a 20 20 0 0 1 20 -20" style="fill:none; stroke: var(--ground); stroke-width: 3"/><circle cx="12" cy="48" r="9" style="fill:#E07A5C"/></svg></div>
    <div class="slider"><div class="fill"></div><div class="knob"></div></div>
    <p>Last week came to $83.40.</p>
  </div>
  <div class="nights">
    <div class="lbl">Cook nights</div>
    <div class="days"><b class="on g-mon">M</b><b class="on g-tue">T</b><b class="on g-wed">W</b><b class="on g-thu">T</b><b class="on g-fri">F</b><b>S</b><b>S</b></div>
  </div>
  <div class="people">
    <div class="lbl">Who's eating</div>
    {person("Dana", ["Vegetarian"])}
    {person("Marcus", ["No shellfish"])}
    {person("Ari", ["Not spicy"], "7")}
    {person("June", [], "4")}
    <p class="rule-note">Every dinner works for all four. Dana's plate gets the vegetarian version when the dish has meat.</p>
  </div>
  <div class="equip">
    <div class="lbl">Your kitchen</div>
    <div class="chips2"><span class="chip on">Oven</span><span class="chip on">Stovetop</span><span class="chip on">Sheet pan</span><span class="chip off">Air fryer</span><span class="chip off">Grill</span></div>
  </div>
  <div class="planbtn"><div class="btn wide">Plan next week</div></div>
  {tabbar("week")}
</section>'''

PAYWALL = f'''<section class="screen paper paywall" data-name="first-week" data-time="19:05">
  <div class="pw-top">
    <div class="eyebrow">Season one · five episodes · ready</div>
    <h1 class="serif">Five dinners for <span class="tnum">$83.40</span>,<br>at Hillside Market.</h1>
  </div>
  <div class="band"><svg class="bandcut" viewBox="0 0 402 150" aria-hidden="true"><path d="M318 4 a 56 56 0 0 1 56 56 l -56 0 z" style="fill:#741A0E"/><path d="M318 22 a 38 38 0 0 1 38 38" style="fill:none; stroke:#AD321C; stroke-width:3"/><circle cx="16" cy="18" r="9" style="fill:#E07A5C"/><circle cx="34" cy="12" r="7" style="fill:#E07A5C"/><circle cx="28" cy="30" r="6" style="fill:#E07A5C"/></svg>
  <div class="plates">
    <div class="pl r-mon"><img src="{IMG["mon"]}" alt=""><span>Mon</span></div>
    <div class="pl r-tue"><img src="{IMG["tue"]}" alt=""><span>Tue</span></div>
    <div class="pl r-wed"><img src="{IMG["wed"]}" alt=""><span>Wed</span></div>
    <div class="pl r-thu"><img src="{IMG["thu"]}" alt=""><span>Thu</span></div>
    <div class="pl r-fri"><img src="{IMG["fri"]}" alt=""><span>Fri</span></div>
  </div></div>
  <p class="keep">This week's plan and list are yours to keep, whether you subscribe or not.</p>
  <ul class="gets">
    <li><b>A new week every Sunday</b>, priced at your store before you shop.</li>
    <li><b>Swap any night</b> and the list reprices by the pack.</li>
    <li><b>Everyone's rules on every plate</b>: Dana, Marcus, Ari and June.</li>
  </ul>
  <div class="offer push">
    <div class="opt on"><div><b>Yearly</b><span>7 days free, then $29.99 a year</span></div><span class="per tnum">$2.50/mo</span></div>
    <div class="opt"><div><b>Monthly</b><span>$7.99 a month, no trial</span></div></div>
  </div>
  <div class="btn wide tomato">Try 7 days free</div>
  <p class="fine">We'll remind you 2 days before the trial ends. Cancel in Settings any time before then and you won't be charged.</p>
  <div class="links"><span>Keep my free week</span><span>Restore</span><span>Terms</span></div>
</section>'''

STORY = f'''<section class="screen board" data-name="signature-spin" data-chrome="none">
  <div class="board-head">
    <div class="eyebrow">Signature</div>
    <h1 class="serif">Spin the plate</h1>
    <p>Swap turns tonight's plate like a lazy Susan. The price rolls with it.</p>
  </div>
  <div class="frames">
    <figure><div class="mini" style="--mini:.36">{today(mini=True, extra_cls="press")}</div><figcaption><b>0 ms</b> Tap Swap. Light haptic.</figcaption></figure>
    <figure><div class="mini" style="--mini:.36">{today(mini=True, spin="spinning", price="<span class=rd><span>1.96</span><span>2.14</span></span>", total="<span class=rd><span>7.84</span><span>8.56</span></span>", under="<span class=rd><span>11.60</span><span>10.88</span></span>", extra_cls="mid")}</div><figcaption><b>260 ms</b> Old dish spins out, new one in. Digits roll.</figcaption></figure>
  </div>
  <div class="frames one">
    <figure><div class="mini" style="--mini:.36">{today(mini=True, img="swap", title="Red curry noodle soup", price="2.14", total="8.56", under="10.88", side="Rice noodles, lime and Thai basil.", mins="35 minutes")}</div><figcaption><b>520 ms</b> Settles, no bounce. Success haptic. Budget now $10.88 under.</figcaption></figure>
  </div>
</section>'''

ICONSEC = '''<section class="app-icon" data-name="icon">
  <div class="ic">
    <svg viewBox="0 0 1032 1032">
      <rect width="1032" height="1032" fill="#AD321C"/>
      <circle cx="516" cy="540" r="330" fill="#FFF5EC"/>
      <circle cx="560" cy="470" r="92" fill="#E9A07F"/>
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
      </g>
      <path d="M740 120 a 210 210 0 0 1 210 210 l -170 0 a 40 40 0 0 1 -40 -40 z" fill="#741A0E"/>
    </svg>
  </div>
</section>'''

CSS = open("mockup.css").read()

html = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Supperwise · screens</title>
<link rel="stylesheet" href="fonts.css"><link rel="stylesheet" href="device.css">
<style>{CSS}</style></head><body>
{today()}
{RECIPE}
{GROCERIES}
{PLAN}
{STORY}
{today(name="today-dark", theme="dark")}
{today(name="today-fri", day="fri", dayname="Friday", ep="5", img="fri", title="Lemon-thyme skillet chicken", price="2.88", total="11.52", under="11.60", side="Crispy potatoes in the same pan.", mins="55 minutes", nextep=None, strip_days=[("M","mon","done"),("T","tue","done"),("W","wed","done"),("T","thu","done"),("F","fri","now")])}
{PAYWALL}
{ICONSEC}
<script src="device.js"></script>
</body></html>'''
open("mockup.html", "w").write(html)
print("wrote mockup.html")
