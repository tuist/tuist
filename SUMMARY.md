# Tuist Cache Performance Analysis Summary

**Date**: October 31, 2025  
**Analysis**: Multi-environment cache performance comparison  
**Environments Tested**: Staging, Production, Central EU

## Executive Summary

Performance analysis of Tuist's cache infrastructure across three environments shows **Central EU region delivers the best overall performance** with 28.5 MB/s aggregate throughput, while **Production offers the lowest individual latency** at 60-100ms typical response times.

## Environment Details

| Environment | Server | Region | Purpose |
|-------------|--------|--------|---------|
| **Staging** | `staging.tuist.dev` | US | Development/Testing |
| **Production** | `tuist.dev` | US | Production |
| **Central** | `cache-eu-central-staging.tuist.dev` | EU Central | Regional Cache |

## Performance Results

### CAS Download Throughput

| Environment | Time Window | Total Data | Aggregate Throughput | Performance |
|-------------|-------------|------------|---------------------|-------------|
| **Central** | 1.64s | 46.66 MB | **28.5 MB/s** | 🥇 Best |
| **Production** | 1.68s | 46.66 MB | **27.8 MB/s** | 🥈 +4% vs Staging |
| **Staging** | 1.75s | 46.66 MB | **26.7 MB/s** | 🥉 Baseline |

**Key Insights:**
- All environments downloaded identical workload (62 cache artifacts)
- Central EU shows **7% better throughput** than staging
- Parallel downloads effectively utilize available bandwidth

### KeyValue.getValue Latency

| Environment | Typical Latency | Best Case | Consistency | Performance |
|-------------|----------------|-----------|-------------|-------------|
| **Production** | 60-100ms | 58ms | Variable | 🥇 ~50% faster |
| **Central** | 65-90ms | 65ms | Excellent | 🥈 ~45% faster |
| **Staging** | 120-180ms | 109ms | Good | 🥉 Baseline |

**Key Insights:**
- Production delivers **fastest individual responses**
- Central shows **most consistent performance** (no outliers)
- Both production environments significantly outperform staging

### Individual Download Performance

**Central EU** - Exceptional small file performance:
- Many downloads: 0.009-0.018s (extremely fast)
- Larger files: 0.2-1.5s (consistent)

**Production** - Fast but variable:
- Small files: 0.135-0.220s 
- Large files: 0.3-0.8s
- 2 outliers: 1.2s, 1.9s (likely cold cache)

**Staging** - Uniform but slower:
- Consistent range: 0.119-0.994s
- Predictable performance

## Recommendations

1. **🎯 Primary**: **Central EU region** for best overall cache performance
2. **🔄 Secondary**: **Production** for lowest latency critical paths
3. **🔧 Optimization**: Investigate staging infrastructure for performance gaps

## Data Collection Guide

### For Future Analysis

When gathering cache performance data for analysis:

#### 1. Log Collection (macOS Console)

```bash
# Open Console app and filter logs
# Filter: subsystem == "dev.tuist.cache"
# Time range: During cache operations
# Export logs to text file
```

#### 2. Key Metrics to Extract

**CAS Download Performance:**
```bash
# Extract CAS completion messages
grep -i "CAS.load completed successfully" logs.txt

# Calculate aggregate throughput
grep -i "CAS.load completed successfully" logs.txt | awk '{
    gsub(/.*loaded /, "", $0)
    gsub(/ bytes.*/, "", $0)
    total += $1
} END {
    print "Total bytes:", total
    print "Total MB:", total/1024/1024
}'
```

**KeyValue Latency:**
```bash
# Extract KeyValue completion messages
grep -i "KeyValue.getValue completed successfully" logs.txt

# Analyze latency patterns
grep -i "KeyValue.getValue completed successfully" logs.txt | \
  awk '{print $NF}' | sort -n
```

#### 3. Time Window Analysis

```bash
# Get first and last timestamps
grep -i "CAS.load completed successfully" logs.txt | \
  head -1 | awk '{print $1, $2}'
grep -i "CAS.load completed successfully" logs.txt | \
  tail -1 | awk '{print $1, $2}'
```

#### 4. Environment Identification

Look for these patterns in logs:
- **Staging**: `staging.tuist.dev`
- **Production**: `tuist.dev`
- **Central EU**: `cache-eu-central-staging.tuist.dev`

### Analysis Commands

```bash
# Count total operations
grep -c "CAS.load completed successfully" logs.txt

# Extract individual download times
grep "CAS.load completed successfully" logs.txt | \
  sed 's/.*in \([0-9.]*\)s.*/\1/' | sort -n

# Calculate statistics
grep "CAS.load completed successfully" logs.txt | \
  awk '{gsub(/.*in /, ""); gsub(/s.*/, ""); print $1}' | \
  awk '{sum+=$1; if($1>max) max=$1; if(min=="" || $1<min) min=$1} 
       END {print "Avg:", sum/NR, "Min:", min, "Max:", max}'
```

## Technical Notes

- **Workload**: Identical across all environments (62 cache artifacts, 46.66 MB total)
- **Measurement**: End-to-end download times including network and processing
- **Concurrency**: High parallelization across multiple threads
- **Cache Strategy**: Content-addressable storage with key-value metadata lookup

## Future Monitoring

For ongoing performance monitoring, focus on:

1. **Aggregate throughput trends** over time
2. **95th percentile latency** for user experience
3. **Cache hit ratios** across regions
4. **Geographic performance variations**

This analysis provides a baseline for cache performance optimization and regional deployment decisions.