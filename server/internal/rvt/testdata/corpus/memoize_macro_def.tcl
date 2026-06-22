# A proc defined through a memoizing decorator macro that takes a trailing flag
# AFTER the body (`-ttl 60`), so `proc NAME ARGS BODY` is no longer the command's
# last four words. The line continuation keeps it a single command. Regression
# test for decorated-proc detection that anchored on the body being the last word.
MEMOIZE proc compute_price {sku} {
    return "price-$sku"
} -ttl 60
