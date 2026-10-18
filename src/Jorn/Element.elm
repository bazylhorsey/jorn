module Jorn.Element exposing
    ( Element
    , element, namespaced, text, map
    , none, fragment
    , advanced, Closing(..)
    )

{-| A pure Elm virtual DOM. Unlike `elm/html`, these values are ordinary data,
so they can be diffed anywhere: in the browser, or on a server streaming
patches to one.


# Types

@docs Element


# Primitives

@docs element, namespaced, text, map


# Nothing and groups

@docs none, fragment


# Full control

@docs advanced, Closing

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
    Vdom.Element "" tag Vdom.Normal attributes children


{-| An element in an XML namespace, such as SVG.
-}
namespaced : String -> String -> List (Attribute msg) -> List (Element msg) -> Element msg
namespaced namespace tag attributes children =
    Vdom.Element namespace tag Vdom.Normal attributes children


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


{-| Renders nothing, for when a view only sometimes shows something:

    if model.saving then
        spinner

    else
        Element.none

It leaves no node in the DOM and costs nothing in the diff. As the whole of a
view, it renders as an empty text node, since a view always has one root.

-}
none : Element msg
none =
    Vdom.Fragment []


{-| Group siblings without a wrapper element. The children take the
fragment's place in its parent, as if they had been written there directly:

    Html.ul []
        [ Html.li [] [ Element.text "First" ]
        , Element.fragment (List.map viewItem items)
        , Html.li [] [ Element.text "Last" ]
        ]

Fragments can nest, and can grow or shrink between renders.

A view always has one root, so a fragment as the whole of a view needs a
stand-in. With no children it renders as an empty text node, with one it is
that child, and with several they are wrapped in a `jorn-fragment` element
styled `display: contents`, which leaves layout as if it weren't there.

-}
fragment : List (Element msg) -> Element msg
fragment =
    Vdom.Fragment


{-| An element with full control over how it's built: its namespace (`""`
for HTML), its tag, and how its tags are written when rendered as HTML.

    Element.advanced { namespace = "", tag = "br", closing = Element.Void } [] []

-}
advanced : { namespace : String, tag : String, closing : Closing } -> List (Attribute msg) -> List (Element msg) -> Element msg
advanced options attributes children =
    Vdom.Element options.namespace options.tag (toClosing options.closing) attributes children


{-| How an element's tags are written as HTML. Only rendering to a string is
affected: the DOM and the patches are the same for all three.

  - `Normal`: an opening and a closing tag, `<div></div>`.
  - `Void`: an opening tag only, `<br>`, for elements that never have
    children.
  - `SelfClosing`: XML style, `<path />`, for SVG and MathML elements with no
    children.

-}
type Closing
    = Normal
    | Void
    | SelfClosing


toClosing : Closing -> Vdom.Closing
toClosing closing =
    case closing of
        Normal ->
            Vdom.Normal

        Void ->
            Vdom.Void

        SelfClosing ->
            Vdom.SelfClosing
