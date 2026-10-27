#!/bin/sh
# =============================================================================
# OPNsense PKG Mirror Speed Test
# =============================================================================
# Ubuntu 24.04 : bash opnsense-mirror-speedtest.sh
#                sh   opnsense-mirror-speedtest.sh
# OPNsense 26.7: sh   opnsense-mirror-speedtest.sh
#   (tcsh users: run as  sh opnsense-mirror-speedtest.sh)
#   (tcsh ユーザーは  sh opnsense-mirror-speedtest.sh  で実行)
#
# Environment variables / 環境変数:
#   VERSION=26.7   OPNsense version to test / テスト対象バージョン (default: 26.7)
#   PARALLEL=1     1=parallel (fast), 0=sequential / 1=並列実行, 0=逐次 (default: 1)
#   SPEED_MB=2     MB to download for speed test / 速度テストの取得量MB (default: 2)
#   NO_COLOR=1     Disable color output / カラー出力を無効化
# =============================================================================

set -u

# ── Configuration / ユーザー設定 ────────────────────────────────────────────────
OPNSENSE_VER="${VERSION:-26.7}"
# On OPNsense, ABI is auto-detected via `pkg config abi`.
# On other hosts, override with FREEBSD_ABI=FreeBSD:15:amd64.
# OPNsense上では pkg config abi で自動取得。他環境では環境変数で上書き可能。
# URL path structure / URLパス構造: {mirror}/{FreeBSD ABI}/{VERSION}/latest/
_detected_abi=$(pkg config abi 2>/dev/null || true)
FREEBSD_ABI="${FREEBSD_ABI:-${_detected_abi:-FreeBSD:15:amd64}}"
CONNECT_TIMEOUT=5      # Connection timeout in seconds / 接続タイムアウト(秒)
TEST_TIMEOUT=25        # Max time per test in seconds / テスト全体のタイムアウト(秒)
SPEED_MB="${SPEED_MB:-2}"
PARALLEL="${PARALLEL:-1}"

# ── Mirror list / ミラーリスト (Name|Base URL) ───────────────────────────────
# Source / 出典: opnsense/core
#   src/opnsense/mvc/app/models/OPNsense/Core/repositories/opnsense.xml
# Matches the Mirror dropdown in System > Firmware > Settings.
# System > Firmware > Settings の Mirror プルダウンと同一リスト。
# Deciso commercial mirrors (subscription required) are excluded.
# Deciso 商用ミラー (要サブスクリプション) は除外。
MIRRORS='OPNsense (NL)|https://pkg.opnsense.org
LeaseWeb AMS (NL)|https://mirror.ams1.nl.leaseweb.net/opnsense
LeaseWeb FRA (DE)|https://mirror.fra10.de.leaseweb.net/opnsense
LeaseWeb SFO (US)|https://mirror.sfo12.us.leaseweb.net/opnsense
LeaseWeb WDC (US)|https://mirror.wdc1.us.leaseweb.net/opnsense
Aalborg Univ (DK)|https://mirrors.dotsrc.org/opnsense
c0urier.net (DK)|https://opnsense.c0urier.net
Cloudfence (BR)|https://mirror.cloudfence.com.br/opnsense
HiHo (CH)|https://opnsense-mirror.hiho.ch
ServerBase AG (CH)|https://mirror-opnsense.serverbase.ch
NYC*BUG (US)|https://mirrors.nycbug.org/pub/opnsense
Univ of Kent (GB)|https://www.mirrorservice.org/sites/opnsense.org
Aivian (CN)|https://opnsense.aivian.org
Quantum Mirror (HU)|http://quantum-mirror.hu/mirrors/pub/opnsense
MARWAN (MA)|http://mirror.marwan.ma/opnsense
Ventura Sys (CO)|http://mirror.venturasystems.tech/opnsense
NTCT(TW)|https://mirror.ntct.edu.tw/opnsense/'

# ── Derived paths / 派生パス (pkg repository structure) ──────────────────────
# URL format / URL形式: {mirror}/{FreeBSD ABI}/{VERSION}/latest/
# Source / 出典: src/etc/pkg/repos/OPNsense.conf.shadow.in
#   → "%%CORE_PACKAGESITE%%/${ABI}/%%CORE_ABI%%/latest"
REPO_BASE="${FREEBSD_ABI}/${OPNSENSE_VER}/latest"
LATENCY_PATH="${REPO_BASE}/meta.conf"      # Small file for latency / レイテンシ用小ファイル
SPEED_PATH="${REPO_BASE}/packagesite.pkg"  # Package catalog for speed / 速度用パッケージカタログ
SPEED_END=$(( SPEED_MB * 1048576 - 1 ))

# ── ANSI colors / ANSIカラー ─────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  cR='\033[0;31m'; cG='\033[0;32m'; cY='\033[1;33m'
  cC='\033[0;36m'; cW='\033[1m';   cN='\033[0m'
else
  cR=''; cG=''; cY=''; cC=''; cW=''; cN=''
fi

