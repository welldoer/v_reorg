module net

#flag -lws2_32
#include <winsock2.h>
#include <Ws2tcpip.h>

// Ref - https://docs.microsoft.com/en-us/windows/win32/api/winsock/nf-winsock-wsastartup
const (
    WSA_V1  = 0x100 // C.MAKEWORD(1, 0)
    WSA_V11 = 0x101 // C.MAKEWORD(1, 1)
    WSA_V2  = 0x200 // C.MAKEWORD(2, 0)
    WSA_V21 = 0x201 // C.MAKEWORD(2, 1)
    WSA_V22 = 0x202 // C.MAKEWORD(2, 2)
)

pub fn socket(family int, stype int, prototype int) Socket {
	sockfd := C.socket(family, _type, proto)
	s := Socket {
		sockfd: sockfd
		family: family
		_type: _type
		proto: proto
	}
	return s
}
