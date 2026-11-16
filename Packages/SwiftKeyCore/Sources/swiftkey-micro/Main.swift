import Darwin
import SwiftKeyRuntime

@main
struct SwiftKeyMicroMain {
    static func main() async {
        exit(await MicroAppCLI.main(Array(CommandLine.arguments.dropFirst())))
    }
}
