module Jorn.Html exposing
    ( Html, Attribute
    , node, nodeNS, text, map
    , div, span, p, h1, h2, h3, a, button, input, label, form, ul, ol, li, section, main_, header, footer, nav
    )

{-| A pure Elm virtual DOM. Unlike `elm/html`, these values are ordinary data,
so they can be diffed anywhere: in the browser, or on a server streaming
patches to one.


# Types

@docs Html, Attribute


# Primitives

@docs node, nodeNS, text, map


# Elements

@docs div, span, p, h1, h2, h3, a, button, input, label, form, ul, ol, li, section, main_, header, footer, nav

-}

import Jorn.Internal.Vdom as Vdom


{-| A node in the tree, producing messages of type `msg`.
-}
type alias Html msg =
    Vdom.Html msg


{-| An attribute, property, or event handler on an element.
-}
type alias Attribute msg =
    Vdom.Attribute msg


{-| An element with any tag name.
-}
node : String -> List (Attribute msg) -> List (Html msg) -> Html msg
node tag attributes children =
    Vdom.Element "" tag attributes children


{-| An element in an XML namespace, such as SVG.
-}
nodeNS : String -> String -> List (Attribute msg) -> List (Html msg) -> Html msg
nodeNS namespace tag attributes children =
    Vdom.Element namespace tag attributes children


{-| A text node.
-}
text : String -> Html msg
text =
    Vdom.Text


{-| Transform the messages produced by a subtree.

This walks the subtree eagerly, so prefer mapping near the leaves.

-}
map : (a -> b) -> Html a -> Html b
map =
    Vdom.map


{-| -}
div : List (Attribute msg) -> List (Html msg) -> Html msg
div =
    node "div"


{-| -}
span : List (Attribute msg) -> List (Html msg) -> Html msg
span =
    node "span"


{-| -}
p : List (Attribute msg) -> List (Html msg) -> Html msg
p =
    node "p"


{-| -}
h1 : List (Attribute msg) -> List (Html msg) -> Html msg
h1 =
    node "h1"


{-| -}
h2 : List (Attribute msg) -> List (Html msg) -> Html msg
h2 =
    node "h2"


{-| -}
h3 : List (Attribute msg) -> List (Html msg) -> Html msg
h3 =
    node "h3"


{-| -}
a : List (Attribute msg) -> List (Html msg) -> Html msg
a =
    node "a"


{-| -}
button : List (Attribute msg) -> List (Html msg) -> Html msg
button =
    node "button"


{-| -}
input : List (Attribute msg) -> List (Html msg) -> Html msg
input =
    node "input"


{-| -}
label : List (Attribute msg) -> List (Html msg) -> Html msg
label =
    node "label"


{-| -}
form : List (Attribute msg) -> List (Html msg) -> Html msg
form =
    node "form"


{-| -}
ul : List (Attribute msg) -> List (Html msg) -> Html msg
ul =
    node "ul"


{-| -}
ol : List (Attribute msg) -> List (Html msg) -> Html msg
ol =
    node "ol"


{-| -}
li : List (Attribute msg) -> List (Html msg) -> Html msg
li =
    node "li"


{-| -}
section : List (Attribute msg) -> List (Html msg) -> Html msg
section =
    node "section"


{-| -}
main_ : List (Attribute msg) -> List (Html msg) -> Html msg
main_ =
    node "main"


{-| -}
header : List (Attribute msg) -> List (Html msg) -> Html msg
header =
    node "header"


{-| -}
footer : List (Attribute msg) -> List (Html msg) -> Html msg
footer =
    node "footer"


{-| -}
nav : List (Attribute msg) -> List (Html msg) -> Html msg
nav =
    node "nav"
