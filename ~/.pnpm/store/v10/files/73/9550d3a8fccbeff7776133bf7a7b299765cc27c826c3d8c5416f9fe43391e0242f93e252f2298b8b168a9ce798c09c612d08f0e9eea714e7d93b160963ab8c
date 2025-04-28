export const nil = "";

export const pointerSegments = function* (pointer) {
  if (pointer.length > 0 && pointer[0] !== "/") {
    throw Error("Invalid JSON Pointer");
  }

  let segmentStart = 1;
  let segmentEnd = 0;

  while (segmentEnd < pointer.length) {
    const position = pointer.indexOf("/", segmentStart);
    segmentEnd = position === -1 ? pointer.length : position;
    const segment = pointer.slice(segmentStart, segmentEnd);
    segmentStart = segmentEnd + 1;

    yield unescape(segment);
  }
};

export const get = (pointer, subject = undefined) => {
  if (subject === undefined) {
    const segments = [...pointerSegments(pointer)];
    return (subject) => _get(segments, subject);
  } else {
    return _get(pointerSegments(pointer), subject);
  }
};

const _get = (segments, subject) => {
  let cursor = nil;
  for (const segment of segments) {
    subject = applySegment(subject, segment, cursor);
    cursor = append(segment, cursor);
  }

  return subject;
};

export const set = (pointer, subject = undefined, value = undefined) => {
  if (subject === undefined) {
    const segments = [...pointerSegments(pointer)];
    return (subject, value) => _set(segments.values(), subject, value);
  } else {
    return _set(pointerSegments(pointer), subject, value);
  }
};

const _set = (segments, subject, value, cursor = nil) => {
  const segment = segments.next();
  if (segment.done) {
    return value;
  }

  if (Array.isArray(subject)) {
    subject = [...subject];
  } else if (typeof subject === "object" && subject !== null) {
    subject = { ...subject };
  } else {
    applySegment(subject, segment.value, cursor);
  }
  cursor = append(segment.value, cursor);

  const computedSegment = computeSegment(subject, segment.value);
  subject[computedSegment] = _set(segments, subject[computedSegment], value, cursor);
  return subject;
};

export const assign = (pointer, subject = undefined, value = undefined) => {
  if (subject === undefined) {
    const segments = [...pointerSegments(pointer)];
    return (subject, value) => _assign(segments.values(), subject, value);
  } else {
    return _assign(pointerSegments(pointer), subject, value);
  }
};

const _assign = (segments, subject, value, cursor = nil) => {
  let lastSegment;
  let lastSubject;
  for (let segment of segments) {
    segment = computeSegment(subject, segment);
    lastSegment = segment;
    lastSubject = subject;
    subject = applySegment(subject, segment, cursor);
    cursor = append(segment, cursor);
  }

  if (lastSubject !== undefined) {
    lastSubject[lastSegment] = value;
  }
};

export const unset = (pointer, subject = undefined) => {
  if (subject === undefined) {
    const segments = [...pointerSegments(pointer)];
    return (subject) => _unset(segments.values(), subject);
  } else {
    return _unset(pointerSegments(pointer), subject);
  }
};

const _unset = (segments, subject, cursor = nil) => {
  const segment = segments.next();
  if (segment.done) {
    return;
  }

  if (Array.isArray(subject)) {
    subject = [...subject];
  } else if (typeof subject === "object" && subject !== null) {
    subject = { ...subject };
  } else {
    applySegment(subject, segment.value, cursor);
  }
  cursor = append(segment.value, cursor);

  const computedSegment = computeSegment(subject, segment.value);
  const unsetSubject = _unset(segments, subject[computedSegment], cursor);
  if (computedSegment in subject) {
    subject[computedSegment] = unsetSubject;
  }
  return subject;
};

export const remove = (pointer, subject = undefined) => {
  if (subject === undefined) {
    const segments = [...pointerSegments(pointer)];
    return (subject) => _remove(segments.values(), subject);
  } else {
    return _remove(pointerSegments(pointer), subject);
  }
};

const _remove = (segments, subject, cursor = nil) => {
  let lastSegment;
  let lastSubject;
  for (let segment of segments) {
    segment = computeSegment(subject, segment);
    lastSegment = segment;
    lastSubject = subject;
    subject = applySegment(subject, segment, cursor);
    cursor = append(segment, cursor);
  }

  if (lastSubject !== undefined) {
    delete lastSubject[lastSegment];
  }
};

export const append = (segment, pointer) => pointer + "/" + escape(segment);

const escape = (segment) => segment.toString().replace(/~/g, "~0").replace(/\//g, "~1");
const unescape = (segment) => segment.toString().replace(/~1/g, "/").replace(/~0/g, "~");
const computeSegment = (value, segment) => Array.isArray(value) && segment === "-" ? value.length : segment;

const applySegment = (value, segment, cursor = "") => {
  if (value === undefined) {
    throw TypeError(`Value at '${cursor}' is undefined and does not have property '${segment}'`);
  } else if (value === null) {
    throw TypeError(`Value at '${cursor}' is null and does not have property '${segment}'`);
  } else if (isScalar(value)) {
    throw TypeError(`Value at '${cursor}' is a ${typeof value} and does not have property '${segment}'`);
  } else {
    const computedSegment = computeSegment(value, segment);
    return value[computedSegment];
  }
};

const isScalar = (value) => value === null || typeof value !== "object";
