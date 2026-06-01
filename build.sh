#!/bin/zsh

swift build -c release && cp $(swift build -c release --show-bin-path)/t ~/.local/bin/t