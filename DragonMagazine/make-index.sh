#!/usr/bin/env bash
# Build index.html: a browsable cover gallery of the PDFs in the files/ subdirectory.
# Each files/<name>.pdf is expected to have <name>.png (cover) and <name>-sn.png (thumbnail) next to it.
# Re-run after adding/removing files. The page uses relative links, so the whole folder can be
# copied anywhere and opened directly (file://) in a browser.

set -euo pipefail
cd "$(dirname "$0")"

# JS array of basenames, from the PDFs actually present.
list=$(cd files && ls *.pdf | sed 's/\.pdf$//' | sort | sed 's/.*/"&"/' | paste -sd, -)

cat > index.html <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Dragon Magazine Archive</title>
<style>
  :root {
    --bg: #f6f3ee; --fg: #2a2522; --muted: #7a6f66; --card: #fff; --border: #e2dbd2;
    --accent: #9b2c1f; --shadow: 0 2px 8px rgba(0,0,0,.12); --overlay: rgba(20,16,14,.85);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #17140f; --fg: #ece5da; --muted: #a0958a; --card: #221e18; --border: #3a332a;
      --accent: #e0735e; --shadow: 0 2px 10px rgba(0,0,0,.5); --overlay: rgba(0,0,0,.88);
    }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--fg);
         font: 15px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  header { position: sticky; top: 0; z-index: 5; background: var(--bg); border-bottom: 1px solid var(--border);
           padding: 12px 16px; display: flex; gap: 16px; align-items: center; flex-wrap: wrap; }
  h1 { font-size: 20px; margin: 0; }
  header input { padding: 6px 10px; border: 1px solid var(--border); border-radius: 6px;
                 background: var(--card); color: var(--fg); font: inherit; width: 220px; max-width: 100%; }
  .count { color: var(--muted); font-size: 13px; }
  main { padding: 8px 16px 40px; }
  h2 { font-size: 16px; margin: 24px 0 10px; color: var(--accent); }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(112px, 1fr)); gap: 14px; }
  .item { background: none; border: 0; padding: 0; cursor: pointer; color: inherit; font: inherit;
          text-align: center; }
  .item img { width: 100%; aspect-ratio: 99 / 128; object-fit: cover; display: block; border-radius: 4px;
              background: var(--card); box-shadow: var(--shadow); transition: transform .12s; }
  .item:hover img, .item:focus-visible img { transform: translateY(-2px); outline: 2px solid var(--accent); }
  .item span { display: block; margin-top: 6px; font-size: 13px; }
  .hidden { display: none !important; }

  /* Hover preview */
  #preview { position: fixed; z-index: 10; pointer-events: none; display: none;
             background: var(--card); padding: 4px; border-radius: 6px; box-shadow: 0 8px 30px rgba(0,0,0,.4); }
  #preview img { display: block; max-height: 70vh; max-width: 40vw; }

  /* Click lightbox */
  #lightbox { position: fixed; inset: 0; z-index: 20; background: var(--overlay); display: none;
              align-items: center; justify-content: center; padding: 16px; }
  #lightbox.open { display: flex; }
  #lightbox figure { margin: 0; display: flex; flex-direction: column; align-items: center; gap: 12px;
                     max-height: 100%; }
  #lightbox img { max-height: calc(100vh - 110px); max-width: calc(100vw - 32px); border-radius: 4px; }
  #lightbox figcaption { color: #fff; display: flex; gap: 16px; align-items: center; flex-wrap: wrap;
                         justify-content: center; }
  #lightbox .title { font-size: 17px; font-weight: 600; }
  #lightbox a.pdf { background: var(--accent); color: #fff; padding: 7px 14px; border-radius: 6px;
                    text-decoration: none; font-weight: 600; }
  #lightbox .nav { background: none; border: 1px solid #fff6; color: #fff; border-radius: 6px;
                   padding: 6px 12px; cursor: pointer; font: inherit; }
  #lightbox .hint { color: #fffa; font-size: 12px; }
</style>
</head>
<body>
<header>
  <h1>Dragon Magazine Archive</h1>
  <input id="filter" type="search" placeholder="Filter, e.g. 42 or review" autocomplete="off">
  <span class="count" id="count"></span>
</header>
<main id="main"></main>

<div id="preview"><img alt=""></div>

<div id="lightbox" role="dialog" aria-modal="true">
  <figure>
    <img alt="">
    <figcaption>
      <button class="nav" id="prev" aria-label="Previous">&larr;</button>
      <span class="title"></span>
      <a class="pdf" target="_blank" rel="noopener">Open PDF</a>
      <button class="nav" id="next" aria-label="Next">&rarr;</button>
      <span class="hint">Esc to close &middot; arrow keys to browse</span>
    </figcaption>
  </figure>
</div>

<script>
const FILES = [$list];
const DIR = "files/";

// Turn a file basename into a readable title.
function titleOf(name) {
  let m = name.match(/^Drmg(\d+)$/);
  if (m) return "Dragon #" + parseInt(m[1], 10);
  m = name.match(/^Strv(\d)(\d\d)$/);
  if (m) return "Strategic Review Vol " + m[1] + " #" + parseInt(m[2], 10);
  return name;
}
function sectionOf(name) {
  if (name.startsWith("Strv")) return "The Strategic Review";
  if (name.startsWith("Drmg")) return "Dragon";
  return "Other";
}

