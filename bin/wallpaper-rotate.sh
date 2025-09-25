#!/bin/bash
# Kill any existing swaybg instances
pkill swaybg

while true; do
  # Find all image files in the background directory
  IMAGE=$(find ~/background -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" \) 2>/dev/null | shuf -n 1)
  
  # Only set wallpaper if we found an image
  if [ -n "$IMAGE" ]; then
    swaybg -i "$IMAGE" -m fill &
    SWAYBG_PID=$!
    
    # Wait before changing (adjust time as needed)
    sleep 600  # 10 minutes
    
    # Kill the current wallpaper before setting a new one
    kill $SWAYBG_PID 2>/dev/null
  else
    # No images found, wait and try again
    echo "No images found in ~/background, waiting..."
    sleep 30
  fi
done
