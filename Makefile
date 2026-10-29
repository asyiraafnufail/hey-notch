TARGET = hey-notch
SRC = Sources/*.swift Sources/Views/*.swift
SWIFTC_FLAGS = -O -wmo -target x86_64-apple-macos13.0 -framework Cocoa -framework IOKit -framework CoreAudio -Xlinker -dead_strip -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist

APP_NAME = Hey Notch
APP_BUNDLE = $(APP_NAME).app
DMG_NAME = HeyNotch.dmg
PKG_NAME = HeyNotch.pkg

all: build

build:
	swiftc $(SWIFTC_FLAGS) $(SRC) -o $(TARGET)
	strip -x $(TARGET)

app: build
	rm -rf dist
	mkdir -p "dist/$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "dist/$(APP_BUNDLE)/Contents/Resources"
	cp $(TARGET) "dist/$(APP_BUNDLE)/Contents/MacOS/$(TARGET)"
	cp Info.plist "dist/$(APP_BUNDLE)/Contents/Info.plist"
	@echo "App bundle siap: dist/$(APP_BUNDLE)"

dmg: app
	rm -f $(DMG_NAME)
	ln -s /Applications dist/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder dist -ov -format UDZO $(DMG_NAME)
	rm -f dist/Applications
	@echo "DMG siap: $(DMG_NAME)"

pkg: app
	rm -f $(PKG_NAME)
	pkgbuild --component "dist/$(APP_BUNDLE)" --install-location /Applications $(PKG_NAME)
	@echo "PKG siap: $(PKG_NAME)"

install: app
	rm -rf "/Applications/$(APP_BUNDLE)"
	cp -R "dist/$(APP_BUNDLE)" /Applications/
	@echo "Terinstall di /Applications/$(APP_BUNDLE)"

run: build
	./$(TARGET)

clean:
	rm -rf $(TARGET) dist $(DMG_NAME) $(PKG_NAME)
