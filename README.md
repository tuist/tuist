# Calendar month navigation recording

Before/after browser recording for https://github.com/tuist/tuist/pull/12986.

- Before source: `5eadecb864`, `noora/js/DatePicker/index.js`.
- After source: `01ce9bc030`, `noora/js/DatePicker/index.js`.
- Uses the real Noora controller and styles in a local component fixture.
- The refresh button explicitly replaces the calendar header controls, then invokes the hook update callback. This reproduces the DOM-replacement failure covered by the regression test; it is not a full Overview LiveView session.
- Both versions receive the same refresh and arrow clicks. Before: July/August stay unchanged. After: the left calendar moves to June and the right calendar to September.
- Captured browser frames were encoded in sequence with their capture timing. The GIF is an 8 fps version of the MP4.

This media-only branch keeps the recording out of the source-code PR diff.
