return function (loader)

  local Webclient = loader.load "cosy.webclient"
  local I18n      = loader.load "cosy.i18n"
  local Layer     = loader.require "layeredata"
  local i18n      = I18n.load {}

  local Editor    = {}
  Editor.__index  = Editor
  Editor.template = Webclient.template "cosy.webclient.editor"

  function Editor.init ()
    local d3     = Webclient.window.d3
    local height = Webclient.jQuery (Webclient.window):height ()
    local width  = Webclient.jQuery (Webclient.window):width  ()
    Editor.model = Layer.new {
      name = "my model",
      data = {},
    }
    Webclient.window.console:log ("deb000")
    local nodes = Webclient.tojs ( {  ---------------  car on ne lutilise quen Lua
    		{ x = width/3 , y = height/2 },
    		{ x = 2*width/3 , y = height/2 },
    	})
    ----  Webclient.window.console:log (nodes[1].x)
    local links = Webclient.tojs {
               { source = 0, target = 1 },
    }
    local styles = {
		     {name = "font-size" , value  = "14px"},
    }	

    local mytext = d3:select "body"
                 : append "h1"
                 : style (  styles[1].name , styles[1].value  ) --------------------  : style("font-size", "14px")
                 : text ("Hello World! v01 ")
                 : style ('fill', 'darkOrange')
    Webclient.window.console:log ("deb001")
    Editor.svg    = d3:select "#editor"
                  : append "svg"
                  : attr ("class", "cosy-editor")
                  : attr ("width" , width )
                  : attr ("height", height)
                  : style ("pointer-events", "all")
    local force   = d3.layout:force ()  ---  ou bien   d3:layout:force ()
                  : size (  Webclient.tojs { width , height } )  
                  : nodes ( nodes )
                  : links ( links )
    force : linkDistance (width/2)

    local link    = Editor.svg : selectAll ('.link')
    Webclient.window.console:log ("deb900")
    Webclient.window.console:log (link)
    local link2 =      link : data ( links )
    Webclient.window.console:log ("deb901")
          link2 =      link2 : enter ()
    Webclient.window.console:log ("deb902")
          link2 =      link2 : append ('line')
    Webclient.window.console:log ("deb903")
          link2 =      link2 : attr ('class', 'link');
    Webclient.window.console:log ("deb904")
    local node    = Editor.svg : selectAll ('.node')
    Webclient.window.console:log ("deb910")
    local node2    = node : data ( nodes )
    Webclient.window.console:log ("deb911")
          node2    = node2 : enter ()
    Webclient.window.console:log ("deb912")
          node2    = node2 : append ('circle')
    Webclient.window.console:log ("deb913")
          node2    = node2 : attr ('class', 'node');
    Webclient.window.console:log ("deb914")

    Webclient.window.console:log ("deb002")


    force : on ('end', function()
                print ("on end")
            node2 : attr ('r', width/25)
                  : attr('cx', function (_, d)  Webclient.window.console:log (d); return d.x end)
                  : attr('cy', function (_, d)  return d.y end)
            link2 : attr('x1', function (_, d)  Webclient.window.console:log (d); return d.source.x end)
                  : attr('y1', function (_, d)  return d.source.y end)
                  : attr('x2', function (_, d)  return d.target.x end)
                  : attr('y2', function (_, d)  return d.target.y end)
               end)



    Webclient.window.console:log ("deb003")
    force : start()
    Webclient.window.console:log ("deb004")








    Editor.outer  = Editor.svg
                  : append "g"
                  : attr ("class", "cosy-editor-outer")
    Editor.inner  = Editor.outer
                  : append "g"
                  : attr ("class", "cosy-editor-inner")
    Editor.zoom   = d3.behavior
                  : zoom ()
    Editor.layout = d3.layout
                  : force ()
                  : size (Webclient.tojs { width, height })
                  : nodes (Webclient.tojs {})
                  : links (Webclient.tojs {})
    Editor.inner  : append "svg:rect"
                  : attr  ("class", "click-capture")
                  : attr  ("width" , width )
                  : attr  ("height", height)
                  : attr  ("visibility", "hidden")
    Webclient.jQuery (Webclient.window):resize (function ()
      d3 : select "#editor"
         : attr ("width" , Webclient.jQuery (Webclient.window):width  ())
         : attr ("height", Webclient.jQuery (Webclient.window):height ())
    end)
  end

  function Editor.update ()

  end

  function Editor.__call ()
    Webclient (function ()
      Webclient.show {
        where    = "main",
        template = Editor.template,
        data     = {},
        i18n     = i18n,
      }
      -- See http://bl.ocks.org/GerHobbelt/3637711 for pinning
      Editor.init ()
    end)
  end

  return setmetatable ({}, Editor)

end
