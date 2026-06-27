# TrainTracker Powerlevel10k segment
#
# Add `train` as the first entry in POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS,
# then paste the two functions below into ~/.p10k.zsh after prompt_example.

function prompt_train() {
  local s
  s=$(defaults read traintracker statusLine 2>/dev/null) || return
  p10k segment -f 43 -t "${s//\%/%%}"
}

function instant_prompt_train() {
  prompt_train
}
