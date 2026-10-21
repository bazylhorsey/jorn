module Jorn.Element exposing
    ( Element
    , element, namespaced, text, map
    , none, fragment
    , memo
    , advanced, Closing(..)
    , unsafeRawHtml
    , toString, toDocumentString, toReadableString
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


# Skipping work

@docs memo


# Full control

@docs advanced, Closing


# Raw HTML

@docs unsafeRawHtml


# HTML strings

@docs toString, toDocumentString, toReadableString

-}

import Jorn.Attribute exposing (Attribute)
import Jorn.Internal.Html as Html
import Jorn.Internal.Vdom as Vdom
import Json.Encode as Encode exposing (Value)


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

This walks the subtree eagerly, so prefer mapping near the leaves. It stops
at a `memo`, which maps what it builds when it builds it.

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


{-| Part of a view that's only built again when what it depends on changes:

    viewTodo : Todo -> Element Msg
    viewTodo todo =
        Element.memo
            [ Encode.int todo.id, Encode.string todo.title, Encode.bool todo.done ]
            (\() -> Html.li [] [ ... ])

While the dependencies are the same as last time, Jorn doesn't call the
function and doesn't diff what it built, so the subtree costs nothing however
big it is. When they change, Jorn builds it once and diffs it like any other
subtree. On a list where one item changes, only that item is built.

The dependencies are JSON values, compared by their encoding, since Elm can't
compare values of different types in one list. Encoders you already have
work: `Element.memo [ encodeTodos model.todos ] ...`. They're encoded each
time the view runs, so a memo pays off when its subtree costs more to build
than its dependencies cost to encode.

The function should only use what's in the dependencies. Anything else it
uses, like another part of the model, stays as it was the last time it was
built, and so do its handlers and any `map` around the memo. Only the
dependencies are compared, so two memos in the same place with the same
dependencies count as the same one.

A memo changes nothing on the wire. It stands for one node: if the function
gives a fragment, the fragment is wrapped the way it would be as a whole view
(see `fragment`). `map` over a memo doesn't walk it: the mapping happens when
it's built.

-}
memo : List Value -> (() -> Element msg) -> Element msg
memo dependencies view =
    Vdom.Memo (Encode.encode 0 (Encode.list identity dependencies)) view


{-| An element with full control over how it's built: its namespace (`""`
for HTML), its tag, and how its tags are written when rendered as HTML.

    Element.advanced { namespace = "", tag = "br", closing = Element.Void } [] []

-}
advanced : { namespace : String, tag : String, closing : Closing } -> List (Attribute msg) -> List (Element msg) -> Element msg
advanced options attributes children =
    Vdom.Element options.namespace options.tag (toClosing options.closing) attributes children


{-| An element whose content is a string of HTML, set as its `innerHTML`.
For content that arrives as HTML, like rendered Markdown:

    Element.unsafeRawHtml "" "article" [ Attribute.class "post" ] post.html

The arguments are the namespace (`""` for HTML), the tag, the element's own
attributes, and the HTML inside it.

**The HTML is not escaped or checked.** Whatever it contains goes into the
page, including attributes like `onerror` that run JavaScript. Only pass HTML
you trust or have sanitized, never text a user typed.

The element's own attributes and handlers work as usual, and events from
inside the content bubble up to them. The content itself is opaque to Jorn: it
has no handlers of its own, and when the HTML changes, it's replaced as a whole.

-}
unsafeRawHtml : String -> String -> List (Attribute msg) -> String -> Element msg
unsafeRawHtml namespace tag attributes html =
    Vdom.Raw namespace tag attributes html


{-| A view as HTML, written the way the browser's `innerHTML` writes the
mounted view, so a page can show it before any script runs.

    Element.toString (Html.p [ Attribute.class "note" ] [ Element.text "1 < 2" ])
    --> "<p class=\"note\">1 &lt; 2</p>"

Text and attribute values are escaped, and void elements like `br` have no
closing tag. A fragment as the whole of a view renders the way it mounts (see
`fragment`).

Handlers don't appear, and neither do properties, which HTML can't express,
except `defaultValue`, `defaultChecked` and `defaultSelected`, which the
browser reflects into the `value`, `checked` and `selected` attributes. A
`textarea`'s `value` is written as its content, where HTML keeps it, rather
than as an attribute.

Text inside an HTML `script` or `style` isn't escaped, since the browser
reads it as it is; any `</` in it is written `<\/` so it can't close the
element early. Raw HTML from `unsafeRawHtml` is written as it is. A tag or
attribute name the browser would refuse, such as one with a space or a quote
in it, is left out.

-}
toString : Element msg -> String
toString =
    Html.toString


{-| `toString` with `<!doctype html>` in front, for a whole page:

    Element.toDocumentString
        (Html.html []
            [ Html.head [] [ Html.title [] [ Element.text "Jorn" ] ]
            , Html.body [] [ Element.text "Hello" ]
            ]
        )
    --> "<!doctype html><html><head><title>Jorn</title></head><body>Hello</body></html>"

-}
toDocumentString : Element msg -> String
toDocumentString =
    Html.toDocumentString


{-| `toString`, with one node per line and children indented under their
parent, for tests and debugging. An element that's empty, or holds only a
line of text, stays on one line:

    Html.ul []
        [ Html.li [] [ Element.text "One" ]
        , Html.li [] [ Element.text "Two" ]
        ]
        |> Element.toReadableString

    --> "<ul>\n  <li>One</li>\n  <li>Two</li>\n</ul>"

The indentation adds whitespace between nodes, so the result isn't the same
HTML. Use `toString` for pages.

-}
toReadableString : Element msg -> String
toReadableString =
    Html.toReadableString


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
