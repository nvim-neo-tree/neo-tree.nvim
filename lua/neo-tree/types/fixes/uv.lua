---@meta
---A series of edited backports from neovim's 0.12 type files since lua-ls has incorrect types.

---@class uv
local uv = {}

uv.constants = {}

--- # Address Families
uv.constants.AF_UNIX = "unix"
uv.constants.AF_INET = "inet"
uv.constants.AF_INET6 = "inet6"
uv.constants.AF_IPX = "ipx"
uv.constants.AF_NETLINK = "netlink"
uv.constants.AF_X25 = "x25"
uv.constants.AF_AX25 = "as25"
uv.constants.AF_ATMPVC = "atmpvc"
uv.constants.AF_APPLETALK = "appletalk"
uv.constants.AF_PACKET = "packet"

--- # Signals
uv.constants.SIGHUP = "sighup"
uv.constants.SIGINT = "sigint"
uv.constants.SIGQUIT = "sigquit"
uv.constants.SIGILL = "sigill"
uv.constants.SIGTRAP = "sigtrap"
uv.constants.SIGABRT = "sigabrt"
uv.constants.SIGIOT = "sigiot"
uv.constants.SIGBUS = "sigbus"
uv.constants.SIGFPE = "sigfpe"
uv.constants.SIGKILL = "sigkill"
uv.constants.SIGUSR1 = "sigusr1"
uv.constants.SIGSEGV = "sigsegv"
uv.constants.SIGUSR2 = "sigusr2"
uv.constants.SIGPIPE = "sigpipe"
uv.constants.SIGALRM = "sigalrm"
uv.constants.SIGTERM = "sigterm"
uv.constants.SIGCHLD = "sigchld"
uv.constants.SIGSTKFLT = "sigstkflt"
uv.constants.SIGCONT = "sigcont"
uv.constants.SIGSTOP = "sigstop"
uv.constants.SIGTSTP = "sigtstp"
uv.constants.SIGBREAK = "sigbreak"
uv.constants.SIGTTIN = "sigttin"
uv.constants.SIGTTOU = "sigttou"
uv.constants.SIGURG = "sigurg"
uv.constants.SIGXCPU = "sigxcpu"
uv.constants.SIGXFSZ = "sigxfsz"
uv.constants.SIGVTALRM = "sigvtalrm"
uv.constants.SIGPROF = "sigprof"
uv.constants.SIGWINCH = "sigwinch"
uv.constants.SIGIO = "sigio"
uv.constants.SIGPOLL = "sigpoll"
uv.constants.SIGLOST = "siglost"
uv.constants.SIGPWR = "sigpwr"
uv.constants.SIGSYS = "sigsys"

--- # Socket Types
uv.constants.SOCK_STREAM = "stream"
uv.constants.SOCK_DGRAM = "dgram"
uv.constants.SOCK_SEQPACKET = "seqpacket"
uv.constants.SOCK_RAW = "raw"
uv.constants.SOCK_RDM = "rdm"

--- # TTY Modes
uv.constants.TTY_MODE_NORMAL = "normal"
uv.constants.TTY_MODE_RAW = "raw"
uv.constants.TTY_MODE_IO = "io"
uv.constants.TTY_MODE_RAW_VT = "raw_vt"

--- # FS Modification Times
uv.constants.FS_UTIME_NOW = "now"
uv.constants.FS_UTIME_OMIT = "omit"

--- Opens path as a directory stream. Returns a handle that the user can pass to
--- `uv.fs_readdir()`. The `entries` parameter defines the maximum number of entries
--- that should be returned by each call to `uv.fs_readdir()`.
--- @param path string
--- @param callback nil (async if provided, sync if `nil`)
--- @param entries integer?
--- @return uv.luv_dir_t? dir
--- @return string? err
--- @return uv.error_name? err_name
--- @overload fun(path: string, callback: fun(err: string?, dir: uv.luv_dir_t?), entries: integer?): uv.uv_fs_t
function uv.fs_opendir(path, callback, entries) end
