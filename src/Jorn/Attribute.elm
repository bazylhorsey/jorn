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
    , open, target, download, ping, rel, hreflang, referrerpolicy
    , as_, blocking, integrity
    , alt, src, srcset, sizes, crossorigin, usemap, ismap, width, height
    , decoding, loading, fetchpriority, autoplay, controls, loop, muted
    , playsinline, poster, preload
    , action, method, enctype, acceptCharset, novalidate, autocomplete, accept
    , required, readonly, multiple, min, max, step, minlength, maxlength
    , pattern, size, cols, rows, list, dirname, form, formaction, formenctype
    , formmethod, formnovalidate, formtarget, popovertarget, popovertargetaction
    , alpha, colorspace
    , selected
    , defaultValue, defaultChecked, defaultSelected
    , httpEquiv, content, charset, media
    , shadowrootmode, shadowrootdelegatesfocus, shadowrootclonable
    , shadowrootserializable
    , colspan, rowspan, span, headers, scope, abbr
    , datetime
    , role, aria
    , ariaActivedescendant, ariaAtomic, ariaAutocomplete, ariaBraillelabel
    , ariaBrailleroledescription, ariaBusy, ariaChecked, ariaColcount
    , ariaColindex, ariaColindextext, ariaColspan, ariaControls, ariaCurrent
    , ariaDescribedby, ariaDescription, ariaDetails, ariaDisabled
    , ariaErrormessage, ariaExpanded, ariaFlowto, ariaHaspopup, ariaHidden
    , ariaInvalid, ariaKeyshortcuts, ariaLabel, ariaLabelledby, ariaLevel
    , ariaLive, ariaModal, ariaMultiline, ariaMultiselectable, ariaOrientation
    , ariaOwns, ariaPlaceholder, ariaPosinset, ariaPressed, ariaReadonly
    , ariaRelevant, ariaRequired, ariaRoledescription, ariaRowcount
    , ariaRowindex, ariaRowindextext, ariaRowspan, ariaSelected, ariaSetsize
    , ariaSort, ariaValuemax, ariaValuemin, ariaValuenow, ariaValuetext
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


# Links

@docs open, target, download, ping, rel, hreflang, referrerpolicy


# Resources

@docs as_, blocking, integrity


# Images and media

@docs alt, src, srcset, sizes, crossorigin, usemap, ismap, width, height
@docs decoding, loading, fetchpriority, autoplay, controls, loop, muted
@docs playsinline, poster, preload


# Forms

@docs action, method, enctype, acceptCharset, novalidate, autocomplete, accept
@docs required, readonly, multiple, min, max, step, minlength, maxlength
@docs pattern, size, cols, rows, list, dirname, form, formaction, formenctype
@docs formmethod, formnovalidate, formtarget, popovertarget, popovertargetaction
@docs alpha, colorspace


# Selection

@docs selected


# Initial values

For controls you don't want to keep in step with your model.

@docs defaultValue, defaultChecked, defaultSelected


# Meta

@docs httpEquiv, content, charset, media


# Templates

@docs shadowrootmode, shadowrootdelegatesfocus, shadowrootclonable
@docs shadowrootserializable


# Tables

@docs colspan, rowspan, span, headers, scope, abbr


# Dates

@docs datetime


# Accessibility

`role` and the ARIA attributes. Every ARIA attribute takes a `String`, since
ARIA values are tokens like `"true"`, `"mixed"` or `"page"`, not plain
booleans:

    Html.button [ Attribute.ariaPressed "mixed", Attribute.ariaControls "menu" ] []

`aria "label" "Close"` sets any `aria-*` attribute, including ones added after
this package was written.

@docs role, aria
@docs ariaActivedescendant, ariaAtomic, ariaAutocomplete, ariaBraillelabel
@docs ariaBrailleroledescription, ariaBusy, ariaChecked, ariaColcount
@docs ariaColindex, ariaColindextext, ariaColspan, ariaControls, ariaCurrent
@docs ariaDescribedby, ariaDescription, ariaDetails, ariaDisabled
@docs ariaErrormessage, ariaExpanded, ariaFlowto, ariaHaspopup, ariaHidden
@docs ariaInvalid, ariaKeyshortcuts, ariaLabel, ariaLabelledby, ariaLevel
@docs ariaLive, ariaModal, ariaMultiline, ariaMultiselectable, ariaOrientation
@docs ariaOwns, ariaPlaceholder, ariaPosinset, ariaPressed, ariaReadonly
@docs ariaRelevant, ariaRequired, ariaRoledescription, ariaRowcount
@docs ariaRowindex, ariaRowindextext, ariaRowspan, ariaSelected, ariaSetsize
@docs ariaSort, ariaValuemax, ariaValuemin, ariaValuenow, ariaValuetext

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


