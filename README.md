# OPNsense Mirror Speed Test

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

### 出力例

```
OPNsense PKG Mirror Speed Test  v26.7 / FreeBSD:15:amd64

レイテンシ測定: {mirror}/FreeBSD:15:amd64/26.7/latest/meta.conf
速度測定      : {mirror}/FreeBSD:15:amd64/26.7/latest/packagesite.pkg (先頭2MB)

Testing 16 mirrors [並列実行]...
  待機中 完了

Mirror                   Status        DNS   Connect     TTFB Speed        Bar (相対速度)
───────────────────────────────────────────────────────────────────────────────────────────────
LeaseWeb AMS (NL)        OK           12ms      45ms    120ms 8.43 MB/s    ██████████████████████
LeaseWeb FRA (DE)        OK           14ms      48ms    135ms 6.21 MB/s    ████████████████░░░░░░
Aalborg Univ (DK)        OK           18ms      62ms    180ms 5.10 MB/s    █████████████░░░░░░░░░
OPNsense (NL)            OK           20ms      70ms    195ms 4.87 MB/s    ████████████░░░░░░░░░░
...
Ventura Sys (CO)         FAIL:000      ---       ---      ---
───────────────────────────────────────────────────────────────────────────────────────────────

最速ミラー : LeaseWeb AMS (NL)
URL        : https://mirror.ams1.nl.leaseweb.net/opnsense
速度       : 8.43 MB/s  (TTFB: 120ms)

OPNsense Settings への設定:
  System > Firmware > Settings > Mirror
  → LeaseWeb AMS (NL)

成功: 14 / 失敗: 2
```

## オプション（環境変数）

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `VERSION` | `26.7` | テスト対象のOPNsenseバージョン |
| `PARALLEL` | `1` | `1`=並列実行（高速）、`0`=逐次実行（進捗が見やすい） |
| `SPEED_MB` | `2` | 速度テストで取得するデータ量 (MB) |
| `NO_COLOR` | — | `1` を指定するとカラー出力を無効化 |

> **`FREEBSD_ABI` について**  
> URLパスに必要な FreeBSD ABI 文字列（例: `FreeBSD:15:amd64`）は、OPNsense上では `pkg config abi` で自動取得します。Ubuntu等で別バージョンをテストする場合は環境変数で上書き可能です。

```sh
# 例: 逐次実行・5MB測定
PARALLEL=0 SPEED_MB=5 sh opnsense-mirror-speedtest.sh

# 例: aarch64環境
FREEBSD_ABI=FreeBSD:15:aarch64 sh opnsense-mirror-speedtest.sh

# 例: 旧バージョン (26.1) をテスト
VERSION=26.1 FREEBSD_ABI=FreeBSD:14:amd64 sh opnsense-mirror-speedtest.sh
```

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
