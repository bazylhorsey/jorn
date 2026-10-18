module Jorn.Element.Html exposing
    ( html, head, base, link, meta, style, title, body
    , address, article, aside, footer, header, h1, h2, h3, h4, h5, h6, hgroup
    , main_, nav, section, search
    , blockquote, dd, div, dl, dt, figcaption, figure, hr, li, menu, ol, p, pre
    , ul
    , a, abbr, b, bdi, bdo, br, cite, code, data, dfn, em, i, kbd, mark, q, rp
    , rt, ruby, s, samp, small, span, strong, sub, sup, time, u, var, wbr
    , area, audio, img, map, track, video
    , embed, iframe, object, picture, source
    , svg, math
    , canvas, noscript, script
    , del, ins
    , caption, col, colgroup, table, tbody, td, tfoot, th, thead, tr
    , button, datalist, fieldset, form, input, label, legend, meter, optgroup
    , option, output, progress, select, textarea
    , details, dialog, summary
    , slot, template
    )

{-| One function per HTML element. Each is a thin wrapper around
`Jorn.Element.element`, so anything missing here still works through `element`
with the tag name.

Void elements, the ones that can never have children (`br`, `hr`, `img`,
`input`, `link`, `meta`, ...), take only attributes:

    Html.input [ Attribute.value model.name, Event.onInput Rename ]


# Document

The document and its metadata.

@docs html, head, base, link, meta, style, title, body


# Sections

@docs address, article, aside, footer, header, h1, h2, h3, h4, h5, h6, hgroup
@docs main_, nav, section, search


# Text content

@docs blockquote, dd, div, dl, dt, figcaption, figure, hr, li, menu, ol, p, pre
@docs ul


# Inline text

@docs a, abbr, b, bdi, bdo, br, cite, code, data, dfn, em, i, kbd, mark, q, rp
@docs rt, ruby, s, samp, small, span, strong, sub, sup, time, u, var, wbr


# Images and media

@docs area, audio, img, map, track, video


# Embedded content

@docs embed, iframe, object, picture, source


# Other namespaces

`svg` and `math` start a subtree in the SVG and MathML namespaces. Build what
goes inside with `Jorn.Element.namespaced`.

@docs svg, math


# Scripting

@docs canvas, noscript, script


# Edits

@docs del, ins


# Tables

@docs caption, col, colgroup, table, tbody, td, tfoot, th, thead, tr


# Forms

@docs button, datalist, fieldset, form, input, label, legend, meter, optgroup
@docs option, output, progress, select, textarea


# Interactive

@docs details, dialog, summary


# Web components

@docs slot, template

-}

import Jorn.Attribute exposing (Attribute)
import Jorn.Element exposing (Element, element, namespaced)
import Jorn.Internal.Vdom as Vdom


{-| -}
html : List (Attribute msg) -> List (Element msg) -> Element msg
html =
    element "html"


{-| -}
head : List (Attribute msg) -> List (Element msg) -> Element msg
head =
    element "head"


{-| -}
base : List (Attribute msg) -> Element msg
base =
    void "base"


{-| -}
link : List (Attribute msg) -> Element msg
link =
    void "link"


{-| -}
meta : List (Attribute msg) -> Element msg
meta =
    void "meta"


{-| -}
style : List (Attribute msg) -> List (Element msg) -> Element msg
style =
    element "style"


{-| -}
title : List (Attribute msg) -> List (Element msg) -> Element msg
title =
    element "title"


{-| -}
body : List (Attribute msg) -> List (Element msg) -> Element msg
body =
    element "body"


{-| -}
address : List (Attribute msg) -> List (Element msg) -> Element msg
address =
    element "address"


{-| -}
article : List (Attribute msg) -> List (Element msg) -> Element msg
article =
    element "article"


{-| -}
aside : List (Attribute msg) -> List (Element msg) -> Element msg
aside =
    element "aside"


