module os

const (
	PathSeparator = '\\' 
) 

// Ref - https://docs.microsoft.com/en-us/windows/desktop/winprog/windows-data-types
// A handle to an object.
type HANDLE voidptr

// Ref - https://docs.microsoft.com/en-us/cpp/c-runtime-library/reference/get-osfhandle?view=vs-2019
// get_file_handle retrieves the operating-system file handle that is associated with the specified file descriptor.
pub fn get_file_handle(path string) HANDLE {
    mode := 'rb'
    _fd := C.fopen(path.cstr(), mode.cstr())
    if _fd == 0 {
	    return HANDLE(INVALID_HANDLE_VALUE)
    }
    _handle := C._get_osfhandle(C._fileno(_fd)) // CreateFile? - hah, no -_-
    return _handle
}

// Ref - https://docs.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-getmodulefilenamea
// get_module_filename retrieves the fully qualified path for the file that contains the specified module. 
// The module must have been loaded by the current process.
pub fn get_module_filename(handle HANDLE) ?string {
    mut sz := int(1024) // Optimized length 
    mut buf := [byte(0); sz] // Not work for GetModuleFileNameW :(
    for {
        status := C.GetModuleFileName(handle, &buf, sz)
        switch status {
        case SUCCESS:
            _filename := tos(buf.data, sz)
            return _filename
        case ERROR_INSUFFICIENT_BUFFER:
            sz += 1024 // increment buffer cluster by 1024
            buf = [byte(0); sz] // clear buffer
        default:
            // Must handled with GetLastError and converted by FormatMessage
            return error('Cannot get file name from handle.')
        }
    }
}

// Ref - https://docs.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-formatmessagea#parameters
const (
    FORMAT_MESSAGE_ALLOCATE_BUFFER = 0x00000100
    FORMAT_MESSAGE_ARGUMENT_ARRAY  = 0x00002000
    FORMAT_MESSAGE_FROM_HMODULE    = 0x00000800
    FORMAT_MESSAGE_FROM_STRING     = 0x00000400
    FORMAT_MESSAGE_FROM_SYSTEM     = 0x00001000
    FORMAT_MESSAGE_IGNORE_INSERTS  = 0x00000200
)

// Ref - winnt.h
const (
    SUBLANG_NEUTRAL = 0x00
    SUBLANG_DEFAULT = 0x01
    LANG_NEUTRAL    = (SUBLANG_NEUTRAL)
)   

fn ptr_get_error_message(code u32) voidptr {
    mut buf := voidptr(0)
    C.FormatMessage(
		FORMAT_MESSAGE_ALLOCATE_BUFFER
		| FORMAT_MESSAGE_FROM_SYSTEM
		| FORMAT_MESSAGE_IGNORE_INSERTS,
        0, code, C.MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), &buf, 0, 0)
    return buf
}

pub fn get_error_msg(code u32) string {
	_ptrdata := ptr_get_error_message(code)
	return tos(_ptrdata, C.strlen(_ptrdata))
}
