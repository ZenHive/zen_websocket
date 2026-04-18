%Doctor.Config{
  ignore_modules: [
    # defrpc is a defmacro used by consumers; Doctor's macro-doc detection
    # under-counts it even though both macros have docstrings.
    ZenWebsocket.JsonRpc
  ],
  ignore_paths: [],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 100,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 100,
  moduledoc_required: true,
  exception_moduledoc_required: true,
  raise: true,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false,
  failed: false
}
