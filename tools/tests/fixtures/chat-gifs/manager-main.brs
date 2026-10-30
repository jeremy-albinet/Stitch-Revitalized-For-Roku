sub main()
    screen = createObject("roSGScreen")
    scene = screen.createScene("GifManagerFixture")
    screen.show()
    scene.callFunc("runFixture")
    screen.close()
end sub
