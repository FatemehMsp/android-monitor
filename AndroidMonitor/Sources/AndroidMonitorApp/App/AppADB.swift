import Foundation

enum AppADB {
    static var url: URL {
        Bundle.main.url(forResource: "adb", withExtension: nil)
            ?? URL(fileURLWithPath: "/opt/homebrew/bin/adb")
    }
}
