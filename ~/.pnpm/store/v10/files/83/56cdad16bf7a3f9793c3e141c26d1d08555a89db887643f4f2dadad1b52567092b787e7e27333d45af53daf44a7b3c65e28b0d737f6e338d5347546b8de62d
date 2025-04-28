import BaseValidationError from './base.js';

class UnevaluatedPropValidationError extends BaseValidationError {
  constructor(...args) {
    super(...args);
    this.name = 'UnevaluatedPropValidationError';
    this.options.isIdentifierLocation = true;
  }

  getError() {
    const { params } = this.options;

    return {
      message: `Property ${params.unevaluatedProperty} is not expected to be here`,
      path: this.instancePath,
    }
  }
}

export { UnevaluatedPropValidationError as default };