const ORDER = ["The Strategic Review", "Dragon", "Other"];
const items = FILES.map(name => ({ name, title: titleOf(name), section: sectionOf(name) }));
const main = document.getElementById("main");
const sections = {};

for (const sec of ORDER) {
  const list = items.filter(i => i.section === sec);
  if (!list.length) continue;
  const wrap = document.createElement("section");
  wrap.innerHTML = "<h2></h2><div class=grid></div>";
  wrap.querySelector("h2").textContent = sec;
  const grid = wrap.querySelector(".grid");
  for (const it of list) {
    const b = document.createElement("button");
    b.className = "item";
    b.innerHTML = '<img loading="lazy" alt=""><span></span>';
    b.querySelector("img").src = DIR + it.name + "-sn.png";
    b.querySelector("span").textContent = it.title;
    b.addEventListener("click", () => openBox(items.indexOf(it)));
    b.addEventListener("mouseenter", () => armPreview(it));
    b.addEventListener("mousemove", () => armPreview(it));
    b.addEventListener("mouseleave", hidePreview);
    it.el = b;
    grid.appendChild(b);
  }
  sections[sec] = wrap;
  main.appendChild(wrap);
}

// Filter
const filter = document.getElementById("filter");
const count = document.getElementById("count");
function applyFilter() {
  const q = filter.value.trim().toLowerCase();
  let shown = 0;
  for (const it of items) {
    const hay = (it.title + " " + it.name).toLowerCase();
    // A bare number matches the issue number exactly; anything else is a substring match.
    const ok = !q || (/^\d+$/.test(q) ? new RegExp("#" + parseInt(q, 10) + "\\\\b").test(hay) : hay.includes(q));
    it.el.classList.toggle("hidden", !ok);
    if (ok) shown++;
  }
  for (const sec in sections) {
    sections[sec].classList.toggle("hidden", !sections[sec].querySelector(".item:not(.hidden)"));
  }
  count.textContent = shown + " of " + items.length + " issues";
}
filter.addEventListener("input", applyFilter);
applyFilter();

// Hover preview: only appears once the mouse has rested on a cover for HOVER_DELAY_MS, so sweeping
// across the grid doesn't pop covers up. Once shown, it follows the mouse within that cover.
const HOVER_DELAY_MS = 600;
const preview = document.getElementById("preview");
const pimg = preview.querySelector("img");
let hoverTimer = null;
function armPreview(it) {
  if (preview.style.display === "block") { movePreview(lastMouse); return; }
  clearTimeout(hoverTimer);
  hoverTimer = setTimeout(() => showPreview(it, lastMouse), HOVER_DELAY_MS);
}
function showPreview(it, e) {
  if (box.classList.contains("open")) return;
  pimg.src = DIR + it.name + ".png";
  preview.style.display = "block";
  movePreview(e);
}
function movePreview(e) {
  if (preview.style.display !== "block") return;
  const pad = 16, w = preview.offsetWidth, h = preview.offsetHeight;
  let x = e.clientX + pad, y = e.clientY - h / 2;
  if (x + w > innerWidth - 8) x = e.clientX - w - pad;  // flip to the left side
  y = Math.max(8, Math.min(y, innerHeight - h - 8));
  preview.style.left = x + "px";
  preview.style.top = y + "px";
}
function hidePreview() { clearTimeout(hoverTimer); preview.style.display = "none"; }
pimg.addEventListener("load", () => preview.style.display === "block" && movePreview(lastMouse));
let lastMouse = { clientX: 0, clientY: 0 };
addEventListener("mousemove", e => lastMouse = e);
addEventListener("scroll", hidePreview, { passive: true });

// Lightbox
const box = document.getElementById("lightbox");
const bimg = box.querySelector("img");
const btitle = box.querySelector(".title");
const blink = box.querySelector("a.pdf");
let cur = -1;
function visible() { return items.filter(i => !i.el.classList.contains("hidden")); }
function openBox(i) {
  hidePreview();
  cur = i;
  const it = items[i];
  bimg.src = DIR + it.name + ".png";
  bimg.alt = it.title + " cover";
  btitle.textContent = it.title;
  blink.href = DIR + it.name + ".pdf";
  box.classList.add("open");
}
function closeBox() { box.classList.remove("open"); if (cur >= 0) items[cur].el.focus(); }
function step(d) {
  const v = visible();
  const pos = v.indexOf(items[cur]);
  const next = v[(pos + d + v.length) % v.length];
  if (next) openBox(items.indexOf(next));
}
box.addEventListener("click", e => { if (e.target === box) closeBox(); });
bimg.addEventListener("click", () => window.open(blink.href, "_blank"));
bimg.style.cursor = "pointer";
document.getElementById("prev").addEventListener("click", () => step(-1));
document.getElementById("next").addEventListener("click", () => step(1));
addEventListener("keydown", e => {
  if (!box.classList.contains("open")) return;
  if (e.key === "Escape") closeBox();
  else if (e.key === "ArrowLeft") step(-1);
  else if (e.key === "ArrowRight") step(1);
});
</script>
</body>
</html>
EOF

echo "Wrote $(pwd)/index.html ($(echo "$list" | tr ',' '\n' | wc -l | tr -d ' ') issues)"
