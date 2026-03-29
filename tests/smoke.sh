#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT_DIR/bin/warp-masque-socks"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TEST_HOME="$TMPDIR/home"
TEST_STATE_DIR="$TMPDIR/state"
TEST_LOCAL_DIR="$TMPDIR/local"
TEST_LAUNCH_AGENTS_DIR="$TMPDIR/LaunchAgents"
FAKEBIN="$TMPDIR/fakebin"
BASE_CONFIG="$TMPDIR/base-config.json"
EXPORT_CONFIG="$TMPDIR/exported-config.json"
RUNTIME_CONFIG="$TMPDIR/runtime-config.json"
PLIST_OUT="$TMPDIR/local.usque-warp-socks.plist"

mkdir -p "$TEST_HOME" "$TEST_STATE_DIR" "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR" "$FAKEBIN"

cat >"$BASE_CONFIG" <<'EOF'
{
  "private_key": "test-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "test-public-key",
  "license": "test-license",
  "id": "test-id",
  "access_token": "test-token",
  "ipv4": "172.16.0.2",
  "ipv6": "2606:4700:110::2"
}
EOF

cat >"$FAKEBIN/launchctl" <<'EOF'
#!/bin/sh
set -eu

state_dir=${TEST_STATE_DIR:?}
cmd=${1:-}

case "$cmd" in
  print)
    [ -f "$state_dir/loaded" ]
    ;;
  bootstrap)
    [ ! -f "$state_dir/disabled" ]
    printf 'bootstrap %s %s\n' "$2" "$3" >>"$state_dir/launchctl.log"
    touch "$state_dir/loaded" "$state_dir/listener"
    ;;
  bootout)
    if [ "$#" -ge 3 ]; then
      printf 'bootout %s %s\n' "$2" "$3" >>"$state_dir/launchctl.log"
    else
      printf 'bootout %s\n' "$2" >>"$state_dir/launchctl.log"
    fi
    rm -f "$state_dir/loaded" "$state_dir/listener"
    ;;
  kickstart|enable|disable)
    case "$cmd" in
      enable)
        rm -f "$state_dir/disabled"
        ;;
      disable)
        touch "$state_dir/disabled"
        ;;
    esac
    printf '%s %s\n' "$cmd" "$2" >>"$state_dir/launchctl.log"
    ;;
  *)
    echo "unexpected launchctl command: $*" >&2
    exit 1
    ;;
esac
EOF

cat >"$FAKEBIN/nc" <<'EOF'
#!/bin/sh
set -eu

[ -f "${TEST_STATE_DIR:?}/listener" ]
EOF

cat >"$FAKEBIN/curl" <<'EOF'
#!/bin/sh
set -eu

state_dir=${TEST_STATE_DIR:?}
url=
data=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --socks5)
      shift 2
      ;;
    --connect-timeout|-X|-H|-o|-w|--data|--data-raw|--data-binary|-d)
      if [ "$1" = "--data" ] || [ "$1" = "--data-raw" ] || [ "$1" = "--data-binary" ] || [ "$1" = "-d" ]; then
        data=${2:-}
      fi
      shift 2
      ;;
    -k|-s|-S|-f|-L|-4)
      shift
      ;;
    http://*|https://*)
      url=$1
      shift
      ;;
    *)
      shift
      ;;
  esac
done

case "$url" in
  https://1.1.1.1/cdn-cgi/trace)
    if [ ! -f "$state_dir/listener" ]; then
      exit 7
    fi

    warp_mode=on
    if [ -f "$state_dir/trace-warp-mode" ]; then
      warp_mode=$(cat "$state_dir/trace-warp-mode")
    fi

    cat <<TRACE
