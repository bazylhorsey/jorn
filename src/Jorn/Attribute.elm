module Jorn.Attribute exposing
    ( Attribute
    , attribute, property, none
    , class, classes, id, style, styles, title, lang, dir, data, tabindex, hidden, inert
    , accesskey, autocapitalize, autocorrect, autofocus, contenteditable, draggable
    , enterkeyhint, inputmode, spellcheck, translate, writingsuggestions
    , popover, closedby, command, commandfor
    , itemid, itemprop, itemscope, itemtype
    , is, nonce
    , href, type_, name, placeholder, for
    , value, checked, disabled
    )

{-| Attributes and properties.

Attributes are strings and show up in server-rendered HTML. Properties are
JSON values set directly on the DOM object, which is what you want for live
state like an input's `value`.


# Types

@docs Attribute


# Primitives

@docs attribute, property, none


# Global attributes

These work on any element.

@docs class, classes, id, style, styles, title, lang, dir, data, tabindex, hidden, inert


# Editing and input

@docs accesskey, autocapitalize, autocorrect, autofocus, contenteditable, draggable
@docs enterkeyhint, inputmode, spellcheck, translate, writingsuggestions


# Popovers and commands

@docs popover, closedby, command, commandfor


# Microdata

@docs itemid, itemprop, itemscope, itemtype


# Other global attributes

@docs is, nonce


# Element attributes

@docs href, type_, name, placeholder, for


# Form controls

These are encoded so that server-rendered HTML and the live DOM agree. See
each function for details.

@docs value, checked, disabled

-}

import Jorn.Internal.Vdom as Vdom
import Json.Encode as Encode exposing (Value)


{-| An attribute, property, or event handler on an element.
-}
type alias Attribute msg =
    Vdom.Attribute msg


{-| Any HTML attribute. Within one element the last attribute with a name
wins, except `class` and `style`, which accumulate: several `class` attributes
are joined with spaces and several `style` attributes with semicolons.
-}
attribute : String -> String -> Attribute msg
attribute =
    Vdom.Attr


{-| Any DOM property, as JSON. Useful for custom elements that take objects.
-}
property : String -> Value -> Attribute msg
property =
    Vdom.Prop


{-| An attribute that does nothing, for attributes you only sometimes want:

    Html.button
        [ Event.onClick Save
        , if model.saving then
            Attribute.disabled True

          else
            Attribute.none
        ]
        [ Element.text "Save" ]

-}
none : Attribute msg
none =
    Vdom.NoAttribute


{-| -}
class : String -> Attribute msg
class =
    attribute "class"


{-| Include each class whose flag is `True`.
-}
classes : List ( String, Bool ) -> Attribute msg
classes classList =
    classList
        |> List.filter Tuple.second
        |> List.map Tuple.first
        |> String.join " "
        |> class


{-| -}
id : String -> Attribute msg
id =
    attribute "id"


{-| One CSS declaration. Several on one element are joined into a single
`style` attribute, the way several `class` attributes are:

    Html.div [ Attribute.style "color" "red", Attribute.style "padding" "1rem" ] []

-}
style : String -> String -> Attribute msg
style property_ value_ =
    attribute "style" (property_ ++ ": " ++ value_)


{-| Several CSS declarations at once. They join any other `style` on the
element.
-}
styles : List ( String, String ) -> Attribute msg
styles declarations =
    declarations
        |> List.map (\( property_, value_ ) -> property_ ++ ": " ++ value_)
        |> String.join "; "
        |> attribute "style"


{-| -}
title : String -> Attribute msg
title =
    attribute "title"


{-| The language of an element's content, like `"en"` or `"pt-BR"`.
-}
lang : String -> Attribute msg
lang =
    attribute "lang"


{-| Text direction: `"ltr"`, `"rtl"` or `"auto"`.
-}
dir : String -> Attribute msg
dir =
    attribute "dir"


