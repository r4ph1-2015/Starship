(() => {
  "use strict";
  const catalog = window.StarshipCatalog;
  const h = catalog.escapeHTML;
  const grid = document.getElementById("wallpaper-grid");
  const searchInput = document.getElementById("wallpaper-search");
  const sortSelect = document.getElementById("wallpaper-sort");
  const summary = document.getElementById("results-summary");
  const emptyState = document.getElementById("gallery-empty");
  const errorState = document.getElementById("gallery-error");
  const loadMoreButton = document.getElementById("load-more");
  const dialog = document.getElementById("wallpaper-dialog");
  const PAGE_SIZE = 24;
  let items = [];
  let filter = "all";
  let visibleLimit = PAGE_SIZE;
  let activeItem = null;
  let favorites = loadFavorites();
  let videoObserver = null;

  function loadFavorites() {
    try { const parsed = JSON.parse(localStorage.getItem("starship-gallery-favorites") || "[]"); return new Set(Array.isArray(parsed) ? parsed : []); }
    catch (_) { return new Set(); }
  }
  function saveFavorites() { try { localStorage.setItem("starship-gallery-favorites", JSON.stringify([...favorites])); } catch (_) {} }
  function getFiltered() {
    const query = (searchInput?.value || "").trim().toLocaleLowerCase();
    let filtered = items.filter((item) => {
      const matchesFilter = filter === "all" || item.kind === filter || (filter === "saved" && favorites.has(item.path));
      const matchesQuery = !query || `${item.title} ${item.name} ${item.path} ${item.extension}`.toLocaleLowerCase().includes(query);
      return matchesFilter && matchesQuery;
    });
    switch (sortSelect?.value) {
      case "name-desc": filtered.sort((a, b) => b.title.localeCompare(a.title, undefined, { numeric: true, sensitivity: "base" })); break;
      case "size-desc": filtered.sort((a, b) => b.size - a.size || a.title.localeCompare(b.title)); break;
      case "size-asc": filtered.sort((a, b) => a.size - b.size || a.title.localeCompare(b.title)); break;
      default: filtered.sort((a, b) => a.title.localeCompare(b.title, undefined, { numeric: true, sensitivity: "base" }));
    }
    return filtered;
  }
  function cardMarkup(item) {
    const title = h(item.title), path = h(item.path), raw = h(item.rawURL), saved = favorites.has(item.path);
    const media = item.kind === "video"
      ? `<video class="card-media" src="${raw}" muted loop playsinline preload="metadata" aria-label="Video preview: ${title}"></video><span class="media-play-mark" aria-hidden="true">▶</span>`
      : `<img class="card-media" src="${raw}" alt="${title}" loading="lazy" decoding="async">`;
    return `<article class="wallpaper-card" data-path="${path}"><button class="card-preview-button" type="button" data-open-wallpaper="${path}" aria-label="Preview ${title}"><div class="card-artwork ${item.kind === "video" ? "is-video" : "is-image"}">${media}<span class="card-type-badge">${item.kind === "video" ? "▶ VIDEO" : "▧ IMAGE"}</span><span class="card-preview-overlay"><span>Preview wallpaper <b aria-hidden="true">↗</b></span></span></div><div class="card-copy"><div class="card-title-row"><h2>${title}</h2><span class="card-filetype">${h(item.extension.toUpperCase())}</span></div><div class="card-subline"><span>${h(catalog.formatBytes(item.size))}</span><span class="card-meta-dot"></span><span>${item.kind === "video" ? "Motion" : "Still image"}</span></div></div></button><button class="favorite-button ${saved ? "is-saved" : ""}" type="button" data-favorite="${path}" aria-label="${saved ? "Remove from saved wallpapers" : "Save wallpaper"}: ${title}" aria-pressed="${saved}">${saved ? "★" : "☆"}</button></article>`;
  }
  function updateStats() {
    document.getElementById("total-count").textContent = items.length;
    document.getElementById("video-count").textContent = items.filter((item) => item.kind === "video").length;
    document.getElementById("image-count").textContent = items.filter((item) => item.kind === "image").length;
    document.getElementById("all-filter-count").textContent = items.length;
  }
  function setupVideoObserver() {
    if (videoObserver) videoObserver.disconnect();
    if (!("IntersectionObserver" in window)) {
      grid.querySelectorAll("video").forEach((video) => { video.play().catch(() => {}); });
      return;
    }
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    videoObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        const video = entry.target;
        if (entry.isIntersecting) {
          if (video.readyState === 0) video.load();
          if (!reducedMotion) video.play().catch(() => {});
        } else video.pause();
      });
    }, { rootMargin: "160px 0px" });
    grid.querySelectorAll("video").forEach((video) => videoObserver.observe(video));
  }
  function render() {
    const filtered = getFiltered();
    const shown = filtered.slice(0, visibleLimit);
    grid.innerHTML = shown.map(cardMarkup).join("");
    const query = (searchInput.value || "").trim();
    summary.textContent = filtered.length === 0 ? "No matching wallpapers" : `Showing ${shown.length} of ${filtered.length} ${filtered.length === 1 ? "wallpaper" : "wallpapers"}${query ? ` for “${query}”` : ""}`;
    emptyState.hidden = filtered.length !== 0;
    loadMoreButton.hidden = shown.length >= filtered.length;
    setupVideoObserver();
    if (window.location.hash.startsWith("#wallpaper=")) {
      const path = decodeURIComponent(window.location.hash.slice("#wallpaper=".length));
      const item = items.find((candidate) => candidate.path === path);
      if (item && !dialog.open) openDialog(item, false);
    }
  }
  function setFilter(next) {
    filter = next;
    visibleLimit = PAGE_SIZE;
    document.querySelectorAll(".filter-pill").forEach((button) => {
      const active = button.dataset.filter === filter;
      button.classList.toggle("active", active);
      button.setAttribute("aria-pressed", String(active));
    });
    render();
  }
  function toggleFavorite(path) {
    if (favorites.has(path)) favorites.delete(path); else favorites.add(path);
    saveFavorites();
    render();
    if (dialog.open && activeItem?.path === path) updateDialogFavorite();
  }
  function renderModalMedia(item) {
    const host = document.getElementById("dialog-media");
    if (item.kind === "video") host.innerHTML = `<video class="dialog-video" src="${h(item.rawURL)}" controls autoplay muted loop playsinline></video>`;
    else host.innerHTML = `<img class="dialog-image" src="${h(item.rawURL)}" alt="${h(item.title)}">`;
    const visual = host.querySelector("img,video");
    const metadata = document.getElementById("dialog-metadata");
    const updateDetails = () => {
      const parts = [item.kind === "video" ? "Video wallpaper" : "Image wallpaper", catalog.formatBytes(item.size)];
      if (visual && visual.videoWidth && visual.videoHeight) parts.push(`${visual.videoWidth} × ${visual.videoHeight}`);
      else if (visual && visual.naturalWidth && visual.naturalHeight) parts.push(`${visual.naturalWidth} × ${visual.naturalHeight}`);
      if (item.kind === "video" && visual?.duration && Number.isFinite(visual.duration)) parts.push(`${Math.floor(visual.duration / 60)}:${String(Math.floor(visual.duration % 60)).padStart(2, "0")}`);
      metadata.innerHTML = parts.map((part) => `<span>${h(part)}</span>`).join("");
    };
    visual?.addEventListener(item.kind === "video" ? "loadedmetadata" : "load", updateDetails, { once: true });
    updateDetails();
  }
  function updateDialogFavorite() {
    const button = document.getElementById("dialog-save");
    if (!activeItem) return;
    const saved = favorites.has(activeItem.path);
    button.textContent = saved ? "★ Saved" : "☆ Save wallpaper";
    button.classList.toggle("is-saved", saved);
  }
  function openDialog(item, updateHash = true) {
    activeItem = item;
    document.getElementById("dialog-title").textContent = item.title;
    document.getElementById("dialog-path").textContent = item.path;
    document.getElementById("dialog-eyebrow").textContent = `${item.kind === "video" ? "VIDEO WALLPAPER" : "IMAGE WALLPAPER"} · ${item.extension.toUpperCase()}`;
    document.getElementById("dialog-open-original").href = item.rawURL;
    document.getElementById("dialog-github").href = item.blobURL;
    document.getElementById("dialog-feedback").textContent = "";
    renderModalMedia(item);
    updateDialogFavorite();
    if (!dialog.open) dialog.showModal();
    if (updateHash) history.replaceState(null, "", `#wallpaper=${encodeURIComponent(item.path)}`);
  }
  function closeDialog() { if (dialog.open) dialog.close(); }

  grid.addEventListener("click", (event) => {
    const favorite = event.target.closest("[data-favorite]");
    if (favorite) { event.preventDefault(); event.stopPropagation(); toggleFavorite(favorite.dataset.favorite); return; }
    const preview = event.target.closest("[data-open-wallpaper]");
    if (preview) {
      const item = items.find((candidate) => candidate.path === preview.dataset.openWallpaper);
      if (item) openDialog(item);
    }
  });
  document.querySelectorAll(".filter-pill").forEach((button) => button.addEventListener("click", () => setFilter(button.dataset.filter)));
  searchInput.addEventListener("input", () => { visibleLimit = PAGE_SIZE; render(); });
  sortSelect.addEventListener("change", () => render());
  loadMoreButton.addEventListener("click", () => { visibleLimit += PAGE_SIZE; render(); });
  document.getElementById("clear-filters").addEventListener("click", () => { searchInput.value = ""; sortSelect.value = "name-asc"; setFilter("all"); });
  document.getElementById("retry-gallery").addEventListener("click", async () => { errorState.hidden = true; grid.hidden = false; grid.innerHTML = '<div class="gallery-skeleton"></div><div class="gallery-skeleton"></div><div class="gallery-skeleton"></div>'; await init(true); });
  document.querySelector(".dialog-close").addEventListener("click", closeDialog);
  dialog.addEventListener("click", (event) => { if (event.target === dialog) closeDialog(); });
  dialog.addEventListener("close", () => { activeItem = null; history.replaceState(null, "", window.location.pathname + window.location.search); });
  document.getElementById("dialog-save").addEventListener("click", () => { if (activeItem) toggleFavorite(activeItem.path); });
  document.getElementById("dialog-github").addEventListener("click", () => {});
  searchInput.addEventListener("keydown", (event) => { if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") { event.preventDefault(); searchInput.focus(); } });
  document.addEventListener("keydown", (event) => { if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") { event.preventDefault(); searchInput.focus(); } });

  async function init(retry = false) {
    errorState.hidden = true;
    grid.hidden = false;
    try {
      if (retry) items = await catalog.load(); else items = await catalog.load();
      updateStats();
      render();
      const params = new URLSearchParams(window.location.search);
      if (params.has("q")) searchInput.value = params.get("q");
      if (params.has("q")) render();
      const note = document.getElementById("results-summary");
      if (!items.length) note.textContent = "No supported image or video files were found in /gallery.";
    } catch (error) {
      grid.hidden = true;
      errorState.hidden = false;
      summary.textContent = "Gallery unavailable";
    }
  }
  document.addEventListener("DOMContentLoaded", () => init());
})();
