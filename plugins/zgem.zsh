autoload +X -U colors && colors


########################## zgem #########################

declare -rx ZGEM_DIR=${ZGEM_DIR:-"$HOME/.zgem"}

function zgem {
  local cmd="$1"
  shift

  case "$cmd" in
    'add')
      zgem::add $@
      ;;
    'update')
      zgem::update $@
      zgem::reload
      ;;
    'clean')
      zgem::clean
      ;;
    *)
      zgem::log error "Unknown command '$cmd'"
      zgem::log error "Usage: $0 {add|update}"
      return 1
      ;;
  esac
}

function zgem::reload {
  exec "$SHELL" -l
}

function zgem::clean {
  zgem::log info "Press ENTER to remove '$ZGEM_DIR/'..." && read
  rm -rf "$ZGEM_DIR"
}

function zgem::add {
  local location="$1"
  shift

  ################ parse parameters ################

  local protocol='file'
  local file=''
  local gem_type='plugin'
  local lazy_load=''
  for param in "$@"; do
    local param_key="${param[(ws|:|)1]}"
    local param_value="${param[(ws|:|)2]}"

    case "$param_key" in
      'from')
        protocol="$param_value"
        ;;
      'use')
        file="$param_value"
        ;;
      'as')
        gem_type="$param_value"
        ;;
      'lazy')
        lazy_load="$param_value"
        ;;
      *)
        zgem::log error "Unknown parameter '$param_key'"
        zgem::log error "Parameter: {from|use|as}"
        return 1
        ;;
    esac
  done

  ################ determine gem dir and file ################

  local gem_dir
  case "$protocol" in
    'file')
      file="$(zgem::basename "$location")"
      gem_dir="$(zgem::dirname "$location")"
      ;;
    'http')
      file=$(zgem::basename "$location")
      gem_name="$file"
      gem_dir="${ZGEM_DIR}/${gem_name}"
      ;;
    'git')
      gem_name="$(zgem::basename "$location" '.git')"
      gem_dir="$ZGEM_DIR/${gem_name}"
      ;;
    *)
      zgem::log error  "Unknown protocol '$protocol'"
      zgem::log error  "Protocol: {file|http|git}"
      return 1 ;;
  esac

  ################ download gem ################

  if [ "$protocol" != 'file' ] && [ ! -e "$gem_dir" ]; then
    zgem::log info "${fg_bold[green]}download${reset_color} '$gem_dir'\n       ${fg_bold[yellow]}from${reset_color}    '$location'"
    zgem::download::$protocol "$location" "$gem_dir"
    echo "$protocol" > "$gem_dir/.gem"
  fi

  ################ load gem ################

  case "$gem_type" in
    'plugin')
      zgem::load::plugin "$gem_dir" "$file" "$lazy_load"
      ;;
    'completion')
      zgem::load::completion "$gem_dir" "$file"
      ;;
    *)
      zgem::log error  "Unknown gem type '$protocol'"
      zgem::log error  "Gem Type: {plugin|completion}"
      return 1 ;;
  esac
}

function zgem::load::completion {
  zgem::log debug "${fg_bold[green]}completion${reset_color}     '$gem_dir/$file'"
  fpath=($fpath "$gem_dir")
}

function zgem::load::plugin {
  local gem_dir="$1"
  local file="$2"
  local lazy_functions="$3"

  if [ -z "$lazy_functions" ]; then
    zgem::log debug "${fg_bold[green]}plugin${reset_color}         '$gem_dir/$file'"
    source "$gem_dir/$file"
  else
    zgem::log debug "${fg_bold[green]}plugin${reset_color}         '$gem_dir/$file' ${fg_bold[blue]}lazy${reset_color} '${lazy_functions}'"
    for lazy_function in ${(ps:,:)${lazy_functions}}; do
      lazy_function=$(echo $lazy_function | tr -d ' ') # re move whitespaces
      eval "$lazy_function() { . \"$gem_dir/$file\" && $lazy_function; }"
    done
  fi
}

function zgem::update {
  for gem_dir in $(find "$ZGEM_DIR" -type d -mindepth 1 -maxdepth 1); do
    zgem::log info "${fg_bold[green]}update${reset_color} '$gem_dir'";

    local gem_name="$(zgem::basename "$gem_dir")"
    local protocol="$(cat "$gem_dir/.gem")"
    case "$protocol" in
      'http')
        zgem::update::http $gem_dir
        ;;
      'git')
        zgem::update::git $gem_dir
        ;;
      *)
        zgem::log error "Unknown protocol '$protocol'"
        zgem::log error "Protocol: {http|git}"
        return 1
        ;;
    esac
  done
}

#### faster than basename command
function zgem::basename {
  local name="$1"
  local sufix="$2"
  name="${name##*/}"
  name="${name%$sufix}"
  echo "$name"
}

#### faster than dirname command
function zgem::dirname {
  local name="$1"
  name="${name%/*}"
  echo "$name"
}

ZGEM_VERBOSE="${ZGEM_VERBOSE:-false}"
function zgem::log {
  local level="$1"
  shift

  case "$level" in
    'error')
      echo "${fg_bold[red]}[zgem]${reset_color}" $@ >&2
      ;;
    'info')
      echo "${fg_bold[blue]}[zgem]${reset_color}" $@
      ;;
    'debug')
      $ZGEM_VERBOSE && echo "${fg_bold[yellow]}[zgem]${reset_color}" $@
      ;;
    *)
      zgem::log error "Unknown log level '$protocol'"
      zgem::log error "Log Level: {error|info|debug}"
      ;;
  esac
}

############################# http ############################

function zgem::download::http {
  local http_url="$1"
  local gem_dir="$2"

  mkdir -p "$gem_dir"
  echo "$http_url" > "$gem_dir/.http" # store url into meta file for allow updating
  echo "Downloading into '$gem_dir'"
  (cd "$gem_dir"; curl -L -O "$http_url")
}

function zgem::update::http {
  local gem_dir="$1"

  local http_url=$(cat "$gem_dir/.http")
  local file="$(zgem::basename "$http_url")"

  if [ $(cd "$gem_dir"; curl -s -L -w %{http_code} -O -z "$file" "$http_url") = '200' ]; then
    echo "From $http_url"
    echo "Updated."
  else
    echo "File is up to date"
  fi
}

############################# git #############################

function zgem::download::git {
  local repo_url="$1"
  local gem_dir="$2"

  mkdir -p "$gem_dir"
  git clone --depth 1 "$repo_url" "$gem_dir"
}

function zgem::update::git {
  local gem_dir="$1"

  local changed_files="$(cd "$gem_dir"; git diff --name-only ..origin)"
  (cd "$gem_dir"; git pull)
  if [ -n "$changed_files" ]; then
    echo "Updated:"
    echo "$changed_files" | sed -e 's/^/  /'
  fi
}