{-| A `data-*` attribute. `data "user-id" "42"` sets `data-user-id="42"`.
-}
data : String -> String -> Attribute msg
data key =
    attribute ("data-" ++ key)


{-| -}
tabindex : Int -> Attribute msg
tabindex index =
    attribute "tabindex" (String.fromInt index)


{-| Encoded the same way as `checked`.
-}
hidden : Bool -> Attribute msg
hidden =
    booleanAttribute "hidden"


{-| Encoded the same way as `checked`.
-}
inert : Bool -> Attribute msg
inert =
    booleanAttribute "inert"


{-| -}
accesskey : String -> Attribute msg
accesskey =
    attribute "accesskey"


{-| How text typed on a virtual keyboard is capitalized: `"off"`, `"on"`,
`"words"` or `"characters"`.
-}
autocapitalize : String -> Attribute msg
autocapitalize =
    attribute "autocapitalize"


{-| -}
autocorrect : Bool -> Attribute msg
autocorrect on =
    attribute "autocorrect" (onOff on)


{-| Encoded the same way as `checked`.
-}
autofocus : Bool -> Attribute msg
autofocus =
    booleanAttribute "autofocus"


{-| `"true"`, `"false"` or `"plaintext-only"`.
-}
contenteditable : String -> Attribute msg
contenteditable =
    attribute "contenteditable"


{-| -}
draggable : Bool -> Attribute msg
draggable on =
    attribute "draggable" (trueFalse on)


{-| The label on a virtual keyboard's enter key: `"enter"`, `"done"`, `"go"`,
`"next"`, `"previous"`, `"search"` or `"send"`.
-}
enterkeyhint : String -> Attribute msg
enterkeyhint =
    attribute "enterkeyhint"


{-| Which virtual keyboard to show: `"text"`, `"decimal"`, `"numeric"`,
`"tel"`, `"search"`, `"email"`, `"url"` or `"none"`.
-}
inputmode : String -> Attribute msg
inputmode =
    attribute "inputmode"


{-| -}
spellcheck : Bool -> Attribute msg
spellcheck on =
    attribute "spellcheck" (trueFalse on)


{-| Whether the element's text should be translated. Sent as `"yes"` or
`"no"`.
-}
translate : Bool -> Attribute msg
translate on =
    attribute "translate"
        (if on then
            "yes"

         else
            "no"
        )


{-| -}
writingsuggestions : Bool -> Attribute msg
writingsuggestions on =
    attribute "writingsuggestions" (trueFalse on)


{-| Make the element a popover: `"auto"`, `"manual"` or `"hint"`.
-}
popover : String -> Attribute msg
popover =
    attribute "popover"


{-| Which user actions close a dialog: `"any"`, `"closerequest"` or `"none"`.
-}
closedby : String -> Attribute msg
closedby =
    attribute "closedby"


{-| The command a button sends to the element named by `commandfor`, like
`"show-modal"`, `"close"` or `"toggle-popover"`.
-}
command : String -> Attribute msg
command =
    attribute "command"


{-| The id of the element a button's `command` acts on.
-}
commandfor : String -> Attribute msg
commandfor =
    attribute "commandfor"


{-| -}
itemid : String -> Attribute msg
itemid =
    attribute "itemid"


{-| -}
itemprop : String -> Attribute msg
itemprop =
    attribute "itemprop"


{-| Encoded the same way as `checked`.
-}
itemscope : Bool -> Attribute msg
itemscope =
    booleanAttribute "itemscope"


{-| -}
itemtype : String -> Attribute msg
itemtype =
    attribute "itemtype"


{-| The customized built-in element to use, for elements that extend a
native one.
-}
is : String -> Attribute msg
is =
    attribute "is"


{-| -}
nonce : String -> Attribute msg
nonce =
    attribute "nonce"


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


trueFalse : Bool -> String
trueFalse on =
    if on then
        "true"

    else
        "false"


onOff : Bool -> String
onOff on =
    if on then
        "on"

    else
        "off"