fl=1023f108
h=1.1.1.1
ip=104.28.165.56
ts=1774765664.000
visit_scheme=https
uag=curl/test
colo=LAX
sliver=none
http=http/2
loc=US
tls=TLSv1.3
sni=off
warp=$warp_mode
gateway=off
rbi=off
kex=X25519
TRACE
    ;;
  https://api.cloudflareclient.com/*/reg/*/account)
    printf '%s' "$data" >"$state_dir/account-update-body.json"

    if [ -f "$state_dir/account-update-http-fail" ]; then
      exit 22
    fi

    license=$(printf '%s' "$data" | jq -r '.license')
    printf '%s' "$license" >"$state_dir/bound-license-key"

    warp_plus=true
    if [ -f "$state_dir/account-update-warp-on" ]; then
      warp_plus=false
    fi

    cat <<JSON
{"id":"registered-account-id","license":"$license","premium_data":1,"quota":1,"referral_count":0,"referral_renewal_countdown":0,"role":"child","created":"now","updated":"now","warp_plus":$warp_plus}
JSON
    ;;
  *)
    echo "unexpected curl request: $url" >&2
    exit 1
    ;;
esac
EOF

cat >"$TEST_LOCAL_DIR/usque" <<'EOF'
#!/bin/sh
set -eu

config=config.json

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c)
      config=$2
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

cmd=${1:-}

case "$cmd" in
  register)
    cat >"$config" <<'JSON'
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "registered-license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  enroll)
    license=$(cat "${TEST_STATE_DIR:?}/bound-license-key" 2>/dev/null || printf 'registered-license')
    cat >"$config" <<JSON
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "$license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  socks)
    sleep 60
    ;;
  *)
    ;;
esac
EOF

chmod 755 "$FAKEBIN/launchctl" "$FAKEBIN/nc" "$FAKEBIN/curl" "$TEST_LOCAL_DIR/usque"

export HOME="$TEST_HOME"
export PATH="$FAKEBIN:/usr/bin:/bin:/usr/sbin:/sbin"
export TEST_STATE_DIR
export USQUE_LOCAL_DIR="$TEST_LOCAL_DIR"
export USQUE_LAUNCH_AGENTS_DIR="$TEST_LAUNCH_AGENTS_DIR"

if ! "$SCRIPT" render-runtime-config "$BASE_CONFIG" "$RUNTIME_CONFIG"; then
  echo "render-runtime-config failed" >&2
  exit 1
fi

if ! jq -e '.endpoint_v4 == "162.159.198.2"' "$RUNTIME_CONFIG" >/dev/null; then
  echo "endpoint_v4 was not rewritten" >&2
  exit 1
fi

if ! jq -e '.endpoint_v6 == "2606:4700:103::2"' "$RUNTIME_CONFIG" >/dev/null; then
  echo "endpoint_v6 was not rewritten" >&2
  exit 1
fi

if ! jq -e '.id == "test-id"' "$RUNTIME_CONFIG" >/dev/null; then
  echo "config identity changed unexpectedly" >&2
  exit 1
fi

if ! "$SCRIPT" render-plist "$PLIST_OUT"; then
  echo "render-plist failed" >&2
  exit 1
fi

if ! grep -q '<string>local.usque-warp-socks</string>' "$PLIST_OUT"; then
  echo "plist label missing" >&2
  exit 1
fi

if ! grep -q '<string>run</string>' "$PLIST_OUT"; then
  echo "plist does not invoke run command" >&2
  exit 1
fi

"$SCRIPT" import-config "$BASE_CONFIG"

if [ ! -f "$TEST_LOCAL_DIR/config.json" ]; then
  echo "import-config did not install local config" >&2
  exit 1
fi

if [ "$(stat -f '%Lp' "$TEST_LOCAL_DIR/config.json")" != "600" ]; then
  echo "imported config permissions are not 600" >&2
  exit 1
fi

status_output=$("$SCRIPT" status)
printf '%s\n' "$status_output" | grep -q 'config: present'
printf '%s\n' "$status_output" | grep -q 'license: present'
printf '%s\n' "$status_output" | grep -q 'launchd: unloaded'
printf '%s\n' "$status_output" | grep -q 'listener: down (127.0.0.1:1080)'

