#!/bin/sh

# Set Session Name
SESSION=$1
SESSIONEXISTS=$(tmux list-sessions | grep $SESSION)

# Only create tmux session if it doesn't already exist
if [ "$SESSIONEXISTS" = "" ]
then
    # Start New Session with our name
    tmux new-session -d -s $SESSION

    # Name first window and start zsh
    tmux rename-window -t 0 'Main'
fi

# Attach Session, on the Main window
tmux attach-session -t $SESSION:0
