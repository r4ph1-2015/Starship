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
  let videoObserver = null;

  function getFiltered() {
    const query = (searchInput?.value || "").trim().toLocaleLowerCase();
    let filtered = items.filter((item) => {
      const matchesFilter = filter === "all" || item.kind === filter;
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
    const title = h(item.title), path = h(item.path), raw = h(item.rawURL);
    const media = item.kind === "video"
      ? `<video class="card-media" src="${raw}" muted loop playsinline preload="metadata" aria-label="Video preview: ${title}"></video><span class="media-play-mark" aria-hidden="true">▶</span>`
      : `<img class="card-media" src="${raw}" alt="${title}" loading="lazy" decoding="async">`;
    return `<article class="wallpaper-card" data-path="${path}"><button class="card-preview-button" type="button" data-open-wallpaper="${path}" aria-label="Preview ${title}"><div class="card-artwork ${item.kind === "video" ? "is-video" : "is-image"}">${media}<span class="card-type-badge">${item.kind === "video" ? "▶ VIDEO" : "▧ IMAGE"}</span><span class="card-preview-overlay"><span>${item.kind === "video" ? "Play video preview" : "Preview wallpaper"} <b aria-hidden="true">↗</b></span></span></div><div class="card-copy"><div class="card-title-row"><h2>${title}</h2><span class="card-filetype">${h(item.extension.toUpperCase())}</span></div><div class="card-subline"><span>${h(catalog.formatBytes(item.size))}</span><span class="card-meta-dot"></span><span>${item.kind === "video" ? "Motion" : "Still image"}</span></div></div></button></article>`;
  }

  function updateStats() {
    document.getElementById("total-count").textContent = items.length;
    document.getElementById("video-count").textContent = items.filter((item) => item.kind === "video").length;
    document.getElementById("image-count").textContent = items.filter((item) => item.kind === "image").length;
    document.getElementById("all-filter-count").textContent = items.length;
  }

  function setupVideoObserver() {
    if (videoObserver) videoObserver.disconnect();
    const videos = grid.querySelectorAll("video");
    if (!("IntersectionObserver" in window)) {
      videos.forEach((video) => video.play().catch(() => {}));
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
    videos.forEach((video) => {
      video.addEventListener("error", () => video.closest(".card-artwork")?.classList.add("video-unavailable"), { once: true });
      videoObserver.observe(video);
    });
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
    if (window.location.hash.startsWith("#wallpaper=") && !dialog.open) {
      try {
        const path = decodeURIComponent(window.location.hash.slice("#wallpaper=".length));
        const item = items.find((candidate) => candidate.path === path);
        if (item) openDialog(item, false);
      } catch (_) { /* Ignore malformed deep links. */ }
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

  function renderModalMedia(item) {
    const host = document.getElementById("dialog-media");
    const metadata = document.getElementById("dialog-metadata");
    const feedback = document.getElementById("dialog-feedback");
    feedback.textContent = "";
    host.replaceChildren();
    let visual;
    if (item.kind === "video") {
      visual = document.createElement("video");
      visual.className = "dialog-video";
      visual.src = item.rawURL;
      visual.controls = true;
      visual.autoplay = true;
      visual.muted = true;
      visual.defaultMuted = true;
      visual.loop = true;
      visual.playsInline = true;
      visual.preload = "auto";
      visual.setAttribute("aria-label", `${item.title} video wallpaper preview`);
      visual.addEventListener("error", () => {
        feedback.textContent = "This video format may not be supported by your browser. Use Download wallpaper to save the original file.";
      });
      visual.addEventListener("canplay", () => { feedback.textContent = "Playing preview · muted · looping"; });
    } else {
      visual = document.createElement("img");
      visual.className = "dialog-image";
      visual.src = item.rawURL;
      visual.alt = item.title;
      visual.addEventListener("error", () => { feedback.textContent = "The preview could not load. Try downloading the original file."; }, { once: true });
    }
    host.appendChild(visual);

    const updateDetails = () => {
      const parts = [item.kind === "video" ? "Video wallpaper" : "Image wallpaper", catalog.formatBytes(item.size)];
      if (visual.videoWidth && visual.videoHeight) parts.push(`${visual.videoWidth} × ${visual.videoHeight}`);
      else if (visual.naturalWidth && visual.naturalHeight) parts.push(`${visual.naturalWidth} × ${visual.naturalHeight}`);
      if (item.kind === "video" && visual.duration && Number.isFinite(visual.duration)) {
        parts.push(`${Math.floor(visual.duration / 60)}:${String(Math.floor(visual.duration % 60)).padStart(2, "0")}`);
      }
      metadata.innerHTML = parts.map((part) => `<span>${h(part)}</span>`).join("");
    };
    visual.addEventListener(item.kind === "video" ? "loadedmetadata" : "load", updateDetails, { once: true });
    updateDetails();
    return visual;
  }

  function openDialog(item, updateHash = true) {
    activeItem = item;
    document.getElementById("dialog-title").textContent = item.title;
    document.getElementById("dialog-path").textContent = item.path;
    document.getElementById("dialog-eyebrow").textContent = `${item.kind === "video" ? "VIDEO WALLPAPER" : "IMAGE WALLPAPER"} · ${item.extension.toUpperCase()}`;
    document.getElementById("dialog-open-original").href = item.rawURL;
    document.getElementById("dialog-github").href = item.blobURL;
    const download = document.getElementById("dialog-download");
    download.href = catalog.downloadURL(item.path);
    download.download = item.name;
    download.setAttribute("aria-label", `Download wallpaper ${item.title}`);

    if (!dialog.open) dialog.showModal();
    const visual = renderModalMedia(item);
    if (item.kind === "video") {
      // Start playback after the dialog is visible. Calling play() only while
      // the video is inside a closed dialog is unreliable in several browsers.
      requestAnimationFrame(() => {
        if (!dialog.open || activeItem?.path !== item.path) return;
        visual.play().then(() => {
          document.getElementById("dialog-feedback").textContent = "Playing preview · muted · looping";
        }).catch(() => {
          document.getElementById("dialog-feedback").textContent = "Press ▶ in the video controls to play. If this format is unsupported, download the original file.";
        });
      });
    }
    if (updateHash) history.replaceState(null, "", `#wallpaper=${encodeURIComponent(item.path)}`);
  }

  function closeDialog() {
    const video = document.querySelector("#dialog-media video");
    if (video) { video.pause(); video.removeAttribute("src"); video.load(); }
    if (dialog.open) dialog.close();
  }

  grid.addEventListener("click", (event) => {
    const preview = event.target.closest("[data-open-wallpaper]");
    if (!preview) return;
    const item = items.find((candidate) => candidate.path === preview.dataset.openWallpaper);
    if (item) openDialog(item);
  });
  document.querySelectorAll(".filter-pill").forEach((button) => button.addEventListener("click", () => setFilter(button.dataset.filter)));
  searchInput.addEventListener("input", () => { visibleLimit = PAGE_SIZE; render(); });
  sortSelect.addEventListener("change", () => render());
  loadMoreButton.addEventListener("click", () => { visibleLimit += PAGE_SIZE; render(); });
  document.getElementById("clear-filters").addEventListener("click", () => { searchInput.value = ""; sortSelect.value = "name-asc"; setFilter("all"); });
  document.getElementById("retry-gallery").addEventListener("click", async () => { errorState.hidden = true; grid.hidden = false; grid.innerHTML = '<div class="gallery-skeleton"></div><div class="gallery-skeleton"></div><div class="gallery-skeleton"></div>'; await init(true); });
  document.querySelector(".dialog-close").addEventListener("click", closeDialog);
  dialog.addEventListener("click", (event) => { if (event.target === dialog) closeDialog(); });
  dialog.addEventListener("close", () => {
    const video = document.querySelector("#dialog-media video");
    if (video) { video.pause(); video.removeAttribute("src"); video.load(); }
    document.getElementById("dialog-media").replaceChildren();
    activeItem = null;
    history.replaceState(null, "", window.location.pathname + window.location.search);
  });
  searchInput.addEventListener("keydown", (event) => { if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") { event.preventDefault(); searchInput.focus(); } });
  document.addEventListener("keydown", (event) => { if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") { event.preventDefault(); searchInput.focus(); } });

  async function init(retry = false) {
    errorState.hidden = true;
    grid.hidden = false;
    try {
      items = await catalog.load();
      updateStats();
      const params = new URLSearchParams(window.location.search);
      if (params.has("q")) searchInput.value = params.get("q");
      render();
      if (!items.length) summary.textContent = "No supported image or video files were found in /gallery.";
    } catch (_) {
      grid.hidden = true;
      errorState.hidden = false;
      summary.textContent = "Gallery unavailable";
    }
  }
  document.addEventListener("DOMContentLoaded", () => init());
})();
