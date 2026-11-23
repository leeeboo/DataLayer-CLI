import OverlayCore

#if os(macOS)
#if !arch(arm64)
#error("DataLayer Studio requires Apple Silicon (arm64, M1 or newer).")
#endif

VideoExportWorker.run()
#endif