"$SCRIPT" start
status_output=$("$SCRIPT" status)
printf '%s\n' "$status_output" | grep -q 'launchd: loaded'
printf '%s\n' "$status_output" | grep -q 'listener: up (127.0.0.1:1080)'

trace_output=$("$SCRIPT" trace)
printf '%s\n' "$trace_output" | grep -q '^warp=on$'
printf '%s\n' "$trace_output" | grep -q '^loc=US$'

"$SCRIPT" export-config "$EXPORT_CONFIG"

if [ "$(stat -f '%Lp' "$EXPORT_CONFIG")" != "600" ]; then
  echo "exported config permissions are not 600" >&2
  exit 1
fi

if ! jq -e '.license == "test-license"' "$EXPORT_CONFIG" >/dev/null; then
  echo "exported config lost license field" >&2
  exit 1
fi

"$SCRIPT" stop
status_output=$("$SCRIPT" status)
printf '%s\n' "$status_output" | grep -q 'launchd: unloaded'
printf '%s\n' "$status_output" | grep -q 'listener: down (127.0.0.1:1080)'

rm -rf "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR"
mkdir -p "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR"
cat >"$TEST_LOCAL_DIR/usque" <<'EOF'
#!/bin/sh
set -eu

config=config.json

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c)
      config=$2
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

cmd=${1:-}

case "$cmd" in
  register)
    cat >"$config" <<'JSON'
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "registered-license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  socks)
    sleep 60
    ;;
  *)
    ;;
esac
EOF
chmod 755 "$TEST_LOCAL_DIR/usque"
rm -f "$TEST_STATE_DIR/loaded" "$TEST_STATE_DIR/listener"

"$SCRIPT" register-start

if [ ! -f "$TEST_LOCAL_DIR/config.json" ]; then
  echo "register-start did not create config" >&2
  exit 1
fi

status_output=$("$SCRIPT" status)
printf '%s\n' "$status_output" | grep -q 'launchd: loaded'
printf '%s\n' "$status_output" | grep -q 'listener: up (127.0.0.1:1080)'

rm -rf "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR"
mkdir -p "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR"
cat >"$TEST_LOCAL_DIR/usque" <<'EOF'
#!/bin/sh
set -eu

config=config.json

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c)
      config=$2
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

cmd=${1:-}

case "$cmd" in
  register)
    cat >"$config" <<'JSON'
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "registered-license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  enroll)
    license=$(cat "${TEST_STATE_DIR:?}/bound-license-key" 2>/dev/null || printf 'registered-license')
    cat >"$config" <<JSON
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "$license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  socks)
    sleep 60
    ;;
  *)
    ;;
esac
EOF
chmod 755 "$TEST_LOCAL_DIR/usque"
rm -f "$TEST_STATE_DIR/loaded" "$TEST_STATE_DIR/listener" "$TEST_STATE_DIR/bound-license-key" \
  "$TEST_STATE_DIR/account-update-body.json" "$TEST_STATE_DIR/account-update-http-fail" \
  "$TEST_STATE_DIR/account-update-warp-on"
printf 'plus' >"$TEST_STATE_DIR/trace-warp-mode"

"$SCRIPT" register-start --license-key test-warp-plus-key

if [ ! -f "$TEST_LOCAL_DIR/config.json" ]; then
  echo "register-start with license key did not create config" >&2
  exit 1
fi

if ! jq -e '.license == "test-warp-plus-key"' "$TEST_LOCAL_DIR/config.json" >/dev/null; then
  echo "register-start with license key did not enroll bound license" >&2
  exit 1
fi

if ! jq -e '.license == "test-warp-plus-key"' "$TEST_STATE_DIR/account-update-body.json" >/dev/null; then
  echo "register-start with license key did not call account update API" >&2
  exit 1
fi

trace_output=$("$SCRIPT" trace)
printf '%s\n' "$trace_output" | grep -q '^warp=plus$'

