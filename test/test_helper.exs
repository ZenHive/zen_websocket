require Logger
## Configure Logger to only show warnings and errors
# [:none, :info, :warning, :debug]
# Logger.configure(level: :info)

ExUnit.start(exclude: [:stability, :stability_dev])
