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
5. **Process Termination**:
   - Hover actions or a right-click context menu option to terminate listening processes.
   - Support for **Normal Kill** and **Sudo Kill** (authenticates securely via standard macOS system authorization dialogs).
6. **Port Filter Bar**: Search connections by PID/process name/IP, or monitor specific comma-separated port numbers (e.g. `80, 443, 8080`).

---

## App Installation

We package the production release build of the application directly as a standard macOS app container.

### How to Install
1. Open Finder at the root workspace directory.
2. Locate `netstat.app` (which displays with the custom minimalist line-art icon).
3. Drag and drop `netstat.app` into your **Applications** folder.
4. Launch **TCP Port Monitor** from your Launchpad, Applications folder, or Spotlight.

---

## How to Build Manually

To rebuild the project and package it:

```bash
# 1. Compile release binary
swift build -c release

# 2. Copy the binary into the app bundle container
cp .build/release/netstat netstat.app/Contents/MacOS/netstat
chmod +x netstat.app/Contents/MacOS/netstat

# 3. Compile and refresh the application icon (using helper script)
./.gemini/antigravity-ide/scratch/create_icons.sh
```

---

## Code Architecture

- **`Sources/Connection.swift`**: Models a parsed socket connection structure containing comparable and queryable keys.
- **`Sources/ConnectionMonitor.swift`**: Asynchronously calls `lsof` to capture networking metrics in a single-pass O(N) filter pass, controls the auto-refresh timer, and handles process termination.
- **`Sources/ContentView.swift`**: The main GUI containing the titlebar layout, input forms, and resizable data table.
- **`Sources/NetstatApp.swift`**: Sets up the app window group with ideal size constraints of 1800x900.
