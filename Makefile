TARGET = hey-notch
SRC = Sources/*.swift Sources/Views/*.swift
SWIFTC_FLAGS = -O -wmo -target x86_64-apple-macos13.0 -framework Cocoa -framework IOKit -framework CoreAudio -Xlinker -dead_strip -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist

all: build

build:
	swiftc $(SWIFTC_FLAGS) $(SRC) -o $(TARGET)
	strip -x $(TARGET)

run: build
	./$(TARGET)

clean:
	rm -f $(TARGET)
