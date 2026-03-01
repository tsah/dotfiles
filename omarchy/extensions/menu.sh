#!/bin/bash

if declare -F go_to_menu >/dev/null 2>&1; then
  original_go_to_menu_definition="$(declare -f go_to_menu)"
  eval "${original_go_to_menu_definition/go_to_menu/__omarchy_original_go_to_menu}"
fi

show_main_menu() {
  go_to_menu "$(menu "Go" "󰀻  Apps\n󰧑  Learn\n󱓞  Trigger\n  Startup\n  Style\n  Setup\n󰉉  Install\n󰭌  Remove\n  Update\n  About\n  System")"
}

go_to_menu() {
  case "${1,,}" in
  *startup*)
    "$HOME/dotfiles/bin/workspace-startup"
    ;;
  *)
    if declare -F __omarchy_original_go_to_menu >/dev/null 2>&1; then
      __omarchy_original_go_to_menu "$1"
    fi
    ;;
  esac
}
