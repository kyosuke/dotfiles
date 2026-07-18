#!/bin/sh
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"' | sed 's/^Claude //;s/ context//')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
dirname=$(basename "$cwd")

branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$branch" ]; then
  branch_part="󰘬 ${branch}  "
else
  branch_part=""
fi

# Helper: make_bar <percentage_int> <width>
make_bar() {
  pct=$1; width=$2
  filled=$(( pct * width / 100 ))
  empty=$(( width - filled ))
  bar=""; i=0
  while [ $i -lt $filled ]; do bar="${bar}█"; i=$(( i + 1 )); done
  i=0
  while [ $i -lt $empty ]; do bar="${bar}░"; i=$(( i + 1 )); done
  printf "%s" "$bar"
}

# Context bar (4 chars):
#   0-20%: white fills at 5% per char (4 chars = full at 20%)
#   >20%:  full bar, red chars replace from left at 25% increments
make_ctx_bar() {
  pct=$1
  if [ "$pct" -le 20 ]; then
    filled=$(( pct / 5 ))
    empty=$(( 4 - filled ))
    bar=""; i=0
    while [ $i -lt $filled ]; do bar="${bar}█"; i=$(( i + 1 )); done
    i=0
    while [ $i -lt $empty ]; do bar="${bar}░"; i=$(( i + 1 )); done
    printf "%s %d%%" "$bar" "$pct"
  else
    red=$(( pct / 25 ))
    [ "$red" -gt 4 ] && red=4
    white=$(( 4 - red ))
    fb=""; i=0
    while [ $i -lt "$red" ]; do fb="${fb}█"; i=$(( i + 1 )); done
    wb=""; i=0
    while [ $i -lt "$white" ]; do wb="${wb}█"; i=$(( i + 1 )); done
    printf "\033[31m%s\033[0m%s \033[31m%d%%\033[0m" "$fb" "$wb" "$pct"
  fi
}

# Format reset time from Unix timestamp: <HH:MM> today, <M/D HH:MM> future days
format_reset_time() {
  epoch=$1
  [ -z "$epoch" ] && return
  today=$(date "+%Y-%m-%d")
  reset_day=$(date -r "$epoch" "+%Y-%m-%d")
  reset_time=$(date -r "$epoch" "+%H:%M")
  if [ "$reset_day" = "$today" ]; then
    printf " <%s>" "$reset_time"
  else
    m=$((10#$(date -r "$epoch" "+%m")))
    d=$((10#$(date -r "$epoch" "+%d")))
    printf " <%d/%d %s>" "$m" "$d" "$reset_time"
  fi
}

if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  ctx_part="󰧑 $(make_ctx_bar "$used_int")"
else
  ctx_part="󰧑 ░░░░ -%"
fi

five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
rate_part=""
if [ -n "$five" ]; then
  five_int=$(printf "%.0f" "$five")
  reset_str=""
  [ "$five_int" -ge 25 ] && reset_str=$(format_reset_time "$five_resets")
  rate_part="  󱑍 $(make_bar "$five_int" 4) ${five_int}%${reset_str}"
fi
if [ -n "$week" ]; then
  week_int=$(printf "%.0f" "$week")
  reset_str=""
  [ "$week_int" -ge 25 ] && reset_str=$(format_reset_time "$week_resets")
  rate_part="${rate_part}  󰃭 $(make_bar "$week_int" 4) ${week_int}%${reset_str}"
fi

printf "󰉋 %s  %s󰚩 %s  %s%s" "$dirname" "$branch_part" "$model" "$ctx_part" "$rate_part"
