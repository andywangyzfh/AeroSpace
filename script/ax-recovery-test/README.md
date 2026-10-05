# Accessibility recovery regression

Use a locally trusted `bobko.aerospace.debug` bundle containing the executable
under test. Keep the original release AeroSpace running. No other debug server
may be running. This script launches the candidate with `--read-only` and injects
faults into **that process only**; it additionally blocks Carbon hotkey
registration, including bootstrap bindings. It never suspends the release server.

```sh
python3 script/ax-recovery-test/run.py /path/to/AeroSpace-Agent.app \
  --report /tmp/ax-recovery.json --target-pid NON_FRONTMOST_APP_PID
```

The stale scenario invalidates cached AX application/window handles permanently;
newly created handles work. The transient scenario returns `cannotComplete`
until the fault is removed. The optional empty scenario presents a successful
empty window list for one application and invalidates that application's cached
windows, then restores them. This simulates close/rediscovery without closing a
user window. Each checks window identity, workspace and layout, and compares the
original manager's desktop state before and after.

The tests require macOS AX permission and real windows, so they are separate from
headless CI's full model/configuration/command regression suite. A passing result
establishes recovery from these injected failures, not the historical cause of
any particular incident or a guarantee about long-running sessions.
