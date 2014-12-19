module microcoverage


## Utility function to construct an Expr from head and args.

function mkex(head::Symbol, args...)
    v = Expr(head)
    for arg in args
        push!(v.args, arg)
    end
    v
end



## We annotate the source file with a sequence of ints and strings.

typealias AnnotationIndexType Array{Union(Int,ASCIIString), 1}

## Constructor for an annotation index.

initannotationindex() = (Union(Int,ASCIIString))[]

# This dictionary maps source file names to their
# annotation indices.

const annotationindexdict = Dict{ASCIIString, AnnotationIndexType}()


# Trackarray holds the counters that track the line
# numbers and calls.

const trackarray = (Int)[]



## incrtrackarray increments the appropriate entry of the
## track array

function incrtrackarray(subscr)
    global trackarray::Array{Int,1}
    trackarray[subscr] += 1
    nothing
end


## makecallinst: Generate an expression that corresponds to the
## statement
##    Main.microcoverage.incrtrackarray(trknum)

makecallinst(trknum::Int) = 
mkex(:call,
     mkex(:., 
          mkex(:.,
                    :Main,
               QuoteNode(:microcoverage)),
          QuoteNode(:incrtrackarray)),
     trknum)
     
## coverage_rewrite_recursive   
## Take an expression inprogram (could be a whole program),
## the name of the tracking array, and an initial position
## in the tracking array.
##
## Produce an outprogram, which is the rewritten inprogram
## with calls to the coverage-statement incrementers.
## Also return the updated trknum (position in the tracking array).
## As a side effect, generate annotationindex, which tracks what should
## be printed in the output after coverage checking is complete.
##
## There are three versions of routine; the correct one is
## selected by multiple dispatch on the first argument.

function coverage_rewrite_recursive(inprogram::LineNumberNode,
                                    starttrknum::Int,
                                    linenumberoffset::Int,
                                    annotationindex::AnnotationIndexType)
    
    # If the argument is of type LineNumberNode, i.e., 
    # a new line number in the source code,
    # replace it with a block that consists of the
    # the line number and a tracking array incrementer
    trknum = starttrknum
    newline = inprogram.line + linenumberoffset
    push!(annotationindex, -newline, trknum)
    outprogram = mkex(:block, 
                      deepcopy(inprogram), 
                      makecallinst(trknum))
    trknum += 1
    return outprogram, trknum
end


function coverage_rewrite_recursive(inprogram::Any,
                                    starttrknum::Int,
                                    linenumberoffset::Int,
                                    ::AnnotationIndexType)

    ## This is the default version of coverage_rewrite_recursive
    ## that doesn't do anything

    return inprogram, starttrknum
end



