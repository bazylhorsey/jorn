module Jorn.Element.Keyed exposing
    ( element, namespaced, fragment
    , ul, ol, div, tbody, dl
    )

{-| Children with keys, for lists that reorder, or gain and lose items in the
middle.

Without keys, children are matched by position, so removing the first item of
a list rewrites every item after it. With keys, children are matched by key:
the DOM node for each item moves with it, so focus, scroll position and what
someone has typed into it stay with the right item, and long lists update with
a handful of moves instead of a rewrite.

    Keyed.ul []
        (List.map (\todo -> ( todo.id, viewTodo todo )) todos)

Keys only need to be unique among siblings. If a key repeats, its occurrences
are matched in order.


# Elements

@docs element, namespaced, fragment


# Common containers

@docs ul, ol, div, tbody, dl

-}

import Jorn.Attribute exposing (Attribute)
import Jorn.Element exposing (Element)
import Jorn.Internal.Vdom as Vdom


{-| An element with any tag name and keyed children.
-}
element : String -> List (Attribute msg) -> List ( String, Element msg ) -> Element msg
element tag attributes children =
    Vdom.Element "" tag Vdom.Normal attributes (List.map key children)


{-| An element in an XML namespace, such as SVG, with keyed children.
-}
namespaced : String -> String -> List (Attribute msg) -> List ( String, Element msg ) -> Element msg
namespaced namespace tag attributes children =
    Vdom.Element namespace tag Vdom.Normal attributes (List.map key children)


{-| Keyed siblings without a wrapper element, like `Jorn.Element.fragment`.
They take the fragment's place among their parent's children, keys included.
-}
fragment : List ( String, Element msg ) -> Element msg
fragment children =
    Vdom.Fragment (List.map key children)


key : ( String, Element msg ) -> Element msg
key ( name, child ) =
    Vdom.Keyed name child


{-| -}
ul : List (Attribute msg) -> List ( String, Element msg ) -> Element msg
ul =
    element "ul"


{-| -}
ol : List (Attribute msg) -> List ( String, Element msg ) -> Element msg
ol =
    element "ol"


{-| -}
div : List (Attribute msg) -> List ( String, Element msg ) -> Element msg
div =
    element "div"


{-| -}
tbody : List (Attribute msg) -> List ( String, Element msg ) -> Element msg
tbody =
    element "tbody"


{-| -}
dl : List (Attribute msg) -> List ( String, Element msg ) -> Element msg
dl =
    element "dl"
