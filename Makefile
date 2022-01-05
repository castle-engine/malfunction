# This Makefile uses "castle-engine" build tool for most operations
# (like compilation).
# See https://castle-engine.io/build_tool
# for instructions how to install/use this build tool.

.PHONY: standalone
standalone:
	castle-engine compile $(CASTLE_ENGINE_TOOL_OPTIONS)

.PHONY: clean
clean:
	castle-engine clean
