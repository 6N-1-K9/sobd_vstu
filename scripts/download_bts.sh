#!/usr/bin/env bash
# Скачивание датасета BTS Reporting Carrier On-Time Performance (2019-2023)
# и распаковка в CSV для последующей загрузки в HDFS.
#
# Источник: transtats.bts.gov (официальные данные USDOT, без регистрации)
# ~29 МБ zip в месяц -> суммарно ~1,7 ГБ загрузки, ~15-17 ГБ CSV.
#
# Особенности:
#   * параллельная загрузка (по умолчанию 4 потока, меняется через PARALLEL=N)
#   * докачка и безопасность перезапуска: качаем в *.part, переименовываем по готовности
set -euo pipefail

BASE_URL="https://transtats.bts.gov/PREZIP/On_Time_Reporting_Carrier_On_Time_Performance_1987_present"
YEARS=(2019 2020 2021 2022 2023)
PARALLEL="${PARALLEL:-4}"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ZIPS_DIR="$REPO_DIR/data/raw"
CSV_DIR="$REPO_DIR/data/csv"
mkdir -p "$ZIPS_DIR" "$CSV_DIR"

download_one() {
    local year="$1" month="$2"
    local zip_path="$ZIPS_DIR/${year}_${month}.zip"
    local url="${BASE_URL}_${year}_${month}.zip"
    # Уже скачан полностью -- пропускаем
    [[ -s "$zip_path" ]] && return 0
    if curl -fL --retry 3 --retry-delay 5 --connect-timeout 30 -C - \
            -o "${zip_path}.part" "$url"; then
        mv -f "${zip_path}.part" "$zip_path"
        echo "OK ${year}-${month}"
    else
        echo "FAIL ${year}-${month}"
    fi
}
export -f download_one
export BASE_URL ZIPS_DIR

TOTAL=$(( ${#YEARS[@]} * 12 ))

# Список ещё не скачанных месяцев
LIST="$(mktemp)"
for year in "${YEARS[@]}"; do
    for month in $(seq 1 12); do
        [[ -s "$ZIPS_DIR/${year}_${month}.zip" ]] || echo "$year $month" >> "$LIST"
    done
done
echo "Уже скачано: $(( TOTAL - $(wc -l < "$LIST") )) из $TOTAL"

xargs -P "$PARALLEL" -n 2 bash -c 'download_one "$0" "$1"' < "$LIST"
rm -f "$LIST"

GOT="$(ls "$ZIPS_DIR"/*.zip 2>/dev/null | wc -l)"
echo "Архивов загружено: $GOT (ожидалось $TOTAL)"
if [[ "$GOT" -lt "$TOTAL" ]]; then
    echo "ОШИБКА: часть архивов не скачалась, перезапустите скрипт (докачает недостающее)"
    exit 1
fi

# --- Распаковка ---
for zip_path in "$ZIPS_DIR"/*.zip; do
    unzip -o -q "$zip_path" -d "$CSV_DIR"
done

echo "CSV-файлов распаковано: $(ls "$CSV_DIR"/*.csv | wc -l)"
du -sh "$ZIPS_DIR" "$CSV_DIR"
