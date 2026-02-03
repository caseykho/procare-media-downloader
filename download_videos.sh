#!/bin/bash
#
# download_videos.sh - Download videos from Procare video list
#
# Description:
#   Downloads video files from URLs in the JSON output of list_videos.sh.
#   Supports throttling, jitter, and resumable downloads (skips existing files).
#
# Prerequisites:
#   - raw_video_list_response.json (or custom input via -f)
#   - jq: Required for JSON parsing
#   - curl: Required for downloads
#
# Output:
#   - videos/<id>.mp4: Downloaded video files
#
# Options:
#   -n <limit>    Number of videos to download (0 = all, default: 0)
#   -t <seconds>  Base sleep time between downloads (default: 2)
#   -j <seconds>  Max random jitter added to sleep (default: 2)
#   -f <file>     Input JSON file (default: raw_video_list_response.json)
#
# Usage:
#   ./download_videos.sh              # Download all videos
#   ./download_videos.sh -n 10        # Download first 10 videos
#   ./download_videos.sh -t 5 -j 3    # Custom throttling
#
set -euo pipefail

# Default values
LIMIT=0
THROTTLE=2
JITTER=2
INPUT_FILE="raw_video_list_response.json"

# Usage function
usage() {
    echo "Usage: $0 [-n limit] [-t throttle_sec] [-j jitter_sec] [-f input_file]"
    echo "  -n: Number of videos to download (default: 0 = all)"
    echo "  -t: Base sleep time between downloads (default: 2)"
    echo "  -j: Max random jitter time added to sleep (default: 2)"
    echo "  -f: Input JSON file (default: raw_video_list_response.json)"
    exit 1
}

# Parse arguments
while getopts "n:t:j:f:" opt; do
    case $opt in
        n) LIMIT=$OPTARG ;;
        t) THROTTLE=$OPTARG ;;
        j) JITTER=$OPTARG ;;
        f) INPUT_FILE=$OPTARG ;;
        *) usage ;;
    esac
done

# Validate numeric arguments
if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
    echo "Error: -n must be a non-negative integer"
    exit 1
fi
if ! [[ "$THROTTLE" =~ ^[0-9]+$ ]]; then
    echo "Error: -t must be a non-negative integer"
    exit 1
fi
if ! [[ "$JITTER" =~ ^[0-9]+$ ]]; then
    echo "Error: -j must be a non-negative integer"
    exit 1
fi

# Check input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found"
    exit 1
fi

# Create videos directory
mkdir -p videos

# Use mktemp for safer temp file creation
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE"' EXIT

# Extract ID and URL
if ! jq -r '.videos[] | "\(.id) \(.video_file_url)"' "$INPUT_FILE" > "$TEMP_FILE"; then
    echo "Error: Failed to parse JSON from '$INPUT_FILE'"
    exit 1
fi

# Counter for limit (counts successful downloads only)
COUNT=0

while read -r id url; do
    # Check limit if set
    if [ "$LIMIT" -gt 0 ] && [ "$COUNT" -ge "$LIMIT" ]; then
        echo "Limit of $LIMIT downloads reached."
        break
    fi

    FILENAME="videos/${id}.mp4"

    if [ -f "$FILENAME" ]; then
        echo "[SKIP] $FILENAME already exists."
    else
        # Throttling with jitter
        if [ "$JITTER" -gt 0 ]; then
            RAND_JITTER=$(( RANDOM % (JITTER + 1) ))
        else
            RAND_JITTER=0
        fi
        SLEEP_TIME=$(( THROTTLE + RAND_JITTER ))

        echo "Sleeping for ${SLEEP_TIME}s..."
        sleep $SLEEP_TIME

        echo "[DOWNLOADING] $FILENAME..."
        if curl -# -L -o "$FILENAME" "$url"; then
            echo "[SUCCESS] Saved to $FILENAME"
            ((COUNT++))
        else
            echo "[ERROR] Failed to download $url"
            rm -f "$FILENAME"
        fi
    fi

done < "$TEMP_FILE"

echo "Downloaded $COUNT video(s)."
