# TODO

## Now

- Complete and record the real-device background, restart, permission, route-quality, timezone/DST, and multi-day energy checks in `TESTING.md`. Passing simulator tests does not validate Core Location scheduling or battery usage.
- Complete the paired iPhone/Apple Watch checks in `TESTING.md`: install/upgrade, application-context delivery, explicit refresh, cached fallback, Shortcut execution, WidgetKit complication discoverability, watchOS background refresh, Core Location relaunch isolation, and before/after energy comparison.
- Preserve original timestamps through GeoJSON export/import. The current export omits them and import assigns new sequential timestamps starting at import time.
