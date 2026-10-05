@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class AgentWorkspaceTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        resetClosedWindowsCache()
        updateFocusCache(nil)
        _prevFocusedWorkspaceName = nil
        let result = parseConfig(Self.toml)
        assertEquals(result.errors, [])
        config.agentWorkspace = result.config.agentWorkspace
        config.modes = result.config.modes
        config.persistentWorkspaces = ["Work", "Agent", "Other"]
        assertTrue(Workspace.get(byName: "Work").focusWorkspace())
    }

    private static let toml = """
        config-version = 2
        [agent-workspace]
        enabled = true
        name = 'Agent'
        entry-binding = 'ctrl-alt-a'
        entry-mode = 'main'
        [mode.main.binding]
        ctrl-alt-a = 'workspace Agent'
        alt-a = 'workspace Agent'
        alt-w = 'workspace Work'
        [mode.other.binding]
        ctrl-alt-a = 'workspace Agent'
        """

    private var agent: Workspace { Workspace.get(byName: "Agent") }

    private func pressEntry() async -> CmdResult {
        await runHotkeyBindingCommands(mode: "main", binding: config.modes["main"]!.bindings.values
            .first { $0.descriptionWithKeyNotation == config.agentWorkspace.entryBinding }!)
    }

    func testNativeActivationDoesNotRevealAgentOrChangeHistory() async {
        await checkOnFocusChangedCallbacks_nonCancellable()
        let previous = _prevFocusedWorkspaceName
        let window = TestWindow.new(id: 100, parent: agent.rootTilingContainer)
        updateFocusCache(window)
        updateFocusCache(window) // Repeated AX notifications must stay blocked.
        await checkOnFocusChangedCallbacks_nonCancellable()
        assertEquals(focus.workspace.name, "Work")
        assertEquals(mainMonitorInfo.activeWorkspace.name, "Work")
        assertEquals(_prevFocusedWorkspaceName, previous)
        assertFalse(agent.isVisible)
    }

    func testNativeActivationOfOtherWorkspaceStillWorks() {
        let other = Workspace.get(byName: "Other")
        let window = TestWindow.new(id: 101, parent: other.rootTilingContainer)
        updateFocusCache(window)
        assertEquals(focus.windowOrNil, window)
        assertEquals(mainMonitorInfo.activeWorkspace.name, "Other")
    }

    func testEntryHotkeyShowsWorkspaceAndPermitDoesNotLeak() async {
        let result = await pressEntry()
        assertEquals(result.exitCode.rawValue, 0)
        assertTrue(agent.isVisible)
        assertEquals(focus.workspace.name, "Agent")
        assertTrue(Workspace.get(byName: "Work").focusWorkspace())
        let blocked = await parseCommand("workspace Agent").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(blocked.exitCode.rawValue, 2)
        assertEquals(focus.workspace.name, "Work")
        assertFalse(agent.isVisible)
    }

    func testWrongHotkeyCannotEnter() async {
        let binding = config.modes["main"]!.bindings.values.first { $0.descriptionWithKeyNotation == "alt-a" }!
        let result = await runHotkeyBindingCommands(mode: "main", binding: binding)
        assertEquals(result.exitCode.rawValue, 2)
        assertFalse(agent.isVisible)
    }

    func testChangingEntryKeyAllowsNewKeyAndRejectsOldKey() async {
        let oldBinding = config.modes["main"]!.bindings.values.first { $0.descriptionWithKeyNotation == "ctrl-alt-a" }!
        let result = parseConfig(Self.toml.replacingOccurrences(of: "ctrl-alt-a", with: "cmd-alt-enter"))
        assertEquals(result.errors, [])
        config.agentWorkspace = result.config.agentWorkspace
        config.modes = result.config.modes
        let blocked = await runHotkeyBindingCommands(mode: "main", binding: oldBinding)
        assertEquals(blocked.exitCode.rawValue, 2)
        assertFalse(agent.isVisible)
        let entered = await pressEntry()
        assertEquals(entered.exitCode.rawValue, 0)
        assertTrue(agent.isVisible)
    }

    func testSameHotkeyInOtherModeCannotEnter() async {
        let result = await runHotkeyBindingCommands(mode: "other", binding: config.modes["other"]!.bindings.values.first!)
        assertEquals(result.exitCode.rawValue, 2)
        assertFalse(agent.isVisible)
    }

    func testSocketTriggerBindingCannotImpersonateHotkey() async {
        let result = await parseCommand("trigger-binding ctrl-alt-a --mode main").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertFalse(agent.isVisible)
    }

    func testCommandEntryPathsAreBlocked() async {
        let window = TestWindow.new(id: 102, parent: agent.rootTilingContainer)
        _prevFocusedWorkspaceName = "Agent"
        for command in ["workspace Agent", "focus --window-id \(window.windowId)", "summon-workspace Agent",
                        "workspace-back-and-forth", "eval 'workspace Agent'"]
        {
            let result = await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode.rawValue, 2, additionalMsg: command)
            assertEquals(focus.workspace.name, "Work", additionalMsg: command)
            assertEquals(mainMonitorInfo.activeWorkspace.name, "Work", additionalMsg: command)
            assertFalse(agent.isVisible)
        }
    }

    func testDirectMonitorEntryIsBlocked() {
        assertFalse(mainMonitorInfo.setActiveWorkspace(agent))
        assertEquals(mainMonitorInfo.activeWorkspace.name, "Work")
    }

    func testMovingWindowIntoAgentDoesNotRevealIt() async {
        let window = TestWindow.new(id: 103, parent: focus.workspace.rootTilingContainer)
        assertTrue(window.focusWindow())
        let result = await parseCommand("move-node-to-workspace Agent").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(window.nodeWorkspace?.name, "Agent")
        assertEquals(mainMonitorInfo.activeWorkspace.name, "Work")
        assertFalse(agent.isVisible)
    }

    func testMoveWithFocusFailsBeforeMovingWindow() async {
        let window = TestWindow.new(id: 104, parent: focus.workspace.rootTilingContainer)
        assertTrue(window.focusWindow())
        let result = await parseCommand("move-node-to-workspace --focus-follows-window Agent").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(window.nodeWorkspace?.name, "Work")
        assertEquals(focus.windowOrNil, window)
        assertFalse(agent.isVisible)
    }

    func testVisibleAgentAllowsNormalWindowFocus() async {
        let first = TestWindow.new(id: 105, parent: agent.rootTilingContainer)
        let second = TestWindow.new(id: 106, parent: agent.rootTilingContainer)
        _ = await pressEntry()
        updateFocusCache(first)
        assertEquals(focus.windowOrNil, first)
        updateFocusCache(second)
        assertEquals(focus.windowOrNil, second)
        assertTrue(agent.isVisible)
    }

    func testVisibleAgentCannotBeSummonedToAnotherMonitor() async {
        _ = await pressEntry()
        let secondMonitor = SecondMonitor()
        assertFalse(secondMonitor.setActiveWorkspace(agent))
        assertEquals(mainMonitorInfo.activeWorkspace.name, "Agent")
        assertTrue(agent.isVisible)
    }

    func testStubWorkspaceNeverAutomaticallySelectsAgent() {
        let stub = getStubWorkspace(for: mainMonitorInfo)
        assertNotEquals(stub.name, "Agent")
    }

    func testCacheRestorationKeepsCurrentlyVisibleAgent() async throws {
        let window = TestWindow.new(id: 107, parent: agent.floatingWindowsContainer)
        _ = await pressEntry()
        cacheClosedWindowIfNeeded()
        let restored = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)
        assertTrue(restored)
        assertTrue(agent.isVisible)
        assertEquals(mainMonitorInfo.activeWorkspace.name, "Agent")
        assertEquals(focus.workspace.name, "Agent")
    }

    func testCacheRestorationDoesNotRevealHiddenAgent() async throws {
        let window = TestWindow.new(id: 108, parent: agent.floatingWindowsContainer)
        cacheClosedWindowIfNeeded()
        let restored = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)
        assertTrue(restored)
        assertFalse(agent.isVisible)
        assertEquals(mainMonitorInfo.activeWorkspace.name, "Work")
    }

    func testStaleVisibleAgentCacheCannotReenterAfterUserLeaves() async throws {
        let window = TestWindow.new(id: 109, parent: agent.floatingWindowsContainer)
        _ = await pressEntry()
        cacheClosedWindowIfNeeded()
        assertTrue(Workspace.get(byName: "Work").focusWorkspace())
        let restored = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)
        assertTrue(restored)
        assertFalse(agent.isVisible)
        assertEquals(mainMonitorInfo.activeWorkspace.name, "Work")
    }

    func testBlockedStaleAgentCacheKeepsCurrentOrdinaryWorkspace() async throws {
        let window = TestWindow.new(id: 111, parent: agent.floatingWindowsContainer)
        _ = await pressEntry()
        cacheClosedWindowIfNeeded()
        assertTrue(Workspace.get(byName: "Other").focusWorkspace())
        let restored = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)
        assertTrue(restored)
        assertFalse(agent.isVisible)
        assertEquals(mainMonitorInfo.activeWorkspace.name, "Other")
        assertEquals(focus.workspace.name, "Other")
    }

    func testStaleOrdinaryCacheCannotHideAgentAfterUserEnters() async throws {
        let window = TestWindow.new(id: 110, parent: agent.floatingWindowsContainer)
        cacheClosedWindowIfNeeded()
        _ = await pressEntry()
        let restored = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)
        assertTrue(restored)
        assertTrue(agent.isVisible)
        assertEquals(mainMonitorInfo.activeWorkspace.name, "Agent")
    }

    func testDisablingPolicyRestoresStandardBehavior() async {
        config.agentWorkspace.enabled = false
        let result = await parseCommand("workspace Agent").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertTrue(agent.isVisible)
    }

    func testDisabledByDefault() {
        assertFalse(parseConfig("").config.agentWorkspace.enabled)
    }

    func testMissingEntryBindingPreventsConfigReload() {
        let result = parseConfig("config-version = 2\n[agent-workspace]\nenabled = true")
        assertFalse(result.allowReloadConfig)
        assertTrue(result.strErrors.contains { $0.contains("must exist") })
    }

    func testEntryBindingMustDirectlyEnterWorkspace() {
        let result = parseConfig(Self.toml.replacingOccurrences(of: "ctrl-alt-a = 'workspace Agent'", with: "ctrl-alt-a = 'workspace Work'"))
        assertFalse(result.allowReloadConfig)
        assertTrue(result.strErrors.contains { $0.contains("must directly run") })
    }

    func testConditionalEntryBindingPreventsConfigReload() {
        for command in ["false && workspace Agent", "true || workspace Agent"] {
            let result = parseConfig(Self.toml.replacingOccurrences(of: "ctrl-alt-a = 'workspace Agent'", with: "ctrl-alt-a = '\(command)'"))
            assertEquals(result.allowReloadConfig, false, additionalMsg: command)
            assertTrue(result.strErrors.contains { $0.contains("as a single command") })
        }
    }

    func testInvalidWorkspaceNamePreventsConfigReload() {
        let result = parseConfig(Self.toml.replacingOccurrences(of: "name = 'Agent'", with: "name = 'next'"))
        assertFalse(result.allowReloadConfig)
        assertTrue(result.strErrors.contains { $0.contains("reserved workspace name") })
    }

    func testUnknownConfigKeyIsReported() {
        let result = parseConfig("config-version = 2\n[agent-workspace]\nenabeld = true")
        assertTrue(result.strErrors.contains { $0.contains("agent-workspace.enabeld") })
    }
}

private struct SecondMonitor: MonitorInfo {
    let monitorAppKitNsScreenScreensId = 2
    let name = "Second Monitor"
    let rect = Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080)
    var visibleRect: Rect { rect }
    let width: CGFloat = 1920
    let height: CGFloat = 1080
    let isMain = false
}
