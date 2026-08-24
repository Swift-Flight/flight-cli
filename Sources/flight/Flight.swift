import ArgumentParser

@main
struct Flight: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flight",
        abstract: "Scaffolding and tooling for Flight applications.",
        version: "0.1.0",
        subcommands: [New.self]
    )
}
