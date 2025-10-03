---@meta
---A series of edited backports from neovim's 0.12 type files since lua-ls has incorrect types.

---@class uv
---@field constants {O_RDONLY: integer, O_WRONLY: integer, O_RDWR: integer, O_APPEND: integer, O_CREAT: integer, O_DSYNC: integer, O_EXCL: integer, O_NOCTTY: integer, O_NONBLOCK: integer, O_RSYNC: integer, O_SYNC: integer, O_TRUNC: integer, SOCK_STREAM: integer, SOCK_DGRAM: integer, SOCK_SEQPACKET: integer, SOCK_RAW: integer, SOCK_RDM: integer, AF_UNIX: integer, AF_INET: integer, AF_INET6: integer, AF_IPX: integer, AF_NETLINK: integer, AF_X25: integer, AF_AX25: integer, AF_ATMPVC: integer, AF_APPLETALK: integer, AF_PACKET: integer, AI_ADDRCONFIG: integer, AI_V4MAPPED: integer, AI_ALL: integer, AI_NUMERICHOST: integer, AI_PASSIVE: integer, AI_NUMERICSERV: integer, SIGHUP: integer, SIGINT: integer, SIGQUIT: integer, SIGILL: integer, SIGTRAP: integer, SIGABRT: integer, SIGIOT: integer, SIGBUS: integer, SIGFPE: integer, SIGKILL: integer, SIGUSR1: integer, SIGSEGV: integer, SIGUSR2: integer, SIGPIPE: integer, SIGALRM: integer, SIGTERM: integer, SIGCHLD: integer, SIGSTKFLT: integer, SIGCONT: integer, SIGSTOP: integer, SIGTSTP: integer, SIGTTIN: integer, SIGWINCH: integer, SIGIO: integer, SIGPOLL: integer, SIGXFSZ: integer, SIGVTALRM: integer, SIGPROF: integer, UDP_RECVMMSG: integer, UDP_MMSG_CHUNK: integer, UDP_REUSEADDR: integer, UDP_PARTIAL: integer, UDP_IPV6ONLY: integer, TCP_IPV6ONLY: integer, UDP_MMSG_FREE: integer, SIGSYS: integer, SIGPWR: integer, SIGTTOU: integer, SIGURG: integer, SIGXCPU: integer}
local uv = {}

--- Opens path as a directory stream. Returns a handle that the user can pass to
--- `uv.fs_readdir()`. The `entries` parameter defines the maximum number of entries
--- that should be returned by each call to `uv.fs_readdir()`.
--- @param path string
--- @param entries integer?
--- @return uv.luv_dir_t? dir
--- @return string? err
--- @return string? err_name
--- @overload fun(path: string, callback: fun(err: string?, dir: uv.luv_dir_t?), entries: integer?): uv.uv_fs_t
function uv.fs_opendir(path, entries) end

--- Equivalent to `lstat(2)`.
--- @param path string
--- @return uv.fs_stat.result? stat
--- @return string? err
--- @return string? err_name
--- @overload fun(path: string, callback: fun(err: string?, stat: uv.fs_stat.result?)): uv.uv_fs_t
function uv.fs_lstat(path) end