{-| Whether a `details` or `dialog` is open. Encoded the same way as
`checked`, since people open and close them.
-}
open : Bool -> Attribute msg
open =
    booleanAttribute "open"


{-| Where to open a link or submit a form: `"_blank"`, `"_self"`, `"_parent"`,
`"_top"`, or a name.
-}
target : String -> Attribute msg
target =
    attribute "target"


{-| Download the link instead of opening it, as this filename. `""` keeps the
server's name.
-}
download : String -> Attribute msg
download =
    attribute "download"


{-| Space-separated URLs to notify when the link is followed.
-}
ping : String -> Attribute msg
ping =
    attribute "ping"


{-| -}
rel : String -> Attribute msg
rel =
    attribute "rel"


{-| -}
hreflang : String -> Attribute msg
hreflang =
    attribute "hreflang"


{-| -}
referrerpolicy : String -> Attribute msg
referrerpolicy =
    attribute "referrerpolicy"


{-| `as`, on a preload `link`: what kind of resource it is.
-}
as_ : String -> Attribute msg
as_ =
    attribute "as"


{-| -}
blocking : String -> Attribute msg
blocking =
    attribute "blocking"


{-| -}
integrity : String -> Attribute msg
integrity =
    attribute "integrity"


{-| -}
alt : String -> Attribute msg
alt =
    attribute "alt"


{-| -}
src : String -> Attribute msg
src =
    attribute "src"


{-| -}
srcset : String -> Attribute msg
srcset =
    attribute "srcset"


{-| -}
sizes : String -> Attribute msg
sizes =
    attribute "sizes"


{-| `"anonymous"` or `"use-credentials"`.
-}
crossorigin : String -> Attribute msg
crossorigin =
    attribute "crossorigin"


{-| -}
usemap : String -> Attribute msg
usemap =
    attribute "usemap"


{-| Encoded the same way as `checked`.
-}
ismap : Bool -> Attribute msg
ismap =
    booleanAttributeWith "ismap" "isMap"


{-| -}
width : Int -> Attribute msg
width n =
    attribute "width" (String.fromInt n)


{-| -}
height : Int -> Attribute msg
height n =
    attribute "height" (String.fromInt n)


{-| `"sync"`, `"async"` or `"auto"`.
-}
decoding : String -> Attribute msg
decoding =
    attribute "decoding"


{-| `"eager"` or `"lazy"`.
-}
loading : String -> Attribute msg
loading =
    attribute "loading"


{-| `"high"`, `"low"` or `"auto"`.
-}
fetchpriority : String -> Attribute msg
fetchpriority =
    attribute "fetchpriority"


{-| Encoded the same way as `checked`.
-}
autoplay : Bool -> Attribute msg
autoplay =
    booleanAttribute "autoplay"


{-| Encoded the same way as `checked`.
-}
controls : Bool -> Attribute msg
controls =
    booleanAttribute "controls"


{-| Encoded the same way as `checked`.
-}
loop : Bool -> Attribute msg
loop =
    booleanAttribute "loop"


{-| Encoded the same way as `checked`.
-}
muted : Bool -> Attribute msg
muted =
    booleanAttribute "muted"


{-| Encoded the same way as `checked`.
-}
playsinline : Bool -> Attribute msg
playsinline =
    booleanAttributeWith "playsinline" "playsInline"


{-| -}
poster : String -> Attribute msg
poster =
    attribute "poster"


{-| `"none"`, `"metadata"` or `"auto"`.
-}
preload : String -> Attribute msg
preload =
    attribute "preload"


{-| -}
action : String -> Attribute msg
action =
    attribute "action"


{-| `"get"`, `"post"` or `"dialog"`.
-}
method : String -> Attribute msg
method =
    attribute "method"


{-| -}
enctype : String -> Attribute msg
enctype =
    attribute "enctype"


{-| `accept-charset`.
-}
acceptCharset : String -> Attribute msg
acceptCharset =
    attribute "accept-charset"


{-| Encoded the same way as `checked`.
-}
novalidate : Bool -> Attribute msg
novalidate =
    booleanAttributeWith "novalidate" "noValidate"


{-| Like `"off"`, `"email"` or `"current-password"`.
-}
autocomplete : String -> Attribute msg
autocomplete =
    attribute "autocomplete"


