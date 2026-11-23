import DataLayerCLICommand

#if os(macOS) && !arch(arm64)
#error("DataLayer Studio requires Apple Silicon (arm64, M1 or newer).")
#endif

@main
struct DataLayerCLIEntry {
    static func main() async { await OverlayCLI.main() }
}
