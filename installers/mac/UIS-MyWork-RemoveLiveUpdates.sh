#!/bin/bash
# UIS My Work - one-time setup for LIVE UPDATES (macOS: Chrome, Edge, Brave).
#
# Run it once in Terminal: type  bash  and a space, drag this file into the
# Terminal window, press Return. No admin password needed.
#
#  1. Puts the extension in ~/Library/Application Support/UIS/MyWork/extension
#  2. Installs the small updater (included below) in ~/Library/Application Support/UIS/MyWork/updater
#     and registers it for this Mac user only, so ONLY the UIS My Work extension
#     can ask it to fetch a new version from https://uis-mobile-portal.web.app
#  3. Copies the extension folder path, so you can paste it into "Load unpacked".
UNINSTALL=1

NAME='com.uis.mywork.updater'
EXT_ID='kpceidgdgjodcjcolmddjcndjbmbahpd'
SUPPORT="$HOME/Library/Application Support"
ROOT="$SUPPORT/UIS/MyWork"
UPD="$ROOT/updater"
EXT="$ROOT/extension"
# browsers that read per-user native messaging hosts from <profile folder>/NativeMessagingHosts
BROWSERS='Google/Chrome
Google/Chrome Beta
Microsoft Edge
BraveSoftware/Brave-Browser
Chromium'

say() { printf '%s\n' "$*"; }
die() { say ''; say "Setup failed: $*"; say ''; exit 1; }

if [ "$(uname -s)" != 'Darwin' ] && [ -z "$UIS_ANY_OS" ]; then
  die 'This installer is for macOS. On Windows use UIS-MyWork-LiveUpdates.ps1.'
fi

# Chrome always, the others only when they are installed
host_dirs() {
  printf '%s\n' "$BROWSERS" | while IFS= read -r b; do
    if [ "$1" = 'all' ] || [ "$b" = 'Google/Chrome' ] || [ -d "$SUPPORT/$b" ]; then printf '%s\n' "$SUPPORT/$b/NativeMessagingHosts"; fi
  done
}

if [ "$UNINSTALL" = '1' ]; then
  host_dirs all | while IFS= read -r d; do rm -f "$d/$NAME.json"; done
  rm -rf "$UPD"
  say ''
  say 'Live updates are off: the UIS My Work updater was removed. The extension folder was kept.'
  say ''
  exit 0
fi

say ''
say '  UIS My Work - turning on live updates'
say ''
mkdir -p "$UPD" "$EXT" || die "Could not create $ROOT"

say '  - installing the updater'
cat > "$UPD/host.sh" <<'UIS_HOST_EOF'
#!/bin/bash
# UIS My Work - live updater for macOS (Chrome / Edge native messaging host).
#
# Installed by the Mac installer into ~/Library/Application Support/UIS/MyWork/updater.
# Chrome starts it only for the UIS My Work extension, sends ONE message and reads
# ONE answer:
#   { "cmd": "ping" }    -> { ok, host, version, token, dir }
#   { "cmd": "update" }  -> downloads the latest release from the fixed UIS address
#                           below into ~/Library/Application Support/UIS/MyWork/extension
#                           -> { ok, version, changed }
# It never downloads from anywhere else and never runs what it downloads.
# Plain bash 3.2 and tools that come with macOS (curl, unzip, shasum, dd, od).
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export LC_ALL=C

HOST_VERSION='1'
BASE='https://uis-mobile-portal.web.app'
HERE="$(cd "$(dirname "$0")" && pwd)"
EXT="$(dirname "$HERE")/extension"
MODE='message'
[ "$1" = 'install' ] && MODE='install'
TMP=''
trap '[ -n "$TMP" ] && rm -rf "$TMP"' EXIT

