-- Common TCL packages for autocompletion
-- stylua: ignore
return {
  -- Core
  "Tcl",
  "Tk",

  -- Networking
  "http",
  "tls",
  "uri",
  "ncgi",

  -- Data formats
  "json",
  "json::write",
  "csv",
  "html",
  "base64",
  "tdom",

  -- Database
  "sqlite3",
  "tdbc",
  "tdbc::sqlite3",
  "tdbc::postgres",
  "tdbc::mysql",

  -- Cryptography
  "md5",
  "sha1",
  "sha256",

  -- Data structures
  "struct::list",
  "struct::set",
  "struct::stack",
  "struct::queue",

  -- Utilities
  "msgcat",
  "fileutil",
  "textutil",
  "cmdline",
  "logger",
  "snit",
}
