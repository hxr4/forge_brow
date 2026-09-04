use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::sync::Mutex;

use adblock::lists::{FilterSet, ParseOptions};
use adblock::request::Request;
use adblock::Engine;

pub struct ForgeAdblockEngine {
    engine: Mutex<Engine>,
    rule_count: usize,
}

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = RefCell::new(None);
}

fn set_error(message: impl Into<String>) {
    let text = message.into();
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = CString::new(text).ok();
    });
}

fn clear_error() {
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = None;
    });
}

unsafe fn cstr_to_str<'a>(value: *const c_char) -> Option<&'a str> {
    if value.is_null() {
        return None;
    }
    CStr::from_ptr(value).to_str().ok()
}

#[no_mangle]
pub unsafe extern "C" fn forge_adblock_new(
    rule_paths: *const *const c_char,
    path_count: usize,
) -> *mut ForgeAdblockEngine {
    clear_error();

    let result = catch_unwind(AssertUnwindSafe(|| {
        if rule_paths.is_null() || path_count == 0 {
            set_error("no filter list paths supplied");
            return ptr::null_mut();
        }

        let mut filter_set = FilterSet::new(false);
        let mut rule_count = 0usize;
        let mut loaded_any = false;

        for index in 0..path_count {
            let raw = *rule_paths.add(index);
            let Some(path) = cstr_to_str(raw) else {
                continue;
            };
            match std::fs::read_to_string(path) {
                Ok(contents) => {
                    rule_count += contents
                        .lines()
                        .filter(|line| {
                            let trimmed = line.trim();
                            !trimmed.is_empty()
                                && !trimmed.starts_with('!')
                                && !trimmed.starts_with("[Adblock")
                        })
                        .count();
                    filter_set.add_filter_list(contents, ParseOptions::default());
                    loaded_any = true;
                }
                Err(error) => {
                    set_error(format!("failed to read {path}: {error}"));
                }
            }
        }

        if !loaded_any {
            set_error("no filter lists could be read");
            return ptr::null_mut();
        }

        let engine = Engine::new_with_filter_set(filter_set);
        Box::into_raw(Box::new(ForgeAdblockEngine {
            engine: Mutex::new(engine),
            rule_count,
        }))
    }));

    match result {
        Ok(pointer) => pointer,
        Err(_) => {
            set_error("panic while building the blocking engine");
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn forge_adblock_free(engine: *mut ForgeAdblockEngine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

#[no_mangle]
pub unsafe extern "C" fn forge_adblock_should_block(
    engine: *const ForgeAdblockEngine,
    url: *const c_char,
    source_url: *const c_char,
    request_type: *const c_char,
) -> bool {
    if engine.is_null() {
        return false;
    }

    let outcome = catch_unwind(AssertUnwindSafe(|| {
        let handle = &*engine;
        let Some(url) = cstr_to_str(url) else {
            return false;
        };
        let source_url = cstr_to_str(source_url).unwrap_or("");
        let request_type = cstr_to_str(request_type).unwrap_or("other");

        let Ok(request) = Request::new(url, source_url, request_type, "GET") else {
            return false;
        };

        let Ok(guard) = handle.engine.lock() else {
            return false;
        };

        let result = guard.check_network_request(&request);
        result.filter.is_some() && (result.important || result.exception.is_none())
    }));

    outcome.unwrap_or(false)
}

#[no_mangle]
pub unsafe extern "C" fn forge_adblock_load_resources(
    engine: *mut ForgeAdblockEngine,
    path: *const c_char,
) -> usize {
    clear_error();
    if engine.is_null() {
        return 0;
    }

    let outcome = catch_unwind(AssertUnwindSafe(|| {
        let handle = &mut *engine;
        let Some(path) = cstr_to_str(path) else {
            set_error("no resource path supplied");
            return 0usize;
        };
        let contents = match std::fs::read_to_string(path) {
            Ok(text) => text,
            Err(error) => {
                set_error(format!("failed to read {path}: {error}"));
                return 0usize;
            }
        };
        let parsed: Vec<adblock::resources::Resource> = match serde_json::from_str(&contents) {
            Ok(list) => list,
            Err(error) => {
                set_error(format!("failed to parse scriptlet resources: {error}"));
                return 0usize;
            }
        };
        let count = parsed.len();
        let Ok(mut guard) = handle.engine.lock() else {
            return 0usize;
        };
        guard.use_resources(parsed);
        count
    }));

    outcome.unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn forge_adblock_cosmetic(
    engine: *const ForgeAdblockEngine,
    url: *const c_char,
) -> *mut c_char {
    if engine.is_null() {
        return ptr::null_mut();
    }

    let outcome = catch_unwind(AssertUnwindSafe(|| {
        let handle = &*engine;
        let Some(url) = cstr_to_str(url) else {
            return ptr::null_mut();
        };
        let Ok(guard) = handle.engine.lock() else {
            return ptr::null_mut();
        };

        let resources = guard.url_cosmetic_resources(url);
        let hide: Vec<&str> = resources.hide_selectors.iter().map(|s| s.as_str()).collect();
        let payload = serde_json::json!({
            "hide": hide,
            "script": resources.injected_script,
        });

        match CString::new(payload.to_string()) {
            Ok(text) => text.into_raw(),
            Err(_) => ptr::null_mut(),
        }
    }));

    outcome.unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn forge_adblock_string_free(text: *mut c_char) {
    if !text.is_null() {
        drop(CString::from_raw(text));
    }
}

#[no_mangle]
pub unsafe extern "C" fn forge_adblock_rule_count(engine: *const ForgeAdblockEngine) -> usize {
    if engine.is_null() {
        return 0;
    }
    (*engine).rule_count
}

#[no_mangle]
pub extern "C" fn forge_adblock_last_error() -> *const c_char {
    LAST_ERROR.with(|slot| match slot.borrow().as_ref() {
        Some(message) => message.as_ptr(),
        None => ptr::null(),
    })
}
