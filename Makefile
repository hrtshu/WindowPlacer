PROJECT_NAME = WindowPlacer
SCHEME_NAME = WindowPlacer

build:
	pod install
	xcodebuild -workspace $(PROJECT_NAME).xcworkspace \
		-scheme $(SCHEME_NAME) \
		-configuration Release \
		DEBUG_INFORMATION_FORMAT=dwarf \
		GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
		SWIFT_COMPILATION_MODE=wholemodule \
		ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=NO \
		OTHER_CFLAGS="-fdebug-prefix-map=$(HOME)=."
