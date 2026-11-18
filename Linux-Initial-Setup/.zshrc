export PATH="/usr/bin:$PATH"
export PATH="$HOME/.npm-global/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
# --- Powerlevel10k instant prompt (must be near the top) ---
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi


# --- Zinit (source only ONE location; this is the current standard path) ---
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
if [[ ! -f "$ZINIT_HOME/zinit.zsh" ]] && command -v git >/dev/null 2>&1; then
  mkdir -p "${ZINIT_HOME:h}"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
if [[ -f "$ZINIT_HOME/zinit.zsh" ]]; then
  source "$ZINIT_HOME/zinit.zsh"
else
  echo "Zinit not found at $ZINIT_HOME/zinit.zsh (git missing or clone failed)"
fi
HAVE_ZINIT=$(( $+functions[zinit] ))


#custom dynamic folder navigation script.
[[ -f ~/.config/zsh/project_nav.zsh ]] && source ~/.config/zsh/project_nav.zsh


# --- Theme: Powerlevel10k ---
if (( HAVE_ZINIT )); then
  zinit ice depth=1
  zinit light romkatv/powerlevel10k
fi


# Load your p10k config (created by `p10k configure`)
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh


# --- History ---
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt share_history hist_ignore_all_dups


# --- Key bindings ---
bindkey -e


# --- Completion styles (set before compinit) ---
# Case-insensitive completion (preserve distinct matches)
zstyle ':completion:*' matcher-list \
  'm:{a-zA-Z}={A-Za-z}'

# Menu selection when multiple matches exist
zstyle ':completion:*' menu select

# Keep original sorting (optional)
zstyle ':completion:*' sort false


# --- Plugins (completion providers load BEFORE compinit) ---
if (( HAVE_ZINIT )); then
  zinit light zsh-users/zsh-completions
  zinit light zsh-users/zsh-autosuggestions

  # --- OMZ core aliases ---
  zinit snippet OMZ::plugins/common-aliases/common-aliases.plugin.zsh

  # --- Useful OMZ snippets ---
  zinit snippet OMZ::plugins/git/git.plugin.zsh
  zinit snippet OMZ::plugins/kubectl/kubectl.plugin.zsh
  zinit snippet OMZ::plugins/docker/docker.plugin.zsh
  zinit snippet OMZ::plugins/terraform/terraform.plugin.zsh
  zinit snippet OMZ::plugins/aws/aws.plugin.zsh
fi


# --- Completion (run once) ---
autoload -Uz compinit
compinit
(( HAVE_ZINIT )) && zinit cdreplay -q


# --- Syntax highlighting (must load last) ---
(( HAVE_ZINIT )) && zinit light zsh-users/zsh-syntax-highlighting


# --- Optional private settings (API keys etc.). chmod 600; never commit ---
[[ -f ~/.zsh_secrets ]] && source ~/.zsh_secrets


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


[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"


alias claude-server='uv run uvicorn server:app --host 0.0.0.0 --port 8082'


alias run-claude='ANTHROPIC_AUTH_TOKEN="freecc" ANTHROPIC_BASE_URL="http://localhost:8082" claude'


# --- SSH agent: reuse one agent per login instead of spawning a new one per shell ---
_agent_env="${XDG_CACHE_HOME:-$HOME/.cache}/ssh-agent.env"
mkdir -p "${_agent_env:h}"
ssh-add -l >/dev/null 2>&1; _rc=$?
if [[ $_rc -eq 2 ]]; then
  [[ -r "$_agent_env" ]] && source "$_agent_env" >/dev/null
  ssh-add -l >/dev/null 2>&1; _rc=$?
  if [[ $_rc -eq 2 ]]; then
    ssh-agent -s > "$_agent_env" 2>/dev/null
    chmod 600 "$_agent_env"
    source "$_agent_env" >/dev/null
    ssh-add -l >/dev/null 2>&1; _rc=$?
  fi
fi
if [[ $_rc -eq 1 ]]; then
  for _key in ~/.ssh/*(N-.); do
    [[ "$_key" == *.pub ]] && continue
    grep -q "PRIVATE KEY" "$_key" 2>/dev/null && ssh-add "$_key" 2>/dev/null
  done
fi
unset _agent_env _rc _key


# --- npm global bin (kept from original; guarded so a missing npm doesn't error) ---
if command -v npm >/dev/null 2>&1; then
  export PATH="$(npm prefix -g)/bin:$PATH"
fi
typeset -U PATH path   # drop duplicate PATH entries
