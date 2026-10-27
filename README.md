# OPNsense Mirror Speed Test

A shell script that benchmarks **OPNsense pkg repository mirrors** and identifies the fastest one for your location.

Tests all 16 mirrors listed in `System > Firmware > Settings > Mirror` dropdown, measuring DNS lookup time, connection time, TTFB, and download speed, then displays a ranked summary.

## Requirements

| Environment | How to run |
|-------------|------------|
| Ubuntu 24.04 | `bash opnsense-mirror-speedtest.sh` |
| OPNsense 26.7 (tcsh) | `sh opnsense-mirror-speedtest.sh` |

Dependencies: `curl` and `awk` (both available by default)

## Usage

```sh
sh opnsense-mirror-speedtest.sh
```

### Example output

```
OPNsense PKG Mirror Speed Test  v26.7 / FreeBSD:15:amd64

Testing 16 mirrors [parallel]...
  Waiting... done

Mirror                   Status        DNS   Connect     TTFB Speed        Bar (relative)
───────────────────────────────────────────────────────────────────────────────────────────────
LeaseWeb AMS (NL)        OK           12ms      45ms    120ms 8.43 MB/s    ██████████████████████
LeaseWeb FRA (DE)        OK           14ms      48ms    135ms 6.21 MB/s    ████████████████░░░░░░
Aalborg Univ (DK)        OK           18ms      62ms    180ms 5.10 MB/s    █████████████░░░░░░░░░
...
Ventura Sys (CO)         FAIL:000      ---       ---      ---
───────────────────────────────────────────────────────────────────────────────────────────────

Fastest mirror : LeaseWeb AMS (NL)
URL            : https://mirror.ams1.nl.leaseweb.net/opnsense
Speed          : 8.43 MB/s  (TTFB: 120ms)

To apply in OPNsense:
  System > Firmware > Settings > Mirror
  → LeaseWeb AMS (NL)

OK: 14 / Failed: 2
```

## Options (environment variables)

| Variable | Default | Description |
|----------|---------|-------------|
| `VERSION` | `26.7` | OPNsense version to test against |
| `PARALLEL` | `1` | `1` = parallel (fast), `0` = sequential (shows progress) |
| `SPEED_MB` | `2` | Data size in MB for speed test |
| `NO_COLOR` | — | Set to `1` to disable color output |

> **About `FREEBSD_ABI`**  
> The FreeBSD ABI string (e.g. `FreeBSD:15:amd64`) is embedded in mirror URL paths. On OPNsense it is auto-detected via `pkg config abi`. Override with the environment variable when testing from a non-OPNsense host.

```sh
# Sequential execution with 5 MB speed test
PARALLEL=0 SPEED_MB=5 sh opnsense-mirror-speedtest.sh

# aarch64 target
FREEBSD_ABI=FreeBSD:15:aarch64 sh opnsense-mirror-speedtest.sh

# Test against an older release (26.1)
VERSION=26.1 FREEBSD_ABI=FreeBSD:14:amd64 sh opnsense-mirror-speedtest.sh
```

## How it works

Each mirror is tested in two phases:

| Phase | File | Metrics |
|-------|------|---------|
| 1. Latency | `meta.conf` (a few KB) | DNS time, connect time, TTFB |
| 2. Speed | `packagesite.pkg` (first 2 MB) | Download speed |

## Mirror list source

The mirror list is sourced from the [opnsense/core](https://github.com/opnsense/core) repository:  
`src/opnsense/mvc/app/models/OPNsense/Core/repositories/opnsense.xml`

Deciso commercial mirrors (subscription required) are excluded.

## License

[BSD 2-Clause License](LICENSE)

---

# OPNsense ミラー速度計測

OPNsense の **pkgリポジトリミラー** の速度を計測し、最速ミラーを特定するシェルスクリプトです。

`System > Firmware > Settings > Mirror` のプルダウンに掲載されているミラーサイト全16件を対象に、DNS解決時間・接続時間・TTFB・ダウンロード速度を測定し、結果を一覧表示します。

## 動作環境

| 環境 | 実行方法 |
|------|---------|
| Ubuntu 24.04 | `bash opnsense-mirror-speedtest.sh` |
| OPNsense 26.7 (tcsh) | `sh opnsense-mirror-speedtest.sh` |

依存ツール: `curl`、`awk`（どちらも標準インストール済み）

## 使い方

```sh
sh opnsense-mirror-speedtest.sh
```

## オプション（環境変数）

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `VERSION` | `26.7` | テスト対象のOPNsenseバージョン |
| `PARALLEL` | `1` | `1`=並列実行（高速）、`0`=逐次実行（進捗が見やすい） |
| `SPEED_MB` | `2` | 速度テストで取得するデータ量 (MB) |
| `NO_COLOR` | — | `1` を指定するとカラー出力を無効化 |

> **`FREEBSD_ABI` について**  
> URLパスに必要な FreeBSD ABI 文字列（例: `FreeBSD:15:amd64`）は、OPNsense上では `pkg config abi` で自動取得します。Ubuntu等から実行する場合は環境変数で上書き可能です。

## 測定内容

各ミラーに対して2段階の測定を行います。

| フェーズ | 対象ファイル | 測定項目 |
|---------|------------|---------|
| 1. レイテンシ | `meta.conf`（数KB） | DNS解決時間・接続時間・TTFB |
| 2. 速度 | `packagesite.pkg`（先頭2MB） | ダウンロード速度 |

## ミラーリスト

[opnsense/core](https://github.com/opnsense/core) リポジトリの  
`src/opnsense/mvc/app/models/OPNsense/Core/repositories/opnsense.xml` に定義されている公式リストを使用しています。

Deciso 商用ミラー（サブスクリプション契約が必要）は除外しています。

## ライセンス

[BSD 2-Clause License](LICENSE)
