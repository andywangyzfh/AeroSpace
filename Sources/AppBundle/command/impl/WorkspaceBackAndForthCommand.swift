import AppKit
import Common

struct WorkspaceBackAndForthCommand: Command {
    let args: WorkspaceBackAndForthCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let workspace = prevFocusedWorkspace else { return .fail }
        guard mayShowAgentWorkspace(workspace, on: workspace.workspaceMonitor.rect.topLeftCorner) else {
            return .fail(io.err(agentWorkspaceEntryError(workspace)))
        }
        return .from(bool: workspace.focusWorkspace())
    }
}
