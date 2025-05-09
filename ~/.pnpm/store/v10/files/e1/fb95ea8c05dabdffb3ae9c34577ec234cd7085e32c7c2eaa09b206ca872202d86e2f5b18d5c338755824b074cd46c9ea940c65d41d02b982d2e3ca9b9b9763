import { requestMethods } from '../entities/spec/requests.js';

/**
 * HTTP methods in a specific order
 * Do not change the order
 */
const REQUEST_METHODS = {
    get: {
        short: 'GET',
        color: 'text-blue',
        backgroundColor: 'bg-blue',
    },
    post: {
        short: 'POST',
        color: 'text-green',
        backgroundColor: 'bg-green',
    },
    put: {
        short: 'PUT',
        color: 'text-orange',
        backgroundColor: 'bg-orange',
    },
    patch: {
        short: 'PATCH',
        color: 'text-yellow',
        backgroundColor: 'bg-yellow',
    },
    delete: {
        short: 'DEL',
        color: 'text-red',
        backgroundColor: 'bg-red',
    },
    options: {
        short: 'OPTS',
        color: 'text-purple',
        backgroundColor: 'bg-purple',
    },
    head: {
        short: 'HEAD',
        color: 'text-scalar-c-2',
        backgroundColor: 'bg-c-2',
    },
    connect: {
        short: 'CONN',
        color: 'text-c-2',
        backgroundColor: 'bg-c-2',
    },
    trace: {
        short: 'TRACE',
        color: 'text-c-2',
        backgroundColor: 'bg-c-2',
    },
};
/** HTTP Methods which can have a body */
const BODY_METHODS = ['post', 'put', 'patch', 'delete'];
/** Makes a check to see if this method CAN have a body */
const canMethodHaveBody = (method) => BODY_METHODS.includes(method);
/**
 * Accepts an HTTP Method name and returns some properties for the tag
 */
const getHttpMethodInfo = (methodName) => {
    const normalizedMethod = methodName.trim().toLowerCase();
    return (REQUEST_METHODS[normalizedMethod] ?? {
        short: normalizedMethod,
        color: 'text-c-2',
        backgroundColor: 'bg-c-2',
    });
};
/** Type guard which takes in a string and returns true if it is in fact an HTTPMethod */
const isHttpMethod = (method) => method ? requestMethods.includes(method) : false;

export { REQUEST_METHODS, canMethodHaveBody, getHttpMethodInfo, isHttpMethod };
