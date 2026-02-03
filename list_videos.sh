#!/bin/bash
#
# list_videos.sh - Fetch paginated video list from Procare API
#
# Description:
#   Retrieves all videos from the Procare parent portal API by paginating
#   through results and merging them into a single JSON file.
#
# Prerequisites:
#   - credentials.txt: File containing the Bearer auth token (no newline)
#   - jq: Required for JSON parsing
#   - curl: Required for API requests
#
# Output:
#   - raw_video_list_response.json: Combined JSON with all videos
#     Format: { "videos": [...], "total": <count> }
#
# Usage:
#   ./list_videos.sh
#

# Configuration
BASE_URL="https://api-school.procareconnect.com/api/web/parent/videos/"
OUTPUT_FILE="raw_video_list_response.json"
TEMP_DIR="tmp_pages"

# Date range
START_YEAR=2023
START_MONTH=2
END_YEAR=2026
END_MONTH=2

# Initialize variables
PAGE=1
TOTAL_VIDEOS=0
PER_PAGE=0
EXPECTED_PAGES=0
ACTUAL_PAGES=0
ACTUAL_VIDEO_COUNT=0

# Load credentials
if [ ! -f "credentials.txt" ]; then
    echo "Error: credentials.txt not found."
    exit 1
fi
AUTH_TOKEN=$(cat credentials.txt | tr -d '\n')


# Create a temp directory for page results
mkdir -p "$TEMP_DIR"
# Clean up any previous run artifacts
rm -f "$TEMP_DIR"/*.json

# Function to get last day of month (macOS compatible)
get_last_day() {
    local year=$1
    local month=$2
    if [ "$month" -eq 12 ]; then
        echo 31
    else
        local next_month=$((month + 1))
        local next_month_padded=$(printf "%02d" $next_month)
        date -j -v-1d -f "%Y-%m-%d" "${year}-${next_month_padded}-01" +%d 2>/dev/null
    fi
}

# Build URL-encoded date range
START_MONTH_PADDED=$(printf "%02d" $START_MONTH)
END_MONTH_PADDED=$(printf "%02d" $END_MONTH)
END_LAST_DAY=$(get_last_day $END_YEAR $END_MONTH)
DATE_FROM="${START_YEAR}-${START_MONTH_PADDED}-01%2000%3A00"
DATE_TO="${END_YEAR}-${END_MONTH_PADDED}-${END_LAST_DAY}%2023%3A59"

echo "Starting video list retrieval..."
echo "Date range: ${START_YEAR}-${START_MONTH_PADDED}-01 to ${END_YEAR}-${END_MONTH_PADDED}-${END_LAST_DAY}"

while true; do
    echo "Fetching page $PAGE..."
    
    # Construct the URL with the current page number
    URL="https://api-school.procareconnect.com/api/web/parent/videos/?page=${PAGE}&filters%5Bvideo%5D%5Bdatetime_from%5D=${DATE_FROM}&filters%5Bvideo%5D%5Bdatetime_to%5D=${DATE_TO}"
    
    CURRENT_PAGE_FILE="${TEMP_DIR}/page_${PAGE}.json"

    curl -s "$URL" \
      -H 'Accept: application/json' \
      -H "Authorization: Bearer $AUTH_TOKEN" \
      -o "$CURRENT_PAGE_FILE"

    # Check curl exit code
    if [ $? -ne 0 ]; then
        echo "Error: Curl command failed for page $PAGE."
        break
    fi

    # Parse response using jq
    # Check if the file is valid JSON and has a videos array
    if ! jq -e . "$CURRENT_PAGE_FILE" >/dev/null 2>&1; then
        echo "Error: Invalid JSON response on page $PAGE."
        cat "$CURRENT_PAGE_FILE"
        break
    fi

    VIDEO_COUNT=$(jq '.videos | length' "$CURRENT_PAGE_FILE")
    
    # If no videos, we are done
    if [ "$VIDEO_COUNT" -eq 0 ]; then
        echo "No videos found on page $PAGE. Reached end of list."
        rm "$CURRENT_PAGE_FILE" # Remove the empty page file
        break
    fi

    ACTUAL_VIDEO_COUNT=$((ACTUAL_VIDEO_COUNT + VIDEO_COUNT))

    # Retrieve Total and Per Page from the first page
    if [ "$PAGE" -eq 1 ]; then
        TOTAL_VIDEOS=$(jq '.total' "$CURRENT_PAGE_FILE")
        PER_PAGE=$(jq '.per_page' "$CURRENT_PAGE_FILE")
    fi

    ACTUAL_PAGES=$((ACTUAL_PAGES + 1))
    PAGE=$((PAGE + 1))
done

# Calculate Expected Pages
if [ "$PER_PAGE" -gt 0 ] 2>/dev/null;
then
    # Integer division with ceiling: (a + b - 1) / b
    EXPECTED_PAGES=$(( (TOTAL_VIDEOS + PER_PAGE - 1) / PER_PAGE ))
else
    EXPECTED_PAGES=0
fi

echo ""
echo "---------------- Summary ----------------"
echo "Expected Videos:         $TOTAL_VIDEOS"
echo "Actual Videos Retrieved: $ACTUAL_VIDEO_COUNT"
echo "Videos Per Page:         $PER_PAGE"
echo "Expected Pages:          $EXPECTED_PAGES"
echo "Actual Pages Fetched:    $ACTUAL_PAGES"
echo "-----------------------------------------"

# Combine all videos into one JSON file
echo "Merging results into $OUTPUT_FILE..."

if [ "$ACTUAL_PAGES" -gt 0 ]; then
    # Merge all page files. 
    # Structure: { "videos": [ ... all videos flattened ... ], "total": ... }
    # We use jq to slurp all files, map to their .videos array, flatten it, and wrap it.
    jq -s --argjson total "$TOTAL_VIDEOS" 'map(.videos) | add | {videos: ., total: $total}' "$TEMP_DIR"/page_*.json > "$OUTPUT_FILE"
else
    echo "{ \"videos\": [], \"total\": 0 }" > "$OUTPUT_FILE"
fi

# Cleanup
rm -rf "$TEMP_DIR"

echo "Done. Full video list saved to $OUTPUT_FILE"
