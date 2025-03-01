#!/bin/bash

# Run all tests in the directory
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'minimal_init.lua'}" -c "q"
