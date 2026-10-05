import Common

struct AgentWorkspaceConfig: ConvenienceMutable {
    var enabled = false
    var name = "Agent"
    var entryBinding = "ctrl-alt-a"
    var entryMode = mainModeId
}

func parseAgentWorkspace(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> AgentWorkspaceConfig {
    parseTable(raw, AgentWorkspaceConfig(), [
        "enabled": Parser(\.enabled, parseBool),
        "name": Parser(\.name, parseString),
        "entry-binding": Parser(\.entryBinding, parseString),
        "entry-mode": Parser(\.entryMode, parseString),
    ], backtrace, &c)
}

@MainActor
func validateAgentWorkspace(_ config: Config, _ c: inout ConfigParserContext) {
    let policy = config.agentWorkspace
    guard policy.enabled else { return }
    let backtrace = ConfigBacktrace.rootKey("agent-workspace")
    if case .failure(let message) = WorkspaceName.parse(policy.name) {
        c.errors.append(.init(backtrace + .key("name"), message, preventConfigReload: true))
    }
    guard let binding = config.modes[policy.entryMode]?.bindings.values
        .first(where: { $0.descriptionWithKeyNotation == policy.entryBinding })
    else {
        c.errors.append(.init(backtrace + .key("entry-binding"),
                              "Binding '\(policy.entryBinding)' must exist in mode '\(policy.entryMode)'",
                              preventConfigReload: true))
        return
    }
    let entersWorkspace = binding.commands.flatten().contains { command in
        (command as? WorkspaceCommand)?.args.target.val.workspaceNameOrNil()?.raw == policy.name
    }
    if !entersWorkspace {
        c.errors.append(.init(backtrace + .key("entry-binding"),
                              "The entry binding must directly run 'workspace \(policy.name)'",
                              preventConfigReload: true))
    }
}
