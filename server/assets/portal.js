// Ridgeline Ops client page: shows the truck on a map and keeps the page fresh without a reload.
// Everything from the server is shown with textContent, never as HTML.
(function () {
  var el = document.getElementById('live');
  if (!el) return;
  var data;
  try { data = JSON.parse(el.textContent); } catch (e) { return; }
  var token = document.body.getAttribute('data-token');
  var L = window.L;
  var map = null, siteMarker = null, trucks = [];

  function text(id, value) { var n = document.getElementById(id); if (n) n.textContent = value || ''; }
  function show(id, on) { var n = document.getElementById(id); if (n) n.style.display = on ? '' : 'none'; }

  function ensureMap(d) {
    if (map || !L || !d.site || !document.getElementById('map')) return;
    map = L.map('map', { zoomControl: true, attributionControl: true }).setView([d.site.latitude, d.site.longitude], 15);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19, attribution: '&copy; OpenStreetMap contributors', referrerPolicy: 'origin'
    }).addTo(map);
    siteMarker = L.marker([d.site.latitude, d.site.longitude], {
      icon: L.divIcon({ className: 'pin', html: '<span class="pin-site"></span>', iconSize: [18, 18] }), title: 'Your property'
    }).addTo(map);
  }

  function render(d) {
    text('status', d.statusText);
    // The colour follows the status too, so a visit that was just finished turns green without a reload.
    var pill = document.getElementById('status');
    if (pill) pill.className = 'status' + (d.status === 'done' ? ' done' : d.status === 'skipped' ? ' skipped' : '');
    if (d.updatedAt) { var when = new Date(d.updatedAt); if (!isNaN(when.getTime())) text('updated', when.toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' })); }
    text('eta', d.eta || '');
    text('etalabel', d.eta ? 'Estimated arrival' : '');
    show('eta', !!d.eta);
    show('etalabel', !!d.eta);
    text('ahead', typeof d.stopsAhead === 'number' && d.status === 'planned'
      ? (d.stopsAhead === 0 ? 'You are next.' : d.stopsAhead + (d.stopsAhead === 1 ? ' stop' : ' stops') + ' before yours.') : '');
    if (d.weather) { text('wxsummary', d.weather.summary); text('wxalerts', (d.weather.alerts || []).join(' · ')); }
    ensureMap(d);
    if (!map || !d.site) return;
    trucks.forEach(function (m) { map.removeLayer(m); });
    trucks = (d.trucks || []).map(function (t) {
      return L.marker([t.latitude, t.longitude], {
        icon: L.divIcon({ className: 'pin', html: '<span class="pin-truck">🚚</span>', iconSize: [26, 26] }), title: t.label
      }).addTo(map);
    });
    // A position that has not been refreshed for a while is said to be old, not shown as if it were live.
    var oldest = (d.trucks || []).reduce(function (m, t) { return Math.max(m, t.ageSeconds || 0); }, 0);
    var seen = oldest >= 90 ? ' Last seen about ' + Math.round(oldest / 60) + ' min ago.' : '';
    text('mapnote', trucks.length ? (d.trucks.length === 1 ? d.trucks[0].label : d.trucks.length + ' trucks') + ' on the map. Positions are approximate.' + seen
      : (d.status === 'planned' ? 'The truck shows here once it is on its way to you.' : ''));
    var pts = [[d.site.latitude, d.site.longitude]].concat((d.trucks || []).map(function (t) { return [t.latitude, t.longitude]; }));
    if (pts.length > 1) map.fitBounds(pts, { padding: [30, 30], maxZoom: 16 });
  }

  function poll() {
    if (document.hidden) return;
    fetch('/c/' + token + '/live.json', { cache: 'no-store' }).then(function (r) { return r.ok ? r.json() : null; })
      .then(function (d) { if (d) { data = d; render(d); } }).catch(function () { /* keep what is shown */ });
  }

  render(data);
  setInterval(poll, 20000);
  document.addEventListener('visibilitychange', function () { if (!document.hidden) poll(); });
})();
