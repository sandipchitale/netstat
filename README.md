# TCP Port Monitor (netstat)

A native macOS application built with SwiftUI that monitors active TCP ports, parses connections, and manages listening processes. 

Designed with modern macOS titlebar controls, resizable columns, and a clean minimalist aesthetic.

---

## Key Features

1. **Active TCP Ports Listing**: Displays process details, PID, protocol type (IPv4/IPv6/IPv4-6), local/remote addresses and ports, TCP states, and user details (login username and UID).
2. **Dual-Stack Awareness**: Wildcard listeners that `lsof` reports as IPv6 but actually accept both protocols (`tcp46`, e.g. Java/Tomcat/Spring Boot servers binding `*:8443`) are detected and tagged **IPv4/6**, so they remain visible under either the IPv4 or IPv6 filter.
3. **Titlebar-Integrated Controls**:
   - **IP Version Toggles**: Inline button stripe to filter between IPv4 and IPv6 (dual-stack listeners show under either).
   - **TCP State Toggles**: Inline button stripe to filter by connection state (`LISTEN`, `ESTABLISHED`, `CLOSE_WAIT`, `TIME_WAIT`, `Others`).
   - **Theme Selector**: Segmented control to switch between **Light**, **Dark**, and **System** themes.
   - **Auto-Refresh controls**: Integrated clock toggle, interval menu (1s to 60s), and manual refresh button.
4. **Table Interaction**:
   - **Resizable Columns**: User-adjustable column widths to fit process names and ports.
   - **Sorting**: Native sorting on headers (defaults to sorting by Local Port).
   - **Selection**: Selecting rows highlights them.
5. **Process Inspector**: Click the **(i)** next to a PID to open a resizable window showing, for that process:
   - the **full launch command** (`ps -ww -o command=`), wrapped and selectable;
   - the **working directory** (`lsof -d cwd`);
   - the **environment** it was launched with — a sorted `KEY=value` list read via the `KERN_PROCARGS2` sysctl (the same source `ps` uses);
   - the originating connection's state and local/remote address, plus a **Kill Process** button that terminates it and refreshes the table.
   - Details for processes owned by other users may be unavailable without elevated privileges.
6. **Process Termination**:
   - Hover actions or a right-click context menu option to terminate listening processes.
   - Support for **Normal Kill** and **Sudo Kill** (authenticates securely via standard macOS system authorization dialogs).
   - Killing from the table or the inspector immediately refreshes the listing so the row disappears.
7. **Port Filter Bar**: Search connections by PID/process name/IP, or monitor specific comma-separated port numbers (e.g. `80, 443, 8080`).

---

## Build & Install

The `netstat.app` bundle is a **build artifact** and is not committed to git — it
is recreated from source by `build-app.sh`. The bundle's inputs (`Info.plist`,
`AppIcon.icns`) live in `packaging/` and are version-controlled.

```bash
# Build the release binary and assemble ./netstat.app
./build-app.sh

# Build, then copy the bundle into /Applications
./build-app.sh --install

# Build, install, and (re)launch the app
./build-app.sh --install --run
```

To install manually instead, drag the freshly built `netstat.app` into your
**Applications** folder, then launch **TCP Port Monitor** from Launchpad or
Spotlight.

### Project layout
- `Sources/` — Swift source (compiled by SwiftPM; see `Package.swift`).
- `packaging/` — app bundle inputs: `Info.plist` and `AppIcon.icns`.
- `build-app.sh` — compiles the binary and assembles `netstat.app`.
- `netstat.app/` — generated bundle (git-ignored).

---

## Code Architecture

- **`Sources/Connection.swift`**: Models a parsed socket connection (`Codable`/`Hashable` so it can be passed as a window value), including the dual-stack protocol type.
- **`Sources/ConnectionMonitor.swift`**: Asynchronously calls `lsof` to capture networking metrics in a single-pass O(N) filter pass, controls the auto-refresh timer, terminates processes, and fetches per-process details (full command via `ps`, working directory via `lsof`, environment via the `KERN_PROCARGS2` sysctl).
- **`Sources/ContentView.swift`**: The main GUI (titlebar layout, filters, resizable table) plus `CommandWindow`, the per-process inspector window.
- **`Sources/NetstatApp.swift`**: Defines the app scenes — the main window and the resizable "Launch Command" `WindowGroup` — sharing a single `ConnectionMonitor` so any window can refresh the table.
