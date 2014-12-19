function internalbranching(i)
    x = (i < 1)? 5 : ((i > 2)? 9 : 3)
    x
end
                
                
statementfunction(x) = x+1
                
function andor(k)
    y = 0
    if k < 10 && k*k < 36
        y = 8
    end
    if k > 20 || k * k > 225
        y = 9
    end
end
                
function hasunreachablestmt(k)
    return k * 19
    x *= 10
end
                
                
function runfuncs()
    for j = 0 : 3
        internalbranching(j)
        statementfunction(j)
    end
                    
    for l = 5 : 22
        andor(l)
    end
    hasunreachablestmt(5)
end
