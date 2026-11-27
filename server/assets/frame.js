// Ridgeline Ops widget pages (/embed/*): tell the website around the frame how tall the page is, so it fits without scrollbars.
// Sends only a number. The website's embed.js checks that the message comes from this server and from its own frame.
(function () {
  if (window.parent === window) return;
  var main = document.querySelector('main');
  if (!main) return;
  var last = -1;
  function send() {
    var h = Math.ceil(main.getBoundingClientRect().height);
    if (h === last || !isFinite(h)) return;
    last = h;
    try { window.parent.postMessage({ ridgeline: 'height', height: h }, '*'); } catch (e) { /* the frame keeps its size */ }
  }
  if (window.ResizeObserver) new ResizeObserver(send).observe(main);
  else setInterval(send, 1000);
  window.addEventListener('load', send);
  send();
})();