function coverage_rewrite_recursive(inprogram::Expr,
                                    starttrknum::Int,
                                    linenumberoffset::Int,
                                    annotationindex::AnnotationIndexType)
    ## This is the primary version of coverage_rewrite
    ## recursive.  It takes an expression and inserts
    ## tracking statements for line numbers and internal branches
    ## in expressions.
    trknum = starttrknum
    if inprogram.head == :line
        # If the expression is an expression of type :line, i.e., 
        # a new line number in the source code,
        # replace it with a block that consists of the
        # the line number and a tracking array incrementer
        newline = inprogram.args[1] + linenumberoffset
        push!(annotationindex, -newline, trknum)
        outprogram = mkex(:block, 
                          deepcopy(inprogram), 
                          makecallinst(trknum))
        trknum += 1
    elseif inprogram.head == :if && (!(typeof(inprogram.args[2]) <: Expr) ||
        inprogram.args[2].head != :block)
        # If the expression is of the form a? b : c
        # then generate tracking statements for b and c
        outprogram = Expr(:if)
        outprogram1, trknum = coverage_rewrite_recursive(inprogram.args[1], 
                                                         trknum, 
                                                         linenumberoffset,
                                                         annotationindex)
        push!(outprogram.args, outprogram1)
        push!(annotationindex, " ? ")
        @assert(length(inprogram.args) == 3)
        for k = 2 : 3
            if k > 2
                push!(annotationindex, " : ")
            end
            a2 = inprogram.args[k]
            push!(annotationindex, "(", trknum)
            callinst = makecallinst(trknum)
            trknum += 1
            outprogram1, trknum = coverage_rewrite_recursive(a2, 
                                                             trknum,
                                                             linenumberoffset,
                                                             annotationindex)
            push!(outprogram.args, mkex(:block, 
                                        callinst,
                                        outprogram1))
            push!(annotationindex, ")")
        end
    elseif inprogram.head == :(=) && typeof(inprogram.args[1]) <: Expr && 
        inprogram.args[1].head == :call && inprogram.args[1].args[1] != :eval
        # If the line is a statement-function definition other than the
        # definition of "eval", then insert
        # a tracking statement into the function body.
        @assert length(inprogram.args) == 2
        outprogram1, trknum = coverage_rewrite_recursive(inprogram.args[1],
                                                         trknum,
                                                         linenumberoffset, 
                                                         annotationindex)
        savetrknum = trknum
        callinst = makecallinst(trknum)
        trknum += 1
        outprogram2, trknum = coverage_rewrite_recursive(inprogram.args[2],
                                                         trknum, 
                                                         linenumberoffset,
                                                         annotationindex)
        push!(annotationindex, "(called", savetrknum, "time(s))")
        outprogram = mkex(:(=), outprogram1, mkex(:block, 
                                                  callinst,
                                                  outprogram2))
    elseif inprogram.head == :|| || inprogram.head == :&&
        ## If the expression is the || or && operator, generate
        ## a tracking statement for each branch.
        @assert length(inprogram.args) == 2
        outprogram = Expr(inprogram.head)
        for k = 1 : 2
            callinst = makecallinst(trknum)
            push!(annotationindex, "(", trknum)
            trknum += 1
            outprogram1, trknum = coverage_rewrite_recursive(inprogram.args[k], 
                                                             trknum,
                                                             linenumberoffset,
                                                             annotationindex)
            push!(outprogram.args, mkex(:block,
                                        callinst,
                                        outprogram1))
            push!(annotationindex, ")")
            if k == 1
                if inprogram.head == :||
                    push!(annotationindex, " || ")
                else
                    push!(annotationindex, " && ")
                end
            end
        end
        
    elseif inprogram.head == :global || inprogram.head == :import ||
        inprogram.head == :importall || inprogram.head == :export ||
        inprogram.head == :typealias || inprogram.head == :abstract ||
        inprogram.head == :using
        
        outprogram = inprogram
    elseif inprogram.head == :immutable || inprogram.head == :type
        outprogram = Expr(inprogram.head)
        for expr1 in inprogram.args
            if typeof(expr1) <: Expr && 
                (expr1.head == :(=) || expr1.head == :function)
                outprogram1, trknum = coverage_rewrite_recursive(expr1,
                                                                 trknum,
                                                                 linenumberoffset,
                                                                 annotationindex)
                push!(outprogram.args, outprogram1)
            else
                push!(outprogram.args, expr1)
            end
        end
    else
        ## For all other expression types, just make the output same as
        ## the input (with recursive calls)
        outprogram = Expr(inprogram.head)
        for expr1 in inprogram.args
            outprogram1, trknum = coverage_rewrite_recursive(expr1,
                                                             trknum,
                                                             linenumberoffset, 
                                                             annotationindex)
            push!(outprogram.args, outprogram1)
        end
    end
    outprogram, trknum
end


function linecount(string)
    count = 0
    pos = 1
    while true
        a = search(string, '\n', pos)
        a == 0 && break
        count += 1
        pos = a + 1
    end
    count
end



filepreamble = "# Automatically generated by microcoverage.jl-- will be automatically deleted upon completion"

## This function takes a sourcefile name.  It renames
## it to <oldname>.orig.  It parses the original file
## and inserts tracking statements.
## Then it generates a new
## sourcefile with the same name as the old.  The new
## file eval's the parsed version of the old file with
## tracking statements.  

function begintrack(sourcefilename::ASCIIString)
    println("reading $sourcefilename")
    src = ""
    open(sourcefilename, "r") do h
        src = convert(ASCIIString, readbytes(h))
    end 
    annotationindex = initannotationindex()
    global trackarray::Array{Int,1}
    lasttrknum = length(trackarray)
    initsize = lasttrknum
    srcpos = 1
    src_parse_rewrite = (Expr)[]
    println("parsing")
    linenumberoffset = 0
    while srcpos <= length(src)
        if isspace(src[srcpos])
            if src[srcpos] == '\n'
                linenumberoffset += 1
            end
            srcpos += 1
        elseif src[srcpos] == '#'
            eolpos = search(src, '\n', srcpos)
            srcpos = eolpos + 1
            linenumberoffset += 1
        else
            src_parse, srcposfinal = parse(src, srcpos)
            rewrite1,lasttrknum = coverage_rewrite_recursive(src_parse, 
                                                             lasttrknum + 1,
                                                             linenumberoffset,
                                                             annotationindex)
            linenumberoffset += linecount(src[srcpos : srcposfinal - 1])
            srcpos = srcposfinal
            push!(src_parse_rewrite, rewrite1)
        end
    end
    resize!(trackarray, lasttrknum)
    for j = initsize + 1 : lasttrknum
        trackarray[j] = 0
    end
    global annotationindexdict::Dict{ASCIIString,AnnotationIndexType}
    annotationindexdict[sourcefilename] = annotationindex
    renamed = sourcefilename * ".orig"
    if stat(renamed).size > 0
        error("Cannot rename original -- file already exists with the name $renamed")
    end
    println("renaming $sourcefilename to $renamed")
    mv(sourcefilename, renamed)
    println("saving machine-generated code in $sourcefilename")
    open(sourcefilename,"w") do h2
        global filepreamble::ASCIIString
        println(h2, filepreamble)
        for rewrite in src_parse_rewrite
            ss = IOBuffer()
            serialize(ss, rewrite)
            ser_rewrite = takebuf_array(ss)
            numbyte = length(ser_rewrite)
            println(h2, "eval(deserialize(IOBuffer((UInt8)[")
            for count = 1 : numbyte
                byte = ser_rewrite[count]
                show(h2, byte)
                count < numbyte && print(h2, ", ")
                count % 8 == 0 && println(h2)
            end
            println(h2, "])))")
        end
    end