{-| -}
footer : List (Attribute msg) -> List (Element msg) -> Element msg
footer =
    element "footer"


{-| -}
header : List (Attribute msg) -> List (Element msg) -> Element msg
header =
    element "header"


{-| -}
h1 : List (Attribute msg) -> List (Element msg) -> Element msg
h1 =
    element "h1"


{-| -}
h2 : List (Attribute msg) -> List (Element msg) -> Element msg
h2 =
    element "h2"


{-| -}
h3 : List (Attribute msg) -> List (Element msg) -> Element msg
h3 =
    element "h3"


{-| -}
h4 : List (Attribute msg) -> List (Element msg) -> Element msg
h4 =
    element "h4"


{-| -}
h5 : List (Attribute msg) -> List (Element msg) -> Element msg
h5 =
    element "h5"


{-| -}
h6 : List (Attribute msg) -> List (Element msg) -> Element msg
h6 =
    element "h6"


{-| -}
hgroup : List (Attribute msg) -> List (Element msg) -> Element msg
hgroup =
    element "hgroup"


{-| `<main>`. The underscore keeps it apart from a module's `main`.
-}
main_ : List (Attribute msg) -> List (Element msg) -> Element msg
main_ =
    element "main"


{-| -}
nav : List (Attribute msg) -> List (Element msg) -> Element msg
nav =
    element "nav"


{-| -}
section : List (Attribute msg) -> List (Element msg) -> Element msg
section =
    element "section"


{-| -}
search : List (Attribute msg) -> List (Element msg) -> Element msg
search =
    element "search"


{-| -}
blockquote : List (Attribute msg) -> List (Element msg) -> Element msg
blockquote =
    element "blockquote"


{-| -}
dd : List (Attribute msg) -> List (Element msg) -> Element msg
dd =
    element "dd"


{-| -}
div : List (Attribute msg) -> List (Element msg) -> Element msg
div =
    element "div"


{-| -}
dl : List (Attribute msg) -> List (Element msg) -> Element msg
dl =
    element "dl"


{-| -}
dt : List (Attribute msg) -> List (Element msg) -> Element msg
dt =
    element "dt"


{-| -}
figcaption : List (Attribute msg) -> List (Element msg) -> Element msg
figcaption =
    element "figcaption"


{-| -}
figure : List (Attribute msg) -> List (Element msg) -> Element msg
figure =
    element "figure"


{-| -}
hr : List (Attribute msg) -> Element msg
hr =
    void "hr"


{-| -}
li : List (Attribute msg) -> List (Element msg) -> Element msg
li =
    element "li"


{-| -}
menu : List (Attribute msg) -> List (Element msg) -> Element msg
menu =
    element "menu"


{-| -}
ol : List (Attribute msg) -> List (Element msg) -> Element msg
ol =
    element "ol"


{-| -}
p : List (Attribute msg) -> List (Element msg) -> Element msg
p =
    element "p"


{-| -}
pre : List (Attribute msg) -> List (Element msg) -> Element msg
pre =
    element "pre"


{-| -}
ul : List (Attribute msg) -> List (Element msg) -> Element msg
ul =
    element "ul"


{-| -}
a : List (Attribute msg) -> List (Element msg) -> Element msg
a =
    element "a"


{-| -}
abbr : List (Attribute msg) -> List (Element msg) -> Element msg
abbr =
    element "abbr"


{-| -}
b : List (Attribute msg) -> List (Element msg) -> Element msg
b =
    element "b"


{-| -}
bdi : List (Attribute msg) -> List (Element msg) -> Element msg
bdi =
    element "bdi"


{-| -}
bdo : List (Attribute msg) -> List (Element msg) -> Element msg
bdo =
    element "bdo"


{-| -}
br : List (Attribute msg) -> Element msg
br =
    void "br"


{-| -}
cite : List (Attribute msg) -> List (Element msg) -> Element msg
cite =
    element "cite"


