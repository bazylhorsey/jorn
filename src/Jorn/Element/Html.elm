module Jorn.Element.Html exposing
    ( div, span, p, h1, h2, h3
    , a
    , button
    , input, label, form
    , ul, ol, li
    , section, main_, header, footer, nav
    )

{-| One function per HTML element. Each is a thin wrapper around
`Jorn.Element.element`, so anything missing here still works through `element`
with the tag name.


# Text content

@docs div, span, p, h1, h2, h3


# Links

@docs a


# Buttons

@docs button


# Forms

@docs input, label, form


# Lists

@docs ul, ol, li


# Sections

@docs section, main_, header, footer, nav

-}

import Jorn.Attribute exposing (Attribute)
import Jorn.Element exposing (Element, element)


{-| -}
div : List (Attribute msg) -> List (Element msg) -> Element msg
div =
    element "div"


{-| -}
span : List (Attribute msg) -> List (Element msg) -> Element msg
span =
    element "span"


{-| -}
p : List (Attribute msg) -> List (Element msg) -> Element msg
p =
    element "p"


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
a : List (Attribute msg) -> List (Element msg) -> Element msg
a =
    element "a"


{-| -}
button : List (Attribute msg) -> List (Element msg) -> Element msg
button =
    element "button"


{-| -}
input : List (Attribute msg) -> List (Element msg) -> Element msg
input =
    element "input"


{-| -}
label : List (Attribute msg) -> List (Element msg) -> Element msg
label =
    element "label"


{-| -}
form : List (Attribute msg) -> List (Element msg) -> Element msg
form =
    element "form"


{-| -}
ul : List (Attribute msg) -> List (Element msg) -> Element msg
ul =
    element "ul"


{-| -}
ol : List (Attribute msg) -> List (Element msg) -> Element msg
ol =
    element "ol"


{-| -}
li : List (Attribute msg) -> List (Element msg) -> Element msg
li =
    element "li"


{-| -}
section : List (Attribute msg) -> List (Element msg) -> Element msg
section =
    element "section"


{-| The `main` element, named with a trailing underscore because `main` is a
function in Elm.
-}
main_ : List (Attribute msg) -> List (Element msg) -> Element msg
main_ =
    element "main"


{-| -}
header : List (Attribute msg) -> List (Element msg) -> Element msg
header =
    element "header"


{-| -}
footer : List (Attribute msg) -> List (Element msg) -> Element msg
footer =
    element "footer"


{-| -}
nav : List (Attribute msg) -> List (Element msg) -> Element msg
nav =
    element "nav"