{-| File types a file input accepts, like `"image/*,.pdf"`.
-}
accept : String -> Attribute msg
accept =
    attribute "accept"


{-| Encoded the same way as `checked`.
-}
required : Bool -> Attribute msg
required =
    booleanAttribute "required"


{-| Encoded the same way as `checked`.
-}
readonly : Bool -> Attribute msg
readonly =
    booleanAttributeWith "readonly" "readOnly"


{-| Encoded the same way as `checked`.
-}
multiple : Bool -> Attribute msg
multiple =
    booleanAttribute "multiple"


{-| A string, since it can be a number or a date.
-}
min : String -> Attribute msg
min =
    attribute "min"


{-| A string, since it can be a number or a date.
-}
max : String -> Attribute msg
max =
    attribute "max"


{-| A number, or `"any"`.
-}
step : String -> Attribute msg
step =
    attribute "step"


{-| -}
minlength : Int -> Attribute msg
minlength n =
    attribute "minlength" (String.fromInt n)


{-| -}
maxlength : Int -> Attribute msg
maxlength n =
    attribute "maxlength" (String.fromInt n)


{-| -}
pattern : String -> Attribute msg
pattern =
    attribute "pattern"


{-| -}
size : Int -> Attribute msg
size n =
    attribute "size" (String.fromInt n)


{-| -}
cols : Int -> Attribute msg
cols n =
    attribute "cols" (String.fromInt n)


{-| -}
rows : Int -> Attribute msg
rows n =
    attribute "rows" (String.fromInt n)


{-| The id of a `datalist` with suggestions.
-}
list : String -> Attribute msg
list =
    attribute "list"


{-| -}
dirname : String -> Attribute msg
dirname =
    attribute "dirname"


{-| The id of the form a control belongs to, when it isn't inside it.
-}
form : String -> Attribute msg
form =
    attribute "form"


{-| -}
formaction : String -> Attribute msg
formaction =
    attribute "formaction"


{-| -}
formenctype : String -> Attribute msg
formenctype =
    attribute "formenctype"


{-| -}
formmethod : String -> Attribute msg
formmethod =
    attribute "formmethod"


{-| Encoded the same way as `checked`.
-}
formnovalidate : Bool -> Attribute msg
formnovalidate =
    booleanAttributeWith "formnovalidate" "formNoValidate"


{-| -}
formtarget : String -> Attribute msg
formtarget =
    attribute "formtarget"


{-| -}
popovertarget : String -> Attribute msg
popovertarget =
    attribute "popovertarget"


{-| `"show"`, `"hide"` or `"toggle"`.
-}
popovertargetaction : String -> Attribute msg
popovertargetaction =
    attribute "popovertargetaction"


{-| Let a color input pick an alpha value.
-}
alpha : Bool -> Attribute msg
alpha =
    booleanAttribute "alpha"


{-| `"limited-srgb"` or `"display-p3"`.
-}
colorspace : String -> Attribute msg
colorspace =
    attribute "colorspace"


{-| Whether an `option` is selected. Sent as an attribute and kept in step
with the live selection, like `checked`.
-}
selected : Bool -> Attribute msg
selected =
    booleanAttribute "selected"


{-| The value a control starts with, without controlling it afterwards: what
someone types stays, even when this changes. Use `value` instead to keep the
control in step with your model. Sent as the `defaultValue` property, which
the browser reflects into the `value` attribute.
-}
defaultValue : String -> Attribute msg
defaultValue v =
    property "defaultValue" (Encode.string v)


{-| Whether a checkbox or radio starts out checked, without controlling it
afterwards. Use `checked` instead to keep it in step with your model.
-}
defaultChecked : Bool -> Attribute msg
defaultChecked on =
    property "defaultChecked" (Encode.bool on)


{-| Whether an `option` starts out selected. Unlike `selected`, Jorn doesn't
copy it onto the live selection, so the option someone picks stays picked. Use
`selected` to keep the selection in step with your model.
-}
defaultSelected : Bool -> Attribute msg
defaultSelected on =
    property "defaultSelected" (Encode.bool on)


{-| `http-equiv`.
-}
httpEquiv : String -> Attribute msg
httpEquiv =
    attribute "http-equiv"


{-| -}
content : String -> Attribute msg
content =
    attribute "content"


{-| -}
charset : String -> Attribute msg
charset =
    attribute "charset"


{-| A media query, like `"(prefers-color-scheme: dark)"`.
-}
media : String -> Attribute msg
media =
    attribute "media"


{-| Make a `template` a declarative shadow root: `"open"` or `"closed"`.
-}
shadowrootmode : String -> Attribute msg
shadowrootmode =
    attribute "shadowrootmode"


