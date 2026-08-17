.PHONY: all run run-x

TARGET_IMAGE = test.ppm
SOURCES = $(shell find . -name "*.odin")

all: run

run: $(TARGET_IMAGE)
	./test.bash "$(TARGET_IMAGE)"

$(TARGET_IMAGE): $(SOURCES)
	odin run src -- -output:"$(TARGET_IMAGE)" -width:800 -height:600
