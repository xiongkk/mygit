#!/usr/bin/env bash
# BashとLinux標準コマンドのみで、全ファイルを再帰的に検査する。
# 改行はLFのみ。LF自体はレコードサイズに含めず、CRは1バイトとして数える。
set -euo pipefail
export LC_ALL=C

if [[ $# -ne 1 || ! -d "$1" ]]; then
    printf '使用方法: bash %s ディレクトリ > 結果.csv\n' "$0" >&2
    exit 2
fi

root=$(cd -- "$1" && pwd -P)
manifest=$(mktemp)
trap 'rm -f -- "$manifest"' EXIT

# NUL区切りで、空白・カンマ・改行を含むファイル名にも対応する。
# ディレクトリのシンボリックリンクはたどらない。
find "$root" -type f -print0 > "$manifest"
printf 'ファイル名,固定長or可変長,1行のレコードサイズ（Byte）,行数\n'
failed=0

while IFS= read -r -d '' path; do
    # LC_ALL=Cにより、length($0)で文字数ではなくバイト数を取得する。
    # フィールド分割やバイトごとの処理を避け、レコード単位で比較する。
    if result=$(awk '
        BEGIN { fixed = 1 }
        {
            size = length($0)
            if (NR == 1) first_size = size
            else if (size != first_size) {
                # 可変長では行数不要のため、長さが異なる時点で検査を終了する。
                fixed = 0
                exit
            }
        }
        END {
            # NRにはLFのない最終行も含まれる。末尾LFの後には空行を追加しない。
            # 単一行と空ファイルは判定保留とする。
            if (NR <= 1) printf "判定保留,,%.0f", NR
            else if (fixed) printf "固定長,%.0f,%.0f", first_size, NR
            else printf "可変長,,"
        }
    ' "$path"); then
        relative=${path#"${root%/}/"}
        # CSVのファイル名は引用符で囲み、内部の引用符を二重化する。
        escaped=${relative//\"/\"\"}
        printf '"%s",%s\n' "$escaped" "$result"
    else
        printf 'エラー: 読み込みに失敗しました: %s\n' "$path" >&2
        failed=1
    fi
done < "$manifest"

exit "$failed"
