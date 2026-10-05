# Agent workspace

This fork can reserve a workspace for agent-operated windows. When the workspace
is hidden, activating one of its apps does not switch the visible workspace.
Only a configured AeroSpace hotkey can reveal it. The feature is off by default.

Merge the following into your configuration (do not replace your existing binding table):

```toml
[agent-workspace]
enabled = true
name = 'Agent'
entry-binding = 'ctrl-alt-a'
entry-mode = 'main'

[mode.main.binding]
ctrl-alt-a = 'workspace Agent'
```

Add `Agent` to `persistent-workspaces` if you want it to exist when empty. Move
agent-operated windows into it using `move-node-to-workspace --window-id ID Agent`,
without `--focus-follows-window`. For Codex itself you can add:

```toml
[[on-window-detected]]
if.app-id = 'com.openai.codex'
run = 'move-node-to-workspace Agent'
```

Other applications should be assigned by individual window when you also use
them yourself. This policy does not constrain which apps an agent can operate.

Use the configured hotkey to enter Agent and your ordinary workspace hotkeys to
leave. Cmd+Tab, Dock activation, `workspace`, `focus`, `summon-workspace`, and
`trigger-binding` cannot reveal a hidden Agent workspace. Once it is visible,
normal focus within it continues to work. Other workspaces behave normally.
The policy also prevents pulling the visible Agent workspace onto another monitor
through ordinary commands. Monitor rearrangement preserves an already visible
workspace; fallback monitor workspaces never select a hidden Agent workspace.

Set `agent-workspace.enabled = false` and reload to restore upstream behavior.
Invalid names or a missing entry binding prevent config reload to avoid lockout.

## Limits

- The registered hotkey is an entry mechanism, not a human-authentication boundary.
  An agent that synthesizes the same key combination may still activate it.
- Keeping the workspace hidden does not prevent macOS keyboard focus from moving
  to an agent-operated app. Typing or Cmd+W can affect a hidden app.
- Desktop computer-use tools that need visible screen coordinates may fail on
  off-screen windows. Background screenshots and input must be tested per app.
- Native fullscreen, system dialogs, app menus, and disabling AeroSpace itself
  are outside this visibility policy.
- The permission is scoped to execution of the configured hotkey's commands;
  later socket requests do not inherit it.

Run `swift test --filter AgentWorkspaceTest` for the policy regression tests,
and `swift test` for the full suite. A desktop trial is separate from these
model tests and should keep the stock app available for rollback.
