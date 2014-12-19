## To use this test routine, execute it
## from the REPL via 
##    include("test_microcoverage.jl")
## It should display some messages on the
## console, and then a file called
## test_microcoverage_ex2.jl.mcov should
## be generated that should be the
## same as
##   test_microcoverage_ex2.jl.mcov.correct

include("microcoverage.jl")
using microcoverage
begintrack("test_microcoverage_ex2.jl")
include("test_microcoverage_ex.jl")
test_microcoverage_ex.runfuncs()
endtrack("test_microcoverage_ex2.jl")
