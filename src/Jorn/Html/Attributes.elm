module Jorn.Html.Attributes exposing
    ( attribute, property
    , class, classList, id, href, type_, name, placeholder, for
    , value, checked, disabled
    )

{-| Attributes and properties.

Attributes are strings and show up in server-rendered HTML. Properties are
JSON values set directly on the DOM object, which is what you want for live
state like an input's `value`.


# Primitives

@docs attribute, property


# Attributes

@docs class, classList, id, href, type_, name, placeholder, for


# Form controls

These are encoded so that server-rendered HTML and the live DOM agree. See
each function for details.

@docs value, checked, disabled

-}

import Jorn.Html exposing (Attribute)
import Jorn.Internal.Vdom as Vdom
import Json.Encode as Encode exposing (Value)


{-| Any HTML attribute. Multiple `class` attributes on one element are joined.
-}
attribute : String -> String -> Attribute msg
attribute =
    Vdom.Attr


{-| Any DOM property, as JSON. Useful for custom elements that take objects.
-}
property : String -> Value -> Attribute msg
property =
    Vdom.Prop


{-| -}
class : String -> Attribute msg
class =
    attribute "class"


{-| Include each class whose flag is `True`.
-}
classList : List ( String, Bool ) -> Attribute msg
classList classes =
    classes
        |> List.filter Tuple.second
        |> List.map Tuple.first
        |> String.join " "
        |> class


{-| -}
id : String -> Attribute msg
id =
    attribute "id"


{-| -}
href : String -> Attribute msg
href =
    attribute "href"


{-| -}
type_ : String -> Attribute msg
type_ =
    attribute "type"


{-| -}
name : String -> Attribute msg
name =
    attribute "name"


{-| -}
placeholder : String -> Attribute msg
placeholder =
    attribute "placeholder"


{-| -}
for : String -> Attribute msg
for =
    attribute "for"


{-| The value of a form control. Sent as the `value` attribute, so it shows up
in server-rendered HTML. The client runtime keeps the live `value` property in
sync with it.
-}
value : String -> Attribute msg
value v =
    attribute "value" v


{-| Present as an attribute when `True`. When `False`, sets the `checked`
property to `false`, so a box the user ticked is reset too.
-}
checked : Bool -> Attribute msg
checked =
    booleanAttribute "checked"


{-| Encoded the same way as `checked`.
-}
disabled : Bool -> Attribute msg
disabled =
    booleanAttribute "disabled"


{-| Boolean attributes: present (with an empty value) when true, and a `false`
property when false, so the live DOM state is reset.
-}
booleanAttribute : String -> Bool -> Attribute msg
booleanAttribute attrName on =
    if on then
        attribute attrName ""

    else
        property attrName (Encode.bool False)
