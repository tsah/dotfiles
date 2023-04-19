#!/bin/sh

ln -sf ~/dotfiles/nvim ~/.config/nvim
ln -sf ~/dotfiles/.zshrc ~/.zshrc
# ln -sf ~/dotfiles/.tmux.conf ~/.tmux.conf
ln -sf ~/dotfiles/.yabairc ~/.yabairc
ln -sf ~/dotfiles/.skhdrc ~/.skhdrc

pushd ~
if [ ! -d .tmux ]; then
  git clone https://github.com/gpakosz/.tmux.git
  ln -s -f .tmux/.tmux.conf
fi
cp ~/dotfiles/.tmux.conf.local .
popd
