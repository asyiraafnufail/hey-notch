TARGET = hey-notch
SRC = Sources/main.swift
SWIFTC_FLAGS = -O -target x86_64-apple-macos13.0 -framework Cocoa -framework IOKit -framework CoreAudio -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist

all: build

build:
	swiftc $(SWIFTC_FLAGS) $(SRC) -o $(TARGET)

run: build
	./$(TARGET)

clean:
	rm -f $(TARGET)
