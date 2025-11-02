#!/bin/bash

# Tuist Cache Performance Analyzer
# Usage: ./analyze_cache_logs.sh <log_file>
#
# This script analyzes Tuist cache logs to extract performance metrics:
# - KeyValue.getValue latency statistics
# - CAS.load throughput and download statistics
# - Overall performance summary

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <log_file>"
    echo "Example: $0 logs-central-home.txt"
    exit 1
fi

LOG_FILE="$1"

if [ ! -f "$LOG_FILE" ]; then
    echo "Error: Log file '$LOG_FILE' not found"
    exit 1
fi

echo "🔍 Analyzing Tuist cache performance from: $LOG_FILE"
echo "=================================================="

# Extract KeyValue operations
echo ""
echo "📊 KeyValue.getValue Performance"
echo "--------------------------------"

KEYVALUE_DATA=$(grep "KeyValue.getValue completed successfully" "$LOG_FILE" | \
    sed 's/.*in \([0-9.]*\)s.*/\1/' | sort -n || true)

if [ -n "$KEYVALUE_DATA" ]; then
    KEYVALUE_COUNT=$(echo "$KEYVALUE_DATA" | wc -l | tr -d ' ')
    KEYVALUE_MIN=$(echo "$KEYVALUE_DATA" | head -1)
    KEYVALUE_MAX=$(echo "$KEYVALUE_DATA" | tail -1)
    KEYVALUE_AVG=$(echo "$KEYVALUE_DATA" | awk '{sum+=$1} END {printf "%.3f", sum/NR}')
    KEYVALUE_MEDIAN=$(echo "$KEYVALUE_DATA" | awk 'NR%2==1{print $1} NR%2==0{print ($1+prev)/2} {prev=$1}' | tail -1)
    
    echo "Total operations: $KEYVALUE_COUNT"
    KEYVALUE_AVG_MS=$(echo "$KEYVALUE_AVG * 1000" | bc -l 2>/dev/null | xargs printf "%.0f" 2>/dev/null || echo "0")
    KEYVALUE_MEDIAN_MS=$(echo "$KEYVALUE_MEDIAN * 1000" | bc -l 2>/dev/null | xargs printf "%.0f" 2>/dev/null || echo "0")
    KEYVALUE_MIN_MS=$(echo "$KEYVALUE_MIN * 1000" | bc -l 2>/dev/null | xargs printf "%.0f" 2>/dev/null || echo "0")
    KEYVALUE_MAX_MS=$(echo "$KEYVALUE_MAX * 1000" | bc -l 2>/dev/null | xargs printf "%.0f" 2>/dev/null || echo "0")
    
    echo "Average latency:  ${KEYVALUE_AVG}s (${KEYVALUE_AVG_MS}ms)"
    echo "Median latency:   ${KEYVALUE_MEDIAN}s (${KEYVALUE_MEDIAN_MS}ms)"
    echo "Min latency:      ${KEYVALUE_MIN}s (${KEYVALUE_MIN_MS}ms)"
    echo "Max latency:      ${KEYVALUE_MAX}s (${KEYVALUE_MAX_MS}ms)"
else
    echo "No KeyValue operations found"
fi

# Extract CAS operations
echo ""
echo "📦 CAS.load Performance"
echo "-----------------------"

CAS_DATA=$(grep "CAS.load completed successfully" "$LOG_FILE" || true)

