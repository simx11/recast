.PHONY: app run install test icon clean

# Build build/Recast.app
app:
	scripts/build.sh release

# Build and launch from the build folder
run: app
	-pkill -x Recast
	open build/Recast.app

# Build and install into /Applications
install: app
	-pkill -x Recast
	rm -rf /Applications/Recast.app
	cp -R build/Recast.app /Applications/Recast.app
	open /Applications/Recast.app

test:
	swift test

# Regenerate Resources/AppIcon.icns
icon:
	scripts/make-icon.sh

clean:
	rm -rf .build build
