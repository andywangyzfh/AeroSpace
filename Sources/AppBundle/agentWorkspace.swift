import AppKit
import Common

// Only the registered hotkey handler grants this scoped permission. Socket commands,
// trigger-binding, callbacks, and native application activation do not grant it.
// This is a workspace policy, not authentication of physical keyboard input.
@TaskLocal
private var agentWorkspaceEntryAllowed = false

@MainActor
func runHotkeyBindingCommands(mode: String, binding: HotkeyBinding) async -> CmdResult {
    let policy = config.agentWorkspace
    let allowsEntry = policy.enabled && mode == policy.entryMode &&
        binding.descriptionWithKeyNotation == policy.entryBinding
    return await $agentWorkspaceEntryAllowed.withValue(allowsEntry) {
        await binding.commands.run(.defaultEnv, .emptyStdin)
    }
}

@MainActor
func isProtectedAgentWorkspace(_ workspace: Workspace) -> Bool {
    config.agentWorkspace.enabled && workspace.name == config.agentWorkspace.name
}

@MainActor
func mayShowAgentWorkspace(_ workspace: Workspace, on monitorPoint: CGPoint) -> Bool {
    !isProtectedAgentWorkspace(workspace) || agentWorkspaceEntryAllowed ||
        (workspace.isVisible && workspace.workspaceMonitor.rect.topLeftCorner == monitorPoint)
}

@MainActor
func agentWorkspaceEntryError(_ workspace: Workspace) -> String {
    "Workspace '\(workspace.name)' can only be shown by hotkey '\(config.agentWorkspace.entryBinding)' " +
        "in mode '\(config.agentWorkspace.entryMode)'"
}