if [ -n "$CAS_DATA" ]; then
    # Extract download times and file sizes
    CAS_TIMES=$(echo "$CAS_DATA" | sed 's/.*in \([0-9.]*\)s.*/\1/' | sort -n)
    
    # Check if logs have new compression format (compressed + decompressed bytes)
    if echo "$CAS_DATA" | grep -q "compressed bytes, decompressed to"; then
        echo "Detected new compression format logs"
        CAS_COMPRESSED_BYTES=$(echo "$CAS_DATA" | sed 's/.*loaded \([0-9]*\) compressed bytes.*/\1/')
        CAS_BYTES=$(echo "$CAS_DATA" | sed 's/.*decompressed to \([0-9]*\) bytes.*/\1/')
    else
        echo "Detected legacy format logs"
        CAS_BYTES=$(echo "$CAS_DATA" | sed 's/.*loaded \([0-9]*\) bytes.*/\1/')
        CAS_COMPRESSED_BYTES=""
    fi
    
    CAS_COUNT=$(echo "$CAS_TIMES" | wc -l | tr -d ' ')
    CAS_MIN_TIME=$(echo "$CAS_TIMES" | head -1)
    CAS_MAX_TIME=$(echo "$CAS_TIMES" | tail -1)
    CAS_AVG_TIME=$(echo "$CAS_TIMES" | awk '{sum+=$1} END {printf "%.3f", sum/NR}')
    
    TOTAL_BYTES=$(echo "$CAS_BYTES" | awk '{sum+=$1} END {print sum}')
    TOTAL_MB=$(echo "scale=2; $TOTAL_BYTES / 1024 / 1024" | bc -l 2>/dev/null || echo "0")
    
    echo "Total operations: $CAS_COUNT"
    if [ -n "$CAS_COMPRESSED_BYTES" ]; then
        TOTAL_COMPRESSED_BYTES=$(echo "$CAS_COMPRESSED_BYTES" | awk '{sum+=$1} END {print sum}')
        TOTAL_COMPRESSED_MB=$(echo "scale=2; $TOTAL_COMPRESSED_BYTES / 1024 / 1024" | bc -l 2>/dev/null || echo "0")
        COMPRESSION_RATIO=$(echo "scale=1; $TOTAL_BYTES / $TOTAL_COMPRESSED_BYTES" | bc -l 2>/dev/null || echo "1.0")
        echo "Total data:       ${TOTAL_MB} MB decompressed (${TOTAL_BYTES} bytes)"
        echo "Compressed data:  ${TOTAL_COMPRESSED_MB} MB (${TOTAL_COMPRESSED_BYTES} bytes)"
        echo "Compression ratio: ${COMPRESSION_RATIO}:1"
    else
        echo "Total data:       ${TOTAL_MB} MB (${TOTAL_BYTES} bytes)"
    fi
    echo "Average time:     ${CAS_AVG_TIME}s"
    echo "Min time:         ${CAS_MIN_TIME}s"
    echo "Max time:         ${CAS_MAX_TIME}s"
    
    # Calculate per-operation throughput statistics
    echo "$CAS_DATA" | while read -r line; do
        TIME=$(echo "$line" | sed 's/.*in \([0-9.]*\)s.*/\1/')
        if echo "$line" | grep -q "compressed bytes, decompressed to"; then
            # New format: use decompressed bytes for throughput
            BYTES=$(echo "$line" | sed 's/.*decompressed to \([0-9]*\) bytes.*/\1/')
        else
            # Legacy format: use loaded bytes
            BYTES=$(echo "$line" | sed 's/.*loaded \([0-9]*\) bytes.*/\1/')
        fi
        if [ "$TIME" != "0" ] && [ "$TIME" != "0.000" ]; then
            THROUGHPUT=$(echo "scale=3; $BYTES / $TIME / 1024 / 1024" | bc -l 2>/dev/null || echo "0")
            echo "$THROUGHPUT"
        fi
    done > /tmp/cas_throughputs.txt
    
    if [ -s /tmp/cas_throughputs.txt ]; then
        AVG_THROUGHPUT=$(awk '{sum+=$1} END {printf "%.1f", sum/NR}' /tmp/cas_throughputs.txt)
        MEDIAN_THROUGHPUT=$(sort -n /tmp/cas_throughputs.txt | awk 'NR%2==1{print $1} NR%2==0{print ($1+prev)/2} {prev=$1}' | tail -1)
        MAX_THROUGHPUT=$(sort -n /tmp/cas_throughputs.txt | tail -1)
        
        echo "Avg throughput:   ${AVG_THROUGHPUT} MB/s per operation"
        echo "Median throughput: ${MEDIAN_THROUGHPUT} MB/s per operation"
        echo "Max throughput:   ${MAX_THROUGHPUT} MB/s per operation"
    fi
    
    rm -f /tmp/cas_throughputs.txt
else
    echo "No CAS operations found"
