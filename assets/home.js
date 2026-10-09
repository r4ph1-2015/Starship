(() => {
  "use strict";
  const catalog = window.StarshipCatalog;
  const h = catalog.escapeHTML;
  const mediaMarkup = (item, extraClass = "") => {
    const title = h(item.title), src = h(item.rawURL);
    if (item.kind === "video") return `<video class="wallpaper-media ${extraClass}" src="${src}" muted loop playsinline preload="metadata" aria-label="Preview of ${title}"></video>`;
    return `<img class="wallpaper-media ${extraClass}" src="${src}" alt="${title}" loading="lazy">`;
  };
  function showHero(item) {
    const host = document.getElementById("hero-wallpaper");
    if (!host || !item) return;
    host.classList.add("has-artwork");
    host.querySelector(".hero-wallpaper-placeholder")?.remove();
    host.insertAdjacentHTML("afterbegin", mediaMarkup(item, "hero-media"));
    const title = document.getElementById("hero-wallpaper-title");
    const meta = document.getElementById("hero-wallpaper-meta");
    if (title) title.textContent = item.title;
    if (meta) meta.textContent = `${item.extension.toUpperCase()} · ${catalog.formatBytes(item.size)}`;
    const video = host.querySelector("video");
    if (video) video.play().catch(() => {});
  }
  function renderCards(items) {
    const grid = document.getElementById("home-wallpaper-grid");
    if (!grid) return;
    const selected = items.slice(0, 3);
    if (!selected.length) {
      grid.innerHTML = `<div class="catalog-empty-card"><span>✧</span><p>No wallpapers are in the gallery yet.</p><a href="https://github.com/r4ph1-2015/Starship/tree/main/gallery" target="_blank" rel="noreferrer">Open the GitHub folder ↗</a></div>`;
      return;
    }
    grid.innerHTML = selected.map((item, index) => `<a class="preview-card preview-card-${index + 1}" href="gallery.html" aria-label="Browse the gallery: ${h(item.title)}"><div class="preview-card-media">${mediaMarkup(item)}</div><div class="preview-card-info"><div><span class="mini-label">${item.kind === "video" ? "VIDEO SCENE" : "WALLPAPER"}</span><h3>${h(item.title)}</h3></div><span class="card-arrow" aria-hidden="true">↗</span></div></a>`).join("");
    grid.querySelectorAll("video").forEach((video) => {
      const play = () => video.play().catch(() => {});
      const pause = () => video.pause();
      video.addEventListener("mouseenter", play);
      video.addEventListener("focus", play);
      video.addEventListener("mouseleave", pause);
    });
  }
  async function init() {
    const note = document.getElementById("home-catalog-note");
    try {
      const items = await catalog.load();
      document.querySelectorAll("[data-wallpaper-count]").forEach((node) => { node.textContent = items.length; });
      // Prefer images in the hero so it appears immediately while video metadata loads.
      const featured = [...items.filter((item) => item.kind === "image"), ...items.filter((item) => item.kind === "video")];
      showHero(featured[0]);
      renderCards(featured);
      if (note) note.textContent = `A live collection from the Starship GitHub repository · ${items.length} wallpapers`;
    } catch (error) {
      if (note) note.textContent = "The live gallery couldn't load just now. You can still browse the wallpaper folder on GitHub.";
      const grid = document.getElementById("home-wallpaper-grid");
      if (grid) grid.innerHTML = `<div class="catalog-empty-card"><span>✧</span><p>We couldn't reach the gallery right now.</p><a href="https://github.com/r4ph1-2015/Starship/tree/main/gallery" target="_blank" rel="noreferrer">Browse wallpapers on GitHub ↗</a></div>`;
    }
  }
  document.addEventListener("DOMContentLoaded", init);
})();
