# oncall-training-infra

## Tooling

All CLI versions are pinned in [`mise.toml`](mise.toml): terraform, tflint, kubectl, kustomize, kubeconform, kind, helm, node 22, pnpm, shellcheck and awscli v2.

```bash
brew install mise                 # or: curl https://mise.run | sh
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc   # then restart the shell
mise install                      # installs every pinned tool for this repo
mise ls --current                 # check what's active
```

Inside the repo, mise puts the pinned versions first on your `PATH`. Docker is also required (for `make images` and kind) and isn't managed by mise.