fi

# Calculate time window and aggregate throughput
echo ""
echo "⏱️  Overall Performance"
echo "----------------------"

# Extract first and last timestamps
FIRST_TIMESTAMP=$(grep -E "(KeyValue\.getValue|CAS\.load)" "$LOG_FILE" | head -1 | awk '{print $1, $2}' || true)
LAST_TIMESTAMP=$(grep -E "(KeyValue\.getValue|CAS\.load)" "$LOG_FILE" | tail -1 | awk '{print $1, $2}' || true)

if [ -n "$FIRST_TIMESTAMP" ] && [ -n "$LAST_TIMESTAMP" ]; then
    echo "First operation:  $FIRST_TIMESTAMP"
    echo "Last operation:   $LAST_TIMESTAMP"
    
    # Calculate time difference (simplified - assumes same day)
    FIRST_TIME=$(echo "$FIRST_TIMESTAMP" | cut -d'+' -f1 | cut -d' ' -f2)
    LAST_TIME=$(echo "$LAST_TIMESTAMP" | cut -d'+' -f1 | cut -d' ' -f2)
    
    # Extract seconds from timestamps for rough calculation
    FIRST_SECONDS=$(echo "$FIRST_TIME" | awk -F: '{print $1*3600 + $2*60 + $3}')
    LAST_SECONDS=$(echo "$LAST_TIME" | awk -F: '{print $1*3600 + $2*60 + $3}')
    
    # Use bc for floating point comparison
    TIME_DIFF_CHECK=$(echo "$LAST_SECONDS > $FIRST_SECONDS" | bc -l 2>/dev/null || echo "0")
    if [ "$TIME_DIFF_CHECK" = "1" ]; then
        TIME_WINDOW=$(echo "$LAST_SECONDS - $FIRST_SECONDS" | bc -l 2>/dev/null || echo "0")
        echo "Time window:      ${TIME_WINDOW}s"
        
        if [ -n "$TOTAL_BYTES" ] && [ "$TIME_WINDOW" != "0" ]; then
            AGGREGATE_THROUGHPUT=$(echo "scale=1; $TOTAL_BYTES / $TIME_WINDOW / 1024 / 1024" | bc -l 2>/dev/null || echo "0")
            echo "Aggregate throughput: ${AGGREGATE_THROUGHPUT} MB/s"
        fi
    fi
fi

# Identify cache region
echo ""
echo "🌐 Cache Region"
echo "---------------"

CACHE_REGION=$(grep -o "https://[^/]*" "$LOG_FILE" | head -1 | sed 's/https:\/\///' || echo "Unknown")
echo "Server: $CACHE_REGION"

# Summary
echo ""
echo "📋 Quick Summary"
echo "----------------"
if [ -n "$KEYVALUE_DATA" ] && [ -n "$CAS_DATA" ]; then
    KEYVALUE_AVG_MS_SUMMARY=$(echo "$KEYVALUE_AVG * 1000" | bc -l 2>/dev/null | xargs printf "%.0f" 2>/dev/null || echo "0")
    echo "• $KEYVALUE_COUNT KeyValue operations, avg ${KEYVALUE_AVG}s (${KEYVALUE_AVG_MS_SUMMARY}ms)"
    echo "• $CAS_COUNT CAS downloads, ${TOTAL_MB} MB total"
    if [ -n "${AGGREGATE_THROUGHPUT:-}" ]; then
        echo "• ${AGGREGATE_THROUGHPUT} MB/s aggregate throughput"
    fi
    if [ -n "${AVG_THROUGHPUT:-}" ]; then
        echo "• ${AVG_THROUGHPUT} MB/s average per-operation throughput"
    fi
    echo "• Cache region: $CACHE_REGION"
elif [ -n "$KEYVALUE_DATA" ]; then
    echo "• $KEYVALUE_COUNT KeyValue operations only, avg ${KEYVALUE_AVG}s"
elif [ -n "$CAS_DATA" ]; then
    echo "• $CAS_COUNT CAS downloads only, ${TOTAL_MB} MB total"
else
    echo "• No cache operations found in log"
fi

echo ""
echo "✅ Analysis complete!"