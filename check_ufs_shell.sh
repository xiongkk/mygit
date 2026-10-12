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
    # odで各バイトを数値に変換し、NULを含むファイルも正しく計測する。
    if result=$(od -An -v -tu1 -- "$path" | awk '
        BEGIN { count = 0; size = 0; fixed = 1 }
        function finish_record() {
            count++
            if (count == 1) first_size = size
            else if (size != first_size) fixed = 0
            size = 0
        }
        {
            for (i = 1; i <= NF; i++) {
                if ($i == 10) finish_record()
                else size++
            }
        }
        END {
            # LFのない最終行も数える。末尾LFの後には空行を追加しない。
            if (size > 0) finish_record()
            # 単一行と空ファイルは判定保留とする。
            if (count <= 1) printf "判定保留,,%.0f", count
            else if (fixed) printf "固定長,%.0f,%.0f", first_size, count
            else printf "可変長,,"
        }
    '); then
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
