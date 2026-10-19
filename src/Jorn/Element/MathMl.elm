module Jorn.Element.MathMl exposing
    ( namespace
    , math
    , mi, mn, mo, ms, mspace, mtext
    , mrow, mfrac, msqrt, mroot, mstyle, merror, mpadded, mphantom
    , msub, msup, msubsup, munder, mover, munderover, mmultiscripts, mprescripts
    , mtable, mtr, mtd
    , semantics, annotation, annotationXml
    )

{-| One function per MathML element, each in the MathML namespace. Attributes
go through `Jorn.Attribute.attribute`:

    MathMl.math [ Attribute.attribute "display" "block" ]
        [ MathMl.msup []
            [ MathMl.mi [] [ Element.text "x" ]
            , MathMl.mn [] [ Element.text "2" ]
            ]
        ]

These are the elements of MathML Core, the part of MathML that browsers
render. Anything else works through `Jorn.Element.namespaced` with `namespace`.


# Namespace

@docs namespace


# Root

@docs math


# Tokens

`mi` is an identifier, `mn` a number, `mo` an operator, `ms` a string literal
and `mtext` plain text. `mspace` is blank space, sized with attributes.

@docs mi, mn, mo, ms, mspace, mtext


# Layout

@docs mrow, mfrac, msqrt, mroot, mstyle, merror, mpadded, mphantom


# Scripts and limits

`mprescripts` goes inside `mmultiscripts`, between the scripts after the base
and the ones before it.

@docs msub, msup, msubsup, munder, mover, munderover, mmultiscripts, mprescripts


# Tables

@docs mtable, mtr, mtd


# Semantics

`semantics` pairs an expression with other ways to describe it, each in an
`annotation` or `annotationXml`.

@docs semantics, annotation, annotationXml

-}

import Jorn.Attribute exposing (Attribute)
import Jorn.Element exposing (Element, namespaced)


{-| The MathML namespace, `http://www.w3.org/1998/Math/MathML`.
-}
namespace : String
namespace =
    "http://www.w3.org/1998/Math/MathML"


{-| The `<math>` element that starts an expression. Same as `Jorn.Element.Html.math`.
-}
math : List (Attribute msg) -> List (Element msg) -> Element msg
math =
    namespaced namespace "math"


{-| -}
mi : List (Attribute msg) -> List (Element msg) -> Element msg
mi =
    namespaced namespace "mi"


{-| -}
mn : List (Attribute msg) -> List (Element msg) -> Element msg
mn =
    namespaced namespace "mn"


{-| -}
mo : List (Attribute msg) -> List (Element msg) -> Element msg
mo =
    namespaced namespace "mo"


{-| -}
ms : List (Attribute msg) -> List (Element msg) -> Element msg
ms =
    namespaced namespace "ms"


{-| -}
mspace : List (Attribute msg) -> List (Element msg) -> Element msg
mspace =
    namespaced namespace "mspace"


{-| -}
mtext : List (Attribute msg) -> List (Element msg) -> Element msg
mtext =
    namespaced namespace "mtext"


{-| -}
mrow : List (Attribute msg) -> List (Element msg) -> Element msg
mrow =
    namespaced namespace "mrow"


{-| -}
mfrac : List (Attribute msg) -> List (Element msg) -> Element msg
mfrac =
    namespaced namespace "mfrac"


{-| -}
msqrt : List (Attribute msg) -> List (Element msg) -> Element msg
msqrt =
    namespaced namespace "msqrt"


{-| -}
mroot : List (Attribute msg) -> List (Element msg) -> Element msg
mroot =
    namespaced namespace "mroot"


{-| -}
mstyle : List (Attribute msg) -> List (Element msg) -> Element msg
mstyle =
    namespaced namespace "mstyle"


{-| -}
merror : List (Attribute msg) -> List (Element msg) -> Element msg
merror =
    namespaced namespace "merror"


{-| -}
mpadded : List (Attribute msg) -> List (Element msg) -> Element msg
mpadded =
    namespaced namespace "mpadded"


{-| -}
mphantom : List (Attribute msg) -> List (Element msg) -> Element msg
mphantom =
    namespaced namespace "mphantom"


{-| -}
msub : List (Attribute msg) -> List (Element msg) -> Element msg
msub =
    namespaced namespace "msub"


{-| -}
msup : List (Attribute msg) -> List (Element msg) -> Element msg
msup =
    namespaced namespace "msup"


{-| -}
msubsup : List (Attribute msg) -> List (Element msg) -> Element msg
msubsup =
    namespaced namespace "msubsup"


{-| -}
munder : List (Attribute msg) -> List (Element msg) -> Element msg
munder =
    namespaced namespace "munder"


{-| -}
mover : List (Attribute msg) -> List (Element msg) -> Element msg
mover =
    namespaced namespace "mover"


{-| -}
munderover : List (Attribute msg) -> List (Element msg) -> Element msg
munderover =
    namespaced namespace "munderover"


{-| -}
mmultiscripts : List (Attribute msg) -> List (Element msg) -> Element msg
mmultiscripts =
    namespaced namespace "mmultiscripts"


{-| -}
mprescripts : List (Attribute msg) -> List (Element msg) -> Element msg
mprescripts =
    namespaced namespace "mprescripts"


{-| -}
mtable : List (Attribute msg) -> List (Element msg) -> Element msg
mtable =
    namespaced namespace "mtable"


{-| -}
mtr : List (Attribute msg) -> List (Element msg) -> Element msg
mtr =
    namespaced namespace "mtr"


{-| -}
mtd : List (Attribute msg) -> List (Element msg) -> Element msg
mtd =
    namespaced namespace "mtd"


{-| -}
semantics : List (Attribute msg) -> List (Element msg) -> Element msg
semantics =
    namespaced namespace "semantics"


{-| -}
annotation : List (Attribute msg) -> List (Element msg) -> Element msg
annotation =
    namespaced namespace "annotation"


{-| `<annotation-xml>`.
-}
annotationXml : List (Attribute msg) -> List (Element msg) -> Element msg
annotationXml =
    namespaced namespace "annotation-xml"
