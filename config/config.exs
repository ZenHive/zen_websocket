import Config

export_dir =
  if Mix.env() == :test do
    System.tmp_dir!() <> "/zen_websocket_test_exports"
  else
    "exports/"
  end

config :zen_websocket, export_dir: export_dir
