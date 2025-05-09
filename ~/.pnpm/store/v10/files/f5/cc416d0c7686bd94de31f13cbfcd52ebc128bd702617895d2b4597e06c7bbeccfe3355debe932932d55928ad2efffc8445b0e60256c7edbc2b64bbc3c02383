// @ts-nocheck
// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.
// resolves . and .. elements in a path array with directory names there
// must be no slashes, empty elements, or device names (c:\) in the array
// (so also no leading and trailing slashes - it does not distinguish
// relative and absolute paths)
function normalizeArray(parts, allowAboveRoot) {
    // if the path tries to go above the root, `up` ends up > 0
    let up = 0;
    for (let i = parts.length - 1; i >= 0; i--) {
        const last = parts[i];
        if (last === '.') {
            parts.splice(i, 1);
        }
        else if (last === '..') {
            parts.splice(i, 1);
            up++;
        }
        else if (up) {
            parts.splice(i, 1);
            up--;
        }
    }
    // if the path is allowed to go above the root, restore leading ..s
    if (allowAboveRoot) {
        for (; up--; up) {
            parts.unshift('..');
        }
    }
    return parts;
}
// Split a filename into [root, dir, basename, ext], unix version
// 'root' is just a slash, or nothing.
const splitPathRe = /^(\/?|)([\s\S]*?)((?:\.{1,2}|[^/]+?|)(\.[^./]*|))(?:[/]*)$/;
const splitPath = function (filename) {
    return splitPathRe.exec(filename).slice(1);
};
// path.normalize(path)
// posix version
function normalize(path) {
    const isPathAbsolute = isAbsolute(path), trailingSlash = substr(path, -1) === '/';
    // Normalize the path
    path = normalizeArray(filter(path.split('/'), function (p) {
        return !!p;
    }), !isPathAbsolute).join('/');
    if (!path && !isPathAbsolute) {
        path = '.';
    }
    if (path && trailingSlash) {
        path += '/';
    }
    return (isPathAbsolute ? '/' : '') + path;
}
// posix version
function isAbsolute(path) {
    return path.charAt(0) === '/';
}
// posix version
function join(...paths) {
    return normalize(filter(paths, function (p, index) {
        if (typeof p !== 'string') {
            throw new TypeError('Arguments to path.join must be strings');
        }
        return p;
    }).join('/'));
}
function dirname(path) {
    const result = splitPath(path), root = result[0];
    let dir = result[1];
    if (!root && !dir) {
        // No dirname whatsoever
        return '.';
    }
    if (dir) {
        // It has a dirname, strip trailing slash
        dir = dir.substr(0, dir.length - 1);
    }
    return root + dir;
}
function filter(xs, f) {
    if (xs.filter)
        return xs.filter(f);
    const res = [];
    for (let i = 0; i < xs.length; i++) {
        if (f(xs[i], i, xs))
            res.push(xs[i]);
    }
    return res;
}
// String.prototype.substr - negative index don't work in IE8
const substr = 'ab'.substr(-1) === 'b'
    ? function (str, start, len) {
        return str.substr(start, len);
    }
    : function (str, start, len) {
        if (start < 0)
            start = str.length + start;
        return str.substr(start, len);
    };

export { dirname, isAbsolute, join, normalize };