# ── Temporary directory / 一時ディレクトリ ───────────────────────────────────
_TMP="${TMPDIR:-/tmp}/opnspeed_$$"
mkdir -p "${_TMP}"
trap 'rm -rf "${_TMP}"' EXIT INT TERM

# ── Helper functions / ヘルパー関数 ──────────────────────────────────────────
die() { printf "${cR}Error / エラー: %s${cN}\n" "$*" >&2; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' not found. Please install it. / 見つかりません。インストールしてください。"
}

fmt_speed() {
    awk -v n="$1" 'BEGIN {
        if      (n >= 1048576) printf "%.2f MB/s", n/1048576
        else if (n >= 1024)    printf "%.1f KB/s", n/1024
        else if (n >  0)       printf "%d B/s",    n
        else                   printf "---"
    }'
}

fmt_ms() {
    if [ "$1" -gt 0 ] 2>/dev/null; then
        printf '%dms' "$1"
    else
        printf '---'
    fi
}

draw_bar() {
    # draw_bar <value> <max> [width=22]
    local v=$1 m=$2 w=${3:-22} f=0 i=0 s=''
    [ "${m}" -gt 0 ] && f=$(( v * w / m ))
    while [ "${i}" -lt "${w}" ]; do
        if [ "${i}" -lt "${f}" ]; then s="${s}█"; else s="${s}░"; fi
        i=$(( i + 1 ))
    done
    printf '%s' "${s}"
}

hline() {
    awk -v n="${1:-88}" 'BEGIN { for(i=0;i<n;i++) printf "─"; print "" }'
}

# ── Mirror test function / ミラーテスト関数 ──────────────────────────────────
# Output format / 出力形式: name|url|status|dns_ms|con_ms|ttfb_ms|spd_bps
#   status: OK / FAIL:<httpcode>
test_mirror() {
    local name="$1" base="$2" out="$3"
    local lat_url="${base}/${LATENCY_PATH}"
    local spd_url="${base}/${SPEED_PATH}"

    # Phase 1: latency via meta.conf / フェーズ1: meta.conf でレイテンシ測定
    local raw http dns con ttfb
    raw=$(curl -sSL \
          --connect-timeout "${CONNECT_TIMEOUT}" \
          --max-time "${TEST_TIMEOUT}" \
          -o /dev/null \
          -w '%{http_code}|%{time_namelookup}|%{time_connect}|%{time_starttransfer}' \
          "${lat_url}" 2>/dev/null) || raw='ERR|0|0|0'

    http=$(printf '%s' "${raw}" | cut -d'|' -f1)
    dns=$( printf '%s' "${raw}" | awk -F'|' '{printf "%.0f", $2*1000}')
    con=$( printf '%s' "${raw}" | awk -F'|' '{printf "%.0f", $3*1000}')
    ttfb=$(printf '%s' "${raw}" | awk -F'|' '{printf "%.0f", $4*1000}')

    if [ "${http}" != "200" ] && [ "${http}" != "206" ]; then
        printf '%s|%s|FAIL:%s|%s|%s|%s|0\n' \
            "${name}" "${base}" "${http}" "${dns}" "${con}" "${ttfb}" >"${out}"
        return
    fi

    # Phase 2: speed via range-download of packagesite.pkg
    # フェーズ2: packagesite.pkg の先頭 SPEED_MB MB をレンジ取得して速度測定
    local spd
    spd=$(curl -sSL \
          --connect-timeout "${CONNECT_TIMEOUT}" \
          --max-time "${TEST_TIMEOUT}" \
          --range "0-${SPEED_END}" \
          -o /dev/null \
          -w '%{speed_download}' \
          "${spd_url}" 2>/dev/null \
        | awk '{printf "%.0f", $1}') || spd=0
    [ -z "${spd}" ] && spd=0

    printf '%s|%s|OK|%s|%s|%s|%s\n' \
        "${name}" "${base}" "${dns}" "${con}" "${ttfb}" "${spd}" >"${out}"
}

# ── Main / メイン ────────────────────────────────────────────────────────────
require_cmd curl
require_cmd awk

printf "${cW}${cC}OPNsense PKG Mirror Speed Test${cN}"
printf "  v%s / %s\n\n" "${OPNSENSE_VER}" "${FREEBSD_ABI}"
printf "Latency / レイテンシ測定: {mirror}/%s\n" "${LATENCY_PATH}"
printf "Speed   / 速度測定      : {mirror}/%s (first %dMB / 先頭%dMB)\n\n" \
    "${SPEED_PATH}" "${SPEED_MB}" "${SPEED_MB}"

# Write mirror list to file to keep while-loop in the main shell (not a subshell).
# while ループをサブシェル外で動かすためミラーリストをファイルに書き出す。
printf '%s\n' "${MIRRORS}" >"${_TMP}/mirrors"
total=$(wc -l <"${_TMP}/mirrors" | tr -d ' \t')

if [ "${PARALLEL}" -eq 1 ]; then
    printf "Testing %d mirrors [parallel / 並列実行]...\n" "${total}"
