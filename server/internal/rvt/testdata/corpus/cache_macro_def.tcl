# A proc defined through a caching decorator macro: the command head is the
# macro (CACHE_PROC), with `proc name args body` as its trailing arguments. The
# line continuation makes it a single command. Before decorated-proc detection,
# this proc was invisible to goto-definition.
CACHE_PROC \
proc compute_widget {id} {
    return "widget-$id"
}
