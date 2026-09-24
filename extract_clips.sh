#!/bin/bash
#
# extract_clips.sh (v2)
#
# Batch-extracts in/out segments from a clips CSV and transcodes them to
# DNxHR for DaVinci Resolve, with the same quality presets as the
# Paper Edit -> Clips browser app.
#
# USAGE:
#   ./extract_clips.sh <clips.csv> <output_dir> [--preset lb|sq|hq|hqx] [--also-hq]
#
#   clips.csv    - source,start,end,output_name  (see log_clip.sh to build one)
#   output_dir   - base output folder; each preset writes into its own
#                  subfolder so different quality passes never collide:
#                    lb  -> output_dir/proxy_lb/
#                    sq  -> output_dir/offline_sq/
#                    hq  -> output_dir/dnxhr_hq/     (default)
#                    hqx -> output_dir/dnxhr_hqx/
#   --preset     - quality preset, default: hq
#   --also-hq    - also render a Full Quality (dnxhr_hq) pass alongside
#                  whichever --preset you chose (ignored if preset is hq)
#
# EXAMPLES:
#   ./extract_clips.sh clips.csv /media/drive/output
#   ./extract_clips.sh clips.csv /media/drive/output --preset lb
#   ./extract_clips.sh clips.csv /media/drive/output --preset lb --also-hq

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: $0 <clips.csv> <output_dir> [--preset lb|sq|hq|hqx] [--also-hq]"
    exit 1
fi

CSV_FILE="$1"
OUTPUT_BASE="$2"
shift 2

PRESET="hq"
ALSO_HQ=0

while [ $# -gt 0 ]; do
    case "$1" in
        --preset)
            PRESET="$2"
            shift 2
            ;;
        --also-hq)
            ALSO_HQ=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ ! -f "$CSV_FILE" ]; then
    echo "Error: CSV file not found: $CSV_FILE"
    exit 1
fi

# preset -> "profile:pix_fmt:subfolder"
preset_spec() {
    case "$1" in
        lb)  echo "dnxhr_lb:yuv422p:proxy_lb" ;;
        sq)  echo "dnxhr_sq:yuv422p:offline_sq" ;;
        hq)  echo "dnxhr_hq:yuv422p:dnxhr_hq" ;;
        hqx) echo "dnxhr_hqx:yuv422p10le:dnxhr_hqx" ;;
        *)   echo "" ;;
    esac
}

SPEC="$(preset_spec "$PRESET")"
if [ -z "$SPEC" ]; then
    echo "Error: unknown preset '$PRESET' (use lb, sq, hq, or hqx)"
    exit 1
fi

PRESETS_TO_RUN=("$SPEC")
if [ "$ALSO_HQ" -eq 1 ] && [ "$PRESET" != "hq" ]; then
    PRESETS_TO_RUN+=("$(preset_spec hq)")
fi

tc_to_seconds() {
    local tc="$1"
    IFS=: read -r h m s <<< "$tc"
    echo "$h * 3600 + $m * 60 + $s" | bc
    }

run_preset() {
    local spec="$1"
    local profile pix_fmt subfolder outdir
    IFS=: read -r profile pix_fmt subfolder <<< "$spec"
    outdir="$OUTPUT_BASE/$subfolder"
    mkdir -p "$outdir"

    echo ""
    echo "=== ${profile} -> $outdir ==="

    local line_num=0 ok_count=0 fail_count=0

    while IFS=, read -r source start end name || [ -n "${source:-}" ]; do
        line_num=$((line_num + 1))
        [[ -z "${source// }" ]] && continue
        [[ "$source" =~ ^# ]] && continue
        [[ "$source" == "source" ]] && continue

        source="$(echo "$source" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        start="$(echo "$start" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        end="$(echo "$end" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        name="$(echo "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        # strip surrounding quotes if present (from a quoted CSV field)
        source="${source%\"}"
        source="${source#\"}"

        if [ ! -f "$source" ]; then
            echo "[line $line_num] SKIP - source not found: $source"
            fail_count=$((fail_count + 1))
            continue
        fi

        local start_sec end_sec duration
        start_sec=$(tc_to_seconds "$start")
        end_sec=$(tc_to_seconds "$end")
        duration=$(echo "$end_sec - $start_sec" | bc)

        if (( $(echo "$duration <= 0" | bc -l) )); then
            echo "[line $line_num] SKIP - end is not after start ($start -> $end)"
            fail_count=$((fail_count + 1))
            continue
        fi

        local outfile="$outdir/${name}.mov"
        echo "[line $line_num] $source  ${start} -> ${end}  (${duration}s)  =>  $outfile"

        if ffmpeg -nostdin -threads 1 -y -ss "$start_sec" -i "$source" -t "$duration" \
            -c:v dnxhd -profile:v "$profile" -pix_fmt "$pix_fmt" -c:a pcm_s16le \
            "$outfile" -loglevel error; then
            ok_count=$((ok_count + 1))
        else
            echo "[line $line_num] FFMPEG FAILED for $name"
            fail_count=$((fail_count + 1))
        fi
    done < "$CSV_FILE"

    echo "--- $subfolder: $ok_count clip(s) written, $fail_count failed/skipped ---"
}

for spec in "${PRESETS_TO_RUN[@]}"; do
    run_preset "$spec"
done

echo ""
echo "All done. Output under: $OUTPUT_BASE"
