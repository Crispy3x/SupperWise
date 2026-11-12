p='build_mockup.py'; s=open(p).read()
def R(a,b):
    global s
    assert a in s, a[:70]; s=s.replace(a,b)
R('    {grow("Broccoli crowns","about 1¼ lb","Thu","2.47")}\n','')
R('''  <p class="keep">This week's plan and list are yours to keep, whether you subscribe or not.</p>''',
'''  <p class="keep">This week's plan and list are yours to keep, whether you subscribe or not.</p>
  <ul class="gets">
    <li><b>A new week every Sunday</b>, priced at your store before you shop.</li>
    <li><b>Swap any night</b> and the list reprices by the pack.</li>
    <li><b>Everyone's rules on every plate</b>: Dana, Marcus, Ari and June.</li>
  </ul>''')
R('<g transform="translate(700 390) rotate(-30)" fill="#4D581C">','<g transform="translate(690 420) rotate(-30) scale(1.9)" fill="#4D581C">')
R('<path d="M0 0 L -50 90" stroke="#4D581C" stroke-width="16" stroke-linecap="round"/>','<path d="M0 0 L -40 70" stroke="#4D581C" stroke-width="10" stroke-linecap="round"/>')
open(p,'w').write(s)