else
    printf "Testing %d mirrors [sequential / 逐次実行]...\n" "${total}"
fi

# Launch tests / テスト起動
idx=0
while IFS='|' read -r mname murl; do
    [ -z "${mname}" ] || [ -z "${murl}" ] && continue
    ofile="${_TMP}/$(printf '%03d' ${idx})"
    idx=$(( idx + 1 ))

    if [ "${PARALLEL}" -eq 1 ]; then
        test_mirror "${mname}" "${murl}" "${ofile}" &
    else
        printf '  %-28s ' "${mname}..."
        test_mirror "${mname}" "${murl}" "${ofile}"
        _st=$(cut -d'|' -f3 "${ofile}" 2>/dev/null || printf 'ERR')
        if [ "${_st}" = "OK" ]; then
            _sp=$(cut -d'|' -f7 "${ofile}")
            printf "${cG}OK${cN} %s\n" "$(fmt_speed "${_sp}")"
        else
            printf "${cR}%s${cN}\n" "${_st}"
        fi
    fi
done <"${_TMP}/mirrors"

if [ "${PARALLEL}" -eq 1 ]; then
    printf '  Waiting / 待機中'
    wait
    printf ' done / 完了\n'
fi

printf '\n'

# ── Collect and sort results / 結果収集・ソート ──────────────────────────────
# OK entries sorted by speed desc, FAIL entries at the bottom.
# OK→速度降順、FAIL→末尾
cat "${_TMP}"/[0-9]* 2>/dev/null >"${_TMP}/all"

awk -F'|' '$3=="OK"  {print "0|" $0}
           $3!="OK"  {print "1|" $0}' "${_TMP}/all" \
  | sort -t'|' -k1,1n -k8,8rn \
  | cut -d'|' -f2- >"${_TMP}/sorted"

# Find max speed for bar scaling / バーのスケーリング用に最大速度を取得
MAX_SPD=$(awk -F'|' '$3=="OK" {s=$7+0; if(s>m)m=s} END{print (m>0?m:1)}' "${_TMP}/sorted")

# ── Print results table / 結果テーブル表示 ───────────────────────────────────
printf "${cW}%-22s %-11s %7s %9s %8s %-12s %s${cN}\n" \
    "Mirror" "Status" "DNS" "Connect" "TTFB" "Speed" "Bar (relative / 相対速度)"
hline 98

rank=1
while IFS='|' read -r name url status dns con ttfb spd; do
    if [ "${status}" = "OK" ]; then
        spd_str=$(fmt_speed "${spd}")
        bar=$(draw_bar "${spd}" "${MAX_SPD}" 22)
        case "${rank}" in
            1)   c="${cG}";;
            2|3) c="${cY}";;
            *)   c="${cN}";;
        esac
        printf "${c}%-22s %-11s %7s %9s %8s %-12s %s${cN}\n" \
            "${name}" "${status}" \
            "$(fmt_ms "${dns}")" "$(fmt_ms "${con}")" "$(fmt_ms "${ttfb}")" \
            "${spd_str}" "${bar}"
        rank=$(( rank + 1 ))
    else
        printf "${cR}%-22s %-11s %7s %9s %8s ---${cN}\n" \
            "${name}" "${status}" \
            "$(fmt_ms "${dns}")" "$(fmt_ms "${con}")" "$(fmt_ms "${ttfb}")"
    fi
done <"${_TMP}/sorted"

hline 98

# ── Summary / サマリー ────────────────────────────────────────────────────────
printf '\n'
best_line=$(awk -F'|' 'NR==1 && $3=="OK"{print $0}' "${_TMP}/sorted")
if [ -n "${best_line}" ]; then
    best_name=$(printf '%s' "${best_line}" | cut -d'|' -f1)
    best_url=$( printf '%s' "${best_line}" | cut -d'|' -f2)
    best_spd=$( printf '%s' "${best_line}" | cut -d'|' -f7)
    best_ttfb=$(printf '%s' "${best_line}" | cut -d'|' -f6)

    printf "${cW}Fastest mirror / 最速ミラー :${cN} %s\n" "${best_name}"
    printf "${cW}URL                        :${cN} %s\n" "${best_url}"
    printf "${cW}Speed / 速度               :${cN} %s  (TTFB: %s)\n" \
        "$(fmt_speed "${best_spd}")" "$(fmt_ms "${best_ttfb}")"
    printf '\n'
    printf "${cW}To apply in OPNsense / OPNsense Settings への設定:${cN}\n"
    printf "  System > Firmware > Settings > Mirror\n"
    printf "  → %s\n" "${best_name}"
fi

ok_count=$(  awk -F'|' '$3=="OK"  {c++} END{print c+0}' "${_TMP}/sorted")
fail_count=$(awk -F'|' '$3!="OK" {c++} END{print c+0}' "${_TMP}/sorted")
printf '\nOK: %d / Failed / 失敗: %d\n' "${ok_count}" "${fail_count}"
