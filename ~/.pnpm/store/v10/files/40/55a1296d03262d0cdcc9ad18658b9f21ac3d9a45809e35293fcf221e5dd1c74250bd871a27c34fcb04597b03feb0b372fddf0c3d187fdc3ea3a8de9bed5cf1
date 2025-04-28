import type { AnyApiDefinitionFormat, AnyObject, LoadResult, Queue, Task } from '../../../types/index.ts';
import type { DereferenceOptions } from '../../dereference.ts';
import type { LoadOptions } from '../../load/load.ts';
import type { ValidateOptions } from '../../validate.ts';
declare global {
    interface Commands {
        load: {
            task: {
                name: 'load';
                options?: LoadOptions;
            };
            result: LoadResult;
        };
    }
}
/**
 * Pass any OpenAPI document
 */
export declare function loadCommand<T extends Task[]>(previousQueue: Queue<T>, input: AnyApiDefinitionFormat, options?: LoadOptions): {
    dereference: (dereferenceOptions?: DereferenceOptions) => {
        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
        files: () => Promise<import("../../../types/index.ts").Filesystem>;
        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
            readonly name: "load";
            readonly options: {
                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                readonly filename?: string;
                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                throwOnError: boolean;
            };
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
                readonly name: "load";
                readonly options: {
                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                    readonly filename?: string;
                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                    throwOnError: boolean;
                };
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
            readonly name: "load";
            readonly options: {
                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                readonly filename?: string;
                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                throwOnError: boolean;
            };
        }, {
            name: "filter";
            options?: import("../../filter.ts").FilterCallback;
        }]>>;
        toJson: () => Promise<string>;
        toYaml: () => Promise<string>;
    };
    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
        readonly name: "load";
        readonly options: {
            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
            readonly filename?: string;
            readonly filesystem?: import("../../../types/index.ts").Filesystem;
            throwOnError: boolean;
        };
    }]>>;
    upgrade: () => {
        dereference: (dereferenceOptions?: DereferenceOptions) => {
            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
            files: () => Promise<import("../../../types/index.ts").Filesystem>;
            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                readonly name: "load";
                readonly options: {
                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                    readonly filename?: string;
                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                    throwOnError: boolean;
                };
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
                    readonly name: "load";
                    readonly options: {
                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                        readonly filename?: string;
                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                        throwOnError: boolean;
                    };
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
                readonly name: "load";
                readonly options: {
                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                    readonly filename?: string;
                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                    throwOnError: boolean;
                };
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
            readonly name: "load";
            readonly options: {
                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                readonly filename?: string;
                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                throwOnError: boolean;
            };
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
                    readonly name: "load";
                    readonly options: {
                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                        readonly filename?: string;
                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                        throwOnError: boolean;
                    };
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
                        readonly name: "load";
                        readonly options: {
                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                            readonly filename?: string;
                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                            throwOnError: boolean;
                        };
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
                    readonly name: "load";
                    readonly options: {
                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                        readonly filename?: string;
                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                        throwOnError: boolean;
                    };
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
                readonly name: "load";
                readonly options: {
                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                    readonly filename?: string;
                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                    throwOnError: boolean;
                };
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
                        readonly name: "load";
                        readonly options: {
                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                            readonly filename?: string;
                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                            throwOnError: boolean;
                        };
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
                            readonly name: "load";
                            readonly options: {
                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                readonly filename?: string;
                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                throwOnError: boolean;
                            };
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
                        readonly name: "load";
                        readonly options: {
                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                            readonly filename?: string;
                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                            throwOnError: boolean;
                        };
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
                    readonly name: "load";
                    readonly options: {
                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                        readonly filename?: string;
                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                        throwOnError: boolean;
                    };
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
                            readonly name: "load";
                            readonly options: {
                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                readonly filename?: string;
                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                throwOnError: boolean;
                            };
                        }, {
                            name: "upgrade";
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
                                readonly name: "load";
                                readonly options: {
                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                    readonly filename?: string;
                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                    throwOnError: boolean;
                                };
                            }, {
                                name: "upgrade";
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
                            readonly name: "load";
                            readonly options: {
                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                readonly filename?: string;
                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                throwOnError: boolean;
                            };
                        }, {
                            name: "upgrade";
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
                        readonly name: "load";
                        readonly options: {
                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                            readonly filename?: string;
                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                            throwOnError: boolean;
                        };
                    }, {
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
                                readonly name: "load";
                                readonly options: {
                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                    readonly filename?: string;
                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                    throwOnError: boolean;
                                };
                            }, {
                                name: "upgrade";
                            }, {
                                name: "validate";
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
                                    readonly name: "load";
                                    readonly options: {
                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                        readonly filename?: string;
                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                        throwOnError: boolean;
                                    };
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
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
                                readonly name: "load";
                                readonly options: {
                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                    readonly filename?: string;
                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                    throwOnError: boolean;
                                };
                            }, {
                                name: "upgrade";
                            }, {
                                name: "validate";
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
                            readonly name: "load";
                            readonly options: {
                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                readonly filename?: string;
                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                throwOnError: boolean;
                            };
                        }, {
                            name: "upgrade";
                        }, {
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
                                    readonly name: "load";
                                    readonly options: {
                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                        readonly filename?: string;
                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                        throwOnError: boolean;
                                    };
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
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
                                        readonly name: "load";
                                        readonly options: {
                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                            readonly filename?: string;
                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                            throwOnError: boolean;
                                        };
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
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
                                    readonly name: "load";
                                    readonly options: {
                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                        readonly filename?: string;
                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                        throwOnError: boolean;
                                    };
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
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
                                readonly name: "load";
                                readonly options: {
                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                    readonly filename?: string;
                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                    throwOnError: boolean;
                                };
                            }, {
                                name: "upgrade";
                            }, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
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
                                        readonly name: "load";
                                        readonly options: {
                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                            readonly filename?: string;
                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                            throwOnError: boolean;
                                        };
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
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
                                            readonly name: "load";
                                            readonly options: {
                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                readonly filename?: string;
                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                throwOnError: boolean;
                                            };
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
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
                                        readonly name: "load";
                                        readonly options: {
                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                            readonly filename?: string;
                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                            throwOnError: boolean;
                                        };
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
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
                                    readonly name: "load";
                                    readonly options: {
                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                        readonly filename?: string;
                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                        throwOnError: boolean;
                                    };
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
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
                                            readonly name: "load";
                                            readonly options: {
                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                readonly filename?: string;
                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                throwOnError: boolean;
                                            };
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
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
                                                readonly name: "load";
                                                readonly options: {
                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                    readonly filename?: string;
                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                    throwOnError: boolean;
                                                };
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
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
                                            readonly name: "load";
                                            readonly options: {
                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                readonly filename?: string;
                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                throwOnError: boolean;
                                            };
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
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
                                        readonly name: "load";
                                        readonly options: {
                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                            readonly filename?: string;
                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                            throwOnError: boolean;
                                        };
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
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
                                                readonly name: "load";
                                                readonly options: {
                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                    readonly filename?: string;
                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                    throwOnError: boolean;
                                                };
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
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
                                                    readonly name: "load";
                                                    readonly options: {
                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                        readonly filename?: string;
                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                        throwOnError: boolean;
                                                    };
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
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
                                                readonly name: "load";
                                                readonly options: {
                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                    readonly filename?: string;
                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                    throwOnError: boolean;
                                                };
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
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
                                            readonly name: "load";
                                            readonly options: {
                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                readonly filename?: string;
                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                throwOnError: boolean;
                                            };
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
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
                                                    readonly name: "load";
                                                    readonly options: {
                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                        readonly filename?: string;
                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                        throwOnError: boolean;
                                                    };
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
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
                                                        readonly name: "load";
                                                        readonly options: {
                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                            readonly filename?: string;
                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                            throwOnError: boolean;
                                                        };
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
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
                                                    readonly name: "load";
                                                    readonly options: {
                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                        readonly filename?: string;
                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                        throwOnError: boolean;
                                                    };
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
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
                                                readonly name: "load";
                                                readonly options: {
                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                    readonly filename?: string;
                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                    throwOnError: boolean;
                                                };
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
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
                                                        readonly name: "load";
                                                        readonly options: {
                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                            readonly filename?: string;
                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                            throwOnError: boolean;
                                                        };
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
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
                                                            readonly name: "load";
                                                            readonly options: {
                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                readonly filename?: string;
                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                throwOnError: boolean;
                                                            };
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
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
                                                        readonly name: "load";
                                                        readonly options: {
                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                            readonly filename?: string;
                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                            throwOnError: boolean;
                                                        };
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
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
                                                    readonly name: "load";
                                                    readonly options: {
                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                        readonly filename?: string;
                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                        throwOnError: boolean;
                                                    };
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
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
                                                            readonly name: "load";
                                                            readonly options: {
                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                readonly filename?: string;
                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                throwOnError: boolean;
                                                            };
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
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
                                                                readonly name: "load";
                                                                readonly options: {
                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                    readonly filename?: string;
                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                    throwOnError: boolean;
                                                                };
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
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
                                                            readonly name: "load";
                                                            readonly options: {
                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                readonly filename?: string;
                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                throwOnError: boolean;
                                                            };
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
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
                                                        readonly name: "load";
                                                        readonly options: {
                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                            readonly filename?: string;
                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                            throwOnError: boolean;
                                                        };
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
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
                                                                readonly name: "load";
                                                                readonly options: {
                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                    readonly filename?: string;
                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                    throwOnError: boolean;
                                                                };
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
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
                                                                    readonly name: "load";
                                                                    readonly options: {
                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                        readonly filename?: string;
                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                        throwOnError: boolean;
                                                                    };
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
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
                                                                readonly name: "load";
                                                                readonly options: {
                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                    readonly filename?: string;
                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                    throwOnError: boolean;
                                                                };
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
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
                                                            readonly name: "load";
                                                            readonly options: {
                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                readonly filename?: string;
                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                throwOnError: boolean;
                                                            };
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
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
                                                                    readonly name: "load";
                                                                    readonly options: {
                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                        readonly filename?: string;
                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                        throwOnError: boolean;
                                                                    };
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
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
                                                                        readonly name: "load";
                                                                        readonly options: {
                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                            readonly filename?: string;
                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                            throwOnError: boolean;
                                                                        };
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
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
                                                                    readonly name: "load";
                                                                    readonly options: {
                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                        readonly filename?: string;
                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                        throwOnError: boolean;
                                                                    };
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
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
                                                                readonly name: "load";
                                                                readonly options: {
                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                    readonly filename?: string;
                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                    throwOnError: boolean;
                                                                };
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
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
                                                                        readonly name: "load";
                                                                        readonly options: {
                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                            readonly filename?: string;
                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                            throwOnError: boolean;
                                                                        };
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
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
                                                                            readonly name: "load";
                                                                            readonly options: {
                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                readonly filename?: string;
                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                throwOnError: boolean;
                                                                            };
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
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
                                                                        readonly name: "load";
                                                                        readonly options: {
                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                            readonly filename?: string;
                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                            throwOnError: boolean;
                                                                        };
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
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
                                                                    readonly name: "load";
                                                                    readonly options: {
                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                        readonly filename?: string;
                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                        throwOnError: boolean;
                                                                    };
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
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
                                                                            readonly name: "load";
                                                                            readonly options: {
                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                readonly filename?: string;
                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                throwOnError: boolean;
                                                                            };
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
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
                                                                                readonly name: "load";
                                                                                readonly options: {
                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                    readonly filename?: string;
                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                    throwOnError: boolean;
                                                                                };
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
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
                                                                            readonly name: "load";
                                                                            readonly options: {
                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                readonly filename?: string;
                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                throwOnError: boolean;
                                                                            };
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
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
                                                                        readonly name: "load";
                                                                        readonly options: {
                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                            readonly filename?: string;
                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                            throwOnError: boolean;
                                                                        };
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
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
                                                                                readonly name: "load";
                                                                                readonly options: {
                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                    readonly filename?: string;
                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                    throwOnError: boolean;
                                                                                };
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
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
                                                                                    readonly name: "load";
                                                                                    readonly options: {
                                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                        readonly filename?: string;
                                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                        throwOnError: boolean;
                                                                                    };
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
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
                                                                                readonly name: "load";
                                                                                readonly options: {
                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                    readonly filename?: string;
                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                    throwOnError: boolean;
                                                                                };
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
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
                                                                            readonly name: "load";
                                                                            readonly options: {
                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                readonly filename?: string;
                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                throwOnError: boolean;
                                                                            };
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
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
                                                                                    readonly name: "load";
                                                                                    readonly options: {
                                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                        readonly filename?: string;
                                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                        throwOnError: boolean;
                                                                                    };
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
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
                                                                                        readonly name: "load";
                                                                                        readonly options: {
                                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                            readonly filename?: string;
                                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                            throwOnError: boolean;
                                                                                        };
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
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
                                                                                    readonly name: "load";
                                                                                    readonly options: {
                                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                        readonly filename?: string;
                                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                        throwOnError: boolean;
                                                                                    };
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
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
                                                                                readonly name: "load";
                                                                                readonly options: {
                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                    readonly filename?: string;
                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                    throwOnError: boolean;
                                                                                };
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
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
                                                                                        readonly name: "load";
                                                                                        readonly options: {
                                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                            readonly filename?: string;
                                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                            throwOnError: boolean;
                                                                                        };
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
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
                                                                                            readonly name: "load";
                                                                                            readonly options: {
                                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                readonly filename?: string;
                                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                throwOnError: boolean;
                                                                                            };
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
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
                                                                                        readonly name: "load";
                                                                                        readonly options: {
                                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                            readonly filename?: string;
                                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                            throwOnError: boolean;
                                                                                        };
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
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
                                                                                    readonly name: "load";
                                                                                    readonly options: {
                                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                        readonly filename?: string;
                                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                        throwOnError: boolean;
                                                                                    };
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
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
                                                                                            readonly name: "load";
                                                                                            readonly options: {
                                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                readonly filename?: string;
                                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                throwOnError: boolean;
                                                                                            };
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
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
                                                                                                readonly name: "load";
                                                                                                readonly options: {
                                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                    readonly filename?: string;
                                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                    throwOnError: boolean;
                                                                                                };
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
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
                                                                                            readonly name: "load";
                                                                                            readonly options: {
                                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                readonly filename?: string;
                                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                throwOnError: boolean;
                                                                                            };
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
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
                                                                                        readonly name: "load";
                                                                                        readonly options: {
                                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                            readonly filename?: string;
                                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                            throwOnError: boolean;
                                                                                        };
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
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
                                                                                                readonly name: "load";
                                                                                                readonly options: {
                                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                    readonly filename?: string;
                                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                    throwOnError: boolean;
                                                                                                };
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
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
                                                                                                    readonly name: "load";
                                                                                                    readonly options: {
                                                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                        readonly filename?: string;
                                                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                        throwOnError: boolean;
                                                                                                    };
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
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
                                                                                                readonly name: "load";
                                                                                                readonly options: {
                                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                    readonly filename?: string;
                                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                    throwOnError: boolean;
                                                                                                };
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
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
                                                                                            readonly name: "load";
                                                                                            readonly options: {
                                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                readonly filename?: string;
                                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                throwOnError: boolean;
                                                                                            };
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
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
                                                                                                    readonly name: "load";
                                                                                                    readonly options: {
                                                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                        readonly filename?: string;
                                                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                        throwOnError: boolean;
                                                                                                    };
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
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
                                                                                                        readonly name: "load";
                                                                                                        readonly options: {
                                                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                            readonly filename?: string;
                                                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                            throwOnError: boolean;
                                                                                                        };
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
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
                                                                                                    readonly name: "load";
                                                                                                    readonly options: {
                                                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                        readonly filename?: string;
                                                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                        throwOnError: boolean;
                                                                                                    };
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
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
                                                                                                readonly name: "load";
                                                                                                readonly options: {
                                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                    readonly filename?: string;
                                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                    throwOnError: boolean;
                                                                                                };
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
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
                                                                                            upgrade: () => any;
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
    toJson: () => Promise<string>;
    toYaml: () => Promise<string>;
    validate: (validateOptions?: ValidateOptions) => {
        dereference: (dereferenceOptions?: DereferenceOptions) => {
            details: () => Promise<import("../../../types/index.ts").DetailsResult>;
            files: () => Promise<import("../../../types/index.ts").Filesystem>;
            get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
                readonly name: "load";
                readonly options: {
                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                    readonly filename?: string;
                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                    throwOnError: boolean;
                };
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
                    readonly name: "load";
                    readonly options: {
                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                        readonly filename?: string;
                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                        throwOnError: boolean;
                    };
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
                readonly name: "load";
                readonly options: {
                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                    readonly filename?: string;
                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                    throwOnError: boolean;
                };
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
            readonly name: "load";
            readonly options: {
                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                readonly filename?: string;
                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                throwOnError: boolean;
            };
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
                    readonly name: "load";
                    readonly options: {
                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                        readonly filename?: string;
                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                        throwOnError: boolean;
                    };
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
                        readonly name: "load";
                        readonly options: {
                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                            readonly filename?: string;
                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                            throwOnError: boolean;
                        };
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
                    readonly name: "load";
                    readonly options: {
                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                        readonly filename?: string;
                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                        throwOnError: boolean;
                    };
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
                readonly name: "load";
                readonly options: {
                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                    readonly filename?: string;
                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                    throwOnError: boolean;
                };
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
                        readonly name: "load";
                        readonly options: {
                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                            readonly filename?: string;
                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                            throwOnError: boolean;
                        };
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
                            readonly name: "load";
                            readonly options: {
                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                readonly filename?: string;
                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                throwOnError: boolean;
                            };
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
                        readonly name: "load";
                        readonly options: {
                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                            readonly filename?: string;
                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                            throwOnError: boolean;
                        };
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
                    readonly name: "load";
                    readonly options: {
                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                        readonly filename?: string;
                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                        throwOnError: boolean;
                    };
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
                            readonly name: "load";
                            readonly options: {
                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                readonly filename?: string;
                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                throwOnError: boolean;
                            };
                        }, {
                            name: "validate";
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
                                readonly name: "load";
                                readonly options: {
                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                    readonly filename?: string;
                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                    throwOnError: boolean;
                                };
                            }, {
                                name: "validate";
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
                            readonly name: "load";
                            readonly options: {
                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                readonly filename?: string;
                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                throwOnError: boolean;
                            };
                        }, {
                            name: "validate";
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
                        readonly name: "load";
                        readonly options: {
                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                            readonly filename?: string;
                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                            throwOnError: boolean;
                        };
                    }, {
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
                                readonly name: "load";
                                readonly options: {
                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                    readonly filename?: string;
                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                    throwOnError: boolean;
                                };
                            }, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "upgrade";
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
                                    readonly name: "load";
                                    readonly options: {
                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                        readonly filename?: string;
                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                        throwOnError: boolean;
                                    };
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
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
                                readonly name: "load";
                                readonly options: {
                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                    readonly filename?: string;
                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                    throwOnError: boolean;
                                };
                            }, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "upgrade";
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
                            readonly name: "load";
                            readonly options: {
                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                readonly filename?: string;
                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                throwOnError: boolean;
                            };
                        }, {
                            name: "validate";
                            options?: ValidateOptions;
                        }, {
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
                                    readonly name: "load";
                                    readonly options: {
                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                        readonly filename?: string;
                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                        throwOnError: boolean;
                                    };
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
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
                                        readonly name: "load";
                                        readonly options: {
                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                            readonly filename?: string;
                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                            throwOnError: boolean;
                                        };
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
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
                                    readonly name: "load";
                                    readonly options: {
                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                        readonly filename?: string;
                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                        throwOnError: boolean;
                                    };
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
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
                                readonly name: "load";
                                readonly options: {
                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                    readonly filename?: string;
                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                    throwOnError: boolean;
                                };
                            }, {
                                name: "validate";
                                options?: ValidateOptions;
                            }, {
                                name: "upgrade";
                            }, {
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
                                        readonly name: "load";
                                        readonly options: {
                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                            readonly filename?: string;
                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                            throwOnError: boolean;
                                        };
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
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
                                            readonly name: "load";
                                            readonly options: {
                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                readonly filename?: string;
                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                throwOnError: boolean;
                                            };
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
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
                                        readonly name: "load";
                                        readonly options: {
                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                            readonly filename?: string;
                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                            throwOnError: boolean;
                                        };
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
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
                                    readonly name: "load";
                                    readonly options: {
                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                        readonly filename?: string;
                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                        throwOnError: boolean;
                                    };
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
                                    name: "upgrade";
                                }, {
                                    name: "validate";
                                    options?: ValidateOptions;
                                }, {
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
                                            readonly name: "load";
                                            readonly options: {
                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                readonly filename?: string;
                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                throwOnError: boolean;
                                            };
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
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
                                                readonly name: "load";
                                                readonly options: {
                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                    readonly filename?: string;
                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                    throwOnError: boolean;
                                                };
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
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
                                            readonly name: "load";
                                            readonly options: {
                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                readonly filename?: string;
                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                throwOnError: boolean;
                                            };
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
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
                                        readonly name: "load";
                                        readonly options: {
                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                            readonly filename?: string;
                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                            throwOnError: boolean;
                                        };
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
                                        name: "validate";
                                        options?: ValidateOptions;
                                    }, {
                                        name: "upgrade";
                                    }, {
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
                                                readonly name: "load";
                                                readonly options: {
                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                    readonly filename?: string;
                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                    throwOnError: boolean;
                                                };
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
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
                                                    readonly name: "load";
                                                    readonly options: {
                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                        readonly filename?: string;
                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                        throwOnError: boolean;
                                                    };
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
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
                                                readonly name: "load";
                                                readonly options: {
                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                    readonly filename?: string;
                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                    throwOnError: boolean;
                                                };
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
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
                                            readonly name: "load";
                                            readonly options: {
                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                readonly filename?: string;
                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                throwOnError: boolean;
                                            };
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
                                            name: "upgrade";
                                        }, {
                                            name: "validate";
                                            options?: ValidateOptions;
                                        }, {
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
                                                    readonly name: "load";
                                                    readonly options: {
                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                        readonly filename?: string;
                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                        throwOnError: boolean;
                                                    };
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
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
                                                        readonly name: "load";
                                                        readonly options: {
                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                            readonly filename?: string;
                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                            throwOnError: boolean;
                                                        };
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
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
                                                    readonly name: "load";
                                                    readonly options: {
                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                        readonly filename?: string;
                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                        throwOnError: boolean;
                                                    };
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
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
                                                readonly name: "load";
                                                readonly options: {
                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                    readonly filename?: string;
                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                    throwOnError: boolean;
                                                };
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
                                                name: "validate";
                                                options?: ValidateOptions;
                                            }, {
                                                name: "upgrade";
                                            }, {
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
                                                        readonly name: "load";
                                                        readonly options: {
                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                            readonly filename?: string;
                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                            throwOnError: boolean;
                                                        };
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
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
                                                            readonly name: "load";
                                                            readonly options: {
                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                readonly filename?: string;
                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                throwOnError: boolean;
                                                            };
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
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
                                                        readonly name: "load";
                                                        readonly options: {
                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                            readonly filename?: string;
                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                            throwOnError: boolean;
                                                        };
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
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
                                                    readonly name: "load";
                                                    readonly options: {
                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                        readonly filename?: string;
                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                        throwOnError: boolean;
                                                    };
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
                                                    name: "upgrade";
                                                }, {
                                                    name: "validate";
                                                    options?: ValidateOptions;
                                                }, {
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
                                                            readonly name: "load";
                                                            readonly options: {
                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                readonly filename?: string;
                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                throwOnError: boolean;
                                                            };
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
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
                                                                readonly name: "load";
                                                                readonly options: {
                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                    readonly filename?: string;
                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                    throwOnError: boolean;
                                                                };
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
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
                                                            readonly name: "load";
                                                            readonly options: {
                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                readonly filename?: string;
                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                throwOnError: boolean;
                                                            };
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
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
                                                        readonly name: "load";
                                                        readonly options: {
                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                            readonly filename?: string;
                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                            throwOnError: boolean;
                                                        };
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
                                                        name: "validate";
                                                        options?: ValidateOptions;
                                                    }, {
                                                        name: "upgrade";
                                                    }, {
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
                                                                readonly name: "load";
                                                                readonly options: {
                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                    readonly filename?: string;
                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                    throwOnError: boolean;
                                                                };
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
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
                                                                    readonly name: "load";
                                                                    readonly options: {
                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                        readonly filename?: string;
                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                        throwOnError: boolean;
                                                                    };
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
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
                                                                readonly name: "load";
                                                                readonly options: {
                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                    readonly filename?: string;
                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                    throwOnError: boolean;
                                                                };
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
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
                                                            readonly name: "load";
                                                            readonly options: {
                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                readonly filename?: string;
                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                throwOnError: boolean;
                                                            };
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
                                                            name: "upgrade";
                                                        }, {
                                                            name: "validate";
                                                            options?: ValidateOptions;
                                                        }, {
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
                                                                    readonly name: "load";
                                                                    readonly options: {
                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                        readonly filename?: string;
                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                        throwOnError: boolean;
                                                                    };
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
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
                                                                        readonly name: "load";
                                                                        readonly options: {
                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                            readonly filename?: string;
                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                            throwOnError: boolean;
                                                                        };
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
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
                                                                    readonly name: "load";
                                                                    readonly options: {
                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                        readonly filename?: string;
                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                        throwOnError: boolean;
                                                                    };
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
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
                                                                readonly name: "load";
                                                                readonly options: {
                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                    readonly filename?: string;
                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                    throwOnError: boolean;
                                                                };
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
                                                                name: "validate";
                                                                options?: ValidateOptions;
                                                            }, {
                                                                name: "upgrade";
                                                            }, {
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
                                                                        readonly name: "load";
                                                                        readonly options: {
                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                            readonly filename?: string;
                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                            throwOnError: boolean;
                                                                        };
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
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
                                                                            readonly name: "load";
                                                                            readonly options: {
                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                readonly filename?: string;
                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                throwOnError: boolean;
                                                                            };
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
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
                                                                        readonly name: "load";
                                                                        readonly options: {
                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                            readonly filename?: string;
                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                            throwOnError: boolean;
                                                                        };
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
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
                                                                    readonly name: "load";
                                                                    readonly options: {
                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                        readonly filename?: string;
                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                        throwOnError: boolean;
                                                                    };
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
                                                                    name: "upgrade";
                                                                }, {
                                                                    name: "validate";
                                                                    options?: ValidateOptions;
                                                                }, {
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
                                                                            readonly name: "load";
                                                                            readonly options: {
                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                readonly filename?: string;
                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                throwOnError: boolean;
                                                                            };
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
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
                                                                                readonly name: "load";
                                                                                readonly options: {
                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                    readonly filename?: string;
                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                    throwOnError: boolean;
                                                                                };
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
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
                                                                            readonly name: "load";
                                                                            readonly options: {
                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                readonly filename?: string;
                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                throwOnError: boolean;
                                                                            };
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
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
                                                                        readonly name: "load";
                                                                        readonly options: {
                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                            readonly filename?: string;
                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                            throwOnError: boolean;
                                                                        };
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
                                                                        name: "validate";
                                                                        options?: ValidateOptions;
                                                                    }, {
                                                                        name: "upgrade";
                                                                    }, {
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
                                                                                readonly name: "load";
                                                                                readonly options: {
                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                    readonly filename?: string;
                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                    throwOnError: boolean;
                                                                                };
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
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
                                                                                    readonly name: "load";
                                                                                    readonly options: {
                                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                        readonly filename?: string;
                                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                        throwOnError: boolean;
                                                                                    };
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
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
                                                                                readonly name: "load";
                                                                                readonly options: {
                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                    readonly filename?: string;
                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                    throwOnError: boolean;
                                                                                };
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
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
                                                                            readonly name: "load";
                                                                            readonly options: {
                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                readonly filename?: string;
                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                throwOnError: boolean;
                                                                            };
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
                                                                            name: "upgrade";
                                                                        }, {
                                                                            name: "validate";
                                                                            options?: ValidateOptions;
                                                                        }, {
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
                                                                                    readonly name: "load";
                                                                                    readonly options: {
                                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                        readonly filename?: string;
                                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                        throwOnError: boolean;
                                                                                    };
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
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
                                                                                        readonly name: "load";
                                                                                        readonly options: {
                                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                            readonly filename?: string;
                                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                            throwOnError: boolean;
                                                                                        };
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
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
                                                                                    readonly name: "load";
                                                                                    readonly options: {
                                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                        readonly filename?: string;
                                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                        throwOnError: boolean;
                                                                                    };
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
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
                                                                                readonly name: "load";
                                                                                readonly options: {
                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                    readonly filename?: string;
                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                    throwOnError: boolean;
                                                                                };
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
                                                                                name: "validate";
                                                                                options?: ValidateOptions;
                                                                            }, {
                                                                                name: "upgrade";
                                                                            }, {
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
                                                                                        readonly name: "load";
                                                                                        readonly options: {
                                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                            readonly filename?: string;
                                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                            throwOnError: boolean;
                                                                                        };
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
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
                                                                                            readonly name: "load";
                                                                                            readonly options: {
                                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                readonly filename?: string;
                                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                throwOnError: boolean;
                                                                                            };
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
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
                                                                                        readonly name: "load";
                                                                                        readonly options: {
                                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                            readonly filename?: string;
                                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                            throwOnError: boolean;
                                                                                        };
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
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
                                                                                    readonly name: "load";
                                                                                    readonly options: {
                                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                        readonly filename?: string;
                                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                        throwOnError: boolean;
                                                                                    };
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
                                                                                    name: "upgrade";
                                                                                }, {
                                                                                    name: "validate";
                                                                                    options?: ValidateOptions;
                                                                                }, {
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
                                                                                            readonly name: "load";
                                                                                            readonly options: {
                                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                readonly filename?: string;
                                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                throwOnError: boolean;
                                                                                            };
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
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
                                                                                                readonly name: "load";
                                                                                                readonly options: {
                                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                    readonly filename?: string;
                                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                    throwOnError: boolean;
                                                                                                };
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
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
                                                                                            readonly name: "load";
                                                                                            readonly options: {
                                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                readonly filename?: string;
                                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                throwOnError: boolean;
                                                                                            };
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
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
                                                                                        readonly name: "load";
                                                                                        readonly options: {
                                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                            readonly filename?: string;
                                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                            throwOnError: boolean;
                                                                                        };
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
                                                                                        name: "validate";
                                                                                        options?: ValidateOptions;
                                                                                    }, {
                                                                                        name: "upgrade";
                                                                                    }, {
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
                                                                                                readonly name: "load";
                                                                                                readonly options: {
                                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                    readonly filename?: string;
                                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                    throwOnError: boolean;
                                                                                                };
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
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
                                                                                                    readonly name: "load";
                                                                                                    readonly options: {
                                                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                        readonly filename?: string;
                                                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                        throwOnError: boolean;
                                                                                                    };
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
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
                                                                                                readonly name: "load";
                                                                                                readonly options: {
                                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                    readonly filename?: string;
                                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                    throwOnError: boolean;
                                                                                                };
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
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
                                                                                            readonly name: "load";
                                                                                            readonly options: {
                                                                                                readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                readonly filename?: string;
                                                                                                readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                throwOnError: boolean;
                                                                                            };
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
                                                                                            name: "upgrade";
                                                                                        }, {
                                                                                            name: "validate";
                                                                                            options?: ValidateOptions;
                                                                                        }, {
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
                                                                                                    readonly name: "load";
                                                                                                    readonly options: {
                                                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                        readonly filename?: string;
                                                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                        throwOnError: boolean;
                                                                                                    };
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
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
                                                                                                        readonly name: "load";
                                                                                                        readonly options: {
                                                                                                            readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                            readonly filename?: string;
                                                                                                            readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                            throwOnError: boolean;
                                                                                                        };
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
                                                                                                        options?: ValidateOptions;
                                                                                                    }, {
                                                                                                        name: "upgrade";
                                                                                                    }, {
                                                                                                        name: "validate";
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
                                                                                                    readonly name: "load";
                                                                                                    readonly options: {
                                                                                                        readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                        readonly filename?: string;
                                                                                                        readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                        throwOnError: boolean;
                                                                                                    };
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
                                                                                                    options?: ValidateOptions;
                                                                                                }, {
                                                                                                    name: "upgrade";
                                                                                                }, {
                                                                                                    name: "validate";
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
                                                                                                readonly name: "load";
                                                                                                readonly options: {
                                                                                                    readonly plugins?: import("../../load/load.ts").LoadPlugin[];
                                                                                                    readonly filename?: string;
                                                                                                    readonly filesystem?: import("../../../types/index.ts").Filesystem;
                                                                                                    throwOnError: boolean;
                                                                                                };
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
                                                                                                name: "validate";
                                                                                                options?: ValidateOptions;
                                                                                            }, {
                                                                                                name: "upgrade";
                                                                                            }, {
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
};
//# sourceMappingURL=loadCommand.d.ts.map