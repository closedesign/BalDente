import BalDenteCore
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    print("usage: baldente status | get state|percent|limit|temperature|zone | limit <upper> <lower> | enable | disable"); exit(2)
}
// `get` is read-only and prints one bare value, so a Shortcuts "Run Shell Script" action can use it directly.
if cmd == "get" {
    guard args.count == 2, let status = DaemonClient.status() else {
        print("cannot reach baldented (is the daemon running?)"); exit(1)
    }
    guard let v = AutomationState.value(args[1], status) else { print("unknown value: state, percent, limit, temperature or zone"); exit(2) }
    print(v); exit(0)
}
guard let reply = DaemonClient.send(args.joined(separator: " ")) else {
    print("cannot reach baldented (is the daemon running?)"); exit(1)
}
if cmd == "status", let s = try? JSONDecoder().decode(Status.self, from: Data(reply.utf8)) {
    print("battery \(s.percent)%  adapter \(s.adapterOn ? "on" : "off (limit hold)")  backend \(s.backend)")
    print("limiter \(s.state.enabled ? "on" : "off")  upper \(s.state.upper)  lower \(s.state.lower)  zone \(s.state.label)")
} else { print(reply) }
