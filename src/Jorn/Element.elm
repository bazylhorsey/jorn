module Jorn.Element exposing
    ( Element
    , element, namespaced, text, map
    )

{-| A pure Elm virtual DOM. Unlike `elm/html`, these values are ordinary data,
so they can be diffed anywhere: in the browser, or on a server streaming
patches to one.


# Types

@docs Element


# Primitives

@docs element, namespaced, text, map

-}

import Jorn.Attribute exposing (Attribute)
import Jorn.Internal.Vdom as Vdom


{-| A node in the tree, producing messages of type `msg`.
-}
type alias Element msg =
    Vdom.Element msg


{-| An element with any tag name.
-}
element : String -> List (Attribute msg) -> List (Element msg) -> Element msg
element tag attributes children =
    Vdom.Element "" tag attributes children


{-| An element in an XML namespace, such as SVG.
-}
namespaced : String -> String -> List (Attribute msg) -> List (Element msg) -> Element msg
namespaced namespace tag attributes children =
    Vdom.Element namespace tag attributes children


{-| A text node.
-}
text : String -> Element msg
text =
    Vdom.Text


{-| Transform the messages produced by a subtree.

This walks the subtree eagerly, so prefer mapping near the leaves.

-}
map : (a -> b) -> Element a -> Element b
map =
    Vdom.map