{-| Encoded the same way as `checked`.
-}
shadowrootdelegatesfocus : Bool -> Attribute msg
shadowrootdelegatesfocus =
    booleanAttributeWith "shadowrootdelegatesfocus" "shadowRootDelegatesFocus"


{-| Encoded the same way as `checked`.
-}
shadowrootclonable : Bool -> Attribute msg
shadowrootclonable =
    booleanAttributeWith "shadowrootclonable" "shadowRootClonable"


{-| Encoded the same way as `checked`.
-}
shadowrootserializable : Bool -> Attribute msg
shadowrootserializable =
    booleanAttributeWith "shadowrootserializable" "shadowRootSerializable"


{-| -}
colspan : Int -> Attribute msg
colspan n =
    attribute "colspan" (String.fromInt n)


{-| -}
rowspan : Int -> Attribute msg
rowspan n =
    attribute "rowspan" (String.fromInt n)


{-| How many columns a `col` or `colgroup` spans.
-}
span : Int -> Attribute msg
span n =
    attribute "span" (String.fromInt n)


{-| Space-separated ids of the header cells for this cell.
-}
headers : String -> Attribute msg
headers =
    attribute "headers"


{-| `"row"`, `"col"`, `"rowgroup"` or `"colgroup"`.
-}
scope : String -> Attribute msg
scope =
    attribute "scope"


{-| -}
abbr : String -> Attribute msg
abbr =
    attribute "abbr"


{-| -}
datetime : String -> Attribute msg
datetime =
    attribute "datetime"


{-| The element's ARIA role, like `"button"`, `"dialog"` or `"tab"`.
-}
role : String -> Attribute msg
role =
    attribute "role"


{-| Any `aria-*` attribute: `aria "label" "Close"` sets `aria-label="Close"`.
-}
aria : String -> String -> Attribute msg
aria name_ =
    attribute ("aria-" ++ name_)


{-| `aria-activedescendant`
-}
ariaActivedescendant : String -> Attribute msg
ariaActivedescendant =
    aria "activedescendant"


{-| `aria-atomic`
-}
ariaAtomic : String -> Attribute msg
ariaAtomic =
    aria "atomic"


{-| `aria-autocomplete`
-}
ariaAutocomplete : String -> Attribute msg
ariaAutocomplete =
    aria "autocomplete"


{-| `aria-braillelabel`
-}
ariaBraillelabel : String -> Attribute msg
ariaBraillelabel =
    aria "braillelabel"


{-| `aria-brailleroledescription`
-}
ariaBrailleroledescription : String -> Attribute msg
ariaBrailleroledescription =
    aria "brailleroledescription"


{-| `aria-busy`
-}
ariaBusy : String -> Attribute msg
ariaBusy =
    aria "busy"


{-| `aria-checked`
-}
ariaChecked : String -> Attribute msg
ariaChecked =
    aria "checked"


{-| `aria-colcount`
-}
ariaColcount : String -> Attribute msg
ariaColcount =
    aria "colcount"


{-| `aria-colindex`
-}
ariaColindex : String -> Attribute msg
ariaColindex =
    aria "colindex"


{-| `aria-colindextext`
-}
ariaColindextext : String -> Attribute msg
ariaColindextext =
    aria "colindextext"


{-| `aria-colspan`
-}
ariaColspan : String -> Attribute msg
ariaColspan =
    aria "colspan"


{-| `aria-controls`
-}
ariaControls : String -> Attribute msg
ariaControls =
    aria "controls"


{-| `aria-current`
-}
ariaCurrent : String -> Attribute msg
ariaCurrent =
    aria "current"


{-| `aria-describedby`
-}
ariaDescribedby : String -> Attribute msg
ariaDescribedby =
    aria "describedby"


{-| `aria-description`
-}
ariaDescription : String -> Attribute msg
ariaDescription =
    aria "description"


{-| `aria-details`
-}
ariaDetails : String -> Attribute msg
ariaDetails =
    aria "details"


{-| `aria-disabled`
-}
ariaDisabled : String -> Attribute msg
ariaDisabled =
    aria "disabled"


{-| `aria-errormessage`
-}
ariaErrormessage : String -> Attribute msg
ariaErrormessage =
    aria "errormessage"


{-| `aria-expanded`
-}
ariaExpanded : String -> Attribute msg
ariaExpanded =
    aria "expanded"


{-| `aria-flowto`
-}
ariaFlowto : String -> Attribute msg
ariaFlowto =
    aria "flowto"