end
        
# Small routine to make an ASCIIString consisting of i spaces
spaces(i::Int) = convert(ASCIIString, 32*ones(UInt8,i))

## The next four functions are handlers for items in annotationindex.
## This first one handles an integer-- dispatches on whether it is positive
## or negative

function printmcov(item::Int,
                   lastprint::Int,
                   curcol::Int,
                   newline::Int,
                   horig::IO,
                   hcov::IO)
    if item < 0
        printmcovli(-item, lastprint,curcol,newline,horig,hcov)
    else
        printmcovtn(item, lastprint,curcol,newline,horig,hcov)
    end
end


## Prints a line number and source line and advances the file
## to that line number, printing more source lines as necessary.

function printmcovli(lineno::Int,
                     lastprint::Int,
                     curcol::Int,
                     newline::Int,
                     horig::IO,
                     hcov::IO)
    oldnewline = newline
    newline = lineno
    if newline < lastprint
        error("Line numbers out of order in tracking info")
    end
    for count = lastprint + 1 : newline - 1
        s = chomp(readline(horig))
        if curcol > 16
            println(hcov)
            curcol = 0
        end
        println(hcov, spaces(16-curcol), "* ", s)
        curcol = 0
    end
    lastprint = newline - 1
    if newline != oldnewline
        nls = "$newline"
        print(hcov, "L", nls, spaces(8 - length(nls)))
        curcol += 9
    end
    lastprint, curcol, newline
end

## Print a tracking number

function printmcovtn(tracknum::Int,
                     lastprint::Int,
                     curcol::Int,
                     newline::Int,
                     ::IO,
                     hcov::IO)

    global trackarray::Array{Int,1}
    cov = trackarray[tracknum]
    cs = " $cov "
    print(hcov, cs)
    curcol += length(cs)
    lastprint, curcol, newline
end

## Print a string

function printmcov(outstring::ASCIIString,
                   lastprint::Int,
                   curcol::Int,
                   newline::Int,
                   ::IO,
                   hcov::IO)
    print(hcov, outstring)
    curcol += length(outstring)
    lastprint, curcol, newline
end




## endtrack is called when the trackign is finished
## It produces a coverage report in a file called <origfilename>.mcov.
## Then it renames the files back to how they were before
## begintrack was called.

function endtrack(sourcefilename::ASCIIString)
    renamed = sourcefilename * ".orig"
    covfilename = sourcefilename * ".mcov"
    open(renamed, "r") do horig
        open(covfilename, "w") do hcov
            println("Writing coverage information to $covfilename")
            global annotationindexdict::Dict{ASCIIString,AnnotationIndexType}
            lastprint = 0
            curcol = 0
            newline = -1
            for item in annotationindexdict[sourcefilename]
                lastprint, curcol, newline = printmcov(item,
                                                       lastprint,
                                                       curcol,
                                                       newline,
                                                       horig,
                                                       hcov)
            end
            if curcol > 16
                curcol = 0
                println(hcov)
            end
            while !eof(horig)
                s = chomp(readline(horig))
                println(hcov, spaces(16-curcol), "* ", s)
                curcol = 0
            end
        end
    end
    restore(sourcefilename)
end

function restore(sourcefilename::ASCIIString)
    renamed = sourcefilename * ".orig"
    if stat(renamed).size == 0
        error("No file called $renamed")
    end
    s = ""
    open(sourcefilename, "r") do hrewr
        s = chomp(readline(hrewr))
    end
    
    global filepreamble::ASCIIString
    if s != filepreamble
        error("Cannot overwrite $sourcefilename; missing preamble statement")
    end
    println("renaming $renamed to $sourcefilename; machine-generated $sourcefilename overwritten")
    mv(renamed, sourcefilename)
end    

export restore
export begintrack
export endtrack

end

