$ curl https://rtx.jdx.dev/rtx-latest-macos-arm64 > ~/bin/rtx
$ chmod +x ~/bin/rtx

# For the bash shell
$ echo 'eval "$(~/bin/rtx activate bash)"' >> ~/.bashrc

# For the zsh shell
$ echo 'eval "$(~/bin/rtx activate zsh)"' >> ~/.zshrc

# For the Fish shell
$ echo '~/bin/rtx activate fish | source' >> ~/.config/fish/config.fish

$ rtx install tuist

$ tuist version
3.25.0

# You should get a semantic version like shown above.