{-| -}
code : List (Attribute msg) -> List (Element msg) -> Element msg
code =
    element "code"


{-| -}
data : List (Attribute msg) -> List (Element msg) -> Element msg
data =
    element "data"


{-| -}
dfn : List (Attribute msg) -> List (Element msg) -> Element msg
dfn =
    element "dfn"


{-| -}
em : List (Attribute msg) -> List (Element msg) -> Element msg
em =
    element "em"


{-| -}
i : List (Attribute msg) -> List (Element msg) -> Element msg
i =
    element "i"


{-| -}
kbd : List (Attribute msg) -> List (Element msg) -> Element msg
kbd =
    element "kbd"


{-| -}
mark : List (Attribute msg) -> List (Element msg) -> Element msg
mark =
    element "mark"


{-| -}
q : List (Attribute msg) -> List (Element msg) -> Element msg
q =
    element "q"


{-| -}
rp : List (Attribute msg) -> List (Element msg) -> Element msg
rp =
    element "rp"


{-| -}
rt : List (Attribute msg) -> List (Element msg) -> Element msg
rt =
    element "rt"


{-| -}
ruby : List (Attribute msg) -> List (Element msg) -> Element msg
ruby =
    element "ruby"


{-| -}
s : List (Attribute msg) -> List (Element msg) -> Element msg
s =
    element "s"


{-| -}
samp : List (Attribute msg) -> List (Element msg) -> Element msg
samp =
    element "samp"


{-| -}
small : List (Attribute msg) -> List (Element msg) -> Element msg
small =
    element "small"


{-| -}
span : List (Attribute msg) -> List (Element msg) -> Element msg
span =
    element "span"


{-| -}
strong : List (Attribute msg) -> List (Element msg) -> Element msg
strong =
    element "strong"


{-| -}
sub : List (Attribute msg) -> List (Element msg) -> Element msg
sub =
    element "sub"


{-| -}
sup : List (Attribute msg) -> List (Element msg) -> Element msg
sup =
    element "sup"


{-| -}
time : List (Attribute msg) -> List (Element msg) -> Element msg
time =
    element "time"


{-| -}
u : List (Attribute msg) -> List (Element msg) -> Element msg
u =
    element "u"


{-| -}
var : List (Attribute msg) -> List (Element msg) -> Element msg
var =
    element "var"


{-| -}
wbr : List (Attribute msg) -> Element msg
wbr =
    void "wbr"


{-| -}
area : List (Attribute msg) -> Element msg
area =
    void "area"


{-| -}
audio : List (Attribute msg) -> List (Element msg) -> Element msg
audio =
    element "audio"


{-| -}
img : List (Attribute msg) -> Element msg
img =
    void "img"


{-| -}
map : List (Attribute msg) -> List (Element msg) -> Element msg
map =
    element "map"


{-| -}
track : List (Attribute msg) -> Element msg
track =
    void "track"


{-| -}
video : List (Attribute msg) -> List (Element msg) -> Element msg
video =
    element "video"


{-| -}
embed : List (Attribute msg) -> Element msg
embed =
    void "embed"


{-| -}
iframe : List (Attribute msg) -> List (Element msg) -> Element msg
iframe =
    element "iframe"


{-| -}
object : List (Attribute msg) -> List (Element msg) -> Element msg
object =
    element "object"


{-| -}
picture : List (Attribute msg) -> List (Element msg) -> Element msg
picture =
    element "picture"


{-| -}
source : List (Attribute msg) -> Element msg
source =
    void "source"


{-| An `<svg>` element, in the SVG namespace.
-}
svg : List (Attribute msg) -> List (Element msg) -> Element msg
svg =
    namespaced "http://www.w3.org/2000/svg" "svg"


{-| A `<math>` element, in the MathML namespace.
-}
math : List (Attribute msg) -> List (Element msg) -> Element msg
math =
    namespaced "http://www.w3.org/1998/Math/MathML" "math"


