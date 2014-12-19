## To use this test routine, execute it
## from the REPL via 
##    include("test_microcoverage.jl")
## It should display some messages on the
## console, and then a file called
## test_microcoverage_ex.jl.mcov should
## be generated that should be the
## same as
##   test_microcoverage_ex.jl.mcov.correct

include(joinpath(Pkg.dir("microcoverage"), "microcoverage.jl"))
using microcoverage
begintrack(joinpath(Pkg.dir("microcoverage"), "test_microcoverage_ex.jl"))
include(joinpath(Pkg.dir("microcoverage"), "test_microcoverage_ex.jl"))
test_microcoverage_ex.runfuncs()
endtrack(joinpath(Pkg.dir("microcoverage"), "test_microcoverage_ex.jl"))