rm -rf "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR"
mkdir -p "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR"
cat >"$TEST_LOCAL_DIR/usque" <<'EOF'
#!/bin/sh
set -eu

config=config.json

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c)
      config=$2
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

cmd=${1:-}

case "$cmd" in
  register)
    cat >"$config" <<'JSON'
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "registered-license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  enroll)
    license=$(cat "${TEST_STATE_DIR:?}/bound-license-key" 2>/dev/null || printf 'registered-license')
    cat >"$config" <<JSON
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "$license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  socks)
    sleep 60
    ;;
  *)
    ;;
esac
EOF
chmod 755 "$TEST_LOCAL_DIR/usque"
rm -f "$TEST_STATE_DIR/loaded" "$TEST_STATE_DIR/listener" "$TEST_STATE_DIR/bound-license-key" \
  "$TEST_STATE_DIR/account-update-body.json" "$TEST_STATE_DIR/account-update-http-fail" \
  "$TEST_STATE_DIR/account-update-warp-on"
printf 'plus' >"$TEST_STATE_DIR/trace-warp-mode"

USQUE_WARP_PLUS_KEY=test-warp-plus-env "$SCRIPT" register

if ! jq -e '.license == "test-warp-plus-env"' "$TEST_LOCAL_DIR/config.json" >/dev/null; then
  echo "register did not accept license key from environment" >&2
  exit 1
fi

if ! jq -e '.license == "test-warp-plus-env"' "$TEST_STATE_DIR/account-update-body.json" >/dev/null; then
  echo "register did not bind environment license key" >&2
  exit 1
fi

rm -rf "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR"
mkdir -p "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR"
cat >"$TEST_LOCAL_DIR/usque" <<'EOF'
#!/bin/sh
set -eu

config=config.json

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c)
      config=$2
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

cmd=${1:-}

case "$cmd" in
  register)
    cat >"$config" <<'JSON'
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "registered-license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  enroll)
    license=$(cat "${TEST_STATE_DIR:?}/bound-license-key" 2>/dev/null || printf 'registered-license')
    cat >"$config" <<JSON
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "$license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  socks)
    sleep 60
    ;;
  *)
    ;;
esac
EOF
chmod 755 "$TEST_LOCAL_DIR/usque"
rm -f "$TEST_STATE_DIR/loaded" "$TEST_STATE_DIR/listener" "$TEST_STATE_DIR/bound-license-key" \
  "$TEST_STATE_DIR/account-update-body.json" "$TEST_STATE_DIR/account-update-http-fail" \
  "$TEST_STATE_DIR/account-update-warp-on"
printf 'plus' >"$TEST_STATE_DIR/trace-warp-mode"

USQUE_WARP_PLUS_KEY=env-should-lose "$SCRIPT" register --license-key flag-wins

if ! jq -e '.license == "flag-wins"' "$TEST_STATE_DIR/account-update-body.json" >/dev/null; then
  echo "register flag did not override environment license key" >&2
  exit 1
fi

rm -rf "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR"
mkdir -p "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR"
cat >"$TEST_LOCAL_DIR/usque" <<'EOF'
#!/bin/sh
set -eu

config=config.json

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c)
      config=$2
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

cmd=${1:-}

case "$cmd" in
  register)
    cat >"$config" <<'JSON'
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "registered-license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  enroll)
    license=$(cat "${TEST_STATE_DIR:?}/bound-license-key" 2>/dev/null || printf 'registered-license')
    cat >"$config" <<JSON
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "$license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  socks)
    sleep 60
    ;;
  *)
    ;;
esac
EOF
chmod 755 "$TEST_LOCAL_DIR/usque"
rm -f "$TEST_STATE_DIR/loaded" "$TEST_STATE_DIR/listener" "$TEST_STATE_DIR/bound-license-key" \
  "$TEST_STATE_DIR/account-update-body.json" "$TEST_STATE_DIR/account-update-http-fail"
