#!/bin/bash
#
# log_clip.sh — append one in/out segment to a clips CSV, from the terminal.
# No browser, no local storage — this CSV is a plain file on disk, so it
# survives reboots, different browsers, private windows, cache clears, etc.
#
# USAGE:
#   ./log_clip.sh <clips.csv> <source> <start> <end> [output_name]
#
#   clips.csv     - the CSV file to append to (created with a header if new)
#   source        - path to the source mp4 (quote it if it has spaces)
#   start         - in point, HH:MM:SS or HH:MM:SS.mmm
#   end           - out point, HH:MM:SS or HH:MM:SS.mmm
#   output_name   - optional; auto-generated from the source filename + a
#                   running segment number if omitted (sourcebase_segN)
#
# EXAMPLES:
#   ./log_clip.sh clips.csv "footage/sample.mp4" 00:03:05 00:03:15
#   ./log_clip.sh clips.csv "footage/sample.mp4" 00:05:00 00:05:25 my_custom_name
#
# Run it once per segment. Multiple segments from the same source file just
# mean multiple calls with that same source — output names auto-number.

set -euo pipefail

if [ $# -lt 4 ]; then
    echo "Usage: $0 <clips.csv> <source> <start> <end> [output_name]"
    exit 1
fi

CSV_FILE="$1"
SOURCE="$2"
START="$3"
END="$4"
NAME="${5:-}"

TIME_RE='^[0-9]{1,2}:[0-5][0-9]:[0-5][0-9](\.[0-9]{1,3})?$'

if ! [[ "$START" =~ $TIME_RE ]]; then
    echo "Error: start '$START' doesn't look like HH:MM:SS or HH:MM:SS.mmm"
    exit 1
fi
if ! [[ "$END" =~ $TIME_RE ]]; then
    echo "Error: end '$END' doesn't look like HH:MM:SS or HH:MM:SS.mmm"
    exit 1
fi

# create the file with a header if it doesn't exist yet
if [ ! -f "$CSV_FILE" ]; then
    echo "source,start,end,output_name" > "$CSV_FILE"
fi

# auto-generate an output name if none given: basename (no ext) + _segN,
# where N is one more than however many rows already reference this source
if [ -z "$NAME" ]; then
    base="$(basename "$SOURCE")"
    base="${base%.*}"
    base="$(echo "$base" | sed -E 's/[^a-zA-Z0-9_-]+/_/g; s/^_+|_+$//g')"
    existing=$(grep -F -c "\"$SOURCE\"" "$CSV_FILE" 2>/dev/null || true)
    existing=${existing:-0}
    n=$((existing + 1))
    NAME="${base}_seg${n}"
fi

# quote the source field (it may contain spaces / commas)
ESCAPED_SOURCE="${SOURCE//\"/\"\"}"
echo "\"$ESCAPED_SOURCE\",$START,$END,$NAME" >> "$CSV_FILE"

echo "Logged: $SOURCE  ${START} -> ${END}  as '$NAME'  (row $(($(wc -l < "$CSV_FILE") - 1)) of $CSV_FILE)"
