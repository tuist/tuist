# Cache Profiles Fixture (Invalid Default)

This fixture intentionally sets a `default` cache profile that does not exist in the `profiles` map to exercise loader validation.

## Expected behavior:

```bash
tuist generate
# Error: Default cache profile 'missing' not found
```
