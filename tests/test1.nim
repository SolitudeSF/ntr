import verynice, tables

var context = getContext "context"

const templ = """
Text text text
{{ lul }}
{{ Something.{{ e: echo else }}.dude }}
{{ e.HOME }}
{{ e:echo 10 {{Something.heh}} }}
{{ e: echo $(({{color.black}}+1)) }}
"""

const result = """
Text text text
OmegaLUL
wtf
/home/solitude
10 lmao
256
"""

doAssert(templ.render(context) == result)
