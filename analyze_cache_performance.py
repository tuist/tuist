#!/usr/bin/env python3

# KeyValue latencies (in seconds)
keyvalue_latencies = [
    0.149, 0.149, 0.151, 0.157, 0.157, 0.156, 0.155, 0.151, 0.153, 0.162, 
    0.163, 0.043, 0.071, 0.069, 0.070, 0.083, 0.076, 0.071, 0.076, 0.075, 
    0.073, 0.102, 0.098, 0.088, 0.086, 0.086, 0.103, 0.107, 0.106, 0.105, 
    0.079, 0.058, 0.060, 0.057, 0.058, 0.059, 0.067, 0.072, 0.073, 0.067, 
    0.082, 0.079, 0.101, 0.096, 0.084, 0.084, 0.095, 0.075, 0.091, 0.087, 
    0.084, 0.106, 0.100, 0.074, 0.074, 0.088, 0.088, 0.081, 0.071
]

# CAS operations (time_in_seconds, bytes)
cas_operations = [
    (0.030, 17720), (0.030, 249), (0.030, 8720), (0.006, 412), (0.007, 10166),
    (0.008, 149), (0.008, 3468), (0.052, 40224), (0.079, 32672), (0.097, 464496),
    (0.100, 66108), (0.100, 35360), (0.089, 42808), (0.139, 267136), (0.141, 285800),
    (0.140, 498496), (0.145, 494208), (0.150, 584384), (0.106, 34728), (0.108, 43096),
    (0.106, 41640), (0.109, 261240), (0.108, 29600), (0.151, 620528), (0.079, 38120),
    (0.082, 245944), (0.209, 1993688), (0.082, 984328), (0.055, 34096), (0.053, 37008),
    (0.056, 34072), (0.081, 139272), (0.079, 278328), (0.101, 893856), (0.106, 58432),
    (0.108, 795088), (0.001, 22712), (0.115, 1216728), (0.002, 148), (0.002, 12840),
    (0.095, 49376), (0.185, 3012688), (0.074, 66496), (0.091, 197408), (0.093, 34560),
    (0.076, 63288), (0.173, 1291312), (0.109, 159120), (0.082, 314072), (0.088, 30952),
    (0.144, 904400), (0.125, 825408), (0.074, 34288), (0.094, 462008), (0.104, 155448),
    (0.108, 206920), (0.075, 34496), (0.110, 80688), (0.115, 119320), (0.084, 30560),
    (0.116, 368792), (0.195, 2066168), (0.116, 679416), (0.159, 1065688), (0.322, 3995544),
    (0.324, 5458080), (0.484, 10277512), (0.204, 4009256)
]

print("=== CACHE PERFORMANCE ANALYSIS - Central EU Region ===\n")

# KeyValue Statistics
print("KeyValue Operations:")
print(f"  Total operations: {len(keyvalue_latencies)}")
print(f"  Average latency: {sum(keyvalue_latencies)/len(keyvalue_latencies)*1000:.1f}ms")
print(f"  Min latency: {min(keyvalue_latencies)*1000:.1f}ms")
print(f"  Max latency: {max(keyvalue_latencies)*1000:.1f}ms")
print()

# CAS Statistics
total_bytes = sum(op[1] for op in cas_operations)
total_time = sum(op[0] for op in cas_operations)

print("CAS Operations:")
print(f"  Total operations: {len(cas_operations)}")
print(f"  Total bytes downloaded: {total_bytes:,} bytes ({total_bytes/1024/1024:.1f} MB)")
print(f"  Total download time: {total_time:.3f}s")
print(f"  Average throughput: {(total_bytes/1024/1024)/total_time:.1f} MB/s")
print()

# Individual CAS operation analysis
throughputs = []
for time_s, bytes_val in cas_operations:
    if time_s > 0:
        throughput = (bytes_val / 1024 / 1024) / time_s
        throughputs.append(throughput)

print("CAS Throughput Distribution:")
print(f"  Average throughput per operation: {sum(throughputs)/len(throughputs):.1f} MB/s")
print(f"  Min throughput: {min(throughputs):.1f} MB/s")
print(f"  Max throughput: {max(throughputs):.1f} MB/s")
print()

# Size distribution
sizes_mb = [bytes_val/1024/1024 for _, bytes_val in cas_operations]
print("CAS File Size Distribution:")
print(f"  Average file size: {sum(sizes_mb)/len(sizes_mb):.2f} MB")
print(f"  Min file size: {min(sizes_mb):.2f} MB")
print(f"  Max file size: {max(sizes_mb):.2f} MB")
print()

print("Time Window: 14:06:33 - 14:06:34 (approximately 1 second)")
print()

print("=== COMPARISON TO PREVIOUS ANALYSIS ===")
print("Previous summary showed Central EU:")
print("  - 28.5 MB/s throughput")
print("  - 65-90ms KeyValue latency")
print()
print("Current detailed analysis shows:")
print(f"  - {(total_bytes/1024/1024)/total_time:.1f} MB/s aggregate throughput")
print(f"  - {sum(keyvalue_latencies)/len(keyvalue_latencies)*1000:.1f}ms average KeyValue latency")
print()