printf 'plus' >"$TEST_STATE_DIR/trace-warp-mode"
touch "$TEST_STATE_DIR/account-update-warp-on"

if "$SCRIPT" register-start --license-key not-plus >/dev/null 2>&1; then
  echo "register-start succeeded even though account update stayed warp=on" >&2
  exit 1
fi

status_output=$("$SCRIPT" status)
printf '%s\n' "$status_output" | grep -q 'launchd: unloaded'

rm -rf "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR"
mkdir -p "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR"
cat >"$TEST_LOCAL_DIR/usque" <<'EOF'
#!/bin/sh
set -eu

config=config.json

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c)
      config=$2
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

cmd=${1:-}

case "$cmd" in
  register)
    cat >"$config" <<'JSON'
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "registered-license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  enroll)
    license=$(cat "${TEST_STATE_DIR:?}/bound-license-key" 2>/dev/null || printf 'registered-license')
    cat >"$config" <<JSON
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "$license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  socks)
    sleep 60
    ;;
  *)
    ;;
esac
EOF
chmod 755 "$TEST_LOCAL_DIR/usque"
rm -f "$TEST_STATE_DIR/loaded" "$TEST_STATE_DIR/listener" "$TEST_STATE_DIR/bound-license-key" \
  "$TEST_STATE_DIR/account-update-body.json" "$TEST_STATE_DIR/account-update-warp-on"
printf 'plus' >"$TEST_STATE_DIR/trace-warp-mode"
touch "$TEST_STATE_DIR/account-update-http-fail"

if "$SCRIPT" register-start --license-key api-fails >/dev/null 2>&1; then
  echo "register-start succeeded even though account update API failed" >&2
  exit 1
fi

status_output=$("$SCRIPT" status)
printf '%s\n' "$status_output" | grep -q 'launchd: unloaded'

rm -f "$TEST_STATE_DIR/account-update-http-fail"
rm -f "$TEST_STATE_DIR/account-update-warp-on"
rm -rf "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR"
mkdir -p "$TEST_LOCAL_DIR" "$TEST_LAUNCH_AGENTS_DIR"
cat >"$TEST_LOCAL_DIR/usque" <<'EOF'
#!/bin/sh
set -eu

config=config.json

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c)
      config=$2
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

cmd=${1:-}

case "$cmd" in
  register)
    cat >"$config" <<'JSON'
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "registered-license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  enroll)
    license=$(cat "${TEST_STATE_DIR:?}/bound-license-key" 2>/dev/null || printf 'registered-license')
    cat >"$config" <<JSON
{
  "private_key": "registered-private-key",
  "endpoint_v4": "162.159.198.1",
  "endpoint_v6": "2606:4700:103::1",
  "endpoint_pub_key": "registered-public-key",
  "license": "$license",
  "id": "registered-id",
  "access_token": "registered-token",
  "ipv4": "172.16.0.3",
  "ipv6": "2606:4700:110::3"
}
JSON
    ;;
  socks)
    sleep 60
    ;;
  *)
    ;;
esac
EOF
chmod 755 "$TEST_LOCAL_DIR/usque"
rm -f "$TEST_STATE_DIR/loaded" "$TEST_STATE_DIR/listener" "$TEST_STATE_DIR/bound-license-key" \
  "$TEST_STATE_DIR/account-update-body.json" "$TEST_STATE_DIR/account-update-http-fail" \
  "$TEST_STATE_DIR/account-update-warp-on"
printf 'on' >"$TEST_STATE_DIR/trace-warp-mode"

if "$SCRIPT" register-start --license-key trace-still-on >/dev/null 2>&1; then
  echo "register-start succeeded even though trace never reached warp=plus" >&2
  exit 1
fi

status_output=$("$SCRIPT" status)
printf '%s\n' "$status_output" | grep -q 'launchd: unloaded'

printf 'smoke ok\n'
