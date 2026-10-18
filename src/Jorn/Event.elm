module Jorn.Event exposing
    ( on, custom, Options
    , onClick, onInput, onCheck, onSubmit
    , onMouseDown, onMouseUp, onMouseEnter, onMouseLeave, onMouseOver, onMouseOut
    , onKeydown, onKeyup, onKeypress
    , onChange, onFocus, onBlur
    , preventDefault, stopPropagation, include
    , targetValue, targetChecked, key
    )

{-| Event handlers.

Options are static: the client must decide whether to call `preventDefault`
the moment the event fires, without waiting on a server. `include` lists the
event fields a server component needs serialized and sent back, as dotted
paths like `"target.value"`. In client mode the whole event is available and
`include` is ignored.

An option is an attribute of the handler it applies to:

    form [ Event.onSubmit Submit ] [...]

    form [ Event.preventDefault (Event.onSubmit Submit) ] [...]

Options on one handler merge, so an option set twice asks for both things. An
option only reaches the handler it wraps.


# Handlers

@docs on, custom, Options


# Common events

@docs onClick, onInput, onCheck, onSubmit


# Mouse

@docs onMouseDown, onMouseUp, onMouseEnter, onMouseLeave, onMouseOver, onMouseOut


# Keyboard

Keyboard handlers get the event's `key`, like `"Enter"`, `"a"` or
`"ArrowUp"`, and include it, so a server component receives it too.

@docs onKeydown, onKeyup, onKeypress


# Forms and focus

@docs onChange, onFocus, onBlur


# Options

@docs preventDefault, stopPropagation, include


# Decoders

@docs targetValue, targetChecked, key

-}

import Jorn.Attribute exposing (Attribute)
import Jorn.Internal.Vdom as Vdom
import Json.Decode as Decode exposing (Decoder)


{-| How the client should treat an event before handing it to Elm.
-}
type alias Options msg =
    Attribute msg -> Attribute msg


{-| Handle an event with no options beyond the ones on the element.
-}
on : String -> Decoder msg -> Attribute msg
on name decoder =
    Vdom.On name decoder


{-| Handle an event with explicit options.
-}
custom : String -> Options msg -> Decoder msg -> Attribute msg
custom name options decoder =
    options (Vdom.On name decoder)


{-| -}
onClick : msg -> Attribute msg
onClick msg =
    on "click" (Decode.succeed msg)


{-| Includes `target.value`.
-}
onInput : (String -> msg) -> Attribute msg
onInput tagger =
    custom "input" (include [ "target.value" ]) (Decode.map tagger targetValue)


{-| Fires on `change`. Includes `target.checked`.
-}
onCheck : (Bool -> msg) -> Attribute msg
onCheck tagger =
    custom "change" (include [ "target.checked" ]) (Decode.map tagger targetChecked)


{-| Prevents the browser's default form submission.
-}
onSubmit : msg -> Attribute msg
onSubmit msg =
    custom "submit" preventDefault (Decode.succeed msg)


{-| -}
onMouseDown : msg -> Attribute msg
onMouseDown msg =
    on "mousedown" (Decode.succeed msg)


{-| -}
onMouseUp : msg -> Attribute msg
onMouseUp msg =
    on "mouseup" (Decode.succeed msg)


{-| Fires when the pointer moves onto the element. Unlike `onMouseOver`, it
doesn't fire again for the element's children.
-}
onMouseEnter : msg -> Attribute msg
onMouseEnter msg =
    on "mouseenter" (Decode.succeed msg)


{-| Fires when the pointer leaves the element. Unlike `onMouseOut`, it doesn't
fire for the element's children.
-}
onMouseLeave : msg -> Attribute msg
onMouseLeave msg =
    on "mouseleave" (Decode.succeed msg)


{-| -}
onMouseOver : msg -> Attribute msg
onMouseOver msg =
    on "mouseover" (Decode.succeed msg)


{-| -}
onMouseOut : msg -> Attribute msg
onMouseOut msg =
    on "mouseout" (Decode.succeed msg)


{-| Includes `key`.

    Html.input [ Event.onKeydown KeyPressed ]

-}
onKeydown : (String -> msg) -> Attribute msg
onKeydown =
    keyHandler "keydown"


{-| Includes `key`.
-}
onKeyup : (String -> msg) -> Attribute msg
onKeyup =
    keyHandler "keyup"


{-| Includes `key`. Browsers have deprecated `keypress`; prefer `onKeydown`.
-}
onKeypress : (String -> msg) -> Attribute msg
onKeypress =
    keyHandler "keypress"


keyHandler : String -> (String -> msg) -> Attribute msg
keyHandler name tagger =
    custom name (include [ "key" ]) (Decode.map tagger key)


{-| Fires when a control's value is committed, for example when a text field
loses focus or a `select` changes. Includes `target.value`.
-}
onChange : (String -> msg) -> Attribute msg
onChange tagger =
    custom "change" (include [ "target.value" ]) (Decode.map tagger targetValue)


{-| -}
onFocus : msg -> Attribute msg
onFocus msg =
    on "focus" (Decode.succeed msg)


{-| -}
onBlur : msg -> Attribute msg
onBlur msg =
    on "blur" (Decode.succeed msg)


{-| Call `preventDefault` on the event before it reaches Elm.
-}
preventDefault : Options msg
preventDefault handler =
    Vdom.Options { preventDefault = True, stopPropagation = False, include = [] } handler


{-| Stop the event from bubbling past the element.
-}
stopPropagation : Options msg
stopPropagation handler =
    Vdom.Options { preventDefault = False, stopPropagation = True, include = [] } handler


{-| Send these event fields back to Elm, as dotted paths like `"target.value"`.

The field is copied off the event into plain JSON, keeping its nesting.

-}
include : List String -> Options msg
include paths handler =
    Vdom.Options { preventDefault = False, stopPropagation = False, include = paths } handler


{-| -}
targetValue : Decoder String
targetValue =
    Decode.at [ "target", "value" ] Decode.string


{-| -}
targetChecked : Decoder Bool
targetChecked =
    Decode.at [ "target", "checked" ] Decode.bool


{-| The `key` of a keyboard event, like `"Enter"`, `"a"` or `"ArrowUp"`.
-}
key : Decoder String
key =
    Decode.field "key" Decode.string
