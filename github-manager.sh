#!/usr/bin/env bash

# ─────────────────────────────────────────────
#  Load .env file
# ─────────────────────────────────────────────
ENV_FILE="$(dirname "$0")/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo -e "\033[0;31m✗ Could not find .env file at: $ENV_FILE\033[0m"
  exit 1
fi

# Export all variables from .env (ignore comments and blank lines)
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# ─────────────────────────────────────────────
#  Colour definitions
# ─────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
WHITE="\033[1;37m"
DIM="\033[2m"

# ─────────────────────────────────────────────
#  Helper: print a section header
# ─────────────────────────────────────────────
print_header() {
  echo ""
  echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${BLUE}║  ${WHITE}$1$(printf '%*s' $((40 - ${#1})) '')${BLUE}║${RESET}"
  echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════╝${RESET}"
  echo ""
}

# ─────────────────────────────────────────────
#  Validate required .env variables
# ─────────────────────────────────────────────
validate_env() {
  local missing=()
  [[ -z "$GITHUB_USERNAME" ]] && missing+=("GITHUB_USERNAME")
  [[ -z "$GITHUB_TOKEN" ]]    && missing+=("GITHUB_TOKEN")
  [[ -z "$GITHUB_ORG" ]]      && missing+=("GITHUB_ORG")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}✗ The following variables are missing from your .env file:${RESET}"
    for var in "${missing[@]}"; do
      echo -e "  ${YELLOW}• $var${RESET}"
    done
    echo ""
    echo -e "${DIM}Example .env file:${RESET}"
    echo -e "${DIM}  GITHUB_USERNAME=your-username${RESET}"
    echo -e "${DIM}  GITHUB_TOKEN=ghp_xxxxxxxxxxxx${RESET}"
    echo -e "${DIM}  GITHUB_ORG=your-organisation${RESET}"
    exit 1
  fi
}

# ─────────────────────────────────────────────
#  Check for required tools
# ─────────────────────────────────────────────
check_dependencies() {
  local missing=()
  command -v git  &>/dev/null || missing+=("git")
  command -v curl &>/dev/null || missing+=("curl")
  command -v jq   &>/dev/null || missing+=("jq")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}✗ The following tools are required but not installed:${RESET}"
    for tool in "${missing[@]}"; do
      echo -e "  ${YELLOW}• $tool${RESET}"
    done
    exit 1
  fi
}

# ─────────────────────────────────────────────
#  GitHub API helper
# ─────────────────────────────────────────────
gh_api() {
  curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "$@"
}

# ─────────────────────────────────────────────
#  Verify GitHub login
# ─────────────────────────────────────────────
verify_login() {
  echo -e "${CYAN}⟳  Connecting to GitHub as ${BOLD}${GITHUB_USERNAME}${RESET}${CYAN}...${RESET}"

  local response
  response=$(gh_api "https://api.github.com/user")

  local api_login
  api_login=$(echo "$response" | jq -r '.login // empty')

  if [[ -z "$api_login" ]]; then
    echo -e "${RED}✗ Could not authenticate with GitHub. Please check your GITHUB_TOKEN.${RESET}"
    exit 1
  fi

  echo -e "${GREEN}✔  Logged in as: ${BOLD}${api_login}${RESET}"
  echo -e "${GREEN}✔  Organisation: ${BOLD}${GITHUB_ORG}${RESET}"
}

# ─────────────────────────────────────────────
#  Fetch list of org repos (handles pagination)
# ─────────────────────────────────────────────
fetch_projects() {
  local page=1
  ALL_REPOS=()
  ALL_DESCS=()

  echo -e "${CYAN}⟳  Fetching projects from ${BOLD}${GITHUB_ORG}${RESET}${CYAN}...${RESET}"

  while true; do
    local response
    response=$(gh_api "https://api.github.com/orgs/${GITHUB_ORG}/repos?per_page=100&page=${page}&type=all")

    [[ $(echo "$response" | jq 'length') -eq 0 ]] && break

    # Extract name and description together as tab-separated pairs — keeps them in sync
    while IFS=$'\t' read -r name desc; do
      ALL_REPOS+=("$name")
      ALL_DESCS+=("$desc")
    done < <(echo "$response" | jq -r '.[] | [.name, (.description // "")] | @tsv')

    (( page++ ))
  done

  if [[ ${#ALL_REPOS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}⚠  No projects found in organisation '${GITHUB_ORG}'.${RESET}"
    exit 1
  fi

  # Sort alphabetically, keeping name+description paired
  local sorted_repos=() sorted_descs=()
  while IFS=$'\t' read -r name desc; do
    sorted_repos+=("$name")
    sorted_descs+=("$desc")
  done < <(
    for i in "${!ALL_REPOS[@]}"; do
      printf '%s\t%s\n' "${ALL_REPOS[$i]}" "${ALL_DESCS[$i]}"
    done | sort -f
  )
  ALL_REPOS=("${sorted_repos[@]}")
  ALL_DESCS=("${sorted_descs[@]}")
}

# ─────────────────────────────────────────────
#  Display numbered project list
# ─────────────────────────────────────────────
display_projects() {
  echo ""
  echo -e "${BOLD}${WHITE}Available projects in ${CYAN}${GITHUB_ORG}${WHITE}:${RESET}"
  echo -e "${DIM}─────────────────────────────────────────────${RESET}"
  local i=0
  for repo in "${ALL_REPOS[@]}"; do
    printf "  ${CYAN}%3d.${RESET}  ${WHITE}%s${RESET}\n" "$((i+1))" "$repo"
    local desc="${ALL_DESCS[$i]}"
    if [[ -n "$desc" ]]; then
      printf "        ${DIM}%s${RESET}\n" "$desc"
    fi
    echo ""
    (( i++ ))
  done
  echo -e "${DIM}─────────────────────────────────────────────${RESET}"
  echo ""
}

# ─────────────────────────────────────────────
#  OPTION 1 — Download a project
# ─────────────────────────────────────────────
download_project() {
  print_header "Download a Project"

  fetch_projects
  display_projects

  # Ask user to pick a project
  local choice
  while true; do
    echo -ne "${YELLOW}Enter the number of the project to download: ${RESET}"
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ALL_REPOS[@]} )); then
      break
    fi
    echo -e "${RED}✗ Invalid choice. Please enter a number between 1 and ${#ALL_REPOS[@]}.${RESET}"
  done

  local repo_name="${ALL_REPOS[$((choice - 1))]}"
  local remote_url="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${GITHUB_ORG}/${repo_name}.git"
  local display_url="https://github.com/${GITHUB_ORG}/${repo_name}"

  echo ""
  echo -e "${GREEN}✔  Selected: ${BOLD}${repo_name}${RESET}"
  echo ""

  # Ask where to save it
  echo -ne "${YELLOW}Where would you like to save it? ${DIM}(default: ./${repo_name})${RESET}${YELLOW}: ${RESET}"
  read -r dest_input
  local dest="${dest_input:-"./${repo_name}"}"

  # Expand ~ if used
  dest="${dest/#\~/$HOME}"

  # Check if folder exists
  if [[ -d "$dest" ]]; then
    echo ""
    echo -e "${YELLOW}⚠  The folder ${BOLD}${dest}${RESET}${YELLOW} already exists.${RESET}"
    echo -ne "${YELLOW}   The existing contents will be replaced. Continue? ${BOLD}[y/n]${RESET}${YELLOW}: ${RESET}"
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      echo -e "${CYAN}⟳  Clearing folder...${RESET}"
      rm -rf "$dest"
    else
      echo -e "${RED}✗ Download cancelled.${RESET}"
      return
    fi
  fi

  # Clone the repo
  echo ""
  echo -e "${CYAN}⟳  Downloading ${BOLD}${repo_name}${RESET}${CYAN} into ${BOLD}${dest}${RESET}${CYAN}...${RESET}"

  if git clone "$remote_url" "$dest" 2>&1 | while IFS= read -r line; do
      echo -e "   ${DIM}${line}${RESET}"
    done; then

    # Set the remote URL (using display-friendly name, auth already embedded)
    git -C "$dest" remote set-url origin "$remote_url" 2>/dev/null

    echo ""
    echo -e "${GREEN}✔  Project downloaded successfully!${RESET}"
    echo -e "${GREEN}   Location : ${BOLD}${dest}${RESET}"
    echo -e "${GREEN}   Source   : ${BOLD}${display_url}${RESET}"
    echo ""
    echo -e "${DIM}   The project is ready to work on. When you're done, use the${RESET}"
    echo -e "${DIM}   Sync option from the main menu to save and upload your changes.${RESET}"
  else
    echo ""
    echo -e "${RED}✗ Download failed. Please check your connection and permissions.${RESET}"
  fi
}

# ─────────────────────────────────────────────
#  OPTION 2 — Sync an existing project
# ─────────────────────────────────────────────
sync_project() {
  print_header "Sync a Project"

  # Determine where to look for local projects
  local search_dir="${PROJECTS_DIR:-$(dirname "$0")}"
  search_dir="${search_dir/#\~/$HOME}"

  # Find all subfolders that are git projects
  local LOCAL_PROJECTS=()
  while IFS= read -r -d $'\0' dir; do
    LOCAL_PROJECTS+=("$dir")
  done < <(find "$search_dir" -mindepth 1 -maxdepth 1 -type d -exec test -d "{}/.git" \; -print0 | sort -z)

  if [[ ${#LOCAL_PROJECTS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}⚠  No local projects found in: ${BOLD}${search_dir}${RESET}"
    echo -e "${DIM}   Download a project first, or set PROJECTS_DIR in your .env file.${RESET}"
    return
  fi

  # Display numbered list
  echo ""
  echo -e "${BOLD}${WHITE}Local projects in ${CYAN}${search_dir}${WHITE}:${RESET}"
  echo -e "${DIM}─────────────────────────────────────────────${RESET}"
  local i=1
  for proj in "${LOCAL_PROJECTS[@]}"; do
    printf "  ${CYAN}%3d.${RESET}  ${WHITE}%s${RESET}\n" "$i" "$(basename "$proj")"
    (( i++ ))
  done
  echo -e "${DIM}─────────────────────────────────────────────${RESET}"
  echo ""

  # Ask user to pick
  local choice
  while true; do
    echo -ne "${YELLOW}Enter the number of the project to sync: ${RESET}"
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#LOCAL_PROJECTS[@]} )); then
      break
    fi
    echo -e "${RED}✗ Invalid choice. Please enter a number between 1 and ${#LOCAL_PROJECTS[@]}.${RESET}"
  done

  local project_path="${LOCAL_PROJECTS[$((choice - 1))]}"
  local project_name
  project_name=$(basename "$project_path")

  echo ""
  echo -e "${GREEN}✔  Selected: ${BOLD}${project_name}${RESET}"
  echo ""

  # ── Check for local changes ──────────────────
  echo -e "${CYAN}⟳  Checking for local changes...${RESET}"

  local status_output
  status_output=$(git -C "$project_path" status --porcelain 2>&1)

  if [[ -n "$status_output" ]]; then
    echo ""
    echo -e "${YELLOW}⚠  You have unsaved local changes:${RESET}"
    echo ""

    # Show changed files nicely
    while IFS= read -r line; do
      local flag="${line:0:2}"
      local file="${line:3}"
      case "$flag" in
        " M"|"M "|"MM") echo -e "   ${YELLOW}~ Modified :${RESET} ${file}" ;;
        " D"|"D "|"DD") echo -e "   ${RED}✗ Deleted  :${RESET} ${file}" ;;
        "??")            echo -e "   ${CYAN}+ New file :${RESET} ${file}" ;;
        "A "|" A")       echo -e "   ${GREEN}+ Added    :${RESET} ${file}" ;;
        *)               echo -e "   ${DIM}  ${flag}         :${RESET} ${file}" ;;
      esac
    done <<< "$status_output"

    echo ""

    # Ask for a change description (commit message)
    local commit_msg
    while true; do
      echo -ne "${YELLOW}Describe the changes you are saving (required): ${RESET}"
      read -r commit_msg
      if [[ -n "$commit_msg" ]]; then
        break
      fi
      echo -e "${RED}✗ A description is required.${RESET}"
    done

    # Stage all changes
    echo ""
    echo -e "${CYAN}⟳  Saving your changes...${RESET}"
    git -C "$project_path" add -A 2>&1 | while IFS= read -r line; do echo -e "   ${DIM}${line}${RESET}"; done

    # Commit
    if git -C "$project_path" commit -m "$commit_msg" 2>&1 | while IFS= read -r line; do
        echo -e "   ${DIM}${line}${RESET}"
      done; then
      echo -e "${GREEN}✔  Changes saved with description: ${BOLD}\"${commit_msg}\"${RESET}"
    else
      echo -e "${RED}✗ Could not save changes. Please check the output above.${RESET}"
      return
    fi

  else
    echo -e "${GREEN}✔  No new local changes — checking if anything still needs uploading...${RESET}"
  fi

  # ── Always push to ensure remote is up to date ──
  echo ""
  echo -e "${CYAN}⟳  Uploading any pending changes to GitHub...${RESET}"
  local branch
  branch=$(git -C "$project_path" rev-parse --abbrev-ref HEAD)

  local push_output
  push_output=$(git -C "$project_path" push origin "$branch" 2>&1)
  local push_exit=$?

  echo "$push_output" | while IFS= read -r line; do
    echo -e "   ${DIM}${line}${RESET}"
  done

  if [[ $push_exit -eq 0 ]]; then
    if echo "$push_output" | grep -q "Everything up-to-date"; then
      echo -e "${GREEN}✔  Remote is already up to date.${RESET}"
    else
      echo -e "${GREEN}✔  Changes uploaded successfully!${RESET}"
    fi
  else
    echo -e "${RED}✗ Upload failed. Please check your connection and permissions.${RESET}"
    return
  fi

  # ── Pull latest changes from GitHub ─────────
  echo ""
  echo -e "${CYAN}⟳  Fetching the latest version from GitHub...${RESET}"

  local pull_output
  pull_output=$(git -C "$project_path" pull 2>&1)
  local pull_exit=$?

  echo "$pull_output" | while IFS= read -r line; do
    echo -e "   ${DIM}${line}${RESET}"
  done

  echo ""
  if [[ $pull_exit -eq 0 ]]; then
    if echo "$pull_output" | grep -q "Already up to date"; then
      echo -e "${GREEN}✔  Project is fully up to date — no new changes from GitHub.${RESET}"
    else
      echo -e "${GREEN}✔  Project updated with the latest changes from GitHub!${RESET}"
    fi
  else
    echo -e "${YELLOW}⚠  There may have been a problem fetching the latest version. Check the output above.${RESET}"
  fi
}

# ─────────────────────────────────────────────
#  Main menu
# ─────────────────────────────────────────────
main_menu() {
  while true; do
    print_header "GitHub Project Manager"

    echo -e "  ${CYAN}${BOLD}1.${RESET}  ${WHITE}Download a new project${RESET}"
    echo -e "      ${DIM}Get a project from GitHub onto your computer${RESET}"
    echo ""
    echo -e "  ${CYAN}${BOLD}2.${RESET}  ${WHITE}Sync an existing project${RESET}"
    echo -e "      ${DIM}Save your changes and get the latest updates${RESET}"
    echo ""
    echo -e "  ${RED}${BOLD}q.${RESET}  ${WHITE}Quit${RESET}"
    echo ""
    echo -e "${DIM}─────────────────────────────────────────────${RESET}"
    echo -ne "${YELLOW}Choose an option ${BOLD}[1, 2, or q]${RESET}${YELLOW}: ${RESET}"
    read -r main_choice

    case "$main_choice" in
      1) download_project ;;
      2) sync_project ;;
      q|Q)
        echo ""
        echo -e "${GREEN}Goodbye!${RESET}"
        echo ""
        exit 0
        ;;
      *)
        echo ""
        echo -e "${RED}✗ Invalid option. Please enter 1, 2, or q.${RESET}"
        ;;
    esac

    # Pause before returning to menu
    echo ""
    echo -ne "${DIM}Press Enter to return to the main menu...${RESET}"
    read -r
  done
}

# ─────────────────────────────────────────────
#  Entry point
# ─────────────────────────────────────────────
check_dependencies
validate_env
verify_login
main_menu
