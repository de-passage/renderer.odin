.PHONY: all build run

SOURCES := $(shell find . -name "*.odin")
APP_NAME := renderer

all: build

build: $(APP_NAME)

$(APP_NAME): $(SOURCES)
	odin build src -out:$(APP_NAME)

run: $(SOURCES)
	odin run src -out:$(APP_NAME) -- -width:800 -height:600

debug: $(SOURCES)
	odin build src -out:$(APP_NAME) -debug
