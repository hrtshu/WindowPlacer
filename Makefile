PROJECT_NAME = WindowPlacer
SCHEME_NAME = WindowPlacer
CONFIGURATION = Release

build:
	pod install
	xcodebuild -workspace $(PROJECT_NAME).xcworkspace -scheme $(SCHEME_NAME) -configuration $(CONFIGURATION)
