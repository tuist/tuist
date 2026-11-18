### How many times each test reruns {#stress-reruns}

It depends on how long the test case took on the first pass:

| First pass | Reruns |
| --- | --- |
| Up to 5s | 10 |
| Up to 10s | 5 |
| Up to 30s | 3 |
| Up to 5min | 2 |
| Over 5min | Not rerun |

The pass stops at 200 test cases or 10 minutes, whichever comes first, and says which limit it hit.
