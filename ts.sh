#!/bin/sh
# Join or create tmux session

# Set Session Name
SESSION=$1
SESSIONEXISTS=$(tmux list-sessions | grep $SESSION)

# Only create tmux session if it doesn't already exist
if [ "$SESSIONEXISTS" = "" ]
then
    echo 'Session not found'
    # Start New Session with our name
    tmux new-session -d -s $SESSION

    # Name first window and start zsh
    tmux rename-window -t 1 'Main'
fi

# Attach Session, on the Main window
tmux attach-session -t $SESSION:1
