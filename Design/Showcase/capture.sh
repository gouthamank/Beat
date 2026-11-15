#!/bin/bash
# Captures Beat Test's window (from `make mac-run-showcase`) as a website screenshot: the window alone, without its
# shadow (the site draws its own), at the screen's full resolution, named for the current appearance.
#   Design/Showcase/capture.sh <name>    writes site/src/assets/shots/<name>-<light|dark>.png
# The first capture may ask to let the terminal record the screen (System Settings > Privacy & Security).
set -euo pipefail
name=${1:?usage: capture.sh <name>}
# The frontmost on-screen window of Beat Test (the UI-test build's display name), by window number.
id=$(swift - <<'EOF'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let beat = windows.first { ($0[kCGWindowOwnerName as String] as? String) == "Beat Test" && ($0[kCGWindowLayer as String] as? Int) == 0 }
print((beat?[kCGWindowNumber as String] as? Int).map(String.init) ?? "")
EOF
)
[ -n "$id" ] || { echo "No Beat Test window on screen: run make mac-run-showcase first." >&2; exit 1; }
appearance=$([ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ] && echo dark || echo light)
out="site/src/assets/shots/$name-$appearance.png"
mkdir -p "$(dirname "$out")"
screencapture -l "$id" -o -x "$out"
echo "$out ($(sips -g pixelWidth -g pixelHeight "$out" | awk '/pixel/ {printf "%s ", $2}'))"
