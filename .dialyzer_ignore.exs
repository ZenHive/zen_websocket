[
  # Mix.Task callback warnings are a known dialyzer issue
  {"lib/mix/tasks/stability_test.ex", :callback_info_missing},
  {"lib/mix/tasks/zen_websocket.usage.ex", :callback_info_missing},
  {"lib/mix/tasks/zen_websocket.validate_usage.ex", :callback_info_missing},
  # Mix module functions are not available during Dialyzer analysis
  {"lib/mix/tasks/zen_websocket.usage.ex", :unknown_function},
  {"lib/mix/tasks/zen_websocket.validate_usage.ex", :unknown_function}
]