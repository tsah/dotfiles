case "$OSTYPE" in
  darwin*)
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    ;;
  linux*)
    # Auto-switch to tty2 only for direct TTY logins.
    if [ "$(tty)" = "/dev/tty1" ] && [ "${XDG_SESSION_TYPE:-tty}" = "tty" ] && [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        exec chvt 2
    fi
    ;;
esac
