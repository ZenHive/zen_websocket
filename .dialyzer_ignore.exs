[
  # LatencyStats uses the :queue opaque type in its struct — dialyzer flags new/1's @spec.
  # Verified 2026-08-20: this is the ONLY live suppression. Five further entries
  # (subscription_manager contract_with_opaque, and callback_info_missing /
  # unknown_function for the two mix tasks) were reported by dialyzer as unnecessary
  # skips and removed. Re-add an entry only after seeing the warning it suppresses.
  {"lib/zen_websocket/latency_stats.ex", :contract_with_opaque}
]
