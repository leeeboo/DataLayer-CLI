// The editor and its export dialog share one isolated page; no external requests are proxied.
// Synchronous loading avoids WebKit dropping a module worker's initial import.
importScripts('./export/isolation-worker.mjs?v=20261026-standalone1');
