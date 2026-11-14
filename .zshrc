export PATH="/usr/bin:$PATH"
export PATH="$HOME/.npm-global/bin:$PATH"
# --- Powerlevel10k instant prompt (must be near the top) ---
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# --- Zinit (source only ONE location; this is the current standard path) ---
if [[ -f "$HOME/.local/share/zinit/zinit.git/zinit.zsh" ]]; then
  source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
else
  echo "⚠️ Zinit not found at $HOME/.local/share/zinit/zinit.git/zinit.zsh"
  echo 'Install: bash -c "$(curl -fsSL https://git.io/zinit-install)"'
fi

#custom dynamic folder navigation script.
source ~/.config/zsh/project_nav.zsh

# --- Theme: Powerlevel10k ---
zinit light romkatv/powerlevel10k

# Load your p10k config (created by `p10k configure`)
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# --- History ---
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt share_history hist_ignore_all_dups

# --- Completion (run once) ---
autoload -Uz compinit
compinit

# --- Key bindings ---
bindkey -e

# --- Plugins ---
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions

# --- OMZ core aliases ---
zinit snippet OMZ::plugins/common-aliases/common-aliases.plugin.zsh

# --- Useful OMZ snippets ---
zinit snippet OMZ::plugins/git/git.plugin.zsh
zinit snippet OMZ::plugins/kubectl/kubectl.plugin.zsh
zinit snippet OMZ::plugins/docker/docker.plugin.zsh
zinit snippet OMZ::plugins/terraform/terraform.plugin.zsh
zinit snippet OMZ::plugins/aws/aws.plugin.zsh

# Initialize completion system
autoload -Uz compinit
compinit

# Case-insensitive completion (preserve distinct matches)
zstyle ':completion:*' matcher-list \
  'm:{a-zA-Z}={A-Za-z}'


# Case-insensitive completion
#zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Menu selection when multiple matches exist
zstyle ':completion:*' menu select

# Keep original sorting (optional)
zstyle ':completion:*' sort false


# Add the dummy API key (required for the tool to start)
#echo 'export ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY"'

# Point to LM Studio's local server
#echo 'export ANTHROPIC_BASE_URL="https://openrouter.ai/api"'

# export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
#echo 'export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1'

# export Openrouter API Key
#echo 'export OPENROUTER_API_KEY=""'

# export Anthropic API Key
#echo 'export ANTHROPIC_API_KEY=""' # Important: Must be explicitly empty

# export Openrouter Free Models

#echo 'export ANTHROPIC_DEFAULT_OPUS_MODEL="qwen/qwen3-coder:free"'
#echo 'export ANTHROPIC_DEFAULT_SONNET_MODEL="google/gemma-4-31b-it:free"'
#echo 'export ANTHROPIC_DEFAULT_HAIKU_MODEL="nvidia/nemotron-3-super-120b-a12b:free"'
#echo 'export CLAUDE_CODE_SUBAGENT_MODEL="qwen/qwen3-next-80b-a3b-instruct:free"'


. "$HOME/.local/bin/env"

alias claude-server='uv run uvicorn server:app --host 0.0.0.0 --port 8082'

alias run-claude='ANTHROPIC_AUTH_TOKEN="freecc" ANTHROPIC_BASE_URL="http://localhost:8082" claude'

eval $(ssh-agent -s) > /dev/null 2>&1
ssh-add ~/.ssh/* 2>/dev/null

export PATH="$(npm prefix -g)/bin:$PATH"
