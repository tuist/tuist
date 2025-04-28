import type { AnyObject, Queue, Task, ValidateResult } from '../../../types/index.ts';
import type { DereferenceOptions } from '../../dereference.ts';
import type { ValidateOptions } from '../../validate.ts';
declare global {
    interface Commands {
        validate: {
            task: {
                name: 'validate';
                options?: ValidateOptions;
            };
            result: ValidateResult;
        };
    }
}
/**
 * Validate the given OpenAPI document
 */
export declare function validateCommand<T extends Task[]>(previousQueue: Queue<T>, options?: ValidateOptions): {
    dereference: (dereferenceOptions?: DereferenceOptions) => {
        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
        files: () => Promise<import("../../../types/index.ts").Filesystem>;
        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
            name: "validate";
            options?: ValidateOptions;
        }, {
            name: "dereference";
            options?: DereferenceOptions;
        }]>>;
        toJson: () => Promise<string>;
        toYaml: () => Promise<string>;
    };
    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
    files: () => Promise<import("../../../types/index.ts").Filesystem>;
    filter: (callback: (specification: AnyObject) => boolean) => {
        dereference: (dereferenceOptions?: DereferenceOptions) => {
            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
            files: () => Promise<import("../../../types/index.ts").Filesystem>;
            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                name: "validate";
                options?: ValidateOptions;
            }, {
                name: "filter";
                options?: import("../../filter.ts").FilterCallback;
            }, {
                name: "dereference";
                options?: DereferenceOptions;
            }]>>;
            toJson: () => Promise<string>;
            toYaml: () => Promise<string>;
        };
        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
        files: () => Promise<import("../../../types/index.ts").Filesystem>;
        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
            name: "validate";
            options?: ValidateOptions;
        }, {
            name: "filter";
            options?: import("../../filter.ts").FilterCallback;
        }]>>;
        toJson: () => Promise<string>;
        toYaml: () => Promise<string>;
    };
    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
        name: "validate";
        options?: ValidateOptions;
    }]>>;
    toJson: () => Promise<string>;
    toYaml: () => Promise<string>;
    upgrade: () => {
        dereference: (dereferenceOptions?: DereferenceOptions) => {
            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
            files: () => Promise<import("../../../types/index.ts").Filesystem>;
            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                name: "validate";
                options?: ValidateOptions;
            }, {
                name: "upgrade";
            }, {
                name: "dereference";
                options?: DereferenceOptions;
            }]>>;
            toJson: () => Promise<string>;
            toYaml: () => Promise<string>;
        };
        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
        files: () => Promise<import("../../../types/index.ts").Filesystem>;
        filter: (callback: (specification: AnyObject) => boolean) => {
            dereference: (dereferenceOptions?: DereferenceOptions) => {
                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                    name: "validate";
                    options?: ValidateOptions;
                }, {
                    name: "upgrade";
                }, {
                    name: "filter";
                    options?: import("../../filter.ts").FilterCallback;
                }, {
                    name: "dereference";
                    options?: DereferenceOptions;
                }]>>;
                toJson: () => Promise<string>;
                toYaml: () => Promise<string>;
            };
            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
            files: () => Promise<import("../../../types/index.ts").Filesystem>;
            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                name: "validate";
                options?: ValidateOptions;
            }, {
                name: "upgrade";
            }, {
                name: "filter";
                options?: import("../../filter.ts").FilterCallback;
            }]>>;
            toJson: () => Promise<string>;
            toYaml: () => Promise<string>;
        };
        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
            name: "validate";
            options?: ValidateOptions;
        }, {
            name: "upgrade";
        }]>>;
        toJson: () => Promise<string>;
        toYaml: () => Promise<string>;
        validate: (validateOptions?: ValidateOptions) => {
            dereference: (dereferenceOptions?: DereferenceOptions) => {
                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                    name: "validate";
                    options?: ValidateOptions;
                }, {
                    name: "upgrade";
                }, {
                    name: "validate";
                    options?: ValidateOptions;
                }, {
                    name: "dereference";
                    options?: DereferenceOptions;
                }]>>;
                toJson: () => Promise<string>;
                toYaml: () => Promise<string>;
            };
            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
            files: () => Promise<import("../../../types/index.ts").Filesystem>;
            filter: (callback: (specification: AnyObject) => boolean) => {
                dereference: (dereferenceOptions?: DereferenceOptions) => {
                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                        name: "validate";
                        options?: ValidateOptions;
                    }, {
                        name: "upgrade";
                    }, {
                        name: "validate";
                        options?: ValidateOptions;
                    }, {
                        name: "filter";
                        options?: import("../../filter.ts").FilterCallback;
                    }, {
                        name: "dereference";
                        options?: DereferenceOptions;
                    }]>>;
                    toJson: () => Promise<string>;
                    toYaml: () => Promise<string>;
                };
                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                    name: "validate";
                    options?: ValidateOptions;
                }, {
                    name: "upgrade";
                }, {
                    name: "validate";
                    options?: ValidateOptions;
                }, {
                    name: "filter";
                    options?: import("../../filter.ts").FilterCallback;
                }]>>;
                toJson: () => Promise<string>;
                toYaml: () => Promise<string>;
            };
            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                name: "validate";
                options?: ValidateOptions;
            }, {
                name: "upgrade";
            }, {
                name: "validate";
                options?: ValidateOptions;
            }]>>;
            toJson: () => Promise<string>;
            toYaml: () => Promise<string>;
            upgrade: () => {
                dereference: (dereferenceOptions?: DereferenceOptions) => {
                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                        name: "validate";
                        options?: ValidateOptions;
                    }, {
                        name: "upgrade";
                    }, {
                        name: "validate";
                        options?: ValidateOptions;
                    }, {
                        name: "upgrade";
                    }, {
                        name: "dereference";
                        options?: DereferenceOptions;
                    }]>>;
                    toJson: () => Promise<string>;
                    toYaml: () => Promise<string>;
                };
                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                filter: (callback: (specification: AnyObject) => boolean) => {
                    dereference: (dereferenceOptions?: DereferenceOptions) => {
                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                            name: "validate";
                            options?: ValidateOptions;
                        }, {
                            name: "upgrade";
                        }, {
                            name: "validate";
                            options?: ValidateOptions;
                        }, {
                            name: "upgrade";
                        }, {
                            name: "filter";
                            options?: import("../../filter.ts").FilterCallback;
                        }, {
                            name: "dereference";
                            options?: DereferenceOptions;
                        }]>>;
                        toJson: () => Promise<string>;
                        toYaml: () => Promise<string>;
                    };
                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                        name: "validate";
                        options?: ValidateOptions;
                    }, {
                        name: "upgrade";
                    }, {
                        name: "validate";
                        options?: ValidateOptions;
                    }, {
                        name: "upgrade";
                    }, {
                        name: "filter";
                        options?: import("../../filter.ts").FilterCallback;
                    }]>>;
                    toJson: () => Promise<string>;
                    toYaml: () => Promise<string>;
                };
                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                    name: "validate";
                    options?: ValidateOptions;
                }, {
                    name: "upgrade";
                }, {
                    name: "validate";
                    options?: ValidateOptions;
                }, {
                    name: "upgrade";
                }]>>;
                toJson: () => Promise<string>;
                toYaml: () => Promise<string>;
                validate: (validateOptions?: ValidateOptions) => {
                    dereference: (dereferenceOptions?: DereferenceOptions) => {
                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                            name: "validate";
                            options?: ValidateOptions;
                        }, {
                            name: "upgrade";
                        }, {
                            name: "validate";
                            options?: ValidateOptions;
                        }, {
                            name: "upgrade";
                        }, {
                            name: "validate";
                            options?: ValidateOptions;
                        }, {
                            name: "dereference";
                            options?: DereferenceOptions;
                        }]>>;
                        toJson: () => Promise<string>;
                        toYaml: () => Promise<string>;
                    };
                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                    filter: (callback: (specification: AnyObject) => boolean) => {
                        dereference: (dereferenceOptions?: DereferenceOptions) => {
                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "upgrade";
                            }, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "upgrade";
                            }, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "filter";
                                options?: import("../../filter.ts").FilterCallback;
                            }, {
                                name: "dereference";
                                options?: DereferenceOptions;
                            }]>>;
                            toJson: () => Promise<string>;
                            toYaml: () => Promise<string>;
                        };
                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                            name: "validate";
                            options?: ValidateOptions;
                        }, {
                            name: "upgrade";
                        }, {
                            name: "validate";
                            options?: ValidateOptions;
                        }, {
                            name: "upgrade";
                        }, {
                            name: "validate";
                            options?: ValidateOptions;
                        }, {
                            name: "filter";
                            options?: import("../../filter.ts").FilterCallback;
                        }]>>;
                        toJson: () => Promise<string>;
                        toYaml: () => Promise<string>;
                    };
                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                        name: "validate";
                        options?: ValidateOptions;
                    }, {
                        name: "upgrade";
                    }, {
                        name: "validate";
                        options?: ValidateOptions;
                    }, {
                        name: "upgrade";
                    }, {
                        name: "validate";
                        options?: ValidateOptions;
                    }]>>;
                    toJson: () => Promise<string>;
                    toYaml: () => Promise<string>;
                    upgrade: () => {
                        dereference: (dereferenceOptions?: DereferenceOptions) => {
                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "upgrade";
                            }, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "upgrade";
                            }, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "upgrade";
                            }, {
                                name: "dereference";
                                options?: DereferenceOptions;
                            }]>>;
                            toJson: () => Promise<string>;
                            toYaml: () => Promise<string>;
                        };
                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                        filter: (callback: (specification: AnyObject) => boolean) => {
                            dereference: (dereferenceOptions?: DereferenceOptions) => {
                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "filter";
                                    options?: import("../../filter.ts").FilterCallback;
                                }, {
                                    name: "dereference";
                                    options?: DereferenceOptions;
                                }]>>;
                                toJson: () => Promise<string>;
                                toYaml: () => Promise<string>;
                            };
                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "upgrade";
                            }, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "upgrade";
                            }, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "upgrade";
                            }, {
                                name: "filter";
                                options?: import("../../filter.ts").FilterCallback;
                            }]>>;
                            toJson: () => Promise<string>;
                            toYaml: () => Promise<string>;
                        };
                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                            name: "validate";
                            options?: ValidateOptions;
                        }, {
                            name: "upgrade";
                        }, {
                            name: "validate";
                            options?: ValidateOptions;
                        }, {
                            name: "upgrade";
                        }, {
                            name: "validate";
                            options?: ValidateOptions;
                        }, {
                            name: "upgrade";
                        }]>>;
                        toJson: () => Promise<string>;
                        toYaml: () => Promise<string>;
                        validate: (validateOptions?: ValidateOptions) => {
                            dereference: (dereferenceOptions?: DereferenceOptions) => {
                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "dereference";
                                    options?: DereferenceOptions;
                                }]>>;
                                toJson: () => Promise<string>;
                                toYaml: () => Promise<string>;
                            };
                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                            filter: (callback: (specification: AnyObject) => boolean) => {
                                dereference: (dereferenceOptions?: DereferenceOptions) => {
                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "filter";
                                        options?: import("../../filter.ts").FilterCallback;
                                    }, {
                                        name: "dereference";
                                        options?: DereferenceOptions;
                                    }]>>;
                                    toJson: () => Promise<string>;
                                    toYaml: () => Promise<string>;
                                };
                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "filter";
                                    options?: import("../../filter.ts").FilterCallback;
                                }]>>;
                                toJson: () => Promise<string>;
                                toYaml: () => Promise<string>;
                            };
                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "upgrade";
                            }, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "upgrade";
                            }, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "upgrade";
                            }, {
                                name: "validate";
                                options?: ValidateOptions;
                            }]>>;
                            toJson: () => Promise<string>;
                            toYaml: () => Promise<string>;
                            upgrade: () => {
                                dereference: (dereferenceOptions?: DereferenceOptions) => {
                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "dereference";
                                        options?: DereferenceOptions;
                                    }]>>;
                                    toJson: () => Promise<string>;
                                    toYaml: () => Promise<string>;
                                };
                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                filter: (callback: (specification: AnyObject) => boolean) => {
                                    dereference: (dereferenceOptions?: DereferenceOptions) => {
                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "filter";
                                            options?: import("../../filter.ts").FilterCallback;
                                        }, {
                                            name: "dereference";
                                            options?: DereferenceOptions;
                                        }]>>;
                                        toJson: () => Promise<string>;
                                        toYaml: () => Promise<string>;
                                    };
                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "filter";
                                        options?: import("../../filter.ts").FilterCallback;
                                    }]>>;
                                    toJson: () => Promise<string>;
                                    toYaml: () => Promise<string>;
                                };
                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }]>>;
                                toJson: () => Promise<string>;
                                toYaml: () => Promise<string>;
                                validate: (validateOptions?: ValidateOptions) => {
                                    dereference: (dereferenceOptions?: DereferenceOptions) => {
                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "dereference";
                                            options?: DereferenceOptions;
                                        }]>>;
                                        toJson: () => Promise<string>;
                                        toYaml: () => Promise<string>;
                                    };
                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                    filter: (callback: (specification: AnyObject) => boolean) => {
                                        dereference: (dereferenceOptions?: DereferenceOptions) => {
                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "filter";
                                                options?: import("../../filter.ts").FilterCallback;
                                            }, {
                                                name: "dereference";
                                                options?: DereferenceOptions;
                                            }]>>;
                                            toJson: () => Promise<string>;
                                            toYaml: () => Promise<string>;
                                        };
                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "filter";
                                            options?: import("../../filter.ts").FilterCallback;
                                        }]>>;
                                        toJson: () => Promise<string>;
                                        toYaml: () => Promise<string>;
                                    };
                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }]>>;
                                    toJson: () => Promise<string>;
                                    toYaml: () => Promise<string>;
                                    upgrade: () => {
                                        dereference: (dereferenceOptions?: DereferenceOptions) => {
                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "dereference";
                                                options?: DereferenceOptions;
                                            }]>>;
                                            toJson: () => Promise<string>;
                                            toYaml: () => Promise<string>;
                                        };
                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                        filter: (callback: (specification: AnyObject) => boolean) => {
                                            dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "filter";
                                                    options?: import("../../filter.ts").FilterCallback;
                                                }, {
                                                    name: "dereference";
                                                    options?: DereferenceOptions;
                                                }]>>;
                                                toJson: () => Promise<string>;
                                                toYaml: () => Promise<string>;
                                            };
                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "filter";
                                                options?: import("../../filter.ts").FilterCallback;
                                            }]>>;
                                            toJson: () => Promise<string>;
                                            toYaml: () => Promise<string>;
                                        };
                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }]>>;
                                        toJson: () => Promise<string>;
                                        toYaml: () => Promise<string>;
                                        validate: (validateOptions?: ValidateOptions) => {
                                            dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "dereference";
                                                    options?: DereferenceOptions;
                                                }]>>;
                                                toJson: () => Promise<string>;
                                                toYaml: () => Promise<string>;
                                            };
                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                            filter: (callback: (specification: AnyObject) => boolean) => {
                                                dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "filter";
                                                        options?: import("../../filter.ts").FilterCallback;
                                                    }, {
                                                        name: "dereference";
                                                        options?: DereferenceOptions;
                                                    }]>>;
                                                    toJson: () => Promise<string>;
                                                    toYaml: () => Promise<string>;
                                                };
                                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "filter";
                                                    options?: import("../../filter.ts").FilterCallback;
                                                }]>>;
                                                toJson: () => Promise<string>;
                                                toYaml: () => Promise<string>;
                                            };
                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }]>>;
                                            toJson: () => Promise<string>;
                                            toYaml: () => Promise<string>;
                                            upgrade: () => {
                                                dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "dereference";
                                                        options?: DereferenceOptions;
                                                    }]>>;
                                                    toJson: () => Promise<string>;
                                                    toYaml: () => Promise<string>;
                                                };
                                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                filter: (callback: (specification: AnyObject) => boolean) => {
                                                    dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "filter";
                                                            options?: import("../../filter.ts").FilterCallback;
                                                        }, {
                                                            name: "dereference";
                                                            options?: DereferenceOptions;
                                                        }]>>;
                                                        toJson: () => Promise<string>;
                                                        toYaml: () => Promise<string>;
                                                    };
                                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "filter";
                                                        options?: import("../../filter.ts").FilterCallback;
                                                    }]>>;
                                                    toJson: () => Promise<string>;
                                                    toYaml: () => Promise<string>;
                                                };
                                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }]>>;
                                                toJson: () => Promise<string>;
                                                toYaml: () => Promise<string>;
                                                validate: (validateOptions?: ValidateOptions) => {
                                                    dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "dereference";
                                                            options?: DereferenceOptions;
                                                        }]>>;
                                                        toJson: () => Promise<string>;
                                                        toYaml: () => Promise<string>;
                                                    };
                                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                    filter: (callback: (specification: AnyObject) => boolean) => {
                                                        dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "filter";
                                                                options?: import("../../filter.ts").FilterCallback;
                                                            }, {
                                                                name: "dereference";
                                                                options?: DereferenceOptions;
                                                            }]>>;
                                                            toJson: () => Promise<string>;
                                                            toYaml: () => Promise<string>;
                                                        };
                                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "filter";
                                                            options?: import("../../filter.ts").FilterCallback;
                                                        }]>>;
                                                        toJson: () => Promise<string>;
                                                        toYaml: () => Promise<string>;
                                                    };
                                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }]>>;
                                                    toJson: () => Promise<string>;
                                                    toYaml: () => Promise<string>;
                                                    upgrade: () => {
                                                        dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "dereference";
                                                                options?: DereferenceOptions;
                                                            }]>>;
                                                            toJson: () => Promise<string>;
                                                            toYaml: () => Promise<string>;
                                                        };
                                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                        filter: (callback: (specification: AnyObject) => boolean) => {
                                                            dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "filter";
                                                                    options?: import("../../filter.ts").FilterCallback;
                                                                }, {
                                                                    name: "dereference";
                                                                    options?: DereferenceOptions;
                                                                }]>>;
                                                                toJson: () => Promise<string>;
                                                                toYaml: () => Promise<string>;
                                                            };
                                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "filter";
                                                                options?: import("../../filter.ts").FilterCallback;
                                                            }]>>;
                                                            toJson: () => Promise<string>;
                                                            toYaml: () => Promise<string>;
                                                        };
                                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }]>>;
                                                        toJson: () => Promise<string>;
                                                        toYaml: () => Promise<string>;
                                                        validate: (validateOptions?: ValidateOptions) => {
                                                            dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "dereference";
                                                                    options?: DereferenceOptions;
                                                                }]>>;
                                                                toJson: () => Promise<string>;
                                                                toYaml: () => Promise<string>;
                                                            };
                                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                            filter: (callback: (specification: AnyObject) => boolean) => {
                                                                dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "filter";
                                                                        options?: import("../../filter.ts").FilterCallback;
                                                                    }, {
                                                                        name: "dereference";
                                                                        options?: DereferenceOptions;
                                                                    }]>>;
                                                                    toJson: () => Promise<string>;
                                                                    toYaml: () => Promise<string>;
                                                                };
                                                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "filter";
                                                                    options?: import("../../filter.ts").FilterCallback;
                                                                }]>>;
                                                                toJson: () => Promise<string>;
                                                                toYaml: () => Promise<string>;
                                                            };
                                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }]>>;
                                                            toJson: () => Promise<string>;
                                                            toYaml: () => Promise<string>;
                                                            upgrade: () => {
                                                                dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "dereference";
                                                                        options?: DereferenceOptions;
                                                                    }]>>;
                                                                    toJson: () => Promise<string>;
                                                                    toYaml: () => Promise<string>;
                                                                };
                                                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                filter: (callback: (specification: AnyObject) => boolean) => {
                                                                    dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "filter";
                                                                            options?: import("../../filter.ts").FilterCallback;
                                                                        }, {
                                                                            name: "dereference";
                                                                            options?: DereferenceOptions;
                                                                        }]>>;
                                                                        toJson: () => Promise<string>;
                                                                        toYaml: () => Promise<string>;
                                                                    };
                                                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "filter";
                                                                        options?: import("../../filter.ts").FilterCallback;
                                                                    }]>>;
                                                                    toJson: () => Promise<string>;
                                                                    toYaml: () => Promise<string>;
                                                                };
                                                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }]>>;
                                                                toJson: () => Promise<string>;
                                                                toYaml: () => Promise<string>;
                                                                validate: (validateOptions?: ValidateOptions) => {
                                                                    dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "dereference";
                                                                            options?: DereferenceOptions;
                                                                        }]>>;
                                                                        toJson: () => Promise<string>;
                                                                        toYaml: () => Promise<string>;
                                                                    };
                                                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                    filter: (callback: (specification: AnyObject) => boolean) => {
                                                                        dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "filter";
                                                                                options?: import("../../filter.ts").FilterCallback;
                                                                            }, {
                                                                                name: "dereference";
                                                                                options?: DereferenceOptions;
                                                                            }]>>;
                                                                            toJson: () => Promise<string>;
                                                                            toYaml: () => Promise<string>;
                                                                        };
                                                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "filter";
                                                                            options?: import("../../filter.ts").FilterCallback;
                                                                        }]>>;
                                                                        toJson: () => Promise<string>;
                                                                        toYaml: () => Promise<string>;
                                                                    };
                                                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }]>>;
                                                                    toJson: () => Promise<string>;
                                                                    toYaml: () => Promise<string>;
                                                                    upgrade: () => {
                                                                        dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "dereference";
                                                                                options?: DereferenceOptions;
                                                                            }]>>;
                                                                            toJson: () => Promise<string>;
                                                                            toYaml: () => Promise<string>;
                                                                        };
                                                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                        filter: (callback: (specification: AnyObject) => boolean) => {
                                                                            dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "filter";
                                                                                    options?: import("../../filter.ts").FilterCallback;
                                                                                }, {
                                                                                    name: "dereference";
                                                                                    options?: DereferenceOptions;
                                                                                }]>>;
                                                                                toJson: () => Promise<string>;
                                                                                toYaml: () => Promise<string>;
                                                                            };
                                                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "filter";
                                                                                options?: import("../../filter.ts").FilterCallback;
                                                                            }]>>;
                                                                            toJson: () => Promise<string>;
                                                                            toYaml: () => Promise<string>;
                                                                        };
                                                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }]>>;
                                                                        toJson: () => Promise<string>;
                                                                        toYaml: () => Promise<string>;
                                                                        validate: (validateOptions?: ValidateOptions) => {
                                                                            dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "dereference";
                                                                                    options?: DereferenceOptions;
                                                                                }]>>;
                                                                                toJson: () => Promise<string>;
                                                                                toYaml: () => Promise<string>;
                                                                            };
                                                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                            filter: (callback: (specification: AnyObject) => boolean) => {
                                                                                dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "filter";
                                                                                        options?: import("../../filter.ts").FilterCallback;
                                                                                    }, {
                                                                                        name: "dereference";
                                                                                        options?: DereferenceOptions;
                                                                                    }]>>;
                                                                                    toJson: () => Promise<string>;
                                                                                    toYaml: () => Promise<string>;
                                                                                };
                                                                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "filter";
                                                                                    options?: import("../../filter.ts").FilterCallback;
                                                                                }]>>;
                                                                                toJson: () => Promise<string>;
                                                                                toYaml: () => Promise<string>;
                                                                            };
                                                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }]>>;
                                                                            toJson: () => Promise<string>;
                                                                            toYaml: () => Promise<string>;
                                                                            upgrade: () => {
                                                                                dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "dereference";
                                                                                        options?: DereferenceOptions;
                                                                                    }]>>;
                                                                                    toJson: () => Promise<string>;
                                                                                    toYaml: () => Promise<string>;
                                                                                };
                                                                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                filter: (callback: (specification: AnyObject) => boolean) => {
                                                                                    dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "filter";
                                                                                            options?: import("../../filter.ts").FilterCallback;
                                                                                        }, {
                                                                                            name: "dereference";
                                                                                            options?: DereferenceOptions;
                                                                                        }]>>;
                                                                                        toJson: () => Promise<string>;
                                                                                        toYaml: () => Promise<string>;
                                                                                    };
                                                                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "filter";
                                                                                        options?: import("../../filter.ts").FilterCallback;
                                                                                    }]>>;
                                                                                    toJson: () => Promise<string>;
                                                                                    toYaml: () => Promise<string>;
                                                                                };
                                                                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }]>>;
                                                                                toJson: () => Promise<string>;
                                                                                toYaml: () => Promise<string>;
                                                                                validate: (validateOptions?: ValidateOptions) => {
                                                                                    dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "dereference";
                                                                                            options?: DereferenceOptions;
                                                                                        }]>>;
                                                                                        toJson: () => Promise<string>;
                                                                                        toYaml: () => Promise<string>;
                                                                                    };
                                                                                    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                    files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                    filter: (callback: (specification: AnyObject) => boolean) => {
                                                                                        dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "filter";
                                                                                                options?: import("../../filter.ts").FilterCallback;
                                                                                            }, {
                                                                                                name: "dereference";
                                                                                                options?: DereferenceOptions;
                                                                                            }]>>;
                                                                                            toJson: () => Promise<string>;
                                                                                            toYaml: () => Promise<string>;
                                                                                        };
                                                                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "filter";
                                                                                            options?: import("../../filter.ts").FilterCallback;
                                                                                        }]>>;
                                                                                        toJson: () => Promise<string>;
                                                                                        toYaml: () => Promise<string>;
                                                                                    };
                                                                                    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }]>>;
                                                                                    toJson: () => Promise<string>;
                                                                                    toYaml: () => Promise<string>;
                                                                                    upgrade: () => {
                                                                                        dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "dereference";
                                                                                                options?: DereferenceOptions;
                                                                                            }]>>;
                                                                                            toJson: () => Promise<string>;
                                                                                            toYaml: () => Promise<string>;
                                                                                        };
                                                                                        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                        files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                        filter: (callback: (specification: AnyObject) => boolean) => {
                                                                                            dereference: (dereferenceOptions?: DereferenceOptions) => {
                                                                                                details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                                files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                                get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "filter";
                                                                                                    options?: import("../../filter.ts").FilterCallback;
                                                                                                }, {
                                                                                                    name: "dereference";
                                                                                                    options?: DereferenceOptions;
                                                                                                }]>>;
                                                                                                toJson: () => Promise<string>;
                                                                                                toYaml: () => Promise<string>;
                                                                                            };
                                                                                            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
                                                                                            files: () => Promise<import("../../../types/index.ts").Filesystem>;
                                                                                            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "filter";
                                                                                                options?: import("../../filter.ts").FilterCallback;
                                                                                            }]>>;
                                                                                            toJson: () => Promise<string>;
                                                                                            toYaml: () => Promise<string>;
                                                                                        };
                                                                                        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }]>>;
                                                                                        toJson: () => Promise<string>;
                                                                                        toYaml: () => Promise<string>;
                                                                                        validate: (validateOptions?: ValidateOptions) => any;
                                                                                    };
                                                                                };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            };
        };
    };
};
//# sourceMappingURL=validateCommand.d.ts.map