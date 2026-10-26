// The editor and its export dialog share one isolated page; no external requests are proxied.
// No module dependencies: load synchronously to avoid WebKit's intermittent module-worker startup stall.
importScripts('./export/isolation-worker.mjs?v=20261026-overlay-only2');