# ---- native messaging: 4-byte little-endian length, then UTF-8 JSON ----
send() {
  local json="$1" n
  n=$(printf '%s' "$json" | wc -c | tr -d ' ')
  printf "\\$(printf '%03o' $((n & 255)))\\$(printf '%03o' $(((n >> 8) & 255)))\\$(printf '%03o' $(((n >> 16) & 255)))\\$(printf '%03o' $(((n >> 24) & 255)))"
  printf '%s' "$json"
}
read_msg() {
  local n
  n=$(dd bs=1 count=4 2>/dev/null | od -An -tu4 | tr -d ' \n')
  [ -n "$n" ] || return 1
  [ "$n" -gt 0 ] 2>/dev/null && [ "$n" -le 65536 ] || return 1
  dd bs=1 count="$n" 2>/dev/null
}
json_str() {
  local s
  s=$(printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  printf '"%s"' "$s"
}
# first "key": "string value" in the JSON on stdin
json_get() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 | sed -e 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//' -e 's/"$//'
}
fail() {
  if [ "$MODE" = 'install' ]; then echo "Error: $1" >&2
  else send "{\"ok\":false,\"error\":$(json_str "$1")}"; fi
  exit 1
}

case "$EXT" in
  */UIS/MyWork/extension) ;;
  *) fail "Unexpected install folder: $EXT" ;;
esac

get_token() { [ -f "$HERE/token.txt" ] && tr -d ' \r\n' < "$HERE/token.txt"; }
# marks this folder as the updater's copy (the extension compares the token)
write_managed() {
  local t; t=$(get_token)
  [ -n "$t" ] && printf '{"token":"%s"}' "$t" > "$EXT/uis-managed.json"
}
installed_version() { [ -f "$EXT/manifest.json" ] && json_get version < "$EXT/manifest.json"; }
# prints 1, 0 or -1
ver_cmp() {
  local IFS=. a b i x y
  a=($1); b=($2)
  for i in 0 1 2 3; do
    x="${a[$i]//[^0-9]/}"; y="${b[$i]//[^0-9]/}"
    x="${x:-0}"; y="${y:-0}"
    if [ "$x" -gt "$y" ]; then echo 1; return; fi
    if [ "$x" -lt "$y" ]; then echo -1; return; fi
  done
  echo 0
}
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"
  else openssl dgst -sha256 -r "$1"; fi | awk '{ print toupper($1) }'
}

# downloads try 3 times: networks drop a connection now and then
get_text() {
  local i out
  for i in 1 2 3; do
    out=$(curl -fsSL --max-time 30 -H 'Cache-Control: no-cache' "$1" 2>/dev/null) && { printf '%s\n' "$out"; return 0; }
    [ "$i" -lt 3 ] && sleep 2
  done
  return 1
}
get_file() {
  local i
  for i in 1 2 3; do
    curl -fsSL --max-time 300 -o "$2" "$1" 2>/dev/null && return 0
    [ "$i" -lt 3 ] && sleep 2
  done
  return 1
}