{-| -}
canvas : List (Attribute msg) -> List (Element msg) -> Element msg
canvas =
    element "canvas"


{-| -}
noscript : List (Attribute msg) -> List (Element msg) -> Element msg
noscript =
    element "noscript"


{-| -}
script : List (Attribute msg) -> List (Element msg) -> Element msg
script =
    element "script"


{-| -}
del : List (Attribute msg) -> List (Element msg) -> Element msg
del =
    element "del"


{-| -}
ins : List (Attribute msg) -> List (Element msg) -> Element msg
ins =
    element "ins"


{-| -}
caption : List (Attribute msg) -> List (Element msg) -> Element msg
caption =
    element "caption"


{-| -}
col : List (Attribute msg) -> Element msg
col =
    void "col"


{-| -}
colgroup : List (Attribute msg) -> List (Element msg) -> Element msg
colgroup =
    element "colgroup"


{-| -}
table : List (Attribute msg) -> List (Element msg) -> Element msg
table =
    element "table"


{-| -}
tbody : List (Attribute msg) -> List (Element msg) -> Element msg
tbody =
    element "tbody"


{-| -}
td : List (Attribute msg) -> List (Element msg) -> Element msg
td =
    element "td"


{-| -}
tfoot : List (Attribute msg) -> List (Element msg) -> Element msg
tfoot =
    element "tfoot"


{-| -}
th : List (Attribute msg) -> List (Element msg) -> Element msg
th =
    element "th"


{-| -}
thead : List (Attribute msg) -> List (Element msg) -> Element msg
thead =
    element "thead"


{-| -}
tr : List (Attribute msg) -> List (Element msg) -> Element msg
tr =
    element "tr"


{-| -}
button : List (Attribute msg) -> List (Element msg) -> Element msg
button =
    element "button"


{-| -}
datalist : List (Attribute msg) -> List (Element msg) -> Element msg
datalist =
    element "datalist"


{-| -}
fieldset : List (Attribute msg) -> List (Element msg) -> Element msg
fieldset =
    element "fieldset"


{-| -}
form : List (Attribute msg) -> List (Element msg) -> Element msg
form =
    element "form"


{-| -}
input : List (Attribute msg) -> Element msg
input =
    void "input"


{-| -}
label : List (Attribute msg) -> List (Element msg) -> Element msg
label =
    element "label"


{-| -}
legend : List (Attribute msg) -> List (Element msg) -> Element msg
legend =
    element "legend"


{-| -}
meter : List (Attribute msg) -> List (Element msg) -> Element msg
meter =
    element "meter"


{-| -}
optgroup : List (Attribute msg) -> List (Element msg) -> Element msg
optgroup =
    element "optgroup"


{-| -}
option : List (Attribute msg) -> List (Element msg) -> Element msg
option =
    element "option"


{-| -}
output : List (Attribute msg) -> List (Element msg) -> Element msg
output =
    element "output"


{-| -}
progress : List (Attribute msg) -> List (Element msg) -> Element msg
progress =
    element "progress"


{-| -}
select : List (Attribute msg) -> List (Element msg) -> Element msg
select =
    element "select"


{-| -}
textarea : List (Attribute msg) -> List (Element msg) -> Element msg
textarea =
    element "textarea"


{-| -}
details : List (Attribute msg) -> List (Element msg) -> Element msg
details =
    element "details"


{-| -}
dialog : List (Attribute msg) -> List (Element msg) -> Element msg
dialog =
    element "dialog"


{-| -}
summary : List (Attribute msg) -> List (Element msg) -> Element msg
summary =
    element "summary"


{-| -}
slot : List (Attribute msg) -> List (Element msg) -> Element msg
slot =
    element "slot"


{-| -}
template : List (Attribute msg) -> List (Element msg) -> Element msg
template =
    element "template"


void : String -> List (Attribute msg) -> Element msg
void tag attributes =
    Vdom.Element "" tag Vdom.Void attributes []
