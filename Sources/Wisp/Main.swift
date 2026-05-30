import WispCore

// Everything lives in WispCore (so it's unit-testable); this just launches it
// on the main actor.
@main
enum Main {
    @MainActor
    static func main() {
        WispApp.run()
    }
}
