local M = {}
local utils = require('tcl-lsp.utils')

-- Comprehensive TCL command documentation
local tcl_docs = {
  -- Core commands
  puts = {
    signature = "puts ?-nonewline? ?channelId? string",
    description = "Write the characters given by string to the channel given by channelId (stdout by default).",
    examples = { 'puts "Hello World"', 'puts -nonewline stderr "Error: "' }
  },
  set = {
    signature = "set varName ?value?",
    description = "Returns the value of variable varName. If value is specified, set varName to value.",
    examples = { 'set x 10', 'set result [expr $x + 5]' }
  },
  proc = {
    signature = "proc name args body",
    description = "Create a new Tcl procedure with the given name, argument list, and body.",
    examples = { 'proc square {x} { return [expr $x * $x] }' }
  },
  if = {
    signature = "if expr1 ?then? body1 ?elseif expr2 ?then? body2 ...? ?else? ?bodyN?",
    description = "Execute body1 if expr1 is true, otherwise try elseif conditions, or execute else body.",
    examples = { 'if {$x > 0} { puts "positive" }', 'if {$x > 0} then { puts "positive" } else { puts "not positive" }' }
  },
  for = {
    signature = "for start test next body",
    description = "Execute start, then repeatedly test condition and execute body followed by next.",
    examples = { 'for {set i 0} {$i < 10} {incr i} { puts $i }' }
  },
  while = {
    signature = "while test body",
    description = "Repeatedly test condition and execute body while test is true.",
    examples = { 'while {$i < 10} { puts $i; incr i }' }
  },
  foreach = {
    signature = "foreach varname list body",
    description = "Execute body for each element in list, with varname set to the current element.",
    examples = { 'foreach item {a b c} { puts $item }' }
  },
  return = {
    signature = "return ?-code code? ?-errorinfo info? ?-errorcode code? ?value?",
    description = "Return from a procedure with the given value (empty string by default).",
    examples = { 'return $result', 'return -code error "Something went wrong"' }
  },
  
  -- String and list operations
  string = {
    signature = "string option arg ?arg ...?",
    description = "Perform string operations like length, index, range, match, etc.",
    examples = { 'string length $str', 'string index $str 0', 'string match "*.txt" $filename' }
  },
  list = {
    signature = "list ?arg arg ...?",
    description = "Create a list from the given arguments.",
    examples = { 'list a b c', 'list $var1 $var2' }
  },
  lappend = {
    signature = "lappend varName ?value value ...?",
    description = "Append values to the list stored in varName.",
    examples = { 'lappend mylist $newitem', 'lappend result {item 1} {item 2}' }
  },
  llength = {
    signature = "llength list",
    description = "Return the number of elements in list.",
    examples = { 'llength $mylist' }
  },
  lindex = {
    signature = "lindex list ?index ...?",
    description = "Return the element at the given index in list.",
    examples = { 'lindex $mylist 0', 'lindex $matrix 0 1' }
  },
  
  -- File operations
  file = {
    signature = "file option name ?arg arg ...?",
    description = "Perform file operations like exists, readable, dirname, etc.",
    examples = { 'file exists $filename', 'file dirname $path', 'file extension $filename' }
  },
  open = {
    signature = "open fileName ?access? ?permissions?",
    description = "Open a file and return a channel identifier.",
    examples = { 'open myfile.txt r', 'open output.txt w' }
  },
  close = {
    signature = "close channelId",
    description = "Close the channel given by channelId.",
    examples = { 'close $fileHandle' }
  },
  gets = {
    signature = "gets channelId ?varName?",
    description = "Read a line from channelId. If varName is given, store the line there.",
    examples = { 'gets stdin line', 'gets $fileHandle' }
  },
  
  -- Control flow
  switch = {
    signature = "switch ?options? string pattern body ?pattern body ...?",
    description = "Compare string against patterns and execute the matching body.",
    examples = { 'switch $var { a { puts "first" } b { puts "second" } }' }
  },
  catch = {
    signature = "catch script ?resultVarName? ?optionsVarName?",
    description = "Execute script and catch any errors that occur.",
    examples = { 'catch { risky_operation } result' }
  },
  error = {
    signature = "error message ?info? ?code?",
    description = "Generate an error with the given message.",
    examples = { 'error "Invalid argument"' }
  },
  
  -- Advanced
  namespace = {
    signature = "namespace option ?arg arg ...?",
    description = "Create and manipulate namespaces for command and variable names.",
    examples = { 'namespace eval myns { variable x 10 }' }
  },
  package = {
    signature = "package option ?arg arg ...?",
    description = "Manage package loading and version requirements.",
    examples = { 'package require Tk', 'package provide MyPackage 1.0' }
  },
  regexp = {
    signature = "regexp ?switches? exp string ?matchVar? ?subMatchVar ...?",
    description = "Match regular expression against string.",
    examples = { 'regexp {[0-9]+} $text match' }
  },
  regsub = {
    signature = "regsub ?switches? exp string subSpec ?varName?",
    description = "Replace matches of regular expression in string.",
    examples = { 'regsub -all { +} $text { } result' }
  }
}

function M.handle(params)
  local uri = params.textDocument.uri
  local position = params.position
  
  -- Get the word under cursor
  local filepath = utils.uri_to_path(uri)
  local bufnr = vim.uri_to_bufnr(uri)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local line = lines[position.line + 1] or ''
  
  local word = utils.get_word_at_position(line, position.character)
  if not word then
    return nil
  end
  
  -- Check built-in TCL commands first
  local doc = tcl_docs[word]
  if doc then
    local content = {
      '**TCL Command:** `' .. word .. '`',
      '',
      '```tcl',
      doc.signature,
      '```',
      '',
      doc.description
    }
    
    if doc.examples and #doc.examples > 0 then
      table.insert(content, '')
      table.insert(content, '**Examples:**')
      table.insert(content, '')
      for _, example in ipairs(doc.examples) do
        table.insert(content, '```tcl')
        table.insert(content, example)
        table.insert(content, '```')
        table.insert(content, '')
      end
    end
    
    return {
      contents = {
        kind = 'markdown',
        value = table.concat(content, '\n')
      }
    }
  end
  
  -- Check user-defined symbols
  local workspace = require('tcl-lsp.workspace')
  local definition = workspace.find_definition(word, filepath)
  
  if definition then
    local content = {
      string.format('**%s:** `%s`', definition.type:gsub('^%l', string.upper), definition.name),
      '',
      string.format('Defined in: `%s:%d`', definition.file, definition.line)
    }
    
    if definition.type == 'procedure' then
      -- Try to get procedure signature
      local file = io.open(definition.file, 'r')
      if file then
        local file_lines = {}
        for file_line in file:lines() do
          table.insert(file_lines, file_line)
        end
        file:close()
        
        local proc_line = file_lines[definition.line]
        if proc_line then
          local signature = proc_line:match('proc%s+%S+%s+{([^}]*)}')
          if signature then
            table.insert(content, '')
            table.insert(content, '```tcl')
            table.insert(content, string.format('proc %s {%s}', definition.name, signature))
            table.insert(content, '```')
          end
        end
      end
    end
    
    return {
      contents = {
        kind = 'markdown',
        value = table.concat(content, '\n')
      }
    }
  end
  
  return nil
end

return M
