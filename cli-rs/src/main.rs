use std::ffi::{CString, c_char, c_int};

unsafe extern "C" {
    fn tuist_run(argc: c_int, argv: *const *const c_char) -> c_int;
}

fn main() {
    let arguments: Vec<CString> = std::env::args_os()
        .map(|argument| CString::new(argument.into_encoded_bytes()).expect("argument contains a NUL byte"))
        .collect();
    let pointers: Vec<*const c_char> = arguments.iter().map(|argument| argument.as_ptr()).collect();
    let code = unsafe { tuist_run(pointers.len() as c_int, pointers.as_ptr()) };
    std::process::exit(code);
}
