(() => {
  "use strict";
  const OWNER = "r4ph1-2015";
  const REPO = "Starship";
  const BRANCH = "main";
  const API_BASE = `https://api.github.com/repos/${OWNER}/${REPO}`;
  const RAW_BASE = `https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}/`;
  const SUPPORTED = new Set(["jpg", "jpeg", "png", "webp", "gif", "avif", "heic", "heif", "mp4", "mov", "m4v", "webm", "mkv"]);
  const VIDEO = new Set(["mp4", "mov", "m4v", "webm", "mkv"]);
  let catalogPromise;

  const extFor = (name) => (name.split(".").pop() || "").toLowerCase();
  const isSupported = (name) => SUPPORTED.has(extFor(name));
  const isVideo = (item) => VIDEO.has(item.extension || extFor(item.name));
  const humanizeTitle = (name) => {
    let stem = String(name || "Wallpaper").split("/").pop().replace(/\.[^.]+$/, "");
    stem = stem.replace(/[._-]+/g, " ").replace(/\s+/g, " ").trim();
    if (!stem) return "Untitled wallpaper";
    return stem.replace(/(^|\s)([a-z])/g, (_, space, char) => space + char.toUpperCase());
  };
  const formatBytes = (size) => {
    if (!Number.isFinite(Number(size)) || Number(size) < 0) return "Size unavailable";
    const bytes = Number(size);
    if (bytes < 1024) return `${bytes} B`;
    const units = ["KB", "MB", "GB", "TB"];
    let n = bytes / 1024, unit = 0;
    while (n >= 1024 && unit < units.length - 1) { n /= 1024; unit++; }
    return `${n.toFixed(n >= 100 ? 0 : n >= 10 ? 1 : 2)} ${units[unit]}`;
  };
  const encodePath = (path) => String(path).split("/").map(encodeURIComponent).join("/");
  const rawURL = (path) => RAW_BASE + encodePath(path);
  const blobURL = (path) => `https://github.com/${OWNER}/${REPO}/blob/${BRANCH}/${encodePath(path)}`;
  // GitHub's /raw endpoint serves the repository file as a download; adding
  // download=1 makes the intent explicit for supported clients.
  const downloadURL = (path) => `https://github.com/${OWNER}/${REPO}/raw/refs/heads/${BRANCH}/${encodePath(path)}?download=1`;
  const escapeHTML = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]));
  const makeItem = (entry) => {
    const path = entry.path;
    const name = path.split("/").pop();
    return { path, name, title: humanizeTitle(name), extension: extFor(name), kind: VIDEO.has(extFor(name)) ? "video" : "image", size: Number(entry.size) || 0, rawURL: rawURL(path), blobURL: blobURL(path) };
  };

  async function fetchJSON(url) {
    const response = await fetch(url, { headers: { Accept: "application/vnd.github+json" }, cache: "no-cache" });
    if (!response.ok) throw new Error(`GitHub returned ${response.status} for ${url}`);
    return response.json();
  }

  async function readContentsFallback(path = "gallery") {
    const collected = [];
    const queue = [path];
    while (queue.length) {
      const current = queue.shift();
      const encoded = current.split("/").map(encodeURIComponent).join("/");
      const entries = await fetchJSON(`${API_BASE}/contents/${encoded}?ref=${encodeURIComponent(BRANCH)}`);
      if (!Array.isArray(entries)) continue;
      for (const entry of entries) {
        if (entry.type === "dir") queue.push(entry.path);
        else if (entry.type === "file" && isSupported(entry.name)) collected.push({ path: entry.path, size: entry.size });
      }
    }
    return collected;
  }

  async function load() {
    if (catalogPromise) return catalogPromise;
    catalogPromise = (async () => {
      let entries;
      try {
        const treeData = await fetchJSON(`${API_BASE}/git/trees/${encodeURIComponent(BRANCH)}?recursive=1`);
        if (!treeData.truncated && Array.isArray(treeData.tree)) {
          entries = treeData.tree.filter((entry) => entry.type === "blob" && entry.path.startsWith("gallery/") && isSupported(entry.path.split("/").pop())).map((entry) => ({ path: entry.path, size: entry.size }));
        } else {
          entries = await readContentsFallback();
        }
      } catch (error) {
        try { entries = await readContentsFallback(); }
        catch (fallbackError) { catalogPromise = null; throw new Error("Unable to read the GitHub wallpaper folder. Check your internet connection and try again.", { cause: fallbackError || error }); }
      }
      const unique = new Map();
      for (const entry of entries || []) {
        if (!entry.path.startsWith("gallery/") || !isSupported(entry.path.split("/").pop())) continue;
        if (entry.path.split("/").pop().toLowerCase() === ".ds_store") continue;
        unique.set(entry.path, makeItem(entry));
      }
      return Array.from(unique.values()).sort((a, b) => a.title.localeCompare(b.title, undefined, { numeric: true, sensitivity: "base" }));
    })();
    return catalogPromise;
  }

  document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll("[data-year]").forEach((element) => { element.textContent = String(new Date().getFullYear()); });
  });
  window.StarshipCatalog = { load, isVideo, humanizeTitle, formatBytes, escapeHTML, rawURL, blobURL, downloadURL };
})();
