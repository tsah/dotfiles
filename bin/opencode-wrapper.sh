#!/bin/bash

# Wrapper script for opencode that activates virtual environment if available

if [ -d ".venv" ]; then
    source .venv/bin/activate && opencode
else
    opencode
fi