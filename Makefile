.PHONY: all build run

SRC_DIR := src/
SOURCES := $(shell find $(SRC_DIR) -name "*.odin")
APP_NAME := renderer

all: check

check:
	odin check $(SRC_DIR)

build: $(APP_NAME)

$(APP_NAME): $(SOURCES)
	odin build $(SRC_DIR) -out:$(APP_NAME)

run: $(SOURCES)
	odin run $(SRC_DIR) -out:$(APP_NAME) -- -width:800 -height:600

debug: $(SOURCES)
	odin build $(SRC_DIR) -out:$(APP_NAME) -debug