RESULT=''
do_update() {
  local info url ver sha cur zip x nv h p
  info=$(get_text "$BASE/version.json?_=$(date +%s)") || fail 'Could not reach the UIS update server. Check your internet connection.'
  url=$(printf '%s\n' "$info" | json_get url)
  ver=$(printf '%s\n' "$info" | json_get version)
  sha=$(printf '%s\n' "$info" | json_get sha256)
  case "$url" in
    "$BASE/"*) ;;
    *) fail "Refusing to download from $url" ;;
  esac
  [ -n "$ver" ] || fail 'The update information has no version.'
  cur=$(installed_version)
  if [ -n "$cur" ] && [ "$(ver_cmp "$cur" "$ver")" -ge 0 ]; then
    write_managed
    RESULT="{\"ok\":true,\"version\":$(json_str "$cur"),\"changed\":false}"
    return 0
  fi
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/uis-mywork.XXXXXX") || fail 'Could not make a temporary folder.'
  zip="$TMP/update.zip"; x="$TMP/x"
  get_file "$url?_=$(date +%s)" "$zip" || fail 'Could not download the new version. Try again later.'
  if [ -n "$sha" ]; then
    h=$(sha256_of "$zip")
    [ "$h" = "$(printf '%s' "$sha" | tr 'a-f' 'A-F')" ] || fail 'The download is damaged (checksum mismatch). Try again later.'
  fi
  mkdir -p "$x"
  unzip -q -o "$zip" -d "$x" >/dev/null 2>&1 || ditto -x -k "$zip" "$x" >/dev/null 2>&1 || fail 'Could not unpack the new version.'
  [ -f "$x/manifest.json" ] || fail 'The download has no manifest.json'
  nv=$(json_get version < "$x/manifest.json")
  mkdir -p "$EXT" || fail "Could not create $EXT"
  # copy the new files over the old ones, then drop files the new version no longer has
  cp -R "$x/." "$EXT/" || fail "Could not copy the new version into $EXT"
  (cd "$EXT" && find . -mindepth 1 -depth -print) | while IFS= read -r p; do
    [ "$p" = './uis-managed.json' ] && continue
    [ -e "$x/$p" ] || rm -rf "$EXT/$p"
  done
  write_managed
  RESULT="{\"ok\":true,\"version\":$(json_str "$nv"),\"changed\":true}"
}

if [ "$MODE" = 'install' ]; then
  # used by the installer: put the latest version in place now
  do_update
  echo "UIS My Work v$(installed_version) is in $EXT"
  exit 0
fi

msg=$(read_msg) || exit 0
case "$msg" in
  *'"cmd":"ping"'*)
    send "{\"ok\":true,\"host\":\"$HOST_VERSION\",\"version\":$(json_str "$(installed_version)"),\"token\":$(json_str "$(get_token)"),\"dir\":$(json_str "$EXT")}" ;;
  *'"cmd":"update"'*)
    do_update
    send "$RESULT" ;;
  *)
    send '{"ok":false,"error":"unknown command"}' ;;
esac
exit 0
UIS_HOST_EOF
chmod 755 "$UPD/host.sh" || die 'Could not make the updater runnable.'
if [ ! -s "$UPD/token.txt" ]; then
  tok=$(uuidgen 2>/dev/null | tr -d '-' | tr 'A-Z' 'a-z')
  [ -n "$tok" ] || tok=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')
  printf '%s' "$tok" > "$UPD/token.txt" || die 'Could not save the updater key.'
fi

json_path=$(printf '%s' "$UPD/host.sh" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
MANIFEST="{
  \"name\": \"$NAME\",
  \"description\": \"UIS My Work live updater\",
  \"path\": \"$json_path\",
  \"type\": \"stdio\",
  \"allowed_origins\": [\"chrome-extension://$EXT_ID/\"]
}"
say '  - registering it for Chrome, Edge and Brave (this Mac user only)'
host_dirs | while IFS= read -r d; do
  mkdir -p "$d" && printf '%s\n' "$MANIFEST" > "$d/$NAME.json"
done
[ -f "$SUPPORT/Google/Chrome/NativeMessagingHosts/$NAME.json" ] || die 'Could not register the updater for Chrome.'

say '  - downloading the latest UIS My Work'
"$UPD/host.sh" install || die 'Could not download the extension. Check your internet connection and run this again.'

if command -v pbcopy >/dev/null 2>&1; then printf '%s' "$EXT" | pbcopy; fi
say ''
say '  Done. One last step (only once):'
say '   1. Open chrome://extensions  (Edge: edge://extensions)'
say '   2. Remove "UIS Portal - My Work Tracker" if it is there'
say '   3. Turn on Developer mode and click "Load unpacked"'
say '   4. In the folder window press Cmd+Shift+G, paste (Cmd+V), press Return, then click Select.'
say '      The folder (already copied):'
say ''
say "      $EXT"
say ''
say '  From then on, new versions install by themselves.'
say ''
