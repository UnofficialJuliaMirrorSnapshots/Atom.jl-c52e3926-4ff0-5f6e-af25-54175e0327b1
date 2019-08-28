@testset "evaluations" begin
    cb = 0  # callback count
    function handle(typ, args...)
        Atom.handlemsg(Dict("type"     => typ,
                            "callback" => (cb += 1)),
                       args...)
    end
    function expect(expected)
        @test readmsg() == ["cb", cb, expected]
    end


    # pingpong
    handle("ping")
    expect("pong")

    # echo
    handle("echo", "echome!")
    expect("echome!")

    # cd
    oldpath = pwd()
    handle("cd", joinpath(oldpath, ".."))
    expect(nothing)
    @test pwd() == realpath(joinpath(oldpath, ".."))
    cd(oldpath)

    # evalsimple
    handle("evalsimple", "1 + 1")
    expect(2)
    handle("evalsimple", "sin(pi)")
    expect(sin(pi))
end