{-| `aria-haspopup`
-}
ariaHaspopup : String -> Attribute msg
ariaHaspopup =
    aria "haspopup"


{-| `aria-hidden`
-}
ariaHidden : String -> Attribute msg
ariaHidden =
    aria "hidden"


{-| `aria-invalid`
-}
ariaInvalid : String -> Attribute msg
ariaInvalid =
    aria "invalid"


{-| `aria-keyshortcuts`
-}
ariaKeyshortcuts : String -> Attribute msg
ariaKeyshortcuts =
    aria "keyshortcuts"


{-| `aria-label`
-}
ariaLabel : String -> Attribute msg
ariaLabel =
    aria "label"


{-| `aria-labelledby`
-}
ariaLabelledby : String -> Attribute msg
ariaLabelledby =
    aria "labelledby"


{-| `aria-level`
-}
ariaLevel : String -> Attribute msg
ariaLevel =
    aria "level"


{-| `aria-live`
-}
ariaLive : String -> Attribute msg
ariaLive =
    aria "live"


{-| `aria-modal`
-}
ariaModal : String -> Attribute msg
ariaModal =
    aria "modal"


{-| `aria-multiline`
-}
ariaMultiline : String -> Attribute msg
ariaMultiline =
    aria "multiline"


{-| `aria-multiselectable`
-}
ariaMultiselectable : String -> Attribute msg
ariaMultiselectable =
    aria "multiselectable"


{-| `aria-orientation`
-}
ariaOrientation : String -> Attribute msg
ariaOrientation =
    aria "orientation"


{-| `aria-owns`
-}
ariaOwns : String -> Attribute msg
ariaOwns =
    aria "owns"


{-| `aria-placeholder`
-}
ariaPlaceholder : String -> Attribute msg
ariaPlaceholder =
    aria "placeholder"


{-| `aria-posinset`
-}
ariaPosinset : String -> Attribute msg
ariaPosinset =
    aria "posinset"


{-| `aria-pressed`
-}
ariaPressed : String -> Attribute msg
ariaPressed =
    aria "pressed"


{-| `aria-readonly`
-}
ariaReadonly : String -> Attribute msg
ariaReadonly =
    aria "readonly"


{-| `aria-relevant`
-}
ariaRelevant : String -> Attribute msg
ariaRelevant =
    aria "relevant"


{-| `aria-required`
-}
ariaRequired : String -> Attribute msg
ariaRequired =
    aria "required"


{-| `aria-roledescription`
-}
ariaRoledescription : String -> Attribute msg
ariaRoledescription =
    aria "roledescription"


{-| `aria-rowcount`
-}
ariaRowcount : String -> Attribute msg
ariaRowcount =
    aria "rowcount"


{-| `aria-rowindex`
-}
ariaRowindex : String -> Attribute msg
ariaRowindex =
    aria "rowindex"


{-| `aria-rowindextext`
-}
ariaRowindextext : String -> Attribute msg
ariaRowindextext =
    aria "rowindextext"


{-| `aria-rowspan`
-}
ariaRowspan : String -> Attribute msg
ariaRowspan =
    aria "rowspan"


{-| `aria-selected`
-}
ariaSelected : String -> Attribute msg
ariaSelected =
    aria "selected"


{-| `aria-setsize`
-}
ariaSetsize : String -> Attribute msg
ariaSetsize =
    aria "setsize"


{-| `aria-sort`
-}
ariaSort : String -> Attribute msg
ariaSort =
    aria "sort"


{-| `aria-valuemax`
-}
ariaValuemax : String -> Attribute msg
ariaValuemax =
    aria "valuemax"


{-| `aria-valuemin`
-}
ariaValuemin : String -> Attribute msg
ariaValuemin =
    aria "valuemin"


{-| `aria-valuenow`
-}
ariaValuenow : String -> Attribute msg
ariaValuenow =
    aria "valuenow"


{-| `aria-valuetext`
-}
ariaValuetext : String -> Attribute msg
ariaValuetext =
    aria "valuetext"


{-| Boolean attributes: present (with an empty value) when true, and a `false`
property when false, so the live DOM state is reset.
-}
booleanAttribute : String -> Bool -> Attribute msg
booleanAttribute attrName =
    booleanAttributeWith attrName attrName


{-| For boolean attributes whose DOM property is spelled differently, like
`readonly` and `readOnly`.
-}
booleanAttributeWith : String -> String -> Bool -> Attribute msg
booleanAttributeWith attrName propName on =
    if on then
        attribute attrName ""

    else
        property propName (Encode.bool False)


